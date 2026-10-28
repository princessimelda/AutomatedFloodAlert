# Interactive map

Home → Open map uses flutter_map with OpenStreetMap standard raster tiles.
No map account or paid key is configured for the development preview. It shows
streets, rivers and supported neighbourhood reference points. It provides no
flood polygons, safe destinations, route calculation or inferred flood severity.
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
coordinates to database metadata. No public geocoding endpoint is called.

Use my location requests one foreground fix. Its marker and metre-based accuracy
circle are separate from neighbourhood pins. Coordinates, accuracy and capture
time appear in text. Permission denial retains manual selection. A manual choice
supersedes a pending GPS fix. Account changes clear selected/saved map state.

## Tiles and attribution

OSM attribution is visible on the map, with a copyright link immediately below.
The native tile client identifies com.example.floodsafe; web uses browser headers.
The app loads tiles on map opening, not Home startup, with panBuffer=0 and no bulk
download, offline packs, prefetch feature or cache-busting. Keep normal browser
Referer/cache headers. Tile requests reveal the viewed area to the tile provider;
GPS is not sent to a separate geocoding service or saved by this map flow.

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
