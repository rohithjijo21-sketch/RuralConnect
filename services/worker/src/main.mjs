import pg from 'pg';
const pool = new pg.Pool({ connectionString: process.env.DATABASE_URL, max: 2 });
if (!process.env.DATABASE_URL) throw Error('DATABASE_URL required');
let stopped = false;
for (const signal of ['SIGINT', 'SIGTERM'])
  process.on(signal, () => {
    stopped = true;
  });
// Durable inbox exists. External delivery stays visibly blocked until an adapter is configured.
while (!stopped) {
  try {
    await pool.query("UPDATE notifications SET status='AWAITING_PROVIDER' WHERE status='PENDING'");
    await pool.query(
      "DELETE FROM vehicle_location_history WHERE received_at<now()-interval '24 hours'",
    );
    await pool.query('DELETE FROM used_refresh_tokens WHERE expires_at<now()');
    await pool.query("DELETE FROM otp_challenges WHERE expires_at<now()-interval '1 hour'");
    await pool.query("DELETE FROM rate_limits WHERE window_start<now()-interval '1 day'");
  } catch (error) {
    console.error(
      JSON.stringify({ level: 'error', component: 'worker', code: error.code ?? 'unknown' }),
    );
  }
  await new Promise((resolve) => setTimeout(resolve, 5000));
}
await pool.end();
