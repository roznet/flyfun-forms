"""Rolling sessions on forms (flyfun-common SlidingSessionMiddleware).

The apps keep their keychain token alive through `X-Renewed-Token`, so an
authenticated forms request must renew a near-expiry token. A revoked token
("log out everywhere") must never be renewed, on any route, and public routes
never renew. Runs in production auth mode against a real SQLite user.
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone

import jwt as pyjwt
import pytest
from fastapi.testclient import TestClient
from flyfun_common.auth.jwt_utils import JWT_ALGORITHM
from flyfun_common.db import get_engine, reset_engine
from flyfun_common.db.models import Base, UserRow
from sqlalchemy.orm import Session

from flightforms.db.models import AppBase

SECRET = "test-secret-key-for-session-renewal"
UID = "test-user-renewal"


@pytest.fixture
def engine(monkeypatch, tmp_path):
    monkeypatch.setenv("ENVIRONMENT", "production")
    monkeypatch.setenv("JWT_SECRET", SECRET)
    reset_engine()
    eng = get_engine(f"sqlite:///{tmp_path / 'renewal-test.db'}")
    Base.metadata.create_all(eng)
    AppBase.metadata.create_all(eng)
    with Session(eng) as db:
        db.add(UserRow(
            id=UID, provider="google", provider_sub="provider-sub-renewal",
            email="renewal@example.invalid", display_name="Renewal Test",
            approved=True,
        ))
        db.commit()
    yield eng
    reset_engine()


@pytest.fixture
def client(engine):
    from flightforms.api.app import create_app

    return TestClient(create_app())


def _bearer(days_until_expiry: int) -> dict[str, str]:
    now = datetime.now(timezone.utc)
    token = pyjwt.encode(
        {
            "sub": UID, "email": "renewal@example.invalid", "name": "Renewal Test",
            "iat": now, "exp": now + timedelta(days=days_until_expiry),
        },
        SECRET,
        algorithm=JWT_ALGORITHM,
    )
    return {"Authorization": f"Bearer {token}"}


def _revoke_all_sessions(engine) -> None:
    with Session(engine) as db:
        db.get(UserRow, UID).tokens_valid_after = datetime.now(timezone.utc) + timedelta(seconds=5)
        db.commit()


def test_authenticated_request_renews_near_expiry_token(client):
    resp = client.get("/auth/me", headers=_bearer(5))
    assert resp.status_code == 200
    renewed = resp.headers.get("x-renewed-token")
    assert renewed
    assert client.get("/auth/me", headers={"Authorization": f"Bearer {renewed}"}).status_code == 200


def test_fresh_token_not_renewed(client):
    resp = client.get("/auth/me", headers=_bearer(25))
    assert resp.status_code == 200
    assert resp.headers.get("x-renewed-token") is None


def test_public_route_does_not_renew(client):
    resp = client.get("/health", headers=_bearer(5))
    assert resp.status_code == 200
    assert resp.headers.get("x-renewed-token") is None


def test_revoked_token_is_never_renewed(client, engine):
    headers = _bearer(5)
    _revoke_all_sessions(engine)
    for path in ("/health", "/auth/providers", "/auth/me"):
        assert client.get(path, headers=headers).headers.get("x-renewed-token") is None, path
    assert client.get("/auth/me", headers=headers).status_code == 401
