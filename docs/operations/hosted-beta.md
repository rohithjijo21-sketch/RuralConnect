# Hosted private beta

The owner authorized internet-accessible beta hosting on 19 October 2026.
The beta API is deployed at https://ruralconnect-beta-api.onrender.com/v1.
Hosting checks below passed on 21 October; real-device and complete app acceptance remain open.

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
5. On Render Free use `INGRESS_MODE=render`, guarded by Render's runtime metadata.
   Do not add competing `TRUSTED_PROXY_CIDRS` values. Other hosts retain explicit
   trusted ingress addresses; do not guess ranges or disable HTTPS.

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

## 20 October deployment checkpoint

Neon project steep-recipe-63187389 / branch br-icy-brook-b3f8o1wi exists in Singapore on the confirmed Free plan. The owner approved transferring its credential into Render. The Render creation form is prepared (not submitted), with Free Docker compute, manual deploys, guarded migration startup and /v1/ready checks. Final browser confirmation for internet exposure is pending. No service URL or successful hosted migration is claimed. Ingress proxy verification remains open; no unrestricted proxy trust is configured. The latest source a6c8bab and authentication hardening 8f9cd61 both passed complete GitHub CI. Credentials are not recorded here.

## 21 October first deployment

User approved public free beta deployment. Render service srv-dbc4us3bc2fs73bakp30 was created with manual deployments in Singapore. First deploy a6c8bab is live at https://ruralconnect-beta-api.onrender.com. HTTPS health and database readiness returned 200. Protected requests initially returned 400 because managed ingress terminates TLS. An explicit INGRESS_MODE=render adapter follows Render's immediate-hop proxy guidance, requires RENDER=true and a valid RENDER_SERVICE_ID, and cannot mix with CIDR overrides. Other hosts keep the explicit address policy. The free service has no private-network ingress; confirm forwarded-header behavior after deployment. Admin CORS origin currently uses an intentionally non-routable HTTPS origin because no browser admin portal is deployed. Source: https://render.com/articles/how-to-implement-authentication-and-authorization . Beta device/login acceptance remains outstanding.

Verified hosted source 7a8d09c: health 200, readiness 200, unauthenticated /me 401, disabled OTP 403, invalid invite 401, role-injection body 400, HTTP edge redirect 301 to HTTPS. The second deployment successfully reused existing migrations. No real tester invitation was issued, and no real-device or full booking flow is claimed. Local backend build and 13 unit tests passed.

## Bus owner deployment checkpoint — 21 October 2026

Source 043296a passed native CI 39555615280 and was deployed to existing Render service via deployment dep-dbccrmks728c73eo4mkg. Readiness now requires migration 004_bus_owner.sql and returned 200. Generated API exposes owner workspace routes; unauthenticated access returns 401. A separate single-use verification login fetched the owner workspace successfully and confirmed no owner application, buses, routes or timetables have been fabricated. Attempting status=APPROVED in owner registration returned 400. Verification session was logged out; fresh private app invitations remain unused. Android 0.4.0 prerelease contains all three APKs and hashes. User should install the Bus update and register their real owner details. Real operator and vehicle approval remains required before publishing.

## Private rides and premium UI checkpoint — 21 October 2026

Source 5f6b426f981678f60701c5cf577404e63739d73c passed the native platform job in CI 39633711359 and was deployed to existing Render Free service through deployment dep-dbcedtom7kps73ffvppg. Render confirmed Deploy succeeded / Live. Migration 005_private_rides.sql applied successfully. External HTTPS health and readiness returned 200; unauthenticated driver offers and private quotes returned 401, and OpenAPI contains the new quote endpoint. Authenticated real-user/device acceptance was deferred by user choice. Existing invitations and signed-in sessions were retained.

All three local read-only previews were rebuilt with the ivory/charcoal/champagne identity and bundled Manrope font. Passenger Taxi / auto opens the new private ride page. The demo does not create real rides or invent GPS. Native mobile CI and 0.6.0 APK publication remain pending. Do not distribute the failed initial private source 5f91112; its independent test setup failure was fixed in 5f6b426. Tag android-dev-v0.6.0 at exactly 5f6b426 only after the complete CI run passes. The release notes in that source describe temporary cash pricing and limitations.

## 23 October hosted rollout

Timetable revisions and safe reinstatement are live from 9b1b134 through Render deployment dep-dbdcienavr4c739jg6jg. Health/readiness 200, generated revision request contract and protected owner 401 were verified. Android 0.7.0 APKs and hashes are published after complete exact-source CI; no manual owner deployment action remains pending. Device acceptance and remaining master requirements stay open.
