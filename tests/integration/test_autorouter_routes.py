"""The "Import from Autorouter" endpoint forms mounts from flyfun-common.

The fetch and normalisation are tested where they live (flyfun-common); these
cover that this app mounts the router, guards it with auth, and maps the two
failure modes onto the statuses the iOS client branches on.
"""

from __future__ import annotations

import json
from unittest.mock import MagicMock

import pytest
from fastapi.testclient import TestClient
from flyfun_common import autorouter as autorouter_module
from flyfun_common.db import DEV_USER_ID, current_user_id, get_db

from flightforms.api.app import create_app


@pytest.fixture
def client(monkeypatch, tmp_path):
    monkeypatch.setenv("ENVIRONMENT", "development")
    monkeypatch.setenv("DATABASE_URL", f"sqlite:///{tmp_path / 'forms-test.db'}")
    app = create_app()
    app.dependency_overrides[current_user_id] = lambda: DEV_USER_ID
    app.dependency_overrides[get_db] = lambda: MagicMock()
    return TestClient(app, raise_server_exceptions=False)


def _patch_token(monkeypatch, value):
    monkeypatch.setattr(
        autorouter_module, "get_autorouter_token", lambda db, uid: value
    )


def _patch_httpx(monkeypatch, *, status_code, json_body=None, raise_exc=None):
    import httpx

    def _fake_get(url, params=None, headers=None, timeout=None):
        if raise_exc is not None:
            raise raise_exc
        resp = MagicMock(spec=httpx.Response)
        resp.status_code = status_code
        resp.text = json.dumps(json_body) if json_body is not None else ""
        resp.json = MagicMock(return_value=json_body)
        return resp

    monkeypatch.setattr(httpx, "get", _fake_get)


def test_returns_routes_for_a_linked_account(client, monkeypatch):
    _patch_token(monkeypatch, "tok")
    _patch_httpx(
        monkeypatch,
        status_code=200,
        json_body=[
            {
                "routeid": "r1",
                "departure": "EGTF",
                "destination": "LFRM",
                "fplan": "(FPL-GABCD-VG-P28A/L-EGTF1000-N0110VFR LFRM-LFRM0130)",
            }
        ],
    )
    response = client.get("/api/autorouter/routes")
    assert response.status_code == 200
    routes = response.json()["routes"]
    assert [r["routeid"] for r in routes] == ["r1"]
    # The raw plan crosses the wire: the app parses it with RZFlight rather
    # than making a second round trip to have the server do it.
    assert routes[0]["fplan"].startswith("(FPL-")


def test_unlinked_account_is_409_not_an_empty_list(client, monkeypatch):
    """The app shows "link your account" on 409; an empty 200 would read as
    "you have no routes" and send the pilot looking in the wrong place."""
    _patch_token(monkeypatch, None)
    response = client.get("/api/autorouter/routes")
    assert response.status_code == 409
    assert response.json()["detail"] == "autorouter_not_linked"


def test_autorouter_being_down_is_502(client, monkeypatch):
    import httpx

    _patch_token(monkeypatch, "tok")
    _patch_httpx(monkeypatch, status_code=0, raise_exc=httpx.ConnectError("nope"))
    response = client.get("/api/autorouter/routes")
    assert response.status_code == 502
    assert response.json()["detail"] == "autorouter_unreachable"


def _mounted_paths() -> set[str]:
    """Every path the app serves, read from its OpenAPI schema.

    `app.routes` holds include-wrappers rather than the routes themselves in
    this FastAPI version, so the schema is both simpler and closer to what a
    client actually sees.
    """
    return set(create_app().openapi()["paths"])


def test_the_route_is_mounted_at_the_path_the_app_calls():
    """The iOS client hard-codes this path; moving it would break the picker
    with a 404 that looks like "no routes"."""
    assert "/api/autorouter/routes" in _mounted_paths()


def test_the_account_linking_flow_is_not_mounted_here():
    """Linking happens once, on the weather app, against the one registered
    redirect URI. Mounting it here too would need a second registration."""
    paths = _mounted_paths()
    assert "/autorouter/link" not in paths
    assert "/auth/callback/autorouter" not in paths
