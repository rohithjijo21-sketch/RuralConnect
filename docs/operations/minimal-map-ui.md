# Minimal mobile UI and maps — 21 October 2026

User requested simpler premium interfaces and Uber-style map features for all three apps. Latest steering: notify when the laptop demo is ready.

## Implemented scope

- Shared restrained Material design, consistent spacing, rounded controls, light/dark themes and large tap targets.
- Passenger map, typed stop search, map/list selection of two distinct published stops, service details, map markers linking to directions, existing trips/account navigation.
- Driver Drive / Vehicles / Account navigation, one server-acknowledged availability action, shared-trip editor with named map-picked stops and rupee fare input.
- Bus Today / Manage / Account navigation. Business setup kept separate from current assignments. Primary boarding/start/complete/resume actions, incident controls behind an expansion, existing server approval rules preserved.
- Bus owner route stops can be chosen on a map; manual coordinate entry remains a fallback.
- Pan/zoom fullscreen map, fit stops, opt-in current-location centre, visible OSM attribution, tile errors and permission denial messages. Compact embedded maps let the page scroll.
- Only fresh server-provided active bus locations appear. Stale/offline/terminal or missing positions never become vehicle markers. Fullscreen passenger maps poll their source; map refresh failures remove live markers. Location-centering never uploads device coordinates. Bus trip sharing remains explicit foreground-only.
- Backend bus search/detail returns ordered stop coordinates; existing endpoint authentication remains unchanged.
- Three web demos use read-only sample data, synthetic static stop coordinates explicitly labelled as demo, no fabricated live vehicle positions or confirmed trips.

## Map service

flutter_map 8.3.2, latlong2 and Flutter url_launcher. Small private beta uses the standard HTTPS OpenStreetMap tiles with app identification, native HTTP-aware tile cache and visible linked attribution. No bulk downloads or region prefetch. MAP_TILE_URL is a build configuration override; a different provider also requires its correct attribution. Review capacity and provider suitability before a public commercial launch; OSM tile service has no SLA. https://operations.osmfoundation.org/policies/tiles/

Directions open Google Maps externally at the selected stop, using its own navigation. This is not embedded turn-by-turn navigation, road routing, traffic ETA, background tracking or automatic proximity-based private-driver dispatch. Those remain unfinished backend/provider work; no paid provider account has been created.

## Verification checkpoint

18 shared mobile tests passed (one existing live local-server test skipped unless enabled), plus all four embedded PostgreSQL/PostGIS integration suites including stop coordinates, authorization and scheduling. All three independent launch smoke tests passed. Browser verification confirmed Passenger and Driver maps, Bus Today/Manage navigation and the owner workspace. Final analysis passed before the last formatting-only cleanup; recheck final source in CI. Native Android CI, hosted API update and new APK publication pending. Existing 0.4.0 APKs are unchanged until checked replacement downloads are published.

## Laptop demo

Local-only launcher in task work/serve-mobile-demos.mjs serves apps/*/build/web at http://127.0.0.1:3005/ with Passenger/Driver/Bus selector. Builds use UI_DEMO=true and per-app base paths; never distribute these UI_DEMO browser builds as the real service. All three previews were built and verified in the in-app browser on 21 October. The laptop demo is available at http://127.0.0.1:3005/. Generated web assets are ignored by Git.
