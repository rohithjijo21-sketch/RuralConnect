import test from 'node:test';
import assert from 'node:assert/strict';
import { runtimeConfig } from '../src/config.js';
const valid = {
  NODE_ENV: 'production',
  PORT: '3001',
  DATABASE_URL: 'postgres://app:long-unique-test-value@db.example.test/app?sslmode=verify-full',
  ADMIN_ORIGIN: 'https://admin.example.test',
  OTP_MODE: 'disabled',
  PAYMENT_MODE: 'disabled',
  REQUIRE_HTTPS: 'true',
  TRUSTED_PROXY_CIDRS: '10.0.1.4/32',
};
test('production accepts explicit TLS, origin and disabled unintegrated providers', () => {
  const c = runtimeConfig(valid);
  assert.equal(c.requireHttps, true);
  assert.deepEqual(c.trustedProxies, ['10.0.1.4/32']);
});
test('production refuses insecure or fixture configuration', () => {
  for (const patch of [
    { OTP_MODE: 'sandbox' },
    { DATABASE_URL: valid.DATABASE_URL + '&sslmode=disable' },
    { TRUSTED_PROXY_CIDRS: '999.1.1.1' },
    { SANDBOX_OTP_CODE: '123456' },
    { SANDBOX_ACCESS_KEY: 'test' },
    { PAYMENT_MODE: 'live' },
    { REQUIRE_HTTPS: 'false' },
    { DATABASE_URL: 'postgres://app:password@db/app?sslmode=verify-full' },
    { DATABASE_URL: 'postgres://app:strong@db/app?sslmode=require' },
    { ADMIN_ORIGIN: 'http://admin.example.test' },
    { ADMIN_ORIGIN: 'https://admin.example.test/path' },
    { TRUSTED_PROXY_CIDRS: 'true' },
    { TRUSTED_PROXY_CIDRS: '1' },
    { TRUSTED_PROXY_CIDRS: '0.0.0.0/0' },
  ])
    assert.throws(() => runtimeConfig({ ...valid, ...patch }));
});
test('development retains Wi-Fi sandbox access without trusting forwarded headers', () => {
  const c = runtimeConfig({
    DATABASE_URL: 'postgres://postgres:postgres@127.0.0.1/test',
    OTP_MODE: 'sandbox',
  });
  assert.equal(c.requireHttps, false);
  assert.deepEqual(c.trustedProxies, []);
});
