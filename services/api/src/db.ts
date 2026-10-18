import { Pool, type PoolClient } from 'pg';
export const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  max: 15,
  connectionTimeoutMillis: 5000,
  statement_timeout: 10000,
});
export async function transaction<T>(fn: (db: PoolClient) => Promise<T>): Promise<T> {
  const db = await pool.connect();
  try {
    await db.query('BEGIN');
    const result = await fn(db);
    await db.query('COMMIT');
    return result;
  } catch (error) {
    await db.query('ROLLBACK');
    throw error;
  } finally {
    db.release();
  }
}
