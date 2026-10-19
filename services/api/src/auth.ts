import {
  Injectable,
  UnauthorizedException,
  ForbiddenException,
  HttpException,
} from '@nestjs/common';
import { z } from 'zod';
import { pool, transaction } from './db.js';
import { hash, token, type Actor, type Role } from './domain.js';
export const phoneSchema = z.string().regex(/^\+91[6-9][0-9]{9}$/);
@Injectable()
export class Auth {
  async rate(key: string, limit: number, seconds: number) {
    const { rows } = await pool.query(
      "INSERT INTO rate_limits(key,window_start,count) VALUES($1,now(),1) ON CONFLICT(key) DO UPDATE SET count=CASE WHEN rate_limits.window_start < now()-($2::int * interval '1 second') THEN 1 ELSE rate_limits.count+1 END,window_start=CASE WHEN rate_limits.window_start < now()-($2::int * interval '1 second') THEN now() ELSE rate_limits.window_start END RETURNING count",
      [key, seconds],
    );
    if (rows[0].count > limit) throw new HttpException('Request limit exceeded', 429);
  }
  async request(phone: string, sandboxKey: string, ip: string) {
    phoneSchema.parse(phone);
    await this.rate('otp-ip:' + hash(ip), 20, 3600);
    await this.rate('otp-phone:' + hash(phone), 5, 3600);
    const sandbox = process.env.OTP_MODE === 'sandbox';
    if (!sandbox) throw new ForbiddenException('OTP provider is not configured');
    if (
      process.env.NODE_ENV === 'production' ||
      !process.env.SANDBOX_ACCESS_KEY ||
      hash(sandboxKey) !== hash(process.env.SANDBOX_ACCESS_KEY)
    )
      throw new ForbiddenException('Sandbox access denied');
    const code = process.env.SANDBOX_OTP_CODE;
    if (!code || !/^\d{6}$/.test(code)) throw new ForbiddenException('Configure sandbox OTP');
    // Sandbox is fixture-only and cannot register arbitrary phone numbers.
    if (
      !(
        await pool.query(
          'SELECT 1 FROM users WHERE phone=$1 AND deleted_at IS NULL AND NOT suspended',
          [phone],
        )
      ).rowCount
    )
      throw new ForbiddenException('Unknown sandbox fixture');
    const salt = token();
    const { rows } = await pool.query(
      "INSERT INTO otp_challenges(phone,code_hash,expires_at) VALUES($1,$2,now()+interval '5 minutes') RETURNING id",
      [phone, salt + ':' + hash(salt + code)],
    );
    return {
      challengeId: rows[0].id,
      mode: 'sandbox',
      message: 'Use the locally configured fixture OTP. No SMS was sent.',
    };
  }
  async verify(challengeId: string, code: string, consentVersion: string) {
    if (process.env.NODE_ENV === 'production' || process.env.OTP_MODE !== 'sandbox') {
      throw new ForbiddenException('Sandbox OTP is disabled');
    }
    const result = await transaction(async (db) => {
      const row = (
        await db.query('SELECT * FROM otp_challenges WHERE id=$1 FOR UPDATE', [challengeId])
      ).rows[0];
      if (!row || row.consumed || row.attempts >= 5 || row.expires_at < new Date()) return null;
      await db.query('UPDATE otp_challenges SET attempts=attempts+1 WHERE id=$1', [challengeId]);
      const [salt, expected] = row.code_hash.split(':');
      if (hash(salt + code) !== expected) return null;
      const user = (
        await db.query(
          'SELECT id FROM users WHERE phone=$1 AND NOT suspended AND deleted_at IS NULL',
          [row.phone],
        )
      ).rows[0];
      if (!user) return null;
      await db.query('UPDATE otp_challenges SET consumed=true WHERE id=$1', [challengeId]);
      await db.query('INSERT INTO consent_records(user_id,version) VALUES($1,$2)', [
        user.id,
        consentVersion,
      ]);
      const accessToken = token(),
        refreshToken = token();
      await db.query(
        "INSERT INTO sessions(user_id,access_hash,refresh_hash,access_expires,refresh_expires) VALUES($1,$2,$3,now()+interval '15 minutes',now()+interval '30 days')",
        [user.id, hash(accessToken), hash(refreshToken)],
      );
      return { accessToken, refreshToken, expiresIn: 900 };
    });
    if (!result) throw new UnauthorizedException('OTP invalid or expired');
    return result;
  }
  async redeemBeta(phone: string, code: string, consentVersion: string, ip: string) {
    if (process.env.BETA_AUTH_ENABLED !== 'true')
      throw new ForbiddenException('Beta sign-in is disabled');
    phoneSchema.parse(phone);
    await this.rate('beta-ip:' + hash(ip), 20, 3600);
    await this.rate('beta-phone:' + hash(phone), 10, 3600);
    const result = await transaction(async (db) => {
      // Match the owner issue/revoke lock order: account first, invitation second.
      // This also serializes revocation against session issuance.
      const user = (
        await db.query(
          "SELECT u.id FROM users u WHERE u.phone=$1 AND NOT u.suspended AND u.deleted_at IS NULL AND EXISTS(SELECT 1 FROM user_roles r WHERE r.user_id=u.id AND r.role IN ('PASSENGER','DRIVER','BUS_CREW')) AND NOT EXISTS(SELECT 1 FROM user_roles r WHERE r.user_id=u.id AND r.role IN ('OPERATOR','ADMIN')) FOR UPDATE OF u",
          [phone],
        )
      ).rows[0];
      if (!user) return null;
      const row = (
        await db.query(
          'SELECT id,user_id FROM beta_invites WHERE user_id=$1 AND token_hash=$2 AND consumed_at IS NULL AND expires_at>now() FOR UPDATE',
          [user.id, hash(code)],
        )
      ).rows[0];
      if (!row) return null;
      await db.query('UPDATE beta_invites SET consumed_at=now() WHERE id=$1', [row.id]);
      await db.query('INSERT INTO consent_records(user_id,version) VALUES($1,$2)', [
        row.user_id,
        consentVersion,
      ]);
      const accessToken = token(),
        refreshToken = token();
      await db.query(
        "INSERT INTO sessions(user_id,access_hash,refresh_hash,access_expires,refresh_expires) VALUES($1,$2,$3,now()+interval '15 minutes',now()+interval '30 days')",
        [row.user_id, hash(accessToken), hash(refreshToken)],
      );
      return { accessToken, refreshToken, expiresIn: 900 };
    });
    if (!result) throw new UnauthorizedException('Invitation invalid, expired or already used');
    return result;
  }
  async actor(header: string | undefined): Promise<Actor> {
    if (!header?.startsWith('Bearer ')) throw new UnauthorizedException();
    const { rows } = await pool.query(
      'SELECT u.id,array_agg(r.role) roles FROM sessions s JOIN users u ON u.id=s.user_id JOIN user_roles r ON r.user_id=u.id WHERE s.access_hash=$1 AND NOT s.revoked AND s.access_expires>now() AND NOT u.suspended AND u.deleted_at IS NULL GROUP BY u.id',
      [hash(header.slice(7))],
    );
    if (!rows[0]) throw new UnauthorizedException();
    return rows[0];
  }
  require(actor: Actor, ...allowed: Role[]) {
    if (!actor.roles.some((r) => allowed.includes(r))) throw new ForbiddenException();
  }
  async refresh(value: string) {
    const result = await transaction(async (db) => {
      const old = hash(value);
      await db.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))', [old]);
      const reused = (
        await db.query('SELECT session_id FROM used_refresh_tokens WHERE hash=$1', [old])
      ).rows[0];
      if (reused) {
        await db.query('UPDATE sessions SET revoked=true WHERE id=$1', [reused.session_id]);
        return null;
      }
      const session = (
        await db.query(
          'SELECT s.* FROM sessions s JOIN users u ON u.id=s.user_id WHERE refresh_hash=$1 AND NOT revoked AND refresh_expires>now() AND NOT u.suspended AND u.deleted_at IS NULL FOR UPDATE OF s',
          [old],
        )
      ).rows[0];
      if (!session) return null;
      const accessToken = token(),
        refreshToken = token();
      await db.query(
        'INSERT INTO used_refresh_tokens(hash,session_id,expires_at) VALUES($1,$2,$3)',
        [old, session.id, session.refresh_expires],
      );
      await db.query(
        "UPDATE sessions SET access_hash=$1,refresh_hash=$2,access_expires=now()+interval '15 minutes' WHERE id=$3",
        [hash(accessToken), hash(refreshToken), session.id],
      );
      return { accessToken, refreshToken, expiresIn: 900 };
    });
    if (!result) throw new UnauthorizedException('Refresh token expired or reused');
    return result;
  }
  async logout(header: string) {
    await this.actor(header);
    await pool.query('UPDATE sessions SET revoked=true WHERE access_hash=$1', [
      hash(header.slice(7)),
    ]);
    return { revoked: true };
  }
}
