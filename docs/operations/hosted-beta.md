# Hosted private beta

The owner authorized internet-accessible beta hosting on 19 October 2026.
Account connections are still required; no hosted URL has been provisioned or verified.

## Deployment configuration

The root `render.yaml` selects a single Free Docker web service in Singapore,
manual deployments, and `/v1/ready` health checks. The database is a separate
Neon Free project; do not create Render's expiring free database. Do not add a
payment method or select a paid plan without the owner's authorization.

Before applying the blueprint:

1. Connect the owner's Render and Neon accounts. Confirm Free plans and available regions.
2. Create an empty private-beta database with PostGIS support, preferably near Singapore.
3. Put its connection string in Render's secret `DATABASE_URL` with exactly one
   `sslmode=verify-full`. Never copy the URL into Git, screenshots or chat.
4. Set `ADMIN_ORIGIN` to the actual API HTTPS origin while no admin website is
   deployed. Native Android clients do not require a browser origin allowance.
5. Obtain and verify actual ingress proxy addresses/CIDRs before setting
   `TRUSTED_PROXY_CIDRS`. Do not use wildcard trust, guessed ranges, or disable HTTPS.

The hosted startup validates production configuration, runs transactional locked
migrations, and starts the API only on success. It never runs demo seeds.
The existing Docker image includes the migration runner's tsx dependency.
No local `.env` file is required. Migration errors stop startup without forwarding
raw database error details. Container build and hosted execution still need verification.

## Acceptance before sharing apps

- Verify the public HTTPS `/v1/health` and `/v1/ready` endpoints.
- Confirm unauthenticated protected requests are rejected and sandbox OTP is disabled.
- Verify forwarded client addresses and HTTPS handling, including spoofed headers.
- Issue a private tester invitation from the owner's trusted workstation using
  `beta-login.md`; confirm redemption and session refresh against the hosted API.
- Verify data survives service restart. Never store data in the container filesystem.
- Configure real driver/vehicle approvals and bus assignments before testing those flows.
- Build and test all three Android apps with the actual HTTPS URL, then publish
  usable APK downloads and test on mobile data with the laptop server stopped.

Render Free sleeps after 15 idle minutes; initial requests can take about a minute.
Free-tier quotas and unfinished product workflows mean this is private beta hosting,
not verified production readiness. SMS remains deferred to the first app update.

References: https://render.com/docs/free, https://render.com/docs/blueprint-spec,
https://neon.com/pricing.
