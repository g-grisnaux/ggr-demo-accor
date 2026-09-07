package com.accor.demo.hotelsearch;

import com.accor.demo.hotelsearch.dto.Availability;
import com.accor.demo.hotelsearch.dto.Hotel;
import com.accor.demo.hotelsearch.dto.RoomOffer;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Repository;

import java.sql.Array;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.time.LocalDate;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Map;
import java.util.Optional;

@Repository
public class HotelRepository {

    private final JdbcTemplate jdbc;

    public HotelRepository(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    private static final RowMapper<Hotel> HOTEL_MAPPER = (rs, rowNum) -> new Hotel(
            rs.getLong("hotel_id"),
            rs.getString("name"),
            rs.getString("brand"),
            rs.getString("city"),
            rs.getString("country"),
            rs.getInt("star_rating"),
            rs.getDouble("guest_rating"),
            rs.getString("address"),
            readArray(rs, "amenities"),
            rs.getString("thumbnail_url")
    );

    private static List<String> readArray(ResultSet rs, String column) throws SQLException {
        Array array = rs.getArray(column);
        if (array == null) {
            return List.of();
        }
        return List.of((String[]) array.getArray());
    }

    /**
     * The indexed search path. `hotels_city_idx` covers the city predicate, so
     * this stays in the low single-digit milliseconds regardless of table size.
     */
    public List<Hotel> searchByCity(String city) {
        return jdbc.query(
                """
                SELECT hotel_id, name, brand, city, country, star_rating,
                       guest_rating, address, amenities, thumbnail_url
                FROM hotels
                WHERE city = ?
                ORDER BY guest_rating DESC
                LIMIT 25
                """,
                HOTEL_MAPPER,
                city
        );
    }

    /**
     * The degraded search path used by the latency scenario.
     *
     * Two things make it slow, and both are realistic regressions rather than an
     * artificial sleep: the city predicate is wrapped in LOWER(), which makes
     * `hotels_city_idx` unusable and forces a sequential scan, and the ordering
     * runs a correlated subquery over availability_daily for every candidate
     * row. DBM shows the plan flip from Index Scan to Seq Scan, which is the
     * point of the scenario.
     */
    public List<Hotel> searchByCityDegraded(String city, LocalDate checkIn, LocalDate checkOut) {
        return jdbc.query(
                """
                SELECT h.hotel_id, h.name, h.brand, h.city, h.country, h.star_rating,
                       h.guest_rating, h.address, h.amenities, h.thumbnail_url
                FROM hotels h
                WHERE LOWER(h.city) = LOWER(?)
                ORDER BY (
                    SELECT COALESCE(SUM(a.rooms_left), 0)
                    FROM availability_daily a
                    WHERE a.hotel_id = h.hotel_id
                      AND a.stay_date >= ?
                      AND a.stay_date < ?
                ) DESC, h.guest_rating DESC
                LIMIT 25
                """,
                HOTEL_MAPPER,
                city, checkIn, checkOut
        );
    }

    public Optional<Hotel> findById(long hotelId) {
        List<Hotel> found = jdbc.query(
                """
                SELECT hotel_id, name, brand, city, country, star_rating,
                       guest_rating, address, amenities, thumbnail_url
                FROM hotels
                WHERE hotel_id = ?
                """,
                HOTEL_MAPPER,
                hotelId
        );
        return found.stream().findFirst();
    }

    /**
     * Availability for a set of hotels in one round-trip. This is what the BFF's
     * dataloader calls; the per-hotel endpoint below is the same logic with a
     * single id, and is what the N+1 scenario hammers.
     */
    public List<Availability> availabilityFor(List<Long> hotelIds, LocalDate checkIn, LocalDate checkOut) {
        if (hotelIds.isEmpty()) {
            return List.of();
        }

        int nights = (int) ChronoUnit.DAYS.between(checkIn, checkOut);
        String placeholders = String.join(",", Collections.nCopies(hotelIds.size(), "?"));

        Object[] args = new Object[hotelIds.size() + 2];
        for (int i = 0; i < hotelIds.size(); i++) {
            args[i] = hotelIds.get(i);
        }
        args[hotelIds.size()] = checkIn;
        args[hotelIds.size() + 1] = checkOut;

        // A stay is bookable only if every night of it has a room left, hence
        // MIN(rooms_left) across the date range rather than a plain count.
        Map<Long, Integer> roomsLeftByHotel = new java.util.HashMap<>();
        jdbc.query(
                """
                SELECT hotel_id, MIN(rooms_left) AS rooms_left, COUNT(*) AS nights_covered
                FROM availability_daily
                WHERE hotel_id IN (%s)
                  AND stay_date >= ?
                  AND stay_date < ?
                GROUP BY hotel_id
                """.formatted(placeholders),
                rs -> {
                    // A hotel missing nights in the range is not bookable for
                    // the whole stay, even if the nights it does have are free.
                    int nightsCovered = rs.getInt("nights_covered");
                    int roomsLeft = nightsCovered >= nights ? rs.getInt("rooms_left") : 0;
                    roomsLeftByHotel.put(rs.getLong("hotel_id"), roomsLeft);
                },
                args
        );

        Map<Long, List<RoomOffer>> offersByHotel = offersFor(hotelIds, nights);

        List<Availability> result = new ArrayList<>();
        for (Long hotelId : hotelIds) {
            int roomsLeft = roomsLeftByHotel.getOrDefault(hotelId, 0);
            List<RoomOffer> offers = roomsLeft > 0
                    ? offersByHotel.getOrDefault(hotelId, List.of())
                    : List.of();
            result.add(new Availability(hotelId, !offers.isEmpty(), roomsLeft, offers));
        }
        return result;
    }

    private Map<Long, List<RoomOffer>> offersFor(List<Long> hotelIds, int nights) {
        String placeholders = String.join(",", Collections.nCopies(hotelIds.size(), "?"));
        Map<Long, List<RoomOffer>> byHotel = new java.util.HashMap<>();

        jdbc.query(
                """
                SELECT hotel_id, rate_code, room_type, board_type,
                       price_per_night_cents, currency, refundable, loyalty_points_earned
                FROM room_offers
                WHERE hotel_id IN (%s)
                ORDER BY price_per_night_cents ASC
                """.formatted(placeholders),
                rs -> {
                    long pricePerNight = rs.getLong("price_per_night_cents");
                    RoomOffer offer = new RoomOffer(
                            rs.getString("rate_code"),
                            rs.getString("room_type"),
                            rs.getString("board_type"),
                            pricePerNight,
                            pricePerNight * nights,
                            rs.getString("currency"),
                            rs.getBoolean("refundable"),
                            rs.getInt("loyalty_points_earned") * nights
                    );
                    byHotel.computeIfAbsent(rs.getLong("hotel_id"), k -> new ArrayList<>()).add(offer);
                },
                hotelIds.toArray()
        );
        return byHotel;
    }
}
