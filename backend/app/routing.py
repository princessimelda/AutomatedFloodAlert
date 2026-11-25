"""Bounded walking-route search. A route is never a flood-safety certification."""

import heapq
import math
from datetime import datetime, timedelta, timezone
from threading import Lock
from time import monotonic
from typing import Literal
from urllib.parse import quote

import httpx
from fastapi import APIRouter, HTTPException
from pydantic import Field, model_validator

from .models import ContractModel
from .repositories import DatabaseUnavailable


class Point(ContractModel):
    latitude: float = Field(ge=-1.50, le=-1.10)
    longitude: float = Field(ge=36.60, le=37.12)

    def xy(self):
        return self.longitude, self.latitude


class RouteRequest(ContractModel):
    origin: Point
    destination: Point | None = None
    avoid_steps: bool = True
    blocked_points: list[Point] = Field(default_factory=list, max_length=12)

    @model_validator(mode="after")
    def bounded(self):
        if self.destination and distance(self.origin.xy(), self.destination.xy()) > 4000:
            raise ValueError("Choose a destination within four kilometres.")
        if any(distance(self.origin.xy(), p.xy()) > 4500 for p in self.blocked_points):
            raise ValueError("Blocked roads must be near the starting point.")
        return self


class RouteResult(ContractModel):
    status: Literal["found", "no_route", "no_assembly_point", "unmapped_start"]
    message: str
    geometry: list[Point] = Field(default_factory=list)
    destination_name: str | None = None
    distance_m: int | None = None
    walking_minutes: int | None = None
    start_gap_m: int | None = None
    destination_gap_m: int | None = None
    roads: list[str] = Field(default_factory=list)
    flood_safety: Literal["unverified"] = "unverified"
    hazard_status: Literal["partial", "unavailable"]
    source: str = "OpenStreetMap contributors"
    generated_at: datetime
    valid_until: datetime


def distance(a, b):
    """Metres, suitable for this small Nairobi search area."""
    dx = (a[0] - b[0]) * math.cos(math.radians((a[1] + b[1]) / 2))
    dy = a[1] - b[1]
    return math.hypot(dx, dy) * 111195


def point_segment(p, a, b):
    dx, dy = b[0] - a[0], b[1] - a[1]
    t = (
        max(0, min(1, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / (dx * dx + dy * dy)))
        if dx or dy
        else 0
    )
    return distance(p, (a[0] + t * dx, a[1] + t * dy))


def intersects(a, b, c, d):
    def cross(p, q, r):
        return (q[0] - p[0]) * (r[1] - p[1]) - (q[1] - p[1]) * (r[0] - p[0])

    def on(p, q, r):
        return (
            abs(cross(p, q, r)) < 1e-12
            and min(p[0], q[0]) <= r[0] <= max(p[0], q[0])
            and min(p[1], q[1]) <= r[1] <= max(p[1], q[1])
        )

    if on(a, b, c) or on(a, b, d) or on(c, d, a) or on(c, d, b):
        return True
    return cross(a, b, c) * cross(a, b, d) < 0 and cross(c, d, a) * cross(c, d, b) < 0


def in_ring(p, ring):
    inside = False
    for a, b in zip(ring, ring[1:]):
        if point_segment(p, a, b) < 0.01:
            return True
        if (a[1] > p[1]) != (b[1] > p[1]) and p[0] < (b[0] - a[0]) * (p[1] - a[1]) / (
            b[1] - a[1]
        ) + a[0]:
            inside = not inside
    return inside


def touches(a, b, geometry):
    polygons = (
        geometry["coordinates"] if geometry["type"] == "MultiPolygon" else [geometry["coordinates"]]
    )
    for polygon in polygons:

        def contains(p):
            return in_ring(p, polygon[0]) and not any(in_ring(p, hole) for hole in polygon[1:])

        if contains(a) or contains(b):
            return True
        if any(intersects(a, b, c, d) for ring in polygon for c, d in zip(ring, ring[1:])):
            return True
    return False


def walkable(tags, avoid_steps):
    if tags.get("highway") not in {
        "footway",
        "path",
        "pedestrian",
        "residential",
        "living_street",
        "service",
        "unclassified",
        "tertiary",
        "secondary",
        "primary",
        "steps",
    }:
        return False
    if tags.get("highway") == "steps" and avoid_steps:
        return False
    if tags.get("foot") in {"no", "private"} or tags.get("access") in {"no", "private"}:
        return False
    if tags.get("ford") not in {None, "no"} or tags.get("flooded") == "yes":
        return False
    if (
        tags.get("highway") in {"primary", "secondary"}
        and tags.get("foot") not in {"yes", "designated"}
        and tags.get("sidewalk") not in {"both", "left", "right", "yes", "separate"}
    ):
        return False
    return True


def solve(request, elements, hazards, hazard_status, now=None):
    now = now or datetime.now(timezone.utc)
    expiry = min([now + timedelta(minutes=10)] + [h["valid_until"] for h in hazards])
    common = dict(hazard_status=hazard_status, generated_at=now, valid_until=expiry)
    nodes = {
        e["id"]: (e["lon"], e["lat"])
        for e in elements
        if e["type"] == "node"
        and "lon" in e
        and -1.50 <= e["lat"] <= -1.10
        and 36.60 <= e["lon"] <= 37.12
    }
    graph = {}
    blocked_nodes = {
        e["id"]
        for e in elements
        if e["type"] == "node"
        and (
            e.get("tags", {}).get("ford") not in {None, "no"}
            or e.get("tags", {}).get("foot") in {"no", "private"}
            or e.get("tags", {}).get("access") in {"no", "private"}
            or e.get("tags", {}).get("locked") == "yes"
            or e.get("tags", {}).get("barrier") in {"wall", "fence", "block"}
        )
    }
    for way in elements:
        tags = way.get("tags", {})
        if way["type"] != "way" or not walkable(tags, request.avoid_steps):
            continue
        ids = way.get("nodes", [])
        for u, v in zip(ids, ids[1:]):
            if u not in nodes or v not in nodes or u in blocked_nodes or v in blocked_nodes:
                continue
            a, b = nodes[u], nodes[v]
            if any(point_segment(p.xy(), a, b) <= 25 for p in request.blocked_points):
                continue
            levels = [h["level"] for h in hazards if touches(a, b, h["geometry"])]
            if "high" in levels:
                continue
            length = distance(a, b)
            if length <= 0 or not math.isfinite(length):
                continue
            cost = length * (3 if "moderate" in levels else 1)
            name = tags.get("name", "Unnamed walking connection")[:120]
            # Foot-specific one-way restrictions are honoured; vehicle one-way is not pedestrian one-way.
            if tags.get("oneway:foot") != "-1":
                graph.setdefault(u, []).append((v, cost, length, name))
            if tags.get("oneway:foot") not in {"yes", "1", "true"}:
                graph.setdefault(v, []).append((u, cost, length, name))
    usable = set(graph) | {edge[0] for edges in graph.values() for edge in edges}

    # Prefer a continuous nearby walking network over isolated mapped courtyard paths.
    # Gaps to the user's pins remain explicitly unverified and are never drawn as roads.
    links = {n: set() for n in usable}
    for u, edges in graph.items():
        for v, *_ in edges:
            links[u].add(v)
            links[v].add(u)
    remaining = set(usable)
    nearby_components = []
    while remaining:
        seed = remaining.pop()
        component, pending = {seed}, [seed]
        for n in pending:
            for v in links[n]:
                if v in remaining:
                    remaining.remove(v)
                    component.add(v)
                    pending.append(v)
        if any(distance(request.origin.xy(), nodes[n]) <= 120 for n in component):
            nearby_components.append(component)
    usable = max(nearby_components, key=len) if nearby_components else set()

    def snap(p):
        if not usable:
            return None, math.inf
        eligible = [
            n
            for n in usable
            if distance(p, nodes[n]) <= 120
            and not any(point_segment(b.xy(), p, nodes[n]) <= 25 for b in request.blocked_points)
            and not any(
                h["level"] == "high" and touches(p, nodes[n], h["geometry"]) for h in hazards
            )
        ]
        if not eligible:
            return None, math.inf
        n = min(eligible, key=lambda n: distance(p, nodes[n]))
        return n, distance(p, nodes[n])

    start, gap = snap(request.origin.xy())
    if (
        start is None
        or gap > 120
        or any(
            touches(request.origin.xy(), nodes[start], h["geometry"]) and h["level"] == "high"
            for h in hazards
        )
    ):
        return RouteResult(
            status="unmapped_start",
            message="No suitable mapped walking connection near your start. Choose another starting point; do not cross floodwater.",
            **common,
        )
    targets = {}
    candidates = []
    if request.destination:
        candidates.append((request.destination.xy(), "Chosen destination"))
    else:
        for e in elements:
            if e.get("tags", {}).get("emergency") != "assembly_point":
                continue
            if e.get("tags", {}).get("access") in {"private", "no"}:
                continue
            p = e if e["type"] == "node" else e.get("center", {})
            if "lon" in p and "lat" in p:
                candidates.append(
                    (
                        (p["lon"], p["lat"]),
                        e.get("tags", {}).get("name", "Mapped assembly point")[:120],
                    )
                )
    for point, name in candidates:
        if distance(request.origin.xy(), point) > 4000:
            continue
        target, target_gap = snap(point)
        if target is None or target_gap > 120 or target == start:
            continue
        # Do not select an assembly point in any recorded elevated-risk area.
        if any(
            h["level"] != "low" and touches(point, nodes[target], h["geometry"]) for h in hazards
        ):
            continue
        targets[target] = (name, target_gap)
    if not targets:
        return RouteResult(
            status="no_route" if request.destination else "no_assembly_point",
            message="No reachable mapped assembly point was found nearby. Choose a destination on the map or contact Emergency Help."
            if not request.destination
            else "Your destination has no suitable mapped walking connection. Choose another destination.",
            **common,
        )
    queue = [(0.0, start)]
    costs, previous = {start: 0.0}, {}
    finish = None
    while queue:
        cost, u = heapq.heappop(queue)
        if cost != costs[u]:
            continue
        if u in targets:
            finish = u
            break
        for v, weight, length, name in graph.get(u, []):
            new_cost = cost + weight
            if new_cost < costs.get(v, math.inf):
                costs[v] = new_cost
                previous[v] = (u, length, name)
                heapq.heappush(queue, (new_cost, v))
    if finish is None:
        return RouteResult(
            status="no_route",
            message="No walking route was found around the recorded hazards and blocked roads. Contact Emergency Help.",
            **common,
        )
    path, roads, total = [finish], [], 0.0
    while path[-1] != start:
        u, length, name = previous[path[-1]]
        total += length
        roads.append(name)
        path.append(u)
    if total > 8000:
        return RouteResult(
            status="no_route",
            message="The available route is too long for this nearby search. Contact Emergency Help.",
            **common,
        )
    path.reverse()
    roads = list(dict.fromkeys(reversed(roads)))[:30]
    return RouteResult(
        status="found",
        message="Suggested walking route. Flood safety and destination availability are unverified. Follow local instructions; never cross floodwater.",
        geometry=[Point(latitude=nodes[n][1], longitude=nodes[n][0]) for n in path],
        destination_name=targets[finish][0],
        distance_m=round(total),
        walking_minutes=max(1, math.ceil(total / 60)),
        start_gap_m=math.ceil(gap),
        destination_gap_m=math.ceil(targets[finish][1]),
        roads=roads,
        **common,
    )


class RoadProvider:
    """One bounded request at a time, cache public map tiles only (not GPS/route results)."""

    def __init__(self, api_key=""):
        self.endpoint = (
            f"https://overpass.nextgis.com/{quote(api_key, safe='')}/api/interpreter"
            if api_key
            else "https://overpass-api.de/api/interpreter"
        )
        self.lock = Lock()
        self.cache = {}
        self.last_fetch = -math.inf

    def fetch(self, request):
        # Coarse tiles and a small corridor avoid city-wide downloads and precise GPS requests.
        lat = math.floor(request.origin.latitude / 0.01) * 0.01
        lon = math.floor(request.origin.longitude / 0.01) * 0.01
        end_lat = (
            math.floor(request.destination.latitude / 0.01) * 0.01 if request.destination else lat
        )
        end_lon = (
            math.floor(request.destination.longitude / 0.01) * 0.01 if request.destination else lon
        )
        bounds = (
            max(-1.50, min(lat, end_lat) - 0.01),
            max(36.60, min(lon, end_lon) - 0.01),
            min(-1.10, max(lat, end_lat) + 0.02),
            min(37.12, max(lon, end_lon) + 0.02),
        )
        key = tuple(round(n, 2) for n in bounds)
        if not self.lock.acquire(blocking=False):
            raise HTTPException(503, "Route search is busy. Try again shortly.")
        try:
            current = monotonic()
            cached = self.cache.get(key)
            if cached and current - cached[0] < 600:
                return cached[1]
            if current - self.last_fetch < 15:
                raise HTTPException(429, "Wait a few seconds before searching a new area.")
            self.last_fetch = current
            bbox = ",".join(f"{n:.2f}" for n in key)
            query = f'[out:json][timeout:20][maxsize:16000000];(way["highway"]({bbox});nwr["emergency"="assembly_point"]({bbox}););out body center;>;out body qt;'
            try:
                with httpx.Client(timeout=25, follow_redirects=False) as client:
                    with client.stream(
                        "POST",
                        self.endpoint,
                        data={"data": query},
                        headers={
                            "User-Agent": "FloodSafe/0.1 (+https://github.com/princessimelda/AutomatedFloodAlert)"
                        },
                    ) as response:
                        response.raise_for_status()
                        body = bytearray()
                        for chunk in response.iter_bytes():
                            body.extend(chunk)
                            if len(body) > 12_000_000:
                                raise ValueError("Map response exceeded limit")
                import json

                data = json.loads(body)
                elements = data["elements"]
                if data.get("remark") or not isinstance(elements, list) or len(elements) > 100000:
                    raise ValueError("Incomplete map response")
                # Recursion output may repeat tagged nodes. Preserve tagged originals.
                unique = {}
                for e in elements:
                    unique.setdefault((e["type"], e["id"]), e)
                elements = list(unique.values())
            except (httpx.HTTPError, ValueError, KeyError, TypeError):
                raise HTTPException(503, "Road information is temporarily unavailable.") from None
            self.cache = {key: (current, elements)}
            return elements
        finally:
            self.lock.release()


def route_router(store, provider=None, api_key=""):
    router = APIRouter()
    provider = provider or RoadProvider(api_key)
    search_lock = Lock()

    @router.post("/v1/routes", response_model=RouteResult)
    def route(request: RouteRequest):
        # Coordinates stay in POST bodies, never app logs or database records.
        if not search_lock.acquire(blocking=False):
            raise HTTPException(503, "Route search is busy. Try again shortly.")
        try:
            try:
                hazards = store.route_hazards()
            except DatabaseUnavailable:
                # A database outage is explicitly unknown hazard coverage, never an all-clear.
                hazards = []
            elements = provider.fetch(request)
            return solve(request, elements, hazards, "partial" if hazards else "unavailable")
        finally:
            search_lock.release()

    return router
