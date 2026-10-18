import { pool, transaction } from '../src/db.js';
if (process.env.NODE_ENV === 'production' || process.env.OTP_MODE !== 'sandbox')
  throw new Error('Demo seeding requires a non-production sandbox');
try {
  await transaction(async (db) => {
    const op = '10000000-0000-4000-8000-000000000001',
      route = '20000000-0000-4000-8000-000000000001',
      version = '30000000-0000-4000-8000-000000000001',
      bus = '40000000-0000-4000-8000-000000000001',
      auto = '40000000-0000-4000-8000-000000000002',
      schedule = '50000000-0000-4000-8000-000000000001';
    const ids = [
      '60000000-0000-4000-8000-000000000001',
      '60000000-0000-4000-8000-000000000002',
      '60000000-0000-4000-8000-000000000003',
      '60000000-0000-4000-8000-000000000004',
    ];
    for (const [i, role] of ['PASSENGER', 'DRIVER', 'BUS_CREW', 'OPERATOR'].entries()) {
      await db.query('INSERT INTO users(id,phone,name) VALUES($1,$2,$3) ON CONFLICT DO NOTHING', [
        ids[i],
        '+91900000000' + (i + 1),
        'DEMO ' + role,
      ]);
      await db.query('INSERT INTO user_roles(user_id,role) VALUES($1,$2) ON CONFLICT DO NOTHING', [
        ids[i],
        role,
      ]);
    }
    await db.query('INSERT INTO passenger_profiles(user_id) VALUES($1) ON CONFLICT DO NOTHING', [
      ids[0],
    ]);
    await db.query(
      "INSERT INTO driver_profiles(user_id,verification) VALUES($1,'APPROVED') ON CONFLICT DO NOTHING",
      [ids[1]],
    );
    await db.query(
      'INSERT INTO operators(id,name,verified) VALUES($1,$2,true) ON CONFLICT DO NOTHING',
      [op, 'DEMO Kerala Transport'],
    );
    for (const crew of [ids[2], ids[3]])
      await db.query(
        'INSERT INTO operator_members(operator_id,user_id) VALUES($1,$2) ON CONFLICT DO NOTHING',
        [op, crew],
      );
    await db.query(
      "INSERT INTO vehicles(id,operator_id,registration,category,capacity,approved) VALUES($1,$2,'DEMO-BUS-001','BUS',40,true) ON CONFLICT DO NOTHING",
      [bus, op],
    );
    await db.query(
      "INSERT INTO vehicles(id,driver_id,registration,category,capacity,approved) VALUES($1,$2,'DEMO-AUTO-001','AUTO',3,true) ON CONFLICT DO NOTHING",
      [auto, ids[1]],
    );
    await db.query(
      'INSERT INTO bus_routes(id,operator_id,name) VALUES($1,$2,$3) ON CONFLICT DO NOTHING',
      [route, op, 'DEMO · Kothamangalam → Muvattupuzha'],
    );
    await db.query(
      'INSERT INTO route_versions(id,route_id,version) VALUES($1,$2,1) ON CONFLICT DO NOTHING',
      [version, route],
    );
    const stops = [
      ['Kothamangalam', 10.0603, 76.6354, 0],
      ['Nellikuzhi', 10.062, 76.607, 10],
      ['Muvattupuzha', 9.9894, 76.579, 35],
    ] as const;
    for (const [i, [name, lat, lng, offset]] of stops.entries()) {
      const stop = '70000000-0000-4000-8000-00000000000' + (i + 1);
      await db.query(
        'INSERT INTO bus_stops(id,operator_id,name,point) VALUES($1,$2,$3,ST_SetSRID(ST_MakePoint($4,$5),4326)::geography) ON CONFLICT DO NOTHING',
        [stop, op, name, lng, lat],
      );
      await db.query(
        'INSERT INTO route_stops(route_version_id,stop_id,sequence,offset_minutes) VALUES($1,$2,$3,$4) ON CONFLICT DO NOTHING',
        [version, stop, i, offset],
      );
    }
    await db.query(
      "INSERT INTO scheduled_trips(id,route_version_id,departure_local) VALUES($1,$2,'09:00') ON CONFLICT DO NOTHING",
      [schedule, version],
    );
    const trip = (
      await db.query(
        "INSERT INTO trip_instances(scheduled_trip_id,operator_id,route_version_id,vehicle_id,service_date,departure_at) VALUES($1,$2,$3,$4,(now() AT TIME ZONE 'Asia/Kolkata')::date,((now() AT TIME ZONE 'Asia/Kolkata')::date+time '09:00') AT TIME ZONE 'Asia/Kolkata') ON CONFLICT(scheduled_trip_id,service_date) DO UPDATE SET scheduled_trip_id=EXCLUDED.scheduled_trip_id RETURNING id",
        [schedule, op, version, bus],
      )
    ).rows[0];
    await db.query(
      "INSERT INTO driver_assignments(trip_id,user_id,duty) VALUES($1,$2,'DRIVER') ON CONFLICT DO NOTHING",
      [trip.id, ids[2]],
    );
    await db.query(
      'INSERT INTO vehicle_assignments(vehicle_id,trip_id) VALUES($1,$2) ON CONFLICT DO NOTHING',
      [bus, trip.id],
    );
    console.log(
      'DEMO fixtures created. No GPS positions, bookings, payments or SMS were fabricated.',
    );
    console.log(
      'Passenger +919000000001; driver +919000000002; bus crew +919000000003; operator +919000000004',
    );
  });
} finally {
  await pool.end();
}
