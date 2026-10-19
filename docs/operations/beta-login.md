# Invite-only beta login — no SMS

Decision, 19 October 2026: SMS OTP is deferred until the first update of the real app. The current beta uses owner-issued, per-user invitations. This is not public registration and does not verify ownership of a phone number. A phone number is only an account identifier. Do not advertise accounts as phone verified.

## Enable

Apply all migrations, including 003_beta_invites.sql. Set BETA_AUTH_ENABLED=true in the API environment. For hosted builds keep OTP_MODE=disabled, PAYMENT_MODE=disabled and all production HTTPS/database checks enabled. Never enable sandbox OTP on a public production server.

Build each client with:

    flutter build apk --debug --dart-define=BETA_AUTH=true

Signed release builds automatically use invitation login; supply the permanent signing credentials and actual HTTPS API_URL as described in production-track.md. The currently published v0.2.0 APKs predate this change; a new tested build is required. Do not use disposable CI signing keys for distribution.

## Issue invitations

On the owner's trusted server or workstation with DATABASE_URL configured in the repository .env:

    pnpm --filter @ruralconnect/api beta:invite +91TESTER_PHONE PASSENGER PRIVATE_OUTPUT_FILE

The role may be PASSENGER, DRIVER or BUS_CREW. A new account is created with that server-selected role. Existing accounts must have exactly the same single role; roles cannot be elevated by this command. Operator/admin accounts cannot redeem beta invitations. New drivers remain PENDING verification; no vehicle is approved and no crew assignment is created automatically.

Use a new file path outside Git (or in ignored .local-data/) for each invitation. The file contains a random 256-bit code, which is never printed to logs or stored in plaintext in the database. The file is created with private permissions where supported; the owner must restrict access on Windows and other shared systems. Deliver it privately to the intended tester after checking their identity. Never put invite codes in public GitHub releases, screenshots or shared group messages.

The invitation expires after seven days and can be redeemed once. Issuing a new invitation invalidates previous unused invitations for that account, but does not end existing signed-in sessions. Testers enter their account phone and invitation code and acknowledge the beta notice. There is no SMS, common OTP or shared sandbox key. Access sessions expire after 15 minutes; rotating refresh sessions last up to 30 days. After logout/reinstall/session expiry, request a fresh invitation. An interrupted redemption may require reissue if the response was lost after the code was consumed.

## Revoke access

    pnpm --filter @ruralconnect/api beta:revoke +91TESTER_PHONE

This invalidates pending invitations and all existing sessions. It does not delete the account. Account suspension also blocks access. Provisioning/revocation require trusted database access; there is no public invite-issuing API.

## Verified scope and remaining work

Integration covers provisioning, phone binding, concurrent single-use redemption, expiry, replacement, suspended/privileged account denial and unapproved-driver restrictions. Mobile tests cover role-specific invitation screens and rejected invitations without local success. Normal authorization, secure token storage and refresh rotation remain in place.

This removes the SMS-provider dependency for supervised private beta participation. It does not complete hosting, privacy/deletion fulfilment, admin MFA, driver checks, real-device acceptance or the remaining transport workflows. It does not certify public production readiness. SMS verification remains planned for the first post-launch update.

Authentication follow-up: OTP verification rejects outstanding sandbox challenges when disabled or in production. Owner revocation and invite redemption share the same account-first locking order. Disabled-OTP and concurrent-revocation regressions passed in embedded PostgreSQL integration; native CI confirmation for the follow-up is pending.
