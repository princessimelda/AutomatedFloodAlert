# Nairobi place search and rainfall

The old search fields filtered only the four published neighbourhood shortcuts.
The new explicit Search action finds Nairobi-area neighbourhoods, roads and
landmarks through Photon/OpenStreetMap. Choosing a result supplies a mapped
coordinate for both the map and the dashboard. It does not create a flood label.

## Flow

1. User submits a name with Search or Enter; typing alone never queries the provider.
2. `POST /v1/places/search` forwards the public name through a bounded backend proxy.
3. Kenya/Nairobi-area filtering and duplicate removal produce up to six selectable
   results. An empty result differs from a provider/network failure.
4. Selection centres the map or checks Home at the chosen coordinate. It is an
   approximate mapped location, not a GPS fix, with no invented accuracy value.
5. `POST /v1/weather` retrieves Open-Meteo rain and showers for coordinates rounded
   to two decimals. Home and Current conditions show the estimate, interval,
   source time and 24-hour forecast window.
6. Old requests cannot replace a newer selection. Missing or expired rainfall is
   unavailable; neither missing values nor failures become zero rainfall or low risk.

The hourly rain/showers values cover preceding hourly intervals. The forecast
sum covers the explicitly displayed 24-hour window starting at the source's
current hour; it is not labelled as exactly 24 hours from the moment of the click.
Current conditions are model estimates, not local rain-gauge observations.

## Service limits and privacy

The search provider is the [Photon public demo service](https://github.com/komoot/photon#demo-server),
whose operator permits reasonable project use without availability guarantees.
Only submitted searches are sent, at most one new provider request per second per
API process. Results are cached in memory for up to a day, with a 128-entry cap.
`FLOODSAFE_GEOCODING_URL` can switch to a compatible HTTPS Photon service. This
does not use the OSM Foundation's public Nominatim API or implement autocomplete.
Place-name attribution is shown with results. Search public place names, not
personal or confidential information.

Weather responses use a separate bounded cache (ten minutes). Responses expire
after at most fifteen minutes and are refreshed while the panel remains open.
The proxy caps response size and request time, suppresses upstream URL logs, and
uses POST bodies for client coordinates/query text. No location history, new
database records or search account is created. Multiple API workers/instances
would require shared rate limiting before scaling beyond the current single-process prototype.

Search selections are temporary. Persistent saved places retain their existing
catalogue-backed behaviour; this change does not insert arbitrary public places
or bypass the saved-place foreign-key/RLS rules.

Weather estimates and forecasts support preparedness. They are independent of
published flood assessments and do not certify flooding, road safety or shelter
availability. No new rainfall-to-flood threshold is introduced.

## Deployment

Rebuild both the Render backend and Flutter frontend after review and merge.
Defaults work without another API key or database migration. The existing NextGIS
key is still used only for road routing, not geocoding or weather.

References: [Photon API](https://github.com/komoot/photon/blob/master/docs/api-v1.md),
[Open-Meteo weather documentation](https://open-meteo.com/en/docs).

## Verification — 25 November 2026

- Flutter analysis passed. The 74-test suite passed, with two additional focused
  expiry/accessibility cases also passing (76 distinct tests). The final affected
  backend-flow and search tests were rerun after empty-state copy was corrected.
- The 55 isolated backend tests passed; the nine new local-information tests were
  rerun after provider-response validation was tightened. Python lint/format passed.
- A release web build succeeded. Unchanged font files affected by a local cloud
  file-copy timeout were restored byte-for-byte from their tracked Git objects.
- Real browser flows found Mathare from Home and River Road from the map, selected
  their coordinates and displayed Open-Meteo estimates and forecast periods.
- Both external providers are best-effort services; failures and missing rainfall
  remain visible and are never presented as zero rainfall or safe conditions.
