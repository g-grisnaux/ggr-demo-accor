package com.accor.demo.hotelsearch;

import com.accor.demo.hotelsearch.dto.Availability;
import com.accor.demo.hotelsearch.dto.AvailabilityBatchResponse;
import com.accor.demo.hotelsearch.dto.Hotel;
import com.accor.demo.hotelsearch.dto.SearchResponse;
import io.opentelemetry.api.trace.Span;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.time.LocalDate;
import java.time.format.DateTimeParseException;
import java.util.Arrays;
import java.util.List;
import java.util.Map;
import java.util.Optional;

@RestController
public class HotelController {

    private static final Logger log = LoggerFactory.getLogger(HotelController.class);

    private final HotelRepository repository;
    private final RankingService ranking;
    private final DemoControls controls;

    public HotelController(HotelRepository repository, RankingService ranking, DemoControls controls) {
        this.repository = repository;
        this.ranking = ranking;
        this.controls = controls;
    }

    @GetMapping("/hotels")
    public ResponseEntity<?> search(
            @RequestParam String city,
            @RequestParam(required = false) String checkIn,
            @RequestParam(required = false) String checkOut,
            @RequestParam(defaultValue = "2") int guests
    ) {
        LocalDate from;
        LocalDate to;
        try {
            from = checkIn != null ? LocalDate.parse(checkIn) : LocalDate.now();
            to = checkOut != null ? LocalDate.parse(checkOut) : from.plusDays(1);
        } catch (DateTimeParseException e) {
            return ResponseEntity.badRequest().body(Map.of(
                    "error_code", "invalid_date_range",
                    "message", "checkIn and checkOut must be ISO-8601 dates"
            ));
        }

        boolean degraded = controls.isSlowSearch();
        Span.current().setAttribute("search.city", city);
        Span.current().setAttribute("search.degraded", degraded);

        List<Hotel> hotels = degraded
                ? repository.searchByCityDegraded(city, from, to)
                : repository.searchByCity(city);

        List<Hotel> ranked = ranking.rank(hotels);

        log.info("hotel search completed city={} results={} degraded={}", city, ranked.size(), degraded);
        return ResponseEntity.ok(new SearchResponse(ranked));
    }

    @GetMapping("/hotels/{hotelId}")
    public ResponseEntity<?> getHotel(@PathVariable long hotelId) {
        Optional<Hotel> hotel = repository.findById(hotelId);
        if (hotel.isEmpty()) {
            return ResponseEntity.status(404).body(Map.of(
                    "error_code", "hotel_not_found",
                    "message", "No hotel with id " + hotelId
            ));
        }
        return ResponseEntity.ok(hotel.get());
    }

    /**
     * Single-hotel availability. The BFF hits this once per search result when
     * its dataloader is disabled — the N+1 the flame graph exposes.
     */
    @GetMapping("/hotels/{hotelId}/availability")
    public ResponseEntity<?> availability(
            @PathVariable long hotelId,
            @RequestParam String checkIn,
            @RequestParam String checkOut
    ) {
        LocalDate from;
        LocalDate to;
        try {
            from = LocalDate.parse(checkIn);
            to = LocalDate.parse(checkOut);
        } catch (DateTimeParseException e) {
            return ResponseEntity.badRequest().body(Map.of(
                    "error_code", "invalid_date_range",
                    "message", "checkIn and checkOut must be ISO-8601 dates"
            ));
        }

        List<Availability> found = repository.availabilityFor(List.of(hotelId), from, to);
        return ResponseEntity.ok(found.isEmpty()
                ? new Availability(hotelId, false, 0, List.of())
                : found.get(0));
    }

    /**
     * Batched availability — one round-trip for a whole page of results. This is
     * what the BFF's dataloader calls.
     */
    @GetMapping("/availability")
    public ResponseEntity<?> availabilityBatch(
            @RequestParam String hotelIds,
            @RequestParam String checkIn,
            @RequestParam String checkOut
    ) {
        List<Long> ids;
        LocalDate from;
        LocalDate to;
        try {
            ids = Arrays.stream(hotelIds.split(","))
                    .map(String::trim)
                    .filter(s -> !s.isEmpty())
                    .map(Long::parseLong)
                    .distinct()
                    .limit(50)
                    .toList();
            from = LocalDate.parse(checkIn);
            to = LocalDate.parse(checkOut);
        } catch (NumberFormatException | DateTimeParseException e) {
            return ResponseEntity.badRequest().body(Map.of(
                    "error_code", "invalid_request",
                    "message", "hotelIds must be numeric and dates ISO-8601"
            ));
        }

        Span.current().setAttribute("availability.batch_size", ids.size());
        return ResponseEntity.ok(new AvailabilityBatchResponse(repository.availabilityFor(ids, from, to)));
    }
}
