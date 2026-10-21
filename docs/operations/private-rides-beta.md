# Private Taxi / Auto beta — 21 October 2026

User explicitly requested finishing private rides and approved temporary beta fares; real-user testing setup is deferred by their choice. Never approve a driver or vehicle without review or make one identity request/accept its own ride.

## Flow

Passenger: Taxi / auto → choose map pickup and destination (optional landmark labels) → Auto/Taxi → quote → confirm cash request → driver accepted/arrived → check registration and confirm pickup → trip → completed/cash receipt. Private ride history is in this screen and the passenger trips screen.

Driver: Private taxi / auto rides → explicitly go online and share actual foreground GPS → nearby matching requests → choose an approved vehicle and accept or decline → external directions → arrived → wait for passenger confirmation → start → complete → record cash received.

Requests expire after 3 minutes. Offers require an approved online driver and approved category-matching vehicle, fresh GPS no older than 60 seconds and pickup within 8 km. Acceptance rechecks all conditions atomically and serializes each driver’s active ride; competing acceptances cannot both win. A passenger cannot have concurrent active requests. Cancellation and pickup confirmation use server versions. Trip start requires passenger confirmation. Only participants can read exact private trip details and assigned tracking. Terminal/stale/offline tracking does not appear as live. No push notification or background GPS claim; keep the private driver page open to receive offers and share location.

Migration 005 adds current driver location, rejection records, pickup confirmation and labels. Default beta-only fare rows (version 0) use Auto 3000 paise + 1500/started straight-line km and Taxi 6000 + 2000/km, cash. BETA_AUTH_ENABLED must be true for those rows to apply. Owner-configured higher version ordinary policies take precedence. Prices are deliberately temporary; estimates are labelled straight-line, never road/traffic or regulatory rates. Fare changes between quote and request are rejected. No digital payment is attempted.

## Verification

Five embedded PostGIS/database/HTTP suites passed, including existing auth/session/bus/owner flows and a new private ride suite covering role/participant isolation, approved-driver GPS, quote validation, idempotent requests, concurrent acceptance, active ride guard, passenger pickup confirmation, cash idempotency, declined offers, stale GPS and expiry. Mobile checks, exact-source native CI, hosted migration/API and new APK publication are being completed. Actual-device acceptance remains deferred by the user and is not claimed.

## Follow-up design and verification

User requested a new premium palette, typeface and layout while private ride delivery was in progress. The shared app identity now uses warm ivory, charcoal and champagne with bundled Manrope variable fonts and the SIL Open Font License. All three apps default to the light design; a warm dark theme remains defined. Passenger transport choices precede the map and journey input lives in a collapsible panel. Driver, Bus and private ride pages use clear editorial headings and consistent action/card spacing. Font source: https://github.com/google/fonts/tree/main/ofl/manrope ; SHA-256 3ae11c49db0455a3cc33e37d380f20fdb8c7f8b41dc07625c177e3d87a9d6ae6.

Initial source 5f91112 had a native integration fixture ordering failure: the private suite assumed another concurrently running test had created an ordinary AUTO fare. The private fixture now provisions its own explicit test fare policy. Five embedded suites and 22 mobile tests pass with the final design. Foreground location work also checks app activity and cancels pending sharing after navigation/backgrounding. Native CI must pass for the final follow-up source before release.

Final premium source 5f6b426 passed the native platform checks, all 22 shared mobile tests and analysis. Render deploy dep-dbcedtom7kps73ffvppg is live with migration 005 and protected endpoint checks verified. All three new local previews were browser reviewed. Complete mobile CI run 39633711359 and checked APK publication still pending. No real-user/device testing is claimed.
