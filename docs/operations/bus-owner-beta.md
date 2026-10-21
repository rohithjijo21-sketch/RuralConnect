# Bus owner and crew beta

The Bus app now includes an owner workspace alongside assigned crew services.
Signing in as BUS_CREW does not grant global operator or administrator roles.

1. Open **Owner setup · buses, routes and timetables** after sign-in.
2. Register the bus business/owner name. This creates a pending owner application.
3. Add the real bus registration and seating capacity. Vehicles start unapproved.
4. Add an ordered route with at least two real stop coordinates and increasing
   minute offsets. The owner can capture their current location while at a stop.
5. Save a one-off trip or recurring timetable: bus, route, existing authorised
   crew member, departure time, dates, operating weekdays and holiday exceptions.
6. After operator and vehicle review, publish up to 31 calendar days at a time.
   Publishing again reuses existing dated trips. Holiday exclusions are skipped.
7. Return to Assigned services. Current-day assigned crew can change trip status
   and explicitly start foreground GPS sharing. Status changes require reasons
   and are audited. Owner-authorised cancellation/reinstatement preserves plans.

Pending owners can save setup details, but cannot publish live passenger services.
No approval flags, account roles or live GPS are fabricated for the beta account.
Passenger searches use the published dated services through the existing API.

## Trusted review

Review ownership and vehicle evidence outside the app before approval. Document
upload/reviewer UI is not implemented in this beta. There is no public approval
endpoint. On the trusted workstation with the hosted DATABASE_URL configured:

    OWNER_REVIEW_ENABLED=true
    pnpm --filter @ruralconnect/api bus:review operator OPERATOR_UUID APPROVE "Ownership evidence reviewed: reference"
    pnpm --filter @ruralconnect/api bus:review vehicle VEHICLE_UUID APPROVE "Vehicle evidence reviewed: reference"

PowerShell uses `$env:OWNER_REVIEW_ENABLED='true'` to set the process variable.
Use REJECT instead of APPROVE when appropriate. The command records an audit
entry and does not grant privileged roles or issue invitations. Do not configure
this review flag on the public API. Keep hosted credentials out of Git and apps.

## Verified and remaining scope

Local embedded PostgreSQL tests cover pending publication denial, unapproved bus
denial, cross-owner route/plan isolation, weekday/holiday materialisation, retry
deduplication and crew assignment. Existing auth/bus/booking integration also pass.
Mobile tests cover owner registration, rejected-save handling and disabled publish
while pending. Native CI, deployed migration/API and actual-device acceptance
must be checked for the final source before distributing the new APK.

Additional crew invitations, document uploads, replacement-bus UI, operational
analytics, map matching/stop detection and complete Malayalam translation remain
unfinished. This change does not claim all master requirements or production readiness.
