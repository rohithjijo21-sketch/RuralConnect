# Production implementation track — Android first

Status: active implementation, not production ready. Hosting is not set up. SMS OTP is deferred to the first post-launch update. No public deployment has been performed.

## First implementation batch

- Fail-fast API configuration: HTTPS admin origin, required HTTPS transport, verified database TLS, explicit trusted ingress IP/CIDRs, no sandbox credentials and disabled unintegrated SMS/payment providers.
- Server-issued request IDs, no-store responses, bounded JSON bodies and correct rate-limit/dependency error separation.
- Android release signing through environment secrets; release task requires an HTTPS API endpoint. No debug signing fallback. Cleartext and backups are disabled in main manifests; debug manifests retain Wi-Fi test access.
- Release Flutter clients use the compiled HTTPS endpoint rather than a saved development address. The sample UI demo entry is excluded from release mode.
- CI builds signed bundles using a disposable test key and a deliberately non-routable API host. Those bundles are build checks only, never distributed or usable production packages.

## Deployment inputs and next implementation batches

1. Choose hosting/database region and a domain; provision staging with native PostgreSQL/PostGIS, verified TLS, ingress controls and backups. Record actual proxy addresses; never use unrestricted trust proxy. Prove restore/rollback before public launch.
2. Use owner-issued invitations for the private beta (beta-login.md), with OTP_MODE=disabled and BETA_AUTH_ENABLED=true. Add strong operator/admin authentication before exposing their portals. SMS delivery and verified-phone registration remain scheduled for the first post-launch update.
3. Finish recurring bus operations, notification delivery, driver verification and private ride matching, safety/support and complete mobile workflows. Track scope and evidence in DELIVERY_STATUS.md.
4. Implement approved gateway sandbox/webhook/refund/reconciliation workflows before enabling digital payments.
5. Real-device multi-role acceptance, accessibility/localization, security/load testing and operational review; then Play internal testing with durable owner-controlled signing credentials. iOS remains deferred.

## Android owner-controlled signing

For each app, supply RC_KEYSTORE_PATH (absolute path), RC_KEYSTORE_PASSWORD, RC_KEY_ALIAS and RC_KEY_PASSWORD through protected CI environment secrets or the local process environment. Never commit a key or passwords. Back up the owner's real key in secure storage. CI's disposable key must never be used for distribution.

Build from apps/passenger, apps/driver or apps/bus with:

    flutter build appbundle --release --dart-define=API_URL=https://YOUR_API_HOST/v1

This enables correct signing/configuration; it does not certify unfinished product flows as release ready. Hosting and provider credentials are configured outside Git. See infrastructure/deployment/production.env.example.

References: [Flutter Android signing](https://docs.flutter.dev/deployment/android), [Express trusted proxy configuration](https://expressjs.com/en/guide/behind-proxies/).

Update, 19 October 2026: SMS OTP is deferred to the first post-launch app update. For the current private beta, use owner-issued invitations in beta-login.md instead of waiting for an SMS provider. Privileged admin/operator authentication remains a separate unfinished requirement.
