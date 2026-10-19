import { pool, transaction } from '../src/db.js';
import { phoneSchema } from '../src/auth.js';
try {
  const phone = phoneSchema.parse(process.argv[2]);
  await transaction(async (db) => {
    const user = (await db.query('SELECT id FROM users WHERE phone=$1 FOR UPDATE', [phone]))
      .rows[0];
    if (!user) throw Error('Account not found');
    await db.query(
      'UPDATE beta_invites SET consumed_at=now() WHERE user_id=$1 AND consumed_at IS NULL',
      [user.id],
    );
    await db.query('UPDATE sessions SET revoked=true WHERE user_id=$1', [user.id]);
  });
  console.log('Pending invitations and active sessions revoked.');
} finally {
  await pool.end();
}
