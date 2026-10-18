# MASTER DEVELOPMENT PROMPT — RURALCONNECT

## ROLE AND OBJECTIVE

You are a principal software architect, senior Flutter developer, backend engineer, UI/UX designer, security engineer, DevOps engineer and QA lead working together to build a production-grade application.

Build **RuralConnect**, a connected rural transportation ecosystem for India, initially launching in Kerala.

The platform consists of:

1. **RuralConnect Passenger** — Flutter Android/iOS application.
2. **RuralConnect Driver** — Flutter Android/iOS application for auto and taxi drivers, including share-auto mode.
3. **RuralConnect Bus** — Flutter Android/iOS application for bus drivers and conductors.
4. **RuralConnect Admin** — Next.js web dashboard for administrators, bus owners and transport operators.
5. **RuralConnect API** — secure, scalable backend shared by all clients.

These must be real, interconnected applications, not separate demonstrations or static prototypes.

## CRITICAL INSTRUCTIONS

- Inspect the current repository and development environment before implementation.
- Determine which languages, frameworks, SDKs and services are available.
- Use stable, actively maintained package versions that are mutually compatible.
- Consult current official documentation when available.
- Create an implementation plan and maintain a progress document.
- Build working software, not just architecture diagrams, mockups or placeholder screens.
- Implement complete vertical features across mobile UI, API, persistence, authorisation and tests.
- Do not create fake successful bookings, payments or real-time vehicle locations.
- Never claim that code, security, deployment or integrations have been tested unless they actually have been.
- If third-party credentials are unavailable, implement documented interfaces, safe sandbox adapters and test fixtures. Clearly identify what still requires credentials.
- Use environment variables for configuration. Never hardcode secrets.
- Do not silently skip difficult features. Record blockers and incomplete work.
- Execute feasible commands, migrations, tests and builds in the development environment.
- Ask questions only when an unanswered decision genuinely blocks safe implementation. Otherwise document reasonable assumptions and continue.
- Maintain readable, modular, well-tested, production-oriented code.

The end goal is a deployable transport platform, with all three mobile applications operating against the same backend and reflecting authorised changes in real time.

---

# PART 1 — TECHNOLOGY STACK

Use the following preferred architecture unless there is a well-justified reason to change it.

### Mobile applications

- Flutter and Dart.
- Riverpod for state management.
- GoRouter for navigation.
- Dio for HTTP networking.
- A typed API client generated from OpenAPI wherever practical.
- Secure storage for authentication tokens.
- Local persistent storage for cached route and timetable data.
- Native Android/iOS integrations for GPS and background location, respecting platform rules.

### Backend

- Node.js with NestJS and TypeScript.
- REST APIs with documented OpenAPI contracts.
- WebSockets for live trip, booking and vehicle-status events.
- PostgreSQL with PostGIS for geographic queries.
- Prisma or another well-supported database access layer; use a safe SQL/PostGIS integration for spatial functionality where required.
- Redis for caching, queues and ephemeral vehicle state.
- Background workers for notifications, scheduled tasks, payment reconciliation and location processing.
- Object storage for authorised document uploads.

### Administration

- Next.js, TypeScript and Tailwind CSS.
- Role-based navigation and permission enforcement.
- Responsive administration screens.
- Map-based operations dashboard.

### External integrations

- Configurable maps/geocoding/navigation provider.
- Firebase Cloud Messaging for push notifications.
- OTP authentication through an approved provider.
- An authorised Indian payment-gateway integration supporting applicable UPI flows.
- Email/SMS notification provider where required.
- Monitoring, logging and crash-reporting providers.

Use interfaces that allow providers to be replaced without rewriting business logic.

---

# PART 2 — REPOSITORY STRUCTURE

Create a maintainable monorepo:

```text
ruralconnect/
  apps/
    passenger/
    driver/
    bus/
    admin/
  services/
    api/
    worker/
  packages/
    api-contracts/
    shared-types/
    shared-config/
  infrastructure/
    docker/
    deployment/
    monitoring/
  docs/
    architecture/
    api/
    product/
    operations/
    compliance/
  scripts/
  .github/workflows/
  README.md
  .env.example
```

Each Flutter application must have independent branding configuration, navigation, permissions and build targets.

Common components should be reusable without tightly coupling their releases.

---

# PART 3 — PASSENGER APPLICATION

## 3.1 Authentication and onboarding

Implement:

- Phone-number OTP authentication.
- Secure session management and logout.
- New-user registration.
- Editable profile.
- Preferred language.
- Permission onboarding.
- Terms and privacy consent.
- Account deletion and data export request workflows.
- Device token registration for push notifications.

Languages:

- English.
- Malayalam.

Architect localisation to allow other Indian languages later.

## 3.2 Passenger home screen

Display:

- Current location, with manual selection as an alternative.
- Pickup and destination search.
- Nearby bus stops.
- Available autos and taxis.
- Available share-auto trips.
- Favourite locations and routes.
- Recent destinations.
- Active booking or tracked journey.
- Transport service alerts.

Do not require continuous location permission merely to browse routes and timetables.

## 3.3 Journey search

Allow passengers to enter origin and destination.

The search engine should support:

1. Bus-only journeys.
2. Private autorickshaw journeys.
3. Taxi journeys.
4. Share-auto journeys.
5. Walking connections.
6. Multimodal journeys combining these options.

Return alternatives with:

- Route information.
- Expected travel duration.
- Walking distance.
- Transfers.
- Estimated or confirmed fare.
- Next departure.
- Tracking-data freshness.
- Availability.
- Booking eligibility.

Label estimated, scheduled and live information distinctly.

Implement the routing service with extensible graph-based journey planning, using GTFS-compatible scheduled data where practical. Do not assume every rural route has a complete GTFS feed.

## 3.4 Live bus finder

Passengers must be able to:

- Discover nearby stops.
- Search buses serving an origin-destination pair.
- See scheduled departures.
- See upcoming bus arrivals.
- View route and stop sequence.
- View a bus on the map if reliable live data exists.
- See last-updated time.
- See bus cancellations, breakdowns and delays.
- Follow favourite routes.
- Subscribe to arrival and disruption alerts.

Do not display fabricated GPS positions or arrival times.

When GPS is stale or unavailable, show a clear warning and display scheduled information separately.

## 3.5 Private auto and taxi bookings

Implement:

- Vehicle type selection.
- Fare quote.
- Driver matching.
- Booking request.
- Driver acceptance/rejection.
- Booking confirmation.
- Driver arrival tracking.
- Pickup confirmation.
- Ride initiation.
- Live ride status.
- Ride completion.
- Payment selection.
- Trip receipt.
- Ratings.
- Cancellation with documented policy.
- Booking history.
- Help and support.

Use a robust booking state machine.

Prevent duplicate booking acceptance and invalid state transitions.

## 3.6 Share-auto booking

This is a core differentiating feature.

Allow passengers to:

- Search share autos by route.
- See available seats.
- See departure time.
- See permitted pickup/drop-off locations.
- See fare per seat.
- Reserve one or more seats.
- Receive booking confirmation.
- Track the vehicle during the shared trip.
- Cancel reservations according to policy.

Seat availability must be authoritative on the backend.

Use database transactions or equivalent concurrency controls to prevent overbooking.

Support booking expiry, cancellation, passenger no-show handling and service completion.

## 3.7 Payments

Support:

- Cash.
- Approved UPI/payment-gateway methods where enabled.
- Payment status.
- Receipts.
- Refund requests.
- Failed payment handling.
- Transaction history.

Always verify payment results on the backend through authoritative provider responses and signed webhooks.

Never trust a passenger application's claim that payment succeeded.

Do not store card credentials or sensitive payment secrets.

## 3.8 Passenger safety

Implement:

- Driver identity and vehicle information.
- Trip sharing with trusted contacts.
- SOS interface.
- Incident reporting.
- Customer support access.
- Report/block functionality.
- Privacy-aware location sharing.

The SOS interface must clearly identify the supported emergency-contact mechanisms and not claim that emergency authorities have been alerted unless an actual supported integration confirms it.

---

# PART 4 — AUTO AND TAXI DRIVER APPLICATION

## 4.1 Driver registration

Implement:

- Mobile OTP login.
- Driver profile.
- Vehicle category.
- Driving licence submission.
- Registration document submission.
- Permit/fitness/insurance records as applicable.
- Document expiry tracking.
- Approved payout account setup.
- Administrator verification.
- Pending, approved, rejected and suspended statuses.

Drivers must not accept commercial bookings until the relevant verification requirements are satisfied.

Protect uploaded documents and restrict access to authorised staff.

## 4.2 Driver dashboard

Display:

- Online/offline state.
- Selected operating mode.
- Incoming requests.
- Active journey.
- Navigation.
- Daily earnings.
- Completed trips.
- Payout information.
- Important alerts.

## 4.3 Private ride mode

Implement:

- Go online.
- Receive eligible nearby ride requests.
- Accept or reject within configured timeout.
- Navigate to pickup.
- Mark arrival.
- Confirm passenger pickup.
- Start trip.
- End trip.
- Record payment.
- View completed trips.

Driver and passenger must see consistent booking states.

## 4.4 Share-auto mode

Drivers must be able to announce a shared trip.

Required information:

- Origin.
- Destination.
- Route geometry or known corridor.
- Intermediate permitted pickup and drop-off points.
- Departure time.
- Seat capacity.
- Seat availability.
- Fare or approved fare policy.
- Trip status.

Shared-trip lifecycle:

DRAFT → PUBLISHED → BOARDING → IN_PROGRESS → COMPLETED.

Support CANCELLED separately with a reason.

Passenger reservations should be matched to their desired pickup and drop-off along the driver's route.

Prevent:

- Seat overbooking.
- Duplicate reservations.
- Invalid stop ordering.
- Boarding after trip completion.
- Reservations for cancelled trips.
- Unauthorised route changes.

The driver must be able to:

- View reservations.
- Confirm boarding.
- Mark no-shows.
- Update permitted availability.
- Close bookings.
- Cancel an announced service.
- Complete the shared trip.

A broadcast should notify only relevant eligible passengers. Use opt-in targeting, throttling and anti-spam safeguards.

## 4.5 GPS tracking

While an authorised active trip is in progress:

- Collect location according to platform permissions.
- Send timestamped coordinates securely.
- Adjust update frequency based on movement and connection quality.
- Queue limited updates during temporary network loss where appropriate.
- Stop unnecessary tracking when a trip is complete.
- Reject implausible or stale updates.
- Avoid tracking drivers indefinitely while offline.

Implement explicit background-location permission flows and comply with Android and iOS requirements.

## 4.6 Driver finances

Implement:

- Trip earnings.
- Cash collected.
- Digital payment status.
- Platform commission calculations where configured.
- Refund adjustments.
- Payout balances.
- Payout history.
- Reconciliation reports.

Use an immutable financial ledger or similarly auditable financial records.

---

# PART 5 — BUS DRIVER APPLICATION

## 5.1 Driver and conductor access

Implement:

- Secure login.
- Driver/conductor role selection based on authorised assignments.
- Assigned buses.
- Assigned scheduled services.
- Today's timetable.
- Active and upcoming trips.

A driver should not have unrestricted permission to modify the official route database.

## 5.2 Bus service startup

A driver should be able to:

1. Select the assigned bus.
2. Select the assigned scheduled trip.
3. Confirm the trip.
4. Start service.
5. Enable authorised live GPS sharing.

The current service must immediately become visible in the passenger application.

## 5.3 Bus trip status

Support:

- Scheduled.
- Boarding.
- Running.
- Delayed.
- Temporarily stopped.
- Breakdown.
- Diverted.
- Cancelled.
- Completed.

Record:

- Event type.
- Event time.
- Actor.
- Reason.
- Expected delay, when known.
- Affected stops.
- Whether the event requires operator approval.

State transitions must be validated and audited.

## 5.4 Delay reporting

Allow authorised users to report a delay and an estimated duration.

Update affected passenger arrival information where the estimate can be computed reliably.

Send notifications to passengers following the affected service.

## 5.5 Breakdown reporting

Implement:

- Breakdown reason category.
- Incident location.
- Incident timestamp.
- Passenger-visible service status.
- Operator notification.
- Optional replacement bus assignment.
- Incident resolution.

## 5.6 Cancellation management

Allow authorised users to mark a specific bus trip cancelled.

A single cancellation must not delete the recurring schedule.

Display cancelled status on the passenger app and notify affected subscribers.

Support service reinstatement with a traceable audit history.

## 5.7 Live bus tracking

Implement:

- Timestamped GPS updates.
- Map matching where feasible.
- Upcoming stop estimation.
- Stop arrival/departure detection.
- Last-known location.
- GPS data-quality status.
- Stale-data detection.
- Server-authoritative trip state.

When location is unavailable, provide a schedule-based fallback clearly marked as such.

## 5.8 Bus driver usability

Use:

- Large buttons.
- Very limited interaction during active driving.
- Clear visual status.
- Malayalam language support.
- Minimal typing.
- Voice assistance only where safely supported.
- Conductor/operator incident-entry workflows.

Never encourage drivers to interact with the application while driving.

---

# PART 6 — BUS OWNER AND OPERATOR PORTAL

Implement web-based operator accounts.

Operators must be able to:

- Register and manage bus fleets.
- Register and verify route details.
- Manage bus stops.
- Configure recurring timetables.
- Assign drivers and conductors.
- Assign buses to scheduled services.
- Manage exceptions for holidays and operating dates.
- Report service cancellations.
- Manage replacement buses.
- View live buses.
- Investigate service incidents.
- Review GPS uptime.
- View operational analytics.

Support multiple operators with strict data isolation.

Changes to routes and schedules must be versioned or auditable.

---

# PART 7 — SYSTEM ADMINISTRATION

Build a separate administrator interface supporting:

- User management.
- Driver approvals.
- Vehicle approvals.
- Operator verification.
- Document review.
- Route and stop moderation.
- Live vehicle monitoring.
- Booking administration.
- Dispute handling.
- Payment reconciliation.
- Refund administration.
- Commission settings.
- Suspension and reinstatement.
- Support ticket management.
- System alerts.
- Audit logs.
- Usage analytics.

Enforce authorisation on the backend, not only by hiding UI controls.

Support least-privilege permissions and secure administrator authentication with MFA where available.

---

# PART 8 — DATABASE DESIGN

Design a normalised PostgreSQL schema with appropriate PostGIS spatial indexes.

At minimum model:

- Users
- UserRoles
- PassengerProfiles
- DriverProfiles
- DriverDocuments
- Operators
- OperatorMembers
- Vehicles
- VehicleDocuments
- VehicleAssignments
- BusRoutes
- RouteVersions
- BusStops
- RouteStops
- ServiceCalendars
- ScheduledTrips
- TripInstances
- TripExceptions
- DriverAssignments
- VehicleLocations
- VehicleLocationHistory
- RideRequests
- PrivateBookings
- SharedTrips
- SharedTripStops
- SeatReservations
- PassengerBoardingEvents
- BookingStateHistory
- FareQuotes
- FarePolicies
- Payments
- Refunds
- LedgerEntries
- Payouts
- Notifications
- NotificationSubscriptions
- ServiceIncidents
- Ratings
- Complaints
- SupportTickets
- AuditLogs
- DeviceTokens
- ConsentRecords

Include:

- Database migrations.
- Foreign-key constraints.
- Spatial indexes.
- Unique constraints.
- Transactional booking operations.
- Soft deletion where legally/operationally appropriate.
- Data retention policies.
- Optimistic locking or equivalent mechanisms where needed.
- Audit metadata.
- Timezone-aware timestamps.

Financial amounts must use precise decimal or integer minor-unit representation, never binary floating-point arithmetic.

Distinguish recurring services from individual dated trip instances.

---

# PART 9 — REAL-TIME SYNCHRONISATION

The three mobile apps must communicate through the same backend.

Required workflows:

### Scenario A — Bus delay

1. Bus driver reports delay.
2. Backend validates permissions and current trip.
3. Status is persisted.
4. ETA information is recalculated when possible.
5. Interested passengers receive the event.
6. Operators see the incident.

### Scenario B — Share-auto broadcast

1. Driver publishes a route.
2. Backend validates eligibility.
3. Shared trip is stored.
4. Matching passengers discover it.
5. Passengers reserve seats.
6. Capacity is updated transactionally.
7. Driver receives reservations.
8. All clients see consistent seat availability.

### Scenario C — Private auto booking

1. Passenger requests a ride.
2. Backend locates eligible drivers.
3. Drivers receive offers according to matching policy.
4. One eligible driver accepts.
5. Backend atomically assigns the ride.
6. Passenger receives driver details.
7. Both parties track the journey.
8. Trip completion triggers payment reconciliation.

### Scenario D — Bus cancellation

1. Authorised actor cancels a dated trip.
2. Backend records the event.
3. Passenger search excludes it from active service results or clearly labels it as cancelled.
4. Saved-route subscribers receive appropriate notifications.

Use WebSocket events with versioned payloads.

Implement reconnect handling, event replay/refetch strategies, duplicate-event tolerance and eventual consistency protections.

---

# PART 10 — RURAL NETWORK CONDITIONS

The platform must work reasonably well with unreliable mobile connectivity.

Implement:

- Cached bus routes.
- Cached stop lists.
- Cached published timetables.
- Network status display.
- Explicit offline states.
- Retry with exponential backoff.
- Bounded local queues for permitted operations.
- Duplicate request protection.
- Location freshness information.
- Reduced map/network usage when data connectivity is poor.

Never represent a queued offline booking or payment as confirmed until the backend acknowledges it.

Provide graceful fallbacks when maps or GPS providers fail.

---

# PART 11 — UI/UX DESIGN

Design an original, modern interface.

Do not copy Uber's protected branding, trade dress or screen designs.

Visual direction:

- Clean, accessible typography.
- Professional transport-oriented visual design.
- Consistent design tokens.
- Light and dark themes.
- Smooth but restrained animations.
- Rounded cards and clear status indicators.
- Accessible contrast.
- Optimised layouts for inexpensive Android phones.
- Malayalam-friendly text sizing and layouts.

Create reusable components for:

- Location search.
- Route cards.
- Fare cards.
- Bus ETA cards.
- Driver information.
- Seat counters.
- Status banners.
- Trip tracking.
- Payment selection.
- Notifications.
- Error and offline states.

Include loading, empty, error, permission-denied and successful states for every significant workflow.

Prioritise speed and clarity over excessive animation.

---

# PART 12 — SECURITY, PRIVACY AND COMPLIANCE

Treat security and privacy as essential product requirements.

Implement:

- Secure authentication.
- Short-lived access tokens and controlled refresh-token rotation.
- Role-based and resource-level authorisation.
- Input validation.
- Request rate limiting.
- OTP abuse protection.
- Encrypted transport.
- Encryption of sensitive stored information where appropriate.
- Secure file-upload scanning and validation.
- Signed webhook verification.
- Secrets management.
- Audit logging.
- Sensitive-data redaction.
- Account suspension.
- Data access and deletion workflows.
- Retention controls.
- Privacy-preserving location-sharing policies.
- Payment idempotency.
- Prevention of cross-operator data leakage.
- Least-privilege service credentials.

Design the platform to support applicable Indian privacy, payment and transport requirements.

Review and document relevant national and Kerala transport-aggregator obligations, permit requirements, data-protection obligations and mobile-platform policies before commercial deployment.

Do not claim regulatory approval or compliance without actual verification.

---

# PART 13 — TESTING

Create meaningful automated tests.

### Backend unit tests

Cover:

- Authentication and authorisation.
- Matching eligibility.
- Fare calculation.
- Booking state transitions.
- Seat availability.
- Schedule exceptions.
- Payment state handling.
- Notifications.
- Location freshness.
- Data isolation.

### Integration tests

Cover:

- PostgreSQL transactions.
- API/database interactions.
- WebSocket delivery.
- Background workers.
- Payment webhook processing.
- Location and trip synchronisation.

### Flutter tests

Cover:

- Authentication screens.
- Form validation.
- Search flows.
- Booking flow.
- Seat reservation.
- Bus updates.
- Permission and offline states.

### End-to-end tests

Simulate:

1. Passenger finds an active bus.
2. Driver reports a bus delay.
3. Passenger sees the status.
4. Auto driver broadcasts a shared trip.
5. Passenger reserves a seat.
6. Capacity decreases correctly.
7. Passenger makes a private booking.
8. Driver accepts the booking.
9. Trip completes.
10. Payment state and receipt are updated.

Test race conditions, expired sessions, network interruptions, malformed events and duplicate requests.

Use real test databases and provider sandboxes where credentials permit.

---

# PART 14 — DEPLOYMENT AND OPERATIONS

Create a repeatable deployment foundation.

Implement:

- Docker configuration.
- Local development environment with Docker Compose.
- Migration and seed commands.
- CI pipelines.
- Static analysis.
- Dependency/security checks.
- Automated tests.
- Build verification.
- Staging configuration.
- Production configuration templates.
- Health and readiness endpoints.
- Structured logging.
- Distributed tracing where appropriate.
- Performance monitoring.
- Crash reporting.
- Backup and restoration procedures.
- Rollback strategy.
- Environment-separated configuration.
- Documented disaster recovery process.

Never expose development credentials in a deployed application.

Do not deploy to production or make paid third-party purchases without explicit authorisation.

---

# PART 15 — REQUIRED IMPLEMENTATION PROCESS

Work in the following phases and complete meaningful working functionality in each phase.

## PHASE 0 — Architecture and planning

Create:

- Architecture decision records.
- Product requirements document.
- Entity relationship diagram.
- API design.
- Roles and permissions matrix.
- Event catalogue.
- Booking and trip state-machine diagrams.
- UI navigation map.
- Risk and compliance register.
- Development milestone checklist.

## PHASE 1 — Platform foundation

Build:

- Monorepo.
- Backend project.
- Database migrations.
- Authentication.
- User roles.
- OpenAPI documentation.
- All Flutter application shells.
- Admin portal shell.
- Shared API clients.
- Docker Compose.
- Test infrastructure.
- CI.

## PHASE 2 — Bus transport system

Build the full vertical flow:

- Operator route creation.
- Stops and schedules.
- Bus assignment.
- Bus driver trip start.
- Live bus location updates.
- Delay and cancellation reporting.
- Passenger bus search.
- Passenger bus status display.
- Notifications.

## PHASE 3 — Auto driver system

Build:

- Driver onboarding.
- Verification workflows.
- Vehicle management.
- Driver availability.
- Private booking.
- Matching.
- Booking state transitions.
- Trip tracking.
- Driver earnings records.

## PHASE 4 — Share-auto system

Build:

- Shared trip broadcasts.
- Stop/route compatibility.
- Seat reservations.
- Capacity control.
- Boarding states.
- Passenger and driver synchronisation.

## PHASE 5 — Payments and financial operations

Build:

- Fare rules.
- Payment intent creation.
- Gateway adapter.
- Webhook processing.
- Cash-payment recording.
- Reconciliation.
- Refund states.
- Ledger and receipts.
- Payout tracking.

## PHASE 6 — Journey planning

Build:

- Unified transport search.
- Walking connectors.
- Bus-plus-auto connections.
- Travel time comparison.
- Fare comparison.
- Route ranking.
- Confidence indicators.

## PHASE 7 — Hardening and release preparation

Complete:

- Integration and end-to-end tests.
- Security review.
- Accessibility review.
- Mobile release configuration.
- Database performance review.
- Monitoring.
- Backup verification.
- Staging deployment.
- Release documentation.

Do not describe an unfinished phase as complete.

---

# PART 16 — DELIVERY EXPECTATIONS

At the end, the repository should include:

1. Working passenger Flutter application.
2. Working auto/taxi driver Flutter application.
3. Working bus driver Flutter application.
4. Functional admin/operator dashboard.
5. Shared backend APIs.
6. Database schema and migrations.
7. Real-time communication system.
8. Payment integration abstraction and tested sandbox implementation.
9. Automated test suites.
10. Docker/local setup.
11. CI and deployment configuration.
12. Seeded demonstration data clearly identified as demo data.
13. API documentation.
14. Architecture documentation.
15. Environment setup guide.
16. Security and operational documentation.
17. Android/iOS build instructions.
18. Outstanding integration and regulatory checklist.

Provide commands for:

- Installing dependencies.
- Starting local services.
- Applying migrations.
- Seeding demonstration data.
- Running each application.
- Running automated tests.
- Building Android applications.
- Preparing iOS builds on a compatible macOS environment.
- Running staging deployment workflows.

Create a `DELIVERY_STATUS.md` file listing every major requirement as:

- Implemented and tested.
- Implemented but unverified.
- Partially implemented.
- Blocked.
- Not started.

Do not classify functionality as production ready solely because it works locally.

---

# PART 17 — ACCEPTANCE CRITERIA

The system is not considered ready for a production release unless:

- All clients communicate with the same deployed API environment.
- Real permissions are enforced on the server.
- Passengers can discover valid bus services.
- Driver-generated service updates reach passengers.
- Share-auto seats cannot be oversold under concurrent requests.
- Private ride booking and matching work reliably.
- Critical trip transitions survive connection interruptions.
- Payment results are verified using approved provider mechanisms.
- Bus cancellations affect only the intended services.
- Location freshness is visible.
- Personal and financial information is protected.
- Administrator actions are audited.
- Automated tests pass in CI.
- Operational monitoring and backup recovery are verified.
- Required third-party integrations are configured.
- Applicable legal, transport and payment requirements have been reviewed.
- Staging user acceptance tests are completed.

Where these conditions cannot be verified in the development environment, document the remaining release gates explicitly.

---

# FINAL INSTRUCTION

Start by inspecting the repository.

Then create the complete architecture, database design, API contracts and implementation plan.

Immediately proceed with implementing **Phase 1 and the first working end-to-end bus-tracking flow**, rather than stopping after documentation.

Continue through the implementation phases using the available environment, validating each completed module before advancing.

Optimise for maintainability, user safety, reliability, low-bandwidth rural usage and real-world operation.

The ultimate goal is to make RuralConnect a genuine, scalable rural transportation platform — not merely an attractive application prototype.
