# API and event catalogue

REST base: /v1. Contract: packages/api-contracts/openapi.json. Authentication: Bearer opaque access token. No access token is accepted in a URL. Zod rejects unknown payload fields. Rate limits are persisted in PostgreSQL and return HTTP 429. Operator scope comes from membership, never an unverified header. HTTP POST success is 201.

| Event topic     | Transactional trigger    | Public payload                          | Consumer                |
| --------------- | ------------------------ | --------------------------------------- | ----------------------- |
| bus.created.v1  | dated service created    | tripId, status                          | service refetch         |
| bus.status.v1   | valid trip transition    | tripId, status, delayMinutes, version   | passenger/crew/operator |
| bus.location.v1 | accepted timestamped GPS | tripId, lat, lng, accuracyM, recordedAt | passenger/crew/operator |

Envelope: id (decimal string; treat as 64-bit cursor), topic, version, payload, created_at. No actor phone, session, document or private-booking payload is published on bus feeds.

WebSocket URL: /v1/live?tripId=UUID&after=CURSOR, with Authorization header. Native Flutter supports this; the browser operator portal uses refetch because browser WebSockets cannot supply arbitrary headers. The server revalidates the session on every poll. Malformed frames cannot mutate data. Sockets receive a maximum of 100 events per poll and close under backpressure. Polling/refetch handles disconnects; cursor deduplication handles replay. Expired/rotated sessions require reconnection with a valid token.

REST replay: GET /bus/trips/{id}/events?after=CURSOR. Replay is historical, not evidence that a location is current. Always refetch the trip and apply recorded_at freshness before showing live data. No Redis Pub/Sub, FCM push delivery, shared-trip/private-booking socket events, retention cursor expiry or horizontal-scaling guarantees exist yet.

Errors: 400 invalid input; 401 missing/expired session; 403 role/resource denial; 404 unavailable resource; 409 stale version/capacity/state/idempotency conflict; 429 rate limit; 500 redacted internal error. Mutating booking requests require an Idempotency-Key (8–100 characters); keys are actor-scoped and bound to the exact request digest. Retry with the same key and input. Never mark an offline request confirmed.
