from datetime import datetime, timedelta, timezone

import pytest
from fastapi.testclient import TestClient
from pydantic import ValidationError

from app.config import Settings
from app.main import create_app
from app.routing import Point, RoadProvider, RouteRequest, solve, touches, walkable


def network():
    points = [(1, 36.82, -1.28), (2, 36.821, -1.28), (3, 36.821, -1.278), (4, 36.822, -1.28)]
    return [
        {
            "type": "node",
            "id": i,
            "lon": x,
            "lat": y,
            "tags": {"emergency": "assembly_point", "name": "Mapped meeting place"}
            if i == 4
            else {},
        }
        for i, x, y in points
    ] + [
        {
            "type": "way",
            "id": 10,
            "nodes": [1, 2, 4],
            "tags": {"highway": "footway", "name": "Short road"},
        },
        {
            "type": "way",
            "id": 11,
            "nodes": [1, 3, 4],
            "tags": {"highway": "footway", "name": "Alternative road"},
        },
    ]


def request(**kwargs):
    return RouteRequest(origin=Point(latitude=-1.28, longitude=36.82), **kwargs)


def hazard(level="high"):
    return {
        "level": level,
        "valid_until": datetime.now(timezone.utc) + timedelta(minutes=4),
        "geometry": {
            "type": "Polygon",
            "coordinates": [
                [
                    [36.8208, -1.2802],
                    [36.8212, -1.2802],
                    [36.8212, -1.2798],
                    [36.8208, -1.2798],
                    [36.8208, -1.2802],
                ]
            ],
        },
    }


def test_shortest_path_and_automatic_destination_use_road_graph():
    result = solve(request(), network(), [], "unavailable")
    assert result.status == "found"
    assert result.distance_m == 222
    assert result.roads == ["Short road"]
    assert result.destination_name == "Mapped meeting place"
    assert result.flood_safety == "unverified"
    assert result.hazard_status == "unavailable"


@pytest.mark.parametrize("level", ["moderate", "high"])
def test_risk_weighted_path_avoids_shorter_hazardous_road(level):
    result = solve(request(), network(), [hazard(level)], "partial")
    assert result.status == "found"
    assert result.roads == ["Alternative road"]
    assert result.distance_m > 222
    assert result.valid_until <= hazard(level)["valid_until"]


def test_blocked_road_no_path_and_no_assembly_are_distinct():
    result = solve(
        request(blocked_points=[Point(latitude=-1.28, longitude=36.821)]),
        network(),
        [],
        "unavailable",
    )
    assert result.roads == ["Alternative road"]
    elements = network()
    elements[3]["tags"] = {}
    assert solve(request(), elements, [], "unavailable").status == "no_assembly_point"
    assert (
        solve(
            request(destination=Point(latitude=-1.28, longitude=36.822)),
            elements,
            [],
            "unavailable",
        ).status
        == "found"
    )
    elements = network()
    elements[-1]["tags"]["access"] = "private"
    assert solve(request(), elements, [hazard()], "partial").status != "found"


def test_unmapped_origin_does_not_draw_invented_connector():
    result = solve(
        RouteRequest(origin=Point(latitude=-1.3, longitude=36.82)), network(), [], "unavailable"
    )
    assert result.status == "unmapped_start"
    assert result.geometry == []


def test_polygon_boundary_and_holes():
    polygon = {
        "type": "Polygon",
        "coordinates": [
            [[0, 0], [4, 0], [4, 4], [0, 4], [0, 0]],
            [[1, 1], [3, 1], [3, 3], [1, 3], [1, 1]],
        ],
    }
    assert touches((0, 0), (0, 0.5), polygon)
    assert touches((-1, 2), (5, 2), polygon)
    assert not touches((1.5, 2), (2.5, 2), polygon)


def test_access_and_steps_are_respected():
    assert not walkable({"highway": "motorway"}, False)
    assert not walkable({"highway": "footway", "ford": "yes"}, False)
    assert not walkable({"highway": "footway", "foot": "no"}, False)
    assert not walkable({"highway": "steps"}, True)
    assert walkable({"highway": "steps"}, False)
    assert not walkable({"highway": "primary"}, False)


def test_input_limits_and_nonfinite_values():
    for origin in [
        {"latitude": float("nan"), "longitude": 36.82},
        {"latitude": 0, "longitude": 36.82},
    ]:
        with pytest.raises(ValidationError):
            RouteRequest(origin=origin)
    with pytest.raises(ValidationError):
        request(destination=Point(latitude=-1.4, longitude=36.82))


def test_provider_uses_fixed_endpoint_and_caches_public_region(monkeypatch):
    import httpx

    calls = []
    original_client = httpx.Client

    def respond(req):
        calls.append(req)
        return httpx.Response(200, json={"elements": network()})

    monkeypatch.setattr(
        "app.routing.httpx.Client",
        lambda **kw: original_client(transport=httpx.MockTransport(respond), **kw),
    )
    provider = RoadProvider("sample/private?key")
    assert provider.endpoint.startswith("https://overpass.nextgis.com/")
    assert "sample%2Fprivate%3Fkey" in provider.endpoint
    assert provider.fetch(request()) == network()
    assert provider.fetch(request()) == network()
    assert len(calls) == 1
    assert b"-1.280000" not in calls[0].content


def test_tagged_ford_node_breaks_connection():
    elements = network()
    elements[1]["tags"] = {"ford": "yes"}
    result = solve(request(), elements, [], "unavailable")
    assert result.roads == ["Alternative road"]


def test_http_route_contract_uses_injected_provider_and_redacts_input():
    class Provider:
        def fetch(self, request):
            return network()

    settings = Settings(_env_file=None, data_mode="fixtures", allow_demo_data=True)
    with TestClient(create_app(settings, route_provider=Provider())) as client:
        response = client.post(
            "/v1/routes", json={"origin": {"latitude": -1.28, "longitude": 36.82}}
        )
        assert response.status_code == 200
        assert response.json()["status"] == "found"
        assert response.headers["cache-control"] == "no-store"
        invalid = client.post(
            "/v1/routes", json={"origin": {"latitude": 3.12345, "longitude": 36.82}}
        )
        assert invalid.status_code == 422
        assert "3.12345" not in invalid.text
