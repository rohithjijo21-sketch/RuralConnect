# Passenger laptop preview

The passenger Flutter app now has a web target. Build a clearly labelled UI preview:

    cd apps/passenger
    flutter build web --debug --dart-define=UI_DEMO=true

Serve apps/passenger/build/web on localhost:3000 and open http://localhost:3000. The demo opens directly and uses sample schedules; no real reservation or payment is created. Use Connect to reach the normal server setup screen. For local live testing use the same API and fixture credentials as the Android apps; the API's configured browser origin must match localhost:3000. Do not put sandbox credentials into the build.

Browser clients use the existing authenticated HTTP polling fallback for bus updates, because browser WebSockets cannot attach the Authorization header required by the API. Native Android retains its authenticated WebSocket connection. Tokens are not moved into URLs.

This is a local development preview, not a hosted production website. The server must be running while viewing it. Release build restrictions and production work remain unchanged.

## Auto-driver preview

Build from apps/driver:

    flutter build web --debug --base-href=/driver/ --dart-define=UI_DEMO=true

Copy apps/driver/build/web into apps/passenger/build/web/driver and serve the passenger web root. Open http://localhost:3000/driver/. The preview shows a labelled sample auto and shared service, without creating a session or allowing mutations. Availability, driver approval, bookings and earnings are not real in this demo. Use server settings for actual local test sign-in. Native Android behavior is retained.
