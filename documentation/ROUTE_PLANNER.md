# Nearby walking-route planner

Related issue: #14. This implements a walking-road search, not an authority-approved
evacuation service. Do not close the complete issue until destination verification,
hazard coverage and operational evaluation are addressed.

## Behaviour

`POST /v1/routes` accepts a Nairobi starting point, an optional destination, up to
12 locally marked blocked-road points, and an option to avoid mapped stairs.
Without a destination, candidates come only from OpenStreetMap
`emergency=assembly_point` features. Missing candidates produce an explicit result
and a manual-destination option; parks, schools and hospitals are not invented as
evacuation shelters. Assembly points are unverified for availability and flood safety.

An adjacency graph is built from mapped pedestrian-compatible roads. Dijkstra's
algorithm minimises nonnegative distance-based costs to a reachable candidate.
High-risk polygon intersections are excluded; moderate-risk intersections cost
three times their distance. Recorded private/restricted access, fords, and blocked
points within 25 metres of a road segment are excluded. Vehicle one-way rules do
not become pedestrian restrictions; explicit foot one-way rules are honoured.
Avoiding stairs does not establish wheelchair accessibility.

Only current, published, non-demo PostGIS assessments with published non-demo
geometry affect route costs. Rainfall proxy scores and seeded polygons never
become street-level flood boundaries. Hazard coverage is always labelled partial
or unavailable. A database outage produces unavailable coverage, never a safe
route designation. Actual local instructions take precedence.

Both endpoints must be within 120 metres of a suitable graph node on a continuous
nearby walking network (preferred over isolated courtyard fragments); otherwise the
request fails explicitly. The route line follows graph edges only. The UI reports
unverified gaps to the pins rather than drawing straight lines across unknown
terrain. This node-based snapping can miss roads with long gaps between mapped
nodes. Path length is capped at eight kilometres; chosen destinations must be
within four kilometres straight-line distance. Areas outside the bounded Nairobi
region are rejected. These limits need field evaluation.

## Provider and privacy

The fixed HTTPS Overpass endpoint is queried with a coarse bounding box, never
the exact GPS position. No redirects, coordinate query strings, route-result
persistence, or app access logs. Cache one public map region for ten minutes;
serialize provider fetches and wait at least 15 seconds between new regions.
The public shared service can reject or delay requests; errors remain explicit.
Timeout, response-size and element-count bounds protect the small deployment.
This shared endpoint is suitable for limited prototype testing, not guaranteed
emergency availability. Re-evaluate a dedicated extract/provider before wider use.

Route validity ends after ten minutes or the earliest hazard expiry. The client
clears expired results and discards late responses when selections change.
Walking time assumes 60 metres/minute and excludes delay or mobility limitations.

References: [Overpass API](https://wiki.openstreetmap.org/wiki/Overpass_API),
[pedestrian access tags](https://wiki.openstreetmap.org/wiki/Key:foot),
[assembly points](https://wiki.openstreetmap.org/wiki/Tag:emergency%3Dassembly_point).

## Checks

Known-graph tests cover shortest paths, moderate penalties, blocked/high-risk
edges, polygon boundaries and holes, manual destinations, missing assembly points,
access/stair restrictions, unmapped starts, strict input bounds and redacted errors.
Flutter tests cover late result rejection and seasonal advisory dates.

## Live verification on 25 November 2026

The original unkeyed public endpoints failed (HTTP 406, timeouts and connection
failure). The user supplied a NextGIS key privately. Authentication succeeded;
the initial city-sized download exceeded the explicit 12 MB response limit.
After narrowing the search, live retrieval returned 16,629 OSM elements. A manual
nearby-destination check produced an 855-metre route with 33 mapped points.
The mapped assembly point in that region was not reachable through the eligible
walking network; automatic search correctly did not return it as a safe destination.
Supabase's read-only hazard query succeeded and returned zero current non-demo
polygons. Therefore flood coverage remains unavailable, not clear of flooding.

Optional free NextGIS support is prepared. In a NextGIS account, use Software and
services → Overpass API → Create API key ([official instructions](https://docs.nextgis.com/docs_ngcom/source/services.html)).
Save the key in ignored `backend/.env.routing` as `FLOODSAFE_ROUTE_OVERPASS_KEY`.
Restart the API after adding it. Production uses the same environment variable on
the Render **backend web service**, never on the Flutter static site. Credentials
are kept server-side; request URLs from HTTP clients are not logged. The provider was verified through the local API with the user-supplied key: HTTP
200, an 855-metre route and 33 mapped points. No paid plan was created automatically.

Automatic assembly searches use an approximately 3.3 km-wide map region around
a coarse start tile (not a guaranteed four-kilometre radius). Manual destinations
expand a bounded corridor. Large responses fail explicitly rather than exceeding
server memory limits. Known blocked points and high-risk polygons also prevent
snapping across a recorded hazard. Pin-to-road access remains unverified.

Final local verification: 71 Flutter tests and 46 isolated backend tests passed;
Flutter analysis and Python lint passed. The Supabase hazard query succeeded in
read-only mode. The NextGIS key file remains ignored and was never printed or
embedded in Flutter. Render deployment is pending user review and approval.

Browser verification also completed against the running API: emulated GPS, map
destination selection, a rendered route and the 855-metre result. The page showed
the flood-safety limitation and unverified gaps to the map pins. The startup
loading message was confirmed to disappear after Flutter rendered its first frame.
