# Interactive map

Home → Open map uses flutter_map with OpenStreetMap standard raster tiles.
It shows streets, rivers, neighbourhood reference points and searched places.
Nearby walking-route suggestions use the backend road graph; see the
[route planner](../../documentation/ROUTE_PLANNER.md) for limits and setup.
No verified flood polygons or verified safe destinations are supplied by the map.
Map selection returns to the existing Home assessment flow. Named neighbourhoods
continue to use place IDs; GPS requests continue to send coordinates only in the
backend POST body. Selecting a marker does not imply a current assessment exists.

## Locations and saved places

The four initial catalogue IDs have approximate reference points in
`lib/maps/map_locations.dart`. These are not measured neighbourhood centroids,
property positions, boundaries or evacuation destinations. References:

- Kibera: https://www.environmentandsociety.org/regions/africa/kenya/nairobi-area/kibera
- Westlands: https://en.wikipedia.org/wiki/Westlands,_Nairobi (Location section)
- Embakasi: https://en.wikipedia.org/wiki/Embakasi
- Kasarani: https://en.wikipedia.org/wiki/Kasarani

Saved places use the same catalogue ID lookup and bookmark markers; their owner
RLS remains unchanged. Unknown IDs remain selectable in the list without an
invented map position. Growing the catalogue should move source-attributed place
coordinates to database metadata. An explicit Search/Enter action now looks up
other public Nairobi-area place names through a cached Photon/OpenStreetMap proxy.
Results include mapped coordinates and can centre the map and load rainfall.
They are temporary selections and do not become catalogue-backed saved places.

Use my location requests one foreground fix. Its marker and metre-based accuracy
circle are separate from neighbourhood pins. Coordinates, accuracy and capture
time distinguish a device fix from an approximate mapped place. Permission denial retains manual selection. A manual choice
supersedes a pending GPS fix. Account changes clear selected/saved map state.

## Tiles and attribution

OSM attribution is visible on the map, with a copyright link immediately below.
The native tile client identifies com.example.floodsafe; web uses browser headers.
The app loads tiles on map opening, not Home startup, with panBuffer=0 and no bulk
download, offline packs, prefetch feature or cache-busting. Keep normal browser
Referer/cache headers. Tile requests reveal the viewed area to the tile provider;
GPS is not sent to the place-name service or saved by this map flow. The weather
proxy rounds selected coordinates to two decimals before requesting Open-Meteo.
Weather estimates, forecast periods and source times appear under Current
conditions; a place's rainfall does not certify flooding or road safety.

OSM standard tiles are a community, best-effort service with no availability
promise. Review suitability and choose a provider with suitable quotas/support
before broader public deployment. Policy:
https://operations.osmfoundation.org/policies/tiles/
Library: https://docs.fleaflet.dev/

Tile errors show a retry control while the list and Home information remain
available. Zoom/recentre buttons, labelled markers, selectable place lists and
location details provide alternatives to map gestures. Automated widget tests
use local image tiles, never the public tile service. Physical-device GPS,
browser rendering and real tile availability still need manual verification.
