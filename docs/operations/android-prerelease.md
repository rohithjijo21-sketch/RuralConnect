# RuralConnect Android 0.7.0 — hosted private beta

Download the Passenger, Driver or Bus Crew APK for your assigned role. These are debug-signed private-beta test builds, not production releases. SHA256SUMS.txt contains the download hashes. Build checks must pass for the exact tagged source; actual-device acceptance remains to be completed.

Use mobile data or any Wi-Fi. The server address is prefilled as https://ruralconnect-beta-api.onrender.com/v1. On first launch, confirm the server connection. The owner's laptop does not need to remain running. The free server can take about a minute to wake; allow the connection check to finish.

Sign in with the account phone number and a private, single-use invitation from the owner. No SMS is sent and phone ownership is not verified. Do not share invitations in public issues or group chats. Roles are assigned by the server. Driver/vehicle approval and crew assignments must be completed separately before operating workflows.

Android installation: open the APK on your phone, allow installation from that browser or file manager if Android requests it, then open RuralConnect. An older APK signed with another development key may require uninstalling the previous app, which clears its local data. Keep Play Protect enabled.

The Passenger labelled UI demo is read-only and separate from the hosted server. A fresh hosted database has no demo routes, vehicles or bookings; empty lists are expected until real beta resources are configured. Digital payments, road routing, traffic-aware arrival estimates, background tracking, notifications and other documented workflows remain unfinished. Private ride matching is available for approved online drivers with fresh foreground GPS. Use this release for supervised beta feedback. iOS is deferred.

Report the app name/version, Android version, steps and error text to the owner. Do not include invitation codes, tokens or other testers' personal information in reports.

Bus 0.4.0 adds Owner setup: register an owner workspace, add buses, ordered route stops with coordinates and offsets, save single-trip or recurring timetables and holiday exceptions, and publish up to 31 days after owner and bus review. Return to Assigned services to board/start/report delay, breakdown, diversion, cancellation or completion, and share foreground GPS. Pending owner and vehicle details can be saved but cannot publish live services. Crew selection currently uses existing workspace members (including the owner account); inviting additional crew, document uploads, replacement-bus UI, map matching, stop detection and full Malayalam translation remain pending.

## Private Taxi / Auto beta

Passenger Taxi / auto opens map-based pickup and destination selection, a temporary straight-line cash estimate and a real ride request. Approved online drivers share foreground GPS to receive matching requests within 8 km. Requests expire after 3 minutes. Passengers confirm pickup in their own app before a driver can start. Completed rides can record cash received; this does not process a digital payment. Private ride location updates require the driver page to remain open. Temporary beta defaults are Auto ₹30 + ₹15 per started straight-line kilometre and Taxi ₹60 + ₹20/km. They are disabled outside invitation beta mode unless an owner-configured normal fare policy exists. Real driver/vehicle approval and a second account are needed for device acceptance. Road navigation opens the phone’s external maps app; traffic ETA, background GPS and automatic road routing are not included.

## Bus timetable revision update

Bus Owner setup adds Create revised timetable with prefilled schedule, bus, route, crew and holiday details. Saving creates an audited new plan while preserving old plans and dated services. Cancel old conflicting services explicitly before publishing the revision. Backend scheduling also rechecks bus and crew reservations when reinstating a cancelled trip. Real approvals remain required.
