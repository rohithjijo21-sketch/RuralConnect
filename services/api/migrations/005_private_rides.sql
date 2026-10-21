CREATE TABLE driver_locations (
  user_id uuid PRIMARY KEY REFERENCES users(id),
  point geography(Point,4326) NOT NULL,
  accuracy_m integer NOT NULL CHECK(accuracy_m BETWEEN 0 AND 100),
  recorded_at timestamptz NOT NULL
);
CREATE INDEX driver_locations_geo ON driver_locations USING gist(point);
CREATE TABLE private_offer_rejections (
  booking_id uuid REFERENCES private_bookings(id),
  driver_id uuid REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(booking_id,driver_id)
);
ALTER TABLE ride_requests ADD COLUMN pickup_label text NOT NULL DEFAULT 'Pickup';
ALTER TABLE ride_requests ADD COLUMN dropoff_label text NOT NULL DEFAULT 'Destination';
ALTER TABLE private_bookings ADD COLUMN pickup_confirmed_at timestamptz;
ALTER TABLE fare_policies ADD COLUMN beta_only boolean NOT NULL DEFAULT false;
-- User-authorized temporary beta prices. Never used when beta authentication is disabled.
INSERT INTO fare_policies(category,base_paise,per_km_paise,version,beta_only)
VALUES ('AUTO',3000,1500,0,true),('TAXI',6000,2000,0,true);
