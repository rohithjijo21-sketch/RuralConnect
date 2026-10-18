# Mobile build and permission gates

Flutter/Dart are not installed on the authoring machine, so these sources and widget tests have NOT been executed. CI is configured to run them. No APK/IPA is delivered. Use a current stable Flutter SDK compatible with go_router 18 and Riverpod 3, then resolve/lock dependencies and commit the lockfiles after review.

The bootstrap script generates independent Android/iOS projects and bundle names under in.ruralconnect. Flutter create can generate a default widget test: remove the default counter test and retain test/smoke_test.dart. If Flutter overwrites an entry point, restore the authored lib/main.dart from Git before continuing. Review generated files before committing.

Android bus app: add INTERNET, ACCESS_FINE_LOCATION and ACCESS_COARSE_LOCATION to android/app/src/main/AndroidManifest.xml. Passenger/Driver do not currently request GPS; do not copy bus permissions to them without a feature need. For local HTTP testing only, add a debug-only network security configuration permitting the chosen development host. Never permit arbitrary cleartext in a release build. Select minSdk/compileSdk as required by the resolved plugins.

iOS bus app: add NSLocationWhenInUseUsageDescription explaining active-service location sharing. Configure secure storage keychain entitlements as required by flutter_secure_storage. Use HTTPS and test actual permission revocation. iOS builds require macOS, current Xcode, signing identities, real-device validation and App Store review.

Background GPS is NOT implemented. Do not add ACCESS_BACKGROUND_LOCATION, foreground service types or iOS always/background location claims until platform workflows, bounded buffering, battery use and privacy are designed/tested. Current tracking is foreground-only; runtime permission is explicitly requested when crew enables sharing for an active assigned service. Stop sharing at completion/cancellation/sign-out. Field test OS suspension and lifecycle interruptions before use.

Release gates: independent icons/labels, signing, deep links, crash reporting, full Malayalam localisation, screen-reader checks, location accuracy, low-end Android performance, offline recovery, secure token storage and native build/test execution.
