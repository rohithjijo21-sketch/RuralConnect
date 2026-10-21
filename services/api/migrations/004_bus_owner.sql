CREATE TABLE bus_owners (
  user_id uuid PRIMARY KEY REFERENCES users(id),
  operator_id uuid UNIQUE NOT NULL REFERENCES operators(id),
  status text NOT NULL DEFAULT 'PENDING' CHECK(status IN ('PENDING','APPROVED','REJECTED')),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE bus_service_plans (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  operator_id uuid NOT NULL REFERENCES operators(id),
  route_version_id uuid NOT NULL REFERENCES route_versions(id),
  vehicle_id uuid NOT NULL REFERENCES vehicles(id),
  crew_id uuid NOT NULL REFERENCES users(id),
  name text NOT NULL,
  departure_time time NOT NULL,
  start_date date NOT NULL,
  end_date date NOT NULL CHECK(end_date>=start_date),
  weekdays integer[] NOT NULL,
  excluded_dates date[] NOT NULL DEFAULT '{}',
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE bus_plan_instances (
  plan_id uuid REFERENCES bus_service_plans(id),
  service_date date NOT NULL,
  trip_id uuid UNIQUE NOT NULL REFERENCES trip_instances(id),
  PRIMARY KEY(plan_id,service_date)
);
