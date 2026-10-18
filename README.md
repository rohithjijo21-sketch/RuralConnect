# RuralConnect

A Kerala-first transport monorepo: Passenger, Driver and Bus Flutter clients, Next.js operator portal, NestJS API and PostgreSQL/PostGIS.

**Development build. Not a production release.** Read [DELIVERY_STATUS.md](DELIVERY_STATUS.md) for requirement-by-requirement evidence and remaining work. No real SMS, digital payment, FCM delivery or simulated live positions are enabled.

## Requirements

Node 24.15+, pnpm 11.25.0, Docker with Compose, Flutter stable with Android SDK. iOS requires macOS and Xcode. The development machine used Node 24.19 and subsequently installed Flutter 3.47.7/Dart 3.13.5. Docker/native PostgreSQL and Android SDK were unavailable locally.

## Local services

From the repository root:

```sh
corepack enable
corepack prepare pnpm@11.25.0 --activate
pnpm install --frozen-lockfile
cp .env.example .env
# Edit .env: choose a PostgreSQL password and match it in DATABASE_URL.
# Generate a random SANDBOX_ACCESS_KEY and a six-digit SANDBOX_OTP_CODE.
docker compose --env-file .env -f infrastructure/docker/compose.yaml up -d
pnpm db:migrate
pnpm db:seed
pnpm dev:api
```

In another terminal:

```sh
# Export NEXT_PUBLIC_API_URL=http://localhost:3001/v1, or place it in apps/admin/.env.local
pnpm dev:admin
```

Open http://localhost:3000. Admin uses API memory-only sessions and requires sign-in again after reload/expiry. API access tokens expire after 15 minutes; mobile implements refresh rotation. All clients must use the SAME API and database.

Demo fixture phone numbers: passenger +919000000001, auto driver +919000000002, bus crew +919000000003, operator +919000000004. Use only your locally configured sandbox key/code. These are local test identifiers; no messages are sent. Production refuses sandbox authentication. Re-run seed on each new service day; it creates one dated DEMO service without GPS data or payments.

## Mobile

```powershell
./scripts/bootstrap-mobile.ps1
cd apps/passenger
flutter run --dart-define=API_URL=http://10.0.2.2:3001/v1
# Repeat from apps/bus and apps/driver with the same API_URL.
```

10.0.2.2 is Android emulator loopback. Physical devices need an accessible development host address and firewall configuration. Use HTTPS outside a local emulator. Follow [mobile configuration](docs/operations/mobile.md) before location testing. Platform projects and baseline foreground permissions are committed; signing, final icons and release configuration remain unfinished. Original Dart sources are preserved by the bootstrap script.

## Test and build

```sh
pnpm test
pnpm typecheck
pnpm build
# Embedded PostgreSQL + experimental PostGIS: applies migrations, seeds and tests HTTP/WebSocket workflows.
pnpm --filter @ruralconnect/api test:embedded
# Against a fresh disposable native PostgreSQL/PostGIS database:
# DATABASE_URL must contain ruralconnect_test. Set RUN_DB_TESTS=1.
pnpm --filter @ruralconnect/api test:integration
pnpm --filter @ruralconnect/worker start
pnpm contracts:generate
```

The native integration database must be migrated and seeded with OTP_MODE=sandbox first. Never point test commands at operational data. CI creates a disposable database. Embedded database tests do not prove native PostgreSQL race behavior or deployment reliability.

```sh
cd apps/passenger
flutter analyze
flutter test
flutter build apk --release --dart-define=API_URL=https://YOUR-STAGING-API/v1
# Repeat for driver and bus.
# On macOS, after Xcode/signing/permissions are configured:
flutter build ios --release --no-codesign --dart-define=API_URL=https://YOUR-STAGING-API/v1
```

## Implemented bus scenario

1. Sign into the operator portal; create a route with ordered stop offsets, then assign an approved bus and authorised crew to a dated service.
2. Sign into Bus as assigned crew. Select that service, mark BOARDING, then RUNNING with an incident reason.
3. Enable foreground GPS while safely stopped. Actual device positions are validated by the API. No GPS data exists until a device supplies it.
4. Passenger searches origin/destination and opens the service. It refetches and consumes authenticated WebSocket events with a replay cursor.
5. Bus crew reports delay/breakdown/cancellation. Passenger and operator refetch the persisted state. Missing/stale coordinates remain unavailable; scheduled times are not presented as live ETAs.
6. Only the owning operator/admin may reinstate a cancelled dated service. All changes are audited. Recurring schedules remain untouched.

This bus workflow passed backend HTTP/database/WebSocket tests. Mobile execution and human end-to-end acceptance remain unverified.

## Documentation

- [Architecture, decisions and diagrams](docs/architecture/design.md)
- [Product requirements and navigation](docs/product/requirements.md)
- [API contracts](packages/api-contracts/openapi.json) and [events](docs/api/events.md)
- [Plan and progress](docs/PROGRESS.md)
- [Operations and release gates](docs/operations/runbook.md)
- [Security and compliance register](docs/compliance/register.md)

No production deployment or paid purchase has been performed. Staging deployment is a manual, approval-gated runbook; no cloud provider credentials were supplied.
