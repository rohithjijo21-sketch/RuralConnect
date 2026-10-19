# Implementation plan and progress

**Current scope: Android first. Further iOS development and build testing are deferred at the user’s request.**

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

Offline logout additionally clears local credentials even if server revocation cannot be reached. A dedicated Dart session test passes; total mobile tests are three app smoke tests, four UI interaction tests and one offline-session test. Server revocation is never claimed when offline.

## Android 0.2.0 phone testing
Runtime server settings, a persistent local backend and passenger UI with labelled read-only demo now support phone testing. A physical phone confirmed Wi-Fi health connectivity. The actual Dio client passed connection, sandbox sign-in, schedule/history and logout checks. Actual APK device acceptance and production release gates remain open.

## Production track started — 18 October 2026

User approved proceeding toward production, with Android first. Hosting/domain/SMS are not yet set up. First batch adds API production configuration and HTTP safeguards, HTTPS-only release client configuration, explicit Android signing and disposable-key release-bundle CI verification. This is release preparation, not production readiness; real SMS login, admin MFA, hosting, remaining product workflows and operational/device acceptance remain open. See docs/operations/production-track.md.

## SMS deferred; private beta invitations implemented

19 October 2026: user deferred SMS OTP to the first update of the real app. Added explicit opt-in invitation login, trusted CLI provisioning/revocation, single-use code migration, phone-bound redemption and all-role mobile screens. No phone ownership verification is claimed; roles/approval/assignments remain server controlled. Existing development OTP is retained for local fixtures only. Public beta hosting and a new app release are still required. See docs/operations/beta-login.md.

## Beta authentication hardening — 19 October 2026

Disabled OTP verification now rejects even pre-existing, unexpired sandbox challenges; production cannot redeem them. Invitation redemption takes the account lock before the invite lock, matching owner issuance/revocation and preventing inconsistent concurrent session issuance. Added regression checks for disabled/production OTP redemption and concurrent invite redemption versus owner revocation. API typecheck and all three embedded PostgreSQL/PostGIS integration scenarios passed. Native CI verification for this follow-up remains pending. Hosting and other production gates are unchanged; no user notification or production-readiness claim is warranted.
