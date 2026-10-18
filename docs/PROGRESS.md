# Implementation plan and progress

Last updated: 18 October 2026. No phase is labelled complete while required work remains. See DELIVERY_STATUS.md.

| Phase          | Delivered work                                                                                                                        | Remaining before phase completion                                                                                                            |
| -------------- | ------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| 0 Architecture | ADRs, product scope, ERD, permissions, event catalogue, state diagrams, navigation, risk register, milestones                         | approved stakeholder requirements, full API typing, data/legal review                                                                        |
| 1 Foundation   | monorepo, NestJS, SQL migrations, sandbox sessions, roles, mobile sources, admin, Compose, CI sources                                 | production OTP/MFA, native mobile projects/verification, provider adapters, native DB CI evidence                                            |
| 2 Bus          | route creation, dated assignment, crew start, GPS validation, delay/cancel/reinstate, passenger search, durable events, HTTP/WS tests | recurring calendar materialisation/exceptions UI, notifications delivery, nearby spatial search, map UI/ETA, replacements, device E2E        |
| 3 Auto         | eligibility, availability, atomic private acceptance/state transitions, cash ledger, API tests                                        | document approval, proximity offers/timeouts, private tracking, full client UI, finances/payouts                                             |
| 4 Shared       | ordered stops, segment-capacity locking, duplicate prevention, cancellation/status, reservation client                                | draft editor, expiry worker, targeted broadcasts, realtime private channels; shared publishing/boarding/no-show UI now authored and analyzed |
| 5 Payments     | integer paise schema, tested cash ledger/idempotency                                                                                  | approved gateway adapter + sandbox credentials, intents, webhook signatures, refunds/reconciliation/receipts/payouts                         |
| 6 Planning     | graph design only                                                                                                                     | actual GTFS/manual-data ingestion, walking/road provider, multimodal graph search and ranking                                                |
| 7 Release      | initial tests/builds, explicit gates and operations procedures                                                                        | mobile/native DB testing, security/accessibility review, staging, UAT, monitoring and restore drill                                          |

## Environment and verification record

- Empty GitHub repository cloned; no existing application or repository instructions.
- Node v24.19.0 and Git available; Flutter/Dart initially absent; SDK 3.47.7/3.13.5 installed into workspace work/ and validated. Docker/native PostgreSQL and Android SDK remain absent locally.
- Backend TypeScript compilation passed. Admin TypeScript and Next.js production build passed.
- Nine domain tests passed.
- Both SQL migrations applied to embedded PostgreSQL/PostGIS. Embedded integration: bus isolation/GPS/status/notification/seat race; HTTP OTP/session reuse/WebSocket replay/private ride/cash ledger passed.
- Embedded socket multiplexer serialises database access differently from native PostgreSQL. Its race test is not sufficient proof of production concurrency behavior; run native PostgreSQL CI.
- Flutter 3.47.7/Dart 3.13.5: analysis passed for all three apps and mobile_core; three smoke tests plus four shared interaction tests passed. Native targets and locks committed. Android/iOS builds and actual-device E2E remain pending. Native PostgreSQL platform CI passed on initial commit; updated CI is being verified.
- No live location was seeded; real device GPS is required. No SMS/UPI/FCM external delivery occurred.

## Immediate next milestones

1. Execute native PostgreSQL CI and fix any engine-specific failures; expand API/authorisation/adversarial tests.
2. Install Flutter/Android toolchain; generate native projects, configure permissions, resolve packages, analyze/test/build and verify all three clients against the API on devices.
3. Complete operator recurring-calendar workflows and FCM delivery with an approved provider.
4. Complete driver onboarding and full private/shared client workflows before commercial booking enablement.
5. Implement gateway sandbox, signed webhooks, reconciliation/refunds, route graph planner and safety/support.
6. Complete legal/privacy/transport review, monitoring and recovery drills, then staging UAT.

Additional evidence: initial GitHub platform CI passed against native PostgreSQL/PostGIS. Flutter 3.47.7/Dart 3.13.5 now installed locally; 3 smoke + 4 interaction tests pass, native targets/locks committed, debug APK CI added. Driver shared publish/boarding sources now exist; expiry/targeted push remain incomplete.
