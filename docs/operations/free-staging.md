# Free staging hosting plan

18 October 2026. User preference: minimize cost and use free tiers while building. No cloud accounts, services or purchases have been created.

| Component          | Candidate                       | Fit and limitations                                                                                                                                                                                       |
| ------------------ | ------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Admin portal       | Cloudflare Pages static hosting | Optional Next.js static export is implemented. Calls the separately hosted API; it does not host the API or database. Real operator authentication/MFA remains unfinished.                                |
| API / WebSockets   | Render Free web service         | Supports the long-running Node API. Sleeps after 15 idle minutes, cold starts and quotas apply. Provider explicitly excludes production use recommendations. No free always-on background worker assumed. |
| PostgreSQL/PostGIS | Neon Free                       | Supports PostGIS. Subject to current storage/compute quotas and cold starts. Validate migration permissions, connection TLS, region and latency in staging.                                               |
| APK downloads      | Existing GitHub prereleases     | Testing distribution already works. Play distribution and commercial release gates are separate.                                                                                                          |
| Phone OTP          | Not configured                  | Hosting does not supply free SMS. Choose a real provider and account before enabling production sign-in.                                                                                                  |

## Admin static build

Set NEXT_PUBLIC_API_URL to the actual HTTPS API address ending in /v1. From the repository root run:

    pnpm --filter @ruralconnect/admin build:static

Output: apps/admin/out. Deploy this directory as static assets (Cloudflare Pages supports Next.js Static HTML Export). Use the generated provider subdomain initially; no custom domain purchase is necessary for testing. All NEXT_PUBLIC variables are public: never place secrets in them. The default admin build remains a normal Next.js build.

## Backend preparation

Build infrastructure/docker/Dockerfile.api from repository root. Configure production variables from infrastructure/deployment/production.env.example using the hosting dashboard. DATABASE_URL belongs only on the server. Apply migrations as a controlled release step before exposing the service; never seed demo accounts into production. Verify provider ingress proxy IP/CIDRs and HTTPS forwarding before enabling API traffic. Do not substitute unrestricted proxy trust to bypass the transport checks.

Authentication stays disabled until real OTP/registration and operator protections are implemented. This plan prepares staging; it is not a claim that public sign-in or commercial bookings are ready. The local phone testing setup remains available without cloud costs.

## Important cost boundaries

Vercel Hobby is limited to personal/non-commercial use; Vercel Functions cannot host our WebSocket server. Free Render services sleep and may suspend at quota limits; Render's free database expires after 30 days, so do not use that database for this plan. Do not add payment details or enable paid upgrades/overages without the owner's approval. Recheck current terms and included quotas when creating the accounts.

Sources: [Render Free](https://render.com/docs/free), [Render billing FAQ](https://render.com/docs/faq), [Cloudflare static Next.js](https://developers.cloudflare.com/pages/framework-guides/nextjs/deploy-a-static-nextjs-site/), [Neon PostGIS](https://neon.com/docs/extensions/postgis), [Neon plans](https://neon.com/pricing), [Vercel Hobby](https://vercel.com/docs/plans/hobby), [Vercel limits](https://vercel.com/docs/limits), [Phone login provider requirement](https://supabase.com/docs/guides/auth/phone-login).
