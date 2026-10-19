import { pool, transaction } from '../src/db.js';
import { phoneSchema } from '../src/auth.js';
import { hash, token } from '../src/domain.js';
import { z } from 'zod';
// Owner-only CLI. No public endpoint may issue invites or choose roles.
const [phoneInput, roleInput, outputPath] = process.argv.slice(2);
try {
  if (process.env.BETA_AUTH_ENABLED !== 'true') throw Error('Set BETA_AUTH_ENABLED=true first');
  const phone = phoneSchema.parse(phoneInput);
  const role = z.enum(['PASSENGER', 'DRIVER', 'BUS_CREW']).parse(roleInput);
  if (!outputPath)
    throw Error('Usage: beta:invite +91PHONE PASSENGER|DRIVER|BUS_CREW PRIVATE_OUTPUT_FILE');
  const code = token();
  // Reserve a private file before changing the database; never overwrite an existing secret.
  const { open } = await import('node:fs/promises');
  const out = await open(outputPath, 'wx', 0o600);
  try {
    const id = await transaction(async (db) => {
      await db.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))', [phone]);
      let user = (await db.query('SELECT * FROM users WHERE phone=$1 FOR UPDATE', [phone])).rows[0];
      if (!user) {
        user = (await db.query('INSERT INTO users(phone) VALUES($1) RETURNING *', [phone])).rows[0];
        await db.query('INSERT INTO user_roles(user_id,role) VALUES($1,$2)', [user.id, role]);
        if (role === 'PASSENGER')
          await db.query('INSERT INTO passenger_profiles(user_id) VALUES($1)', [user.id]);
        if (role === 'DRIVER')
          await db.query('INSERT INTO driver_profiles(user_id) VALUES($1)', [user.id]);
      }
      const roles = (
        await db.query('SELECT role FROM user_roles WHERE user_id=$1', [user.id])
      ).rows.map((r) => r.role);
      if (user.suspended || user.deleted_at || roles.length !== 1 || roles[0] !== role)
        throw Error(
          'Account unavailable or role mismatch. This command cannot elevate existing accounts.',
        );
      await db.query(
        'UPDATE beta_invites SET consumed_at=now() WHERE user_id=$1 AND consumed_at IS NULL',
        [user.id],
      );
      await db.query(
        "INSERT INTO beta_invites(user_id,token_hash,expires_at) VALUES($1,$2,now()+interval '7 days')",
        [user.id, hash(code)],
      );
      return user.id;
    });
    await out.writeFile(
      `RuralConnect private beta invitation\nPhone: ${phone}\nRole: ${role}\nOne-time invitation code: ${code}\nExpires in 7 days. Keep private. No SMS is sent and phone ownership is not verified.\nDriver approval, vehicle approval and crew assignments are separate.\nAccount: ${id}\n`,
    );
    console.log('Invitation written to the private output file. No code printed.');
  } finally {
    await out.close();
  }
} finally {
  await pool.end();
}
