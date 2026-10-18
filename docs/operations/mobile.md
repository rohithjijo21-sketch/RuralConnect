# Mobile build and permission gates

Flutter 3.47.7 / Dart 3.13.5 were installed in workspace work/. All three apps pass local analysis and smoke tests; mobile_core passes four interaction tests. Native Android/iOS targets and lockfiles are committed. Android SDK and macOS/Xcode are unavailable locally; debug APK builds are configured in CI. No release APK/IPA or device acceptance is claimed.

The bootstrap script generates independent Android/iOS projects and bundle names under in.ruralconnect. Flutter create can generate a default widget test: remove the default counter test and retain test/smoke_test.dart. If Flutter overwrites an entry point, restore the authored lib/main.dart from Git before continuing. Review generated files before committing.

Android bus app: add INTERNET, ACCESS_FINE_LOCATION and ACCESS_COARSE_LOCATION to android/app/src/main/AndroidManifest.xml. Passenger/Driver do not currently request GPS; do not copy bus permissions to them without a feature need. For local HTTP testing only, add a debug-only network security configuration permitting the chosen development host. Never permit arbitrary cleartext in a release build. Select minSdk/compileSdk as required by the resolved plugins.

iOS bus app: add NSLocationWhenInUseUsageDescription explaining active-service location sharing. Configure secure storage keychain entitlements as required by flutter_secure_storage. Use HTTPS and test actual permission revocation. iOS builds require macOS, current Xcode, signing identities, real-device validation and App Store review.

Background GPS is NOT implemented. Do not add ACCESS_BACKGROUND_LOCATION, foreground service types or iOS always/background location claims until platform workflows, bounded buffering, battery use and privacy are designed/tested. Current tracking is foreground-only; runtime permission is explicitly requested when crew enables sharing for an active assigned service. Stop sharing at completion/cancellation/sign-out. Field test OS suspension and lifecycle interruptions before use.

Release gates: independent icons/labels, signing, deep links, crash reporting, full Malayalam localisation, screen-reader checks, location accuracy, low-end Android performance, offline recovery, secure token storage and native build/test execution.

Android release tasks deliberately fail with an explicit Gradle release-signing gate. Configure a real release signing workflow and verify it before removing that gate; the Flutter template debug key must not sign a commercial release. CI builds debug APKs for local emulator testing only.
