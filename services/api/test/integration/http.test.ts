import test from 'node:test';
import assert from 'node:assert/strict';
import { WebSocket } from 'ws';
const enabled = process.env.RUN_DB_TESTS === '1';
test(
  'OTP sessions, bus HTTP update, authenticated WebSocket replay and cash ledger',
  { skip: !enabled },
  async () => {
    process.env.RURALCONNECT_TEST_IMPORT = '1';
    process.env.OTP_MODE = 'sandbox';
    process.env.SANDBOX_ACCESS_KEY = 'integration-test-only';
    process.env.SANDBOX_OTP_CODE = '849321';
    const { bootstrap } = await import('../../src/main.js');
    const { pool } = await import('../../src/db.js');
    const app = await bootstrap(0);
    const address = app.getHttpServer().address();
    const base = 'http://127.0.0.1:' + address.port + '/v1';
    let socket: WebSocket | undefined;
    async function request(
      path: string,
      method = 'GET',
      body?: unknown,
      access?: string,
      extra: Record<string, string> = {},
    ) {
      const r = await fetch(base + path, {
        method,
        headers: {
          'Content-Type': 'application/json',
          ...(access ? { Authorization: 'Bearer ' + access } : {}),
          ...extra,
        },
        body: body ? JSON.stringify(body) : undefined,
      });
      return { status: r.status, data: (await r.json()) as any };
    }
    async function login(phone: string) {
      const challenge = await request('/auth/otp/request', 'POST', { phone }, undefined, {
        'X-Sandbox-Key': process.env.SANDBOX_ACCESS_KEY!,
      });
      assert.equal(challenge.status, 201);
      const result = await request('/auth/otp/verify', 'POST', {
        challengeId: challenge.data.challengeId,
        code: process.env.SANDBOX_OTP_CODE,
        consentVersion: 'test-v1',
      });
      assert.equal(result.status, 201);
      return result.data;
    }
    try {
      const healthy = await fetch(base + '/health');
      assert.match(healthy.headers.get('x-request-id') ?? '', /^[a-f0-9-]{36}$/);
      assert.equal(healthy.headers.get('cache-control'), 'no-store');
      assert.equal(healthy.headers.get('x-powered-by'), null);
      const oversized = await fetch(base + '/auth/otp/request', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ phone: 'x'.repeat(70000) }),
      });
      assert.equal(oversized.status, 413);
      const malformed = await fetch(base + '/auth/otp/request', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: '{',
      });
      assert.equal(malformed.status, 400);
      const passenger = await login('+919000000001'),
        crew = await login('+919000000003'),
        driver = await login('+919000000002');
      assert.equal(
        (await request('/bus/trips?date=bad', 'GET', undefined, passenger.accessToken)).status,
        400,
      );
      assert.equal((await request('/crew/trips')).status, 401);
      const trips = await request('/crew/trips', 'GET', undefined, crew.accessToken);
      assert.equal(trips.status, 200);
      const trip = trips.data[0];
      assert.ok(trip.id);
      assert.equal(
        (
          await request(
            '/bus/trips/' + trip.id + '/status',
            'POST',
            { status: 'BOARDING', reason: 'Ready', delayMinutes: 0, version: trip.version },
            passenger.accessToken,
          )
        ).status,
        403,
      );
      const boarding = await request(
        '/bus/trips/' + trip.id + '/status',
        'POST',
        { status: 'BOARDING', reason: 'Ready', delayMinutes: 0, version: trip.version },
        crew.accessToken,
      );
      assert.equal(boarding.status, 201);
      const running = await request(
        '/bus/trips/' + trip.id + '/status',
        'POST',
        { status: 'RUNNING', reason: 'Started', delayMinutes: 0, version: boarding.data.version },
        crew.accessToken,
      );
      assert.equal(running.status, 201);
      assert.equal(
        (
          await request(
            '/bus/trips/' + trip.id + '/location',
            'POST',
            { lat: 10.06, lng: 76.63, accuracyM: 12, recordedAt: new Date().toISOString() },
            crew.accessToken,
          )
        ).status,
        201,
      );
      assert.equal(
        (await request('/bus/trips/' + trip.id, 'GET', undefined, passenger.accessToken)).data
          .locationQuality,
        'LIVE',
      );
      socket = new WebSocket(base.replace('http', 'ws') + '/live?tripId=' + trip.id + '&after=0', {
        headers: { Authorization: 'Bearer ' + passenger.accessToken },
      });
      const event = await new Promise<any>((resolve, reject) => {
        const timeout = setTimeout(() => reject(Error('WebSocket replay timed out')), 10000);
        socket!.on('message', (raw) => {
          const e = JSON.parse(raw.toString());
          if (e.topic === 'bus.status.v1') {
            clearTimeout(timeout);
            resolve(e);
          }
        });
        socket!.on('error', reject);
      });
      assert.equal(event.payload.tripId, trip.id);
      const refresh = await request('/auth/refresh', 'POST', {
        refreshToken: passenger.refreshToken,
      });
      assert.equal(refresh.status, 201);
      assert.notEqual(refresh.data.accessToken, passenger.accessToken);
      assert.equal(
        (await request('/auth/refresh', 'POST', { refreshToken: passenger.refreshToken })).status,
        401,
      );
      assert.equal((await request('/me', 'GET', undefined, refresh.data.accessToken)).status, 401);
      const p2 = await login('+919000000001');
      await pool.query(
        "INSERT INTO fare_policies(category,base_paise,per_km_paise,version) VALUES('AUTO',2500,1500,1)",
      );
      const booking = await request(
        '/bookings',
        'POST',
        {
          pickup: { lat: 10.06, lng: 76.63 },
          dropoff: { lat: 10.07, lng: 76.63 },
          category: 'AUTO',
        },
        p2.accessToken,
        { 'Idempotency-Key': 'http-booking-1' },
      );
      assert.equal(booking.status, 201);
      const vehicle = (await request('/driver/vehicles', 'GET', undefined, driver.accessToken))
        .data[0];
      await request('/driver/availability', 'POST', { online: true }, driver.accessToken);
      assert.equal(
        (
          await request(
            '/driver/location',
            'POST',
            { lat: 10.06, lng: 76.63, accuracyM: 10, recordedAt: new Date().toISOString() },
            driver.accessToken,
          )
        ).status,
        201,
      );
      let b = (
        await request(
          '/bookings/' + booking.data.id + '/accept',
          'POST',
          { vehicleId: vehicle.id },
          driver.accessToken,
        )
      ).data;
      assert.equal(b.status, 'ACCEPTED');
      for (const status of ['ARRIVED', 'IN_PROGRESS', 'COMPLETED']) {
        if (status === 'IN_PROGRESS')
          b = (
            await request(
              '/bookings/' + b.id + '/confirm-pickup',
              'POST',
              { version: b.version },
              p2.accessToken,
            )
          ).data;
        const result = await request(
          '/bookings/' + b.id + '/status',
          'POST',
          { status, version: b.version },
          driver.accessToken,
        );
        assert.equal(result.status, 201);
        b = result.data;
      }
      const payment = await request(
        '/bookings/' + b.id + '/cash',
        'POST',
        undefined,
        driver.accessToken,
        { 'Idempotency-Key': 'cash-payment-1' },
      );
      assert.equal(payment.status, 201);
      assert.equal(payment.data.method, 'CASH');
      assert.equal(
        (
          await request('/bookings/' + b.id + '/cash', 'POST', undefined, driver.accessToken, {
            'Idempotency-Key': 'cash-payment-1',
          })
        ).data.id,
        payment.data.id,
      );
      const ledger = (
        await pool.query(
          'SELECT sum(amount_paise)::text total,count(*)::int n FROM ledger_entries WHERE payment_id=$1',
          [payment.data.id],
        )
      ).rows[0];
      assert.equal(ledger.total, '0');
      assert.equal(ledger.n, 2);
      await assert.rejects(
        pool.query('UPDATE ledger_entries SET amount_paise=0 WHERE payment_id=$1', [
          payment.data.id,
        ]),
      );
    } finally {
      socket?.terminate();
      await app.close();
      await pool.end();
    }
  },
);
