# RuralConnect Android 0.1.0 — development testing

Download and install the APK for each role:

- RuralConnect-passenger-0.1.0-dev.apk
- RuralConnect-driver-0.1.0-dev.apk
- RuralConnect-bus-0.1.0-dev.apk

These are debug-signed Android testing builds, not production releases. Android application source: 0325fd9b8b02a283a98e8cd3d2e6e5a4f484e7f9. Built and tested by GitHub Actions run 39121614656. SHA256SUMS.txt verifies the downloaded APK files.

## API setup is required

All three APKs target http://10.0.2.2:3001/v1 — the Android emulator's route to an API on the development computer. Start the shared API/database and seed the fixture accounts using the repository README. There is no hosted production backend, and no SMS is sent. Use your locally configured sandbox OTP and sandbox access key to sign in.

These APKs can be installed on a phone, but their emulator API address will not connect from a physical phone. A phone build needs a reachable API_URL (LAN development server or an HTTPS staging API). Do not enter real personal/payment data into these development builds.

Passenger fixture: +919000000001. Driver: +919000000002. Bus crew: +919000000003. Operator portal: +919000000004.

Implemented functionality and remaining work are recorded in DELIVERY_STATUS.md. Production OTP, digital payments, full onboarding, device/GPS acceptance, staging operations and other release gates remain unfinished. Future development APKs may need an uninstall before installation if their debug signing key changes. iOS is deferred.
