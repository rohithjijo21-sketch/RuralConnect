import { isIP } from 'node:net';
import { z } from 'zod';

const httpsOrigin = z
  .string()
  .url()
  .refine((value) => {
    const u = new URL(value);
    return u.protocol === 'https:' && u.origin === value && !u.username && !u.password;
  }, 'must be an HTTPS origin without a path');

/** Explicit proxy addresses only: never trust a user-supplied hop count or wildcard. */
export function runtimeConfig(env: NodeJS.ProcessEnv = process.env) {
  const production = env.NODE_ENV === 'production';
  const port = z.coerce
    .number()
    .int()
    .min(1)
    .max(65535)
    .parse(env.PORT ?? '3001');
  const databaseUrl = z.string().url().parse(env.DATABASE_URL);
  const database = new URL(databaseUrl);
  if (!['postgres:', 'postgresql:'].includes(database.protocol))
    throw Error('DATABASE_URL must use PostgreSQL');
  const adminOrigin = production
    ? httpsOrigin.parse(env.ADMIN_ORIGIN)
    : z
        .string()
        .url()
        .parse(env.ADMIN_ORIGIN ?? 'http://localhost:3000');
  const trustedProxies = (env.TRUSTED_PROXY_CIDRS ?? '')
    .split(',')
    .map((v) => v.trim())
    .filter(Boolean);
  if (
    trustedProxies.some((value) => {
      const [ip, prefix, extra] = value.split('/');
      const version = isIP(ip ?? '');
      if (!version || extra !== undefined || ip === '0.0.0.0' || ip === '::') return true;
      if (prefix === undefined) return false;
      return (
        !/^\d+$/.test(prefix) || Number(prefix) < 1 || Number(prefix) > (version === 4 ? 32 : 128)
      );
    })
  )
    throw Error('TRUSTED_PROXY_CIDRS must list explicit proxy IP addresses or restricted CIDRs');
  if (production) {
    if (env.OTP_MODE !== 'disabled')
      throw Error('Production OTP remains disabled until an approved provider is integrated');
    if (env.SANDBOX_ACCESS_KEY || env.SANDBOX_OTP_CODE)
      throw Error('Remove sandbox credentials from production');
    if (env.PAYMENT_MODE !== 'disabled')
      throw Error('Digital payments must remain disabled until an approved gateway is integrated');
    if (env.REQUIRE_HTTPS !== 'true') throw Error('REQUIRE_HTTPS=true is required in production');
    if (
      database.searchParams.getAll('sslmode').length !== 1 ||
      database.searchParams.get('sslmode') !== 'verify-full'
    )
      throw Error('Production DATABASE_URL requires sslmode=verify-full');
    if (
      !database.password ||
      /^(replace-me|password|postgres|disposable-ci-only)$/.test(
        decodeURIComponent(database.password),
      )
    )
      throw Error('Production database credentials must be configured');
  }
  return {
    production,
    port,
    adminOrigin,
    trustedProxies,
    requireHttps: production || env.REQUIRE_HTTPS === 'true',
  };
}
