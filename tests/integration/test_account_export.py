"""GET /account/export (GDPR Art. 20, server half).

Runs in production auth mode against a real SQLite database, authenticating
with real `ff_` API tokens, so the user scoping is the one the server uses and
not a dependency override. All data is self-describing dummy data.
"""

from __future__ import annotations

import hashlib
import json
from datetime import datetime, timedelta, timezone

import pytest
from fastapi.testclient import TestClient
from flyfun_common.db import get_engine, reset_engine
from flyfun_common.db.models import (
    ApiTokenRow,
    Base,
    CostLedgerRow,
    UserPreferencesRow,
    UserRow,
)
from flyfun_common.oauth.models import OAuthAuthorizationCodeRow, OAuthRefreshTokenRow
from sqlalchemy import text
from sqlalchemy.orm import Session

from flightforms.api import account_export
from flightforms.db.models import AppBase, Usage

USERS = ("test-user-a", "test-user-b")


def _token(uid: str) -> str:
    return f"ff_dummy-token-for-{uid}"


@pytest.fixture
def engine(monkeypatch, tmp_path):
    monkeypatch.setenv("ENVIRONMENT", "production")
    monkeypatch.setenv("JWT_SECRET", "test-secret-key-for-account-export")
    reset_engine()
    eng = get_engine(f"sqlite:///{tmp_path / 'export-test.db'}")
    Base.metadata.create_all(eng)
    AppBase.metadata.create_all(eng)
    with Session(eng) as db:
        for uid in USERS:
            _seed(db, uid)
        db.commit()
    yield eng
    reset_engine()


@pytest.fixture
def client(engine):
    from flightforms.api.app import create_app

    return TestClient(create_app())


def _seed(db: Session, uid: str) -> None:
    now = datetime.now(timezone.utc)
    db.add(UserRow(
        id=uid, provider="google", provider_sub=f"provider-sub-secret-{uid}",
        email=f"{uid}@example.invalid", display_name=f"Display Name {uid}",
        tokens_valid_after=now - timedelta(days=1),
    ))
    db.flush()  # user_preferences has a foreign key to users
    db.add(UserPreferencesRow(
        user_id=uid, setup_completed=True,
        encrypted_creds_json=f"encrypted-creds-secret-{uid}",
        app_prefs_json=json.dumps({"pref_owner": uid}),
    ))
    db.add(Usage(user_id=uid, endpoint="generate", airport_icao="ZZZZ", form_id=f"form-{uid}"))
    db.add(Usage(user_id=uid, endpoint="prefill", airport_icao="YYYY", form_id=f"web-{uid}"))
    db.add(ApiTokenRow(
        user_id=uid, token_hash=hashlib.sha256(_token(uid).encode()).hexdigest(),
        name=f"token-name-{uid}",
    ))
    db.add(OAuthRefreshTokenRow(
        user_id=uid, client_id=f"client-{uid}", scope="mcp",
        token_hash=f"refresh-hash-secret-{uid}",
        access_token_hash=f"access-hash-secret-{uid}",
    ))
    db.add(OAuthAuthorizationCodeRow(
        code=f"auth-code-secret-{uid}", client_id=f"client-{uid}", user_id=uid,
        redirect_uri=f"https://redirect-secret-{uid}.invalid/cb",
        code_challenge=f"challenge-secret-{uid}", expires_at=now + timedelta(minutes=5),
    ))
    db.add(CostLedgerRow(
        user_id=uid, service=account_export.COST_SERVICE, action="generate", cost=0.01,
        metadata_json=json.dumps({"airport": "ZZZZ", "form": f"form-{uid}"}),
    ))
    db.add(CostLedgerRow(
        user_id=uid, service="flyfun-weather", action=f"weather-action-{uid}", cost=0.5,
    ))


def _secrets(uid: str) -> list[str]:
    return [
        f"provider-sub-secret-{uid}",
        f"encrypted-creds-secret-{uid}",
        hashlib.sha256(_token(uid).encode()).hexdigest(),
        _token(uid),
        f"refresh-hash-secret-{uid}",
        f"access-hash-secret-{uid}",
        f"auth-code-secret-{uid}",
        f"challenge-secret-{uid}",
        f"redirect-secret-{uid}",
    ]


def _export(client, uid: str):
    return client.get("/account/export", headers={"Authorization": f"Bearer {_token(uid)}"})


# ── Content ──────────────────────────────────────────────────────────────────

def test_export_returns_own_rows_as_a_download(client):
    resp = _export(client, "test-user-a")
    assert resp.status_code == 200
    assert resp.headers["content-disposition"] == (
        'attachment; filename="flightforms-account-export.json"'
    )
    assert resp.headers["cache-control"] == "no-store"

    body = resp.json()
    assert body["format"] == "flightforms/account-export"
    assert body["version"] == 1
    assert body["exportedAt"].endswith("+00:00")
    assert body["user"]["id"] == "test-user-a"
    assert body["user"]["email"] == "test-user-a@example.invalid"
    assert body["preferences"]["app_prefs_json"] == {"pref_owner": "test-user-a"}

    assert sorted(u["form_id"] for u in body["usage"]) == ["form-test-user-a", "web-test-user-a"]
    assert set(body["usage"][0]) == {"endpoint", "airport_icao", "form_id", "timestamp"}

    [token] = body["apiTokens"]
    assert token["name"] == "token-name-test-user-a"
    assert token["last_used_at"] is not None  # this request authenticated with it

    assert [g["client_id"] for g in body["oauthGrants"]] == ["client-test-user-a"]
    assert [c["client_id"] for c in body["oauthPendingCodes"]] == ["client-test-user-a"]

    [cost] = body["formCosts"]
    assert cost["service"] == "flyfun-forms"
    assert cost["metadata_json"] == {"airport": "ZZZZ", "form": "form-test-user-a"}


def test_export_leaves_out_every_excluded_field(client):
    body = _export(client, "test-user-a").json()
    sections = {
        "users": [body["user"]],
        "user_preferences": [body["preferences"]],
        "usage": body["usage"],
        "api_tokens": body["apiTokens"],
        "oauth_refresh_tokens": body["oauthGrants"],
        "oauth_authorization_codes": body["oauthPendingCodes"],
        "cost_ledger": body["formCosts"],
    }
    assert set(sections) == set(account_export._EXCLUDE) == account_export.EXPORTED_TABLES
    for table, rows in sections.items():
        assert rows, table
        for row in rows:
            leaked = account_export._EXCLUDE[table] & set(row)
            assert not leaked, f"{table} exports {leaked}"


def test_no_secret_value_appears_anywhere(client):
    raw = _export(client, "test-user-a").text
    for secret in _secrets("test-user-a"):
        assert secret not in raw


def test_two_users_never_see_each_others_rows(client):
    for me, other in (USERS, USERS[::-1]):
        raw = _export(client, me).text
        assert me in raw
        assert other not in raw, f"{me}'s export mentions {other}"


def test_cost_rows_from_other_apps_are_not_included(client):
    raw = _export(client, "test-user-a").text
    assert "weather-action" not in raw


# ── Auth ─────────────────────────────────────────────────────────────────────

def test_unauthenticated_is_401(client):
    assert client.get("/account/export").status_code == 401


def test_unknown_token_is_401(client):
    resp = client.get("/account/export", headers={"Authorization": "Bearer ff_not-a-real-token"})
    assert resp.status_code == 401


# ── Coverage: export mirrors deletion ────────────────────────────────────────

def _user_keyed_tables() -> set[str]:
    tables = {"users"}
    for metadata in (Base.metadata, AppBase.metadata):
        for table in metadata.tables.values():
            if "user_id" in table.columns:
                tables.add(table.name)
    return tables


def test_every_user_keyed_table_is_classified():
    """A new table holding user rows (here or in flyfun-common) forces a decision."""
    classified = account_export.EXPORTED_TABLES | set(account_export.NOT_EXPORTED)
    assert not account_export.EXPORTED_TABLES & set(account_export.NOT_EXPORTED)
    unclassified = _user_keyed_tables() - classified
    assert not unclassified, (
        f"{sorted(unclassified)} hold user rows: export them in account_export.py "
        "or list them in NOT_EXPORTED with the reason"
    )
    known = set(Base.metadata.tables) | set(AppBase.metadata.tables)
    assert classified <= known, f"stale entries: {sorted(classified - known)}"


def _rows_for(engine, user_id: str) -> dict[str, int]:
    counts = {}
    with engine.connect() as conn:
        for table in sorted(_user_keyed_tables()):
            column = "id" if table == "users" else "user_id"
            counts[table] = conn.execute(
                text(f"SELECT COUNT(*) FROM {table} WHERE {column} = :uid"), {"uid": user_id}
            ).scalar()
    return counts


def test_every_table_deletion_empties_is_in_the_export(client, engine):
    """Run the real DELETE /auth/account (forms' hook + flyfun-common's own
    deletes) and check that each table it empties is exported."""
    before = _rows_for(engine, "test-user-a")
    resp = client.delete("/auth/account", headers={"Authorization": f"Bearer {_token('test-user-a')}"})
    assert resp.status_code == 204
    after = _rows_for(engine, "test-user-a")

    deleted = {t for t in before if after[t] < before[t]}
    assert {"users", "usage", "api_tokens"} <= deleted  # sanity: deletion ran
    missing = deleted - account_export.EXPORTED_TABLES
    assert not missing, f"account deletion removes {sorted(missing)} but the export omits it"

    # The other user is untouched.
    assert _rows_for(engine, "test-user-b")["usage"] == 2


# Every column of every exported table, as of this change. A column added to a
# model (e.g. by a flyfun-common upgrade) fails here until it is either
# exported knowingly or added to _EXCLUDE.
EXPECTED_COLUMNS = {
    "users": {
        "id", "provider", "provider_sub", "email", "display_name", "approved",
        "created_at", "last_login_at", "tokens_valid_after",
    },
    "user_preferences": {"user_id", "setup_completed", "encrypted_creds_json", "app_prefs_json"},
    "usage": {"id", "user_id", "endpoint", "airport_icao", "form_id", "timestamp"},
    "api_tokens": {
        "id", "user_id", "token_hash", "name", "created_at", "expires_at",
        "last_used_at", "revoked", "oauth_client_id", "scope",
    },
    "oauth_refresh_tokens": {
        "id", "token_hash", "client_id", "user_id", "access_token_hash", "scope",
        "created_at", "expires_at", "revoked",
    },
    "oauth_authorization_codes": {
        "code", "client_id", "user_id", "redirect_uri", "code_challenge", "scope",
        "expires_at", "used", "access_token_hash",
    },
    "cost_ledger": {
        "id", "user_id", "service", "action", "cost", "metadata_json", "created_at",
        "category", "description", "detail_json", "reference_id",
    },
}


@pytest.mark.parametrize("table", sorted(EXPECTED_COLUMNS))
def test_column_set_is_pinned(table):
    all_tables = {**Base.metadata.tables, **AppBase.metadata.tables}
    assert set(all_tables[table].columns.keys()) == EXPECTED_COLUMNS[table], (
        f"{table} changed: decide whether each new column is exported or excluded"
    )
