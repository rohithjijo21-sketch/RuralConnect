# Device and staging acceptance record

Status: **not executed**. Backend integration tests and widget tests are not substitutes for this record. Use only fixture accounts on a segregated staging environment until approved onboarding, OTP, payment and privacy workflows exist.

## Preparation

- Record API commit, app build/commit, Flutter version, devices/OS, operator and test date (Asia/Kolkata).
- Use the same API_URL in all clients. CI debug APKs target Android emulator loopback (10.0.2.2:3001); rebuild debug APKs for a physical device's reachable development/staging API. Do not use cleartext outside isolated development.
- Prepare an approved test bus, assigned crew, one operator, a passenger and an approved test auto with known capacity. Keep demo records labelled DEMO. Do not send test OTPs to real people.
- Assign an observer/conductor for data entry; drivers must remain safely parked while operating controls.
- Keep evidence (screenshots, event IDs, timestamps, audit rows and assertion results) free of personal data.

## Bus service and disruptions

1. Operator creates ordered stops/route and a dated service with own approved bus/crew. A second operator cannot inspect private resources, assign the bus or alter the service.
2. Passenger searches origin/destination without granting location permission. Confirm route order and scheduled departure; no GPS position or computed ETA should exist yet.
3. Assigned crew selects the service, supplies a reason and moves SCHEDULED → BOARDING → RUNNING. An unrelated crew/passenger must be rejected by the API.
4. While parked, crew explicitly grants foreground location and enables sharing. Passenger receives a timestamped position only after the API accepts a real fix. Record latitude/longitude, accuracy, event ID and device/server time.
5. Stop location sharing for more than 60 seconds. Passenger must display stale/unavailable GPS and no current coordinates, with scheduled information distinguished from a live ETA.
6. Report a ten-minute delay. Confirm persisted passenger status, owning-operator audit and notification inbox record. External push is not expected until configured.
7. Report breakdown/cancel the dated service. Confirm the passenger sees cancellation and no live coordinates. The recurring schedule must remain present. Only operator/admin may reinstate the dated instance.
8. Replay an event/reconnect a socket and trigger a stale version update. Verify duplicate events do not duplicate state changes, writes reject stale versions and refetch restores authoritative state.
9. Put the bus app in background, revoke permission and sign out. Confirm the application stops foreground tracking. Background tracking is not implemented and must not be reported as supported.

## Share-auto capacity and boarding

1. Approved auto driver publishes a future trip with ordered stops, capacity and an approved test fare. Invalid/unapproved driver/vehicle and over-capacity submissions are rejected.
2. Passenger discovers the trip, sees backend availability and requests a seat. No queued or offline request may appear confirmed.
3. From two clients, compete for the last seat. Exactly one request may succeed. Retry its Idempotency-Key and verify the same reservation returns; changing the payload under that key is rejected.
4. Driver sees the reservation, moves to BOARDING and confirms boarding. Unrelated actors and boarding after completion are rejected.
5. Mark a no-show only after departure. Complete the service and verify BOARDED reservations become COMPLETED and outstanding confirmed reservations become NO_SHOW.
6. Validate cancellation before departure releases segment capacity. Reservation expiry automation, digital payment and targeted push remain unsupported release gates.

## Identity, private rides and finance

- Verify OTP expiry/attempt limits, session expiry, concurrent refresh/reuse revocation, suspension and logout. Offline logout must clear local credentials without claiming server revocation succeeded.
- Private ride lifecycle and cash-ledger tests currently run through the API. Complete proximity matching, pickup verification and passenger/driver UI before mobile UAT can pass this scenario.
- No approved gateway is configured. Do not accept a client-provided success flag as payment evidence. Digital-payment/refund/payout acceptance remains blocked.
- Verify account export/deletion requests are PENDING; fulfilment is not implemented and must not be claimed complete.

## Release sign-off table

| Gate                                             | Evidence and reviewer                                | Outcome      |
| ------------------------------------------------ | ---------------------------------------------------- | ------------ |
| Multi-device bus flow                            | Not collected                                        | Not executed |
| Native GPS permission/lifecycle/freshness        | Not collected                                        | Not executed |
| Operator isolation and adverse network recovery  | Backend tests only; device evidence missing          | Partial      |
| Share-auto concurrency and boarding              | Native DB integration tests; device evidence missing | Partial      |
| Private matching/pickup/tracking                 | Missing complete client/provider workflows           | Blocked      |
| OTP/MFA/notifications/payments                   | Approved integrations missing                        | Blocked      |
| Accessibility/Malayalam/low-end phone review     | Not collected                                        | Not executed |
| Backup restore, monitoring and incident drills   | Not collected                                        | Not executed |
| National/Kerala transport/privacy/payment review | Qualified review missing                             | Blocked      |
| Staging owner approval                           | Not collected                                        | Not executed |

No commercial release is authorised by this document or by passing CI.
