import { z } from 'zod';
import { pool, transaction } from '../src/db.js';
const [kindInput, idInput, decisionInput, ...notes] = process.argv.slice(2);
try {
  if (process.env.OWNER_REVIEW_ENABLED !== 'true')
    throw Error(
      'Trusted owner review is disabled. Set OWNER_REVIEW_ENABLED=true only on the trusted workstation.',
    );
  const kind = z.enum(['operator', 'vehicle']).parse(kindInput),
    id = z.uuid().parse(idInput),
    decision = z.enum(['APPROVE', 'REJECT']).parse(decisionInput),
    note = z.string().trim().min(12).max(1000).parse(notes.join(' '));
  await transaction(async (db) => {
    let operatorId: string;
    if (kind === 'operator') {
      const row = (await db.query('SELECT * FROM bus_owners WHERE operator_id=$1 FOR UPDATE', [id]))
        .rows[0];
      if (!row) throw Error('Owner workspace not found');
      operatorId = id;
      await db.query('UPDATE bus_owners SET status=$1 WHERE operator_id=$2', [
        decision === 'APPROVE' ? 'APPROVED' : 'REJECTED',
        id,
      ]);
      await db.query('UPDATE operators SET verified=$1 WHERE id=$2', [decision === 'APPROVE', id]);
    } else {
      const row = (
        await db.query(
          "SELECT v.*,b.status FROM vehicles v JOIN bus_owners b ON b.operator_id=v.operator_id WHERE v.id=$1 AND v.category='BUS' FOR UPDATE OF v,b",
          [id],
        )
      ).rows[0];
      if (!row) throw Error('Bus in owner workspace not found');
      if (decision === 'APPROVE' && row.status !== 'APPROVED')
        throw Error('Approve the operator after reviewing their evidence first');
      operatorId = row.operator_id;
      await db.query('UPDATE vehicles SET approved=$1 WHERE id=$2', [decision === 'APPROVE', id]);
    }
    await db.query(
      'INSERT INTO audit_logs(operator_id,action,resource_id,detail) VALUES($1,$2,$3,$4)',
      [
        operatorId,
        'owner-review.' + kind,
        id,
        JSON.stringify({ decision, note, source: 'trusted_owner_cli' }),
      ],
    );
  });
  console.log('Review recorded. No account role or privileged invitation created.');
} finally {
  await pool.end();
}
