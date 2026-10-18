# RuralConnect delivery status

18 October 2026 — development implementation. **No phase or platform is production ready.** Classification uses the requested vocabulary. “Implemented and tested” only covers the scope explicitly stated in the evidence column. Untested native mobile and external integrations are not implied by passing backend tests.

| Major requirement                                           | Status                     | Evidence / remaining work                                                                                         |
| ----------------------------------------------------------- | -------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| Monorepo, NestJS API and Next.js portal                     | Implemented and tested     | API TS compile; admin TS and production build pass                                                                |
| Architecture, PRD, ERD, roles, state diagrams and plan      | Partially implemented      | docs/architecture, product, api, compliance, PROGRESS; stakeholder/legal review pending                           |
| PostgreSQL/PostGIS models and migrations                    | Implemented and tested     | both migrations applied to embedded PostgreSQL/PostGIS; native container verification pending                     |
| Spatial indexes, constraints, locks, dated trips            | Implemented and tested     | embedded route/trip/reservation tests; native locking behavior still needs verification                           |
| Phone OTP                                                   | Partially implemented      | tested fixture-only sandbox; no SMS sent, provider onboarding blocked                                             |
| Access/refresh sessions, reuse revocation, logout           | Implemented and tested     | HTTP integration rotates and rejects replay, DB stores digests                                                    |
| Server roles, bus assignments and tenant isolation          | Implemented and tested     | forbidden passenger update and cross-operator mutation assertions                                                 |
| Production authentication / admin MFA                       | Blocked                    | approved OTP/identity provider credentials and implementation needed                                              |
| Registration / permission onboarding                        | Partially implemented      | sandbox login, explicit foreground GPS permission; real registration pending                                      |
| Profile, preferred language and consent                     | Partially implemented      | API records/profile update; mobile profile and approved notices pending                                           |
| Account deletion / export                                   | Partially implemented      | pending request records only; no fulfilment falsely claimed                                                       |
| Device token registration                                   | Implemented but unverified | endpoint and ownership upsert; no FCM delivery                                                                    |
| Passenger Flutter app                                       | Partially implemented      | API-backed login/search/trip/events/shared request sources; SDK/build/device execution unavailable                |
| Auto/taxi Driver Flutter app                                | Partially implemented      | independent entry, login, owned vehicles and online/offline; booking/publishing/onboarding UI pending             |
| Bus Flutter app                                             | Partially implemented      | assigned trip/state/reason/foreground GPS sources; not built or device tested                                     |
| Independent native Android/iOS targets                      | Partially implemented      | per-app source/pubspec and bootstrap script; generated projects/signing/branding pending                          |
| Riverpod, GoRouter, Dio, secure storage                     | Implemented but unverified | mobile_core sources; package resolution and native tests pending                                                  |
| Shared typed API contracts/client                           | Partially implemented      | OpenAPI and generated TS types; mobile uses shared Dio wrapper, full Dart generation pending                      |
| English/Malayalam                                           | Partially implemented      | locale delegates and selected headings; complete translation/review pending                                       |
| Home: location, nearby vehicles/stops, favourites, recent   | Not started                | manual bus stop-name search only                                                                                  |
| Journey alternatives / multimodal graph / GTFS              | Not started                | graph design documented; no operational planner                                                                   |
| Bus origin-destination search and stop sequence             | Implemented and tested     | ordered route stops, date/name query, backend integration                                                         |
| Live bus details/freshness and schedule fallback            | Implemented and tested     | server freshness and terminal-state suppression tests; native map UI pending                                      |
| Nearby stop geographic queries                              | Not started                | spatial schema exists; no nearby API/UI                                                                           |
| Operator routes/stops creation                              | Implemented and tested     | membership, monotonic offsets and route versions in integration                                                   |
| Dated service, bus/crew assignment                          | Implemented and tested     | own-operator/approved bus/crew checks and audit                                                                   |
| Recurring calendars and holiday exceptions                  | Partially implemented      | schema separates schedules/instances; no materialisation or operator editor                                       |
| Bus start, delay, breakdown, cancel/reinstate               | Implemented and tested     | API/DB/HTTP tests; recurring service never deleted                                                                |
| Operator incidents/replacement buses/analytics              | Partially implemented      | incidents persist; replacement and analytics pending                                                              |
| Real GPS upload                                             | Partially implemented      | tested timestamp/velocity/state validation, Flutter foreground source; device integration pending                 |
| Background GPS/offline bounded queue                        | Not started                | intentionally no background-tracking claim                                                                        |
| ETA/map matching/stop detection                             | Not started                | ETA returned null; no fabricated live arrivals                                                                    |
| Real-time bus WebSocket/refetch/replay                      | Implemented and tested     | authenticated HTTP/WS integration and durable event replay                                                        |
| Shared/private realtime channels                            | Not started                | shared/private state is REST only                                                                                 |
| Alert subscriptions/inbox                                   | Partially implemented      | opt-in DB records and transactional outbox assertions; delivery blocked                                           |
| FCM/SMS/email provider                                      | Blocked                    | credentials, adapter and delivery/retry review needed                                                             |
| Driver profiles/documents/expiry/verification               | Partially implemented      | schema + approved-only eligibility; secure upload/review/onboarding missing                                       |
| Private booking creation/atomic acceptance/state            | Implemented and tested     | API lifecycle with category/online/approval checks; matching/offer flow incomplete                                |
| Proximity matching/timeouts/rejection                       | Not started                | no automatic nearby offers; acceptance currently requires booking ID                                              |
| Private tracking/pickup verification/history/receipt/rating | Partially implemented      | owned booking list/state API and schema; secure pickup/tracking/receipt/rating UI pending                         |
| Shared trip publishing/stops/status                         | Partially implemented      | validated API with approved auto/capacity; draft editor, reasons/audit and driver UI pending                      |
| Share-auto segment capacity/duplicate protection            | Implemented and tested     | trip-row lock, overlapping occupancy, unique reservation, idempotent replay and competing requests in embedded DB |
| Passenger seat reservation                                  | Partially implemented      | one-seat first-to-final mobile source; full seat/stop picker and mobile tests pending                             |
| Reservation cancellation                                    | Implemented but unverified | row-locked backend policy before departure; more cancellation races pending                                       |
| Boarding/no-show/expiry/availability controls               | Partially implemented      | completion status handling/schema only; explicit boarding and expiry worker missing                               |
| Targeted opt-in share broadcast                             | Not started                | no mass notification sent                                                                                         |
| Cash settlement and immutable ledger                        | Implemented and tested     | completed-driver-only, balanced integer ledger, retry identity and immutable update assertions                    |
| Gateway/UPI integration and signed webhooks                 | Blocked                    | approved provider/sandbox credentials and implementation needed; disabled                                         |
| Refunds/failed payments/reconciliation/payouts              | Not started                | schema only; no financial provider success claimed                                                                |
| Safety/SOS/trip sharing/block/report/support                | Not started                | schema for complaints/support only; no dispatch claim                                                             |
| Operator dashboard                                          | Partially implemented      | build-verified routes, dated assignments, status and audit; fleet editor/maps/full portal pending                 |
| Full system administration                                  | Partially implemented      | server ADMIN permission branch; user/doc/refund/dispute/settings UI pending                                       |
| Offline/cache/retry                                         | Partially implemented      | cached schedule source, explicit offline, socket backoff/refetch; no offline mutation confirmation                |
| Accessible visual system/light/dark                         | Partially implemented      | Material3 and responsive admin tokens; independent accessibility/device review pending                            |
| Security input validation/rate limit/redaction              | Partially implemented      | strict Zod, persistent limits, digested tokens, redacted errors; abuse/penetration review pending                 |
| Sensitive uploads/encryption/secrets                        | Partially implemented      | env config, no committed secrets; upload scanning/KMS/TLS deployment pending                                      |
| Retention/privacy rights                                    | Partially implemented      | worker defaults and request records; legal approval and fulfilment pending                                        |
| Unit tests                                                  | Implemented and tested     | nine domain tests pass; full auth/matching/calendar/payment unit coverage pending                                 |
| Embedded database/API/WebSocket integration                 | Implemented and tested     | two integration scenarios pass; experimental engine/multiplexer limitation documented                             |
| Native PostgreSQL race tests                                | Implemented but unverified | integration suite + CI source; native engine not available locally                                                |
| Flutter widget tests                                        | Implemented but unverified | sign-in smoke tests authored; no Flutter runtime available                                                        |
| Full mobile/browser E2E                                     | Not started                | HTTP workflows pass; no actual multi-device acceptance test                                                       |
| Docker/Compose/local migration/seed                         | Implemented but unverified | source authored; Docker absent; migration/seed verified on embedded DB                                            |
| Worker                                                      | Partially implemented      | provider-blocked inbox state and retention source; worker runtime test pending                                    |
| Redis cache/queue                                           | Not started                | local service provisioned only; backend uses PostgreSQL                                                           |
| CI/static analysis/dependency audit                         | Implemented but unverified | workflow authored; remote CI outcome pending push/run                                                             |
| Staging/prod templates and health                           | Partially implemented      | health/readiness, Docker and runbook; staging not provisioned/deployed                                            |
| Monitoring/tracing/crash reporting                          | Partially implemented      | redacted server errors + monitoring checklist; providers unconfigured                                             |
| Backup/restore/rollback/disaster recovery                   | Implemented but unverified | procedures only; no restore drill performed                                                                       |
| National/Kerala privacy/payment/transport review            | Blocked                    | qualified current review and commercial permissions required                                                      |
| Staging UAT / production deployment                         | Not started                | no authorisation, credentials or completed release gates                                                          |

## Verified commands

- Backend TypeScript compilation and admin TypeScript checking: passed.
- Next.js 16.4.2 production build: passed.
- Domain tests: 9 passed.
- Embedded PostgreSQL/PostGIS migrations: both applied; seed succeeded.
- Embedded integration suites: 2 passed, including HTTP/WebSocket/session/private/cash and bus/seat-capacity tests.

Run native PostgreSQL CI, Flutter tests/builds and real-device E2E before advancing release claims. Integration fixtures are local, explicitly demo-labelled and never seed fake successful trips, live coordinates or payments. Test scenarios intentionally generate local synthetic activity and do not represent commercial operations.
