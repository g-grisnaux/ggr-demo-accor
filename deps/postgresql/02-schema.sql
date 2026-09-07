-- Domain schema for the ALL booking demo.
--
-- Owned jointly by hotel-search-api (hotels, room_offers, availability_daily)
-- and booking-api (bookings, payments). Two logical owners in one instance keeps
-- the demo cheap to run; the trace still shows two distinct services talking to
-- the same database.

CREATE TABLE hotels (
    hotel_id      BIGSERIAL PRIMARY KEY,
    name          TEXT NOT NULL,
    brand         TEXT,
    city          TEXT NOT NULL,
    country       TEXT,
    star_rating   INT  NOT NULL DEFAULT 3,
    guest_rating  NUMERIC(3,1) NOT NULL DEFAULT 7.5,
    address       TEXT,
    amenities     TEXT[] NOT NULL DEFAULT '{}',
    thumbnail_url TEXT
);

CREATE TABLE room_offers (
    offer_id              BIGSERIAL PRIMARY KEY,
    hotel_id              BIGINT NOT NULL REFERENCES hotels(hotel_id),
    rate_code             TEXT NOT NULL,
    room_type             TEXT NOT NULL,
    board_type            TEXT,
    price_per_night_cents BIGINT NOT NULL,
    currency              TEXT NOT NULL DEFAULT 'EUR',
    refundable            BOOLEAN NOT NULL DEFAULT TRUE,
    loyalty_points_earned INT NOT NULL DEFAULT 0
);

CREATE TABLE availability_daily (
    hotel_id   BIGINT NOT NULL REFERENCES hotels(hotel_id),
    stay_date  DATE   NOT NULL,
    rooms_left INT    NOT NULL DEFAULT 0,
    PRIMARY KEY (hotel_id, stay_date)
);

CREATE TABLE bookings (
    booking_id        BIGSERIAL PRIMARY KEY,
    reference         TEXT NOT NULL UNIQUE,
    status            TEXT NOT NULL,
    hotel_id          BIGINT NOT NULL,
    guest_id          TEXT NOT NULL,
    check_in          DATE NOT NULL,
    check_out         DATE NOT NULL,
    guests            INT NOT NULL DEFAULT 2,
    rate_code         TEXT,
    room_type         TEXT,
    total_price_cents BIGINT NOT NULL DEFAULT 0,
    currency          TEXT NOT NULL DEFAULT 'EUR',
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE payments (
    payment_id     BIGSERIAL PRIMARY KEY,
    booking_id     BIGINT REFERENCES bookings(booking_id),
    status         TEXT NOT NULL,
    amount_cents   BIGINT NOT NULL,
    currency       TEXT NOT NULL DEFAULT 'EUR',
    method         TEXT,
    decline_reason TEXT,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- The index the healthy search path relies on. The degraded query wraps the
-- city predicate in LOWER(), which makes this index unusable and forces the
-- sequential scan DBM surfaces.
CREATE INDEX hotels_city_idx ON hotels (city);

CREATE INDEX room_offers_hotel_idx ON room_offers (hotel_id);
CREATE INDEX bookings_guest_idx    ON bookings (guest_id);
CREATE INDEX payments_booking_idx  ON payments (booking_id);
