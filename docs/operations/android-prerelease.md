# RuralConnect Android 0.2.0 — phone testing

Install the passenger, driver and bus APKs from this release. These are debug-signed development builds. SHA256SUMS.txt verifies the files. The release uses the successful CI build for the tagged commit.

The passenger app includes an interactive, labelled read-only UI demo that needs no server. For live testing, connect all three apps to the API on your computer in server settings. Share Wi-Fi and enter http://YOUR_COMPUTER_LAN_IP:3001/v1.

Start the persistent local server with `pnpm dev:phone`. It generates sandbox credentials and a private PHONE_TESTING.md outside the repository. Use those credentials with passenger +919000000001, driver +919000000002 or bus crew +919000000003. No SMS is sent. Keep the computer and server running.

Passenger improvements include bus search/details, freshness indicators, shared-seat reservations, history, profile and connection settings. Demo data never creates bookings or payments. Production SMS, digital payments, full private ride matching, operational hardening and device acceptance remain unfinished; see DELIVERY_STATUS.md. A changed debug signing key may require uninstalling the previous app, clearing its local data. iOS is deferred.
