# Punto de Apoyo Venezuela

> Collaborative emergency map for Venezuela after the 2026 earthquake. Community-driven, non-profit.

**Production**: [puntodeapoyovenezuela.com](https://www.puntodeapoyovenezuela.com/)
**Contact**: [@vxlentinF](https://twitter.com/vxlentinF)

---

## What is it?

A single-file web app (`index.html`) that shows on a map:

- Hospitals with patient counts and blood donor requests
- Official collection centers (centros de acopio) from verified public sources
- Citizen offers (water, power, transport, supplies, etc.)
- Citizen requests (medical help, transport, food, etc.)
- Danger zones / rescue situations

Users can **report points anonymously**, **confirm** verified info, and **mark requests as fulfilled** (requires 2 separate confirmations).

## Stack

- **Frontend**: vanilla HTML + JavaScript, no build step, no framework
- **Map**: Leaflet with CartoDB Voyager tiles, Leaflet.markerCluster for grouping
- **DB**: Supabase (PostgreSQL + Realtime + RLS)
- **Hosting**: Vercel (HTTPS, global CDN, privacy-friendly analytics)
- **Geocoding**: Nominatim (OpenStreetMap) with cache and hardcoded Venezuelan hospital dictionary

## Features

- Auto geolocation + locate button
- Search with autocomplete (Nominatim, Venezuela-only)
- 3-step onboarding on first visit
- Confirmation system per report (anti-double-vote via RPC)
- Mark requests as fulfilled (requires 2 distinct confirmations + mandatory note)
- Blood donor badge on hospitals actively requesting donations
- Map bounded to Venezuela (cannot pan outside)
- Dark UI for battery savings, light map tiles for readability
- Mobile responsive, dynamic viewport (`100dvh`)
- Realtime: new reports appear instantly via Supabase channels
- Strict CSP, input sanitization, DB-level rate limiting

## Data sources

| Source | Type | Frequency | License / attribution |
|---|---|---|---|
| OpenStreetMap | Tiles + geocoding | — | © OpenStreetMap contributors (ODbL) |
| CartoDB Voyager | Map tiles | — | © CARTO |
| [ayudaparavenezuela.com](https://ayudaparavenezuela.com) | Collection centers (verified, `is_active`) | 30 min | Free use with attribution |
| Google Sheets (hospitals) | Patient counts | 15 min | Public community-maintained list |
| [caracasayuda.com](https://caracasayuda.com) | Citizen reports (Supabase) | 30 min | Caracas Merch initiative, attribution shown |
| [localizadosvenezuela.com](https://localizadosvenezuela.com) | Hospitals + located persons count | On-load | MIT, by Giuseppe Gangi |

All integrated data is **read-only** from public APIs or public sheets. If your platform wants to integrate or opt out, open an issue or reach out on X.

## Deploy

### Vercel (recommended)

1. Fork this repo on GitHub
2. Connect to Vercel (Workers & Pages → New project → Import repo)
3. Build settings: leave everything empty (static HTML)
4. Output directory: `/`
5. Variables: none required (Supabase credentials are anon key, embedded in `index.html`)
6. Deploy

HTTPS and CDN are automatic. Geolocation requires HTTPS — Vercel handles that.

### Supabase

Run `supabase_setup.sql` in the SQL Editor of your project. It is idempotent — creates the `reports` table, RPCs `confirm_report` and `fulfill_report`, RLS policies, rate limits, and constraints.

Make sure to:
1. Use **only the `anon` key** in the HTML (never `service_role`)
2. Set **Site URL** in Authentication → URL Configuration to your domain
3. Enable **Realtime** on the `reports` table so inserts broadcast to all clients

## Privacy

- No accounts, no email, no name required.
- Geolocation happens only in the browser, never sent to any server.
- Reports store only: lat/lng, category, type, optional note, timestamp. No PII.
- Anonymous local fingerprint (UUID in localStorage) for rate-limiting and anti-double-vote only.
- Help requests are automatically hidden after 24 hours; offers after 72 hours (enforced by RLS).
- No third-party cookies. Vercel Analytics is privacy-friendly and first-party.

## Contributing

Any PR is welcome, especially:

- **Hospital coordinates** missing in `HOSPITAL_COORDS` (search in `index.html`)
- **Copy improvements** or translations
- **Bug fixes** or accessibility improvements
- **Security reports**: via DM at [@vxlentinF](https://twitter.com/vxlentinF), please do not open a public issue

## License

[MIT](LICENSE) — use, remix, modify with attribution. If you build something derived, ideally coordinate to avoid duplicating efforts: there are many sister initiatives and cross-pollination is valuable.

## Credits

Built with AI assistance (Claude). Inspired and enriched by the work of many communities:

- [ayudaparavenezuela.com](https://ayudaparavenezuela.com) — verified collection center database (primary centro source)
- [caracasayuda.com](https://caracasayuda.com) (Caracas Merch) — citizen reports integration
- [localizadosvenezuela.com](https://localizadosvenezuela.com) (Giuseppe Gangi, [@ggangix](https://twitter.com/ggangix)) — hospital data
- [terremotovenezuela.app](https://terremotovenezuela.app) (Arturo Rios, [open source](https://github.com/ArturoRiosMock/mapa-emergencia-rescate))
- Comando ConVzla, Caritas, Venezuelan Red Cross, municipalities, NGOs, and thousands of citizens who maintain the public lists.

*Solidarity is our greatest strength.*
