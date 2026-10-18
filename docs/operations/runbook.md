# Operations and staging runbook

## Environment separation

Use separate database, Redis, storage, OTP/gateway projects, FCM and encryption keys for dev/staging/production. Never deploy .env, fixture OTP, fixture users or demo approved drivers. Production bootstrap refuses sandbox OTP; a production authentication provider must be implemented first. Apply least-privilege database users and require TLS. The migration role may create extensions/tables; runtime role must not be a database owner/superuser. Ledger immutability trigger is a guard, not protection against a superuser.

## Staging deployment (manual, not executed)

1. Satisfy DELIVERY_STATUS.md release blockers; provision authorised staging infrastructure.
2. Install pinned dependencies; run CI, native PostGIS integration and all Flutter checks.
3. Build image: docker build -f infrastructure/docker/Dockerfile.api -t ruralconnect-api:COMMIT .
4. Run migrations as a one-off job before traffic. Use expand/contract schema changes. No destructive automatic down migration exists.
5. Provide environment secrets through a secret manager; terminate TLS at the ingress, restrict network access, configure ADMIN_ORIGIN and NEXT_PUBLIC_API_URL to the staging endpoints.
6. Start API and worker, deploy Next.js, point all mobile builds at that API. Check /v1/ready, scoped login and the bus acceptance scenario with actual devices.
7. Enable alarms for error rate, p95 latency, DB saturation, stale GPS, notification backlog, rejected bookings and ledger discrepancies.
8. Execute operator/passenger/driver UAT and record evidence. Production deployment requires explicit authorisation. No cloud resources, credentials or deployment have been configured here.

## Backup and recovery (procedure, unverified)

Use managed encrypted PITR backups or scheduled pg_dump -Fc. Restrict access and retain recovery keys separately. Regularly restore into an isolated database using pg_restore; compare schema versions, route/service counts, financial ledger totals and user/tenant boundaries. Check PostGIS version compatibility. Record measured RPO/RTO; proposed targets must be approved rather than claimed. A successful backup command alone does not prove recoverability.

## Rollback and disaster recovery

Keep the previous signed image, lockfile and migration manifest. Roll back application images only when schema compatibility is confirmed. Restore into a new database for destructive changes; never overwrite the only surviving copy. Freeze financial writes during reconciliation, preserve audit and payment-provider evidence, validate balanced ledger entries, and resume traffic after an incident owner approves. Revoke leaked secrets/sessions, restore providers and send accurate user incident communications through an authorised workflow.

## Logging and monitoring

Nest startup logs and redacted structured internal-error logs exist. No request-body/access-token logging. Full request IDs, OpenTelemetry traces, metrics exporter, alert routing and mobile crash reporting remain unfinished. Monitoring manifests in infrastructure/monitoring describe intended checks only. Worker preserves AWAITING_PROVIDER status instead of claiming delivery.
