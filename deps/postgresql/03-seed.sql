-- Seed data.
--
-- Volume matters here: the degraded search has to be visibly slow without a
-- pg_sleep, so `hotels` needs enough rows for a sequential scan to hurt and
-- `availability_daily` enough for the correlated subquery to add real work.
-- ~24k hotels and ~1.1M availability rows seed in a few seconds.

-- A handful of recognisable Paris properties, so the demo UI shows real names
-- rather than "Hotel 14732".
INSERT INTO hotels (name, brand, city, country, star_rating, guest_rating, address, amenities, thumbnail_url) VALUES
  ('Sofitel Paris Le Faubourg',    'Sofitel',  'Paris', 'FR', 5, 8.9, '15 Rue Boissy d''Anglas',      '{spa,wifi,bar,fitness}',        'https://cdn.example.com/sofitel-faubourg.jpg'),
  ('Pullman Paris Tour Eiffel',    'Pullman',  'Paris', 'FR', 4, 8.4, '18 Avenue de Suffren',         '{wifi,bar,fitness,restaurant}', 'https://cdn.example.com/pullman-eiffel.jpg'),
  ('Novotel Paris Les Halles',     'Novotel',  'Paris', 'FR', 4, 8.2, '8 Place Marguerite de Navarre','{wifi,restaurant,family}',      'https://cdn.example.com/novotel-halles.jpg'),
  ('MGallery Hotel Molitor Paris', 'MGallery', 'Paris', 'FR', 5, 8.7, '13 Rue Nungesser',             '{pool,spa,wifi,bar}',           'https://cdn.example.com/molitor.jpg'),
  ('ibis Paris Gare du Nord',      'ibis',     'Paris', 'FR', 3, 7.6, '18 Rue Saint-Quentin',         '{wifi,breakfast}',              'https://cdn.example.com/ibis-nord.jpg'),
  ('Mercure Paris Opera Garnier',  'Mercure',  'Paris', 'FR', 4, 8.1, '4 Rue de la Michodiere',       '{wifi,bar,breakfast}',          'https://cdn.example.com/mercure-opera.jpg'),
  ('Raffles Paris Le Royal Monceau','Raffles', 'Paris', 'FR', 5, 9.1, '37 Avenue Hoche',              '{spa,pool,wifi,bar,fitness}',   'https://cdn.example.com/royal-monceau.jpg'),
  ('Sofitel Lyon Bellecour',       'Sofitel',  'Lyon',  'FR', 5, 8.6, '20 Quai Gailleton',            '{spa,wifi,restaurant}',         'https://cdn.example.com/sofitel-lyon.jpg'),
  ('Novotel London Bridge',        'Novotel',  'London','GB', 4, 8.3, '53-61 Southwark Bridge Road',  '{wifi,fitness,restaurant}',     'https://cdn.example.com/novotel-london.jpg'),
  ('Sofitel Legend The Grand',     'Sofitel',  'Amsterdam','NL', 5, 9.0, 'Oudezijds Voorburgwal 197', '{spa,wifi,bar}',                'https://cdn.example.com/grand-amsterdam.jpg');

-- Bulk filler across the same cities, so a city search returns a realistic
-- page size out of a large table.
INSERT INTO hotels (name, brand, city, country, star_rating, guest_rating, address, amenities, thumbnail_url)
SELECT
    brands.brand || ' ' || cities.city || ' ' || g,
    brands.brand,
    cities.city,
    cities.country,
    2 + (g % 4),
    6.0 + ((g * 7) % 40) / 10.0,
    g || ' Rue de la Demo',
    CASE WHEN g % 3 = 0 THEN '{wifi,breakfast}'::TEXT[] ELSE '{wifi}'::TEXT[] END,
    NULL
FROM generate_series(1, 400) AS g
CROSS JOIN (VALUES
    ('Paris','FR'), ('Lyon','FR'), ('Marseille','FR'), ('Nice','FR'),
    ('London','GB'), ('Amsterdam','NL'), ('Berlin','DE'), ('Madrid','ES')
) AS cities(city, country)
CROSS JOIN (VALUES
    ('ibis'), ('Novotel'), ('Mercure'), ('Pullman'), ('Sofitel'), ('MGallery'), ('Adagio')
) AS brands(brand);

-- Two or three rate plans per hotel.
INSERT INTO room_offers (hotel_id, rate_code, room_type, board_type, price_per_night_cents, currency, refundable, loyalty_points_earned)
SELECT
    h.hotel_id,
    plans.rate_code,
    plans.room_type,
    plans.board_type,
    (8000 + (h.star_rating * 6000) + ((h.hotel_id * 13) % 5000)) * plans.multiplier / 100,
    'EUR',
    plans.refundable,
    plans.points
FROM hotels h
CROSS JOIN (VALUES
    ('FLEX',   'Standard Double', 'Room only',      100, TRUE,  250),
    ('SAVER',  'Standard Double', 'Room only',        82, FALSE, 120),
    ('BB-FLEX','Superior Double', 'Breakfast included', 128, TRUE, 400)
) AS plans(rate_code, room_type, board_type, multiplier, refundable, points)
WHERE h.star_rating >= 3 OR plans.rate_code <> 'BB-FLEX';

-- 45 nights of inventory for every hotel. A deterministic pattern leaves some
-- hotels sold out on some dates, which is what feeds HOTEL_UNAVAILABLE.
INSERT INTO availability_daily (hotel_id, stay_date, rooms_left)
SELECT
    h.hotel_id,
    CURRENT_DATE + d,
    CASE WHEN (h.hotel_id + d) % 17 = 0 THEN 0 ELSE 1 + ((h.hotel_id + d) % 12) END
FROM hotels h
CROSS JOIN generate_series(0, 44) AS d;

CREATE INDEX availability_hotel_date_idx ON availability_daily (hotel_id, stay_date);

-- Planner statistics have to exist before the first search, otherwise the very
-- first demo query picks a plan for an empty table.
ANALYZE hotels;
ANALYZE room_offers;
ANALYZE availability_daily;
