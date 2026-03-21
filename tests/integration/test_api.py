"""Integration tests for the FastAPI endpoints.

Uses TestClient with the real create_app factory, with auth dependencies overridden.
"""

import os
import pytest

from tests.conftest import (
    make_aircraft,
    make_flight,
    make_passenger,
    make_pilot,
)


class _NoOpSession:
    """Minimal stand-in for SQLAlchemy Session — just swallows add/commit/flush."""
    def add(self, obj):
        pass
    def commit(self):
        pass
    def flush(self):
        pass
    def close(self):
        pass


@pytest.fixture(scope="module")
def client():
    # Set environment so flyfun_common treats this as dev mode
    os.environ.setdefault("ENVIRONMENT", "development")
    os.environ.setdefault("DATABASE_URL", "sqlite:///")
    os.environ.setdefault("JWT_SECRET", "test-secret-key-for-pytest")

    from fastapi.testclient import TestClient
    from flightforms.api.app import create_app
    from flyfun_common.db import current_user_id, get_db

    app = create_app()
    app.dependency_overrides[current_user_id] = lambda: "test-user-001"
    app.dependency_overrides[get_db] = lambda: _NoOpSession()

    return TestClient(app)


# ── Health ────────────────────────────────────────────────────────────────────

class TestHealth:
    def test_health(self, client):
        resp = client.get("/health")
        assert resp.status_code == 200
        assert resp.json()["status"] == "ok"


# ── Airports endpoints ────────────────────────────────────────────────────────

class TestAirports:
    def test_list_airports(self, client):
        resp = client.get("/airports")
        assert resp.status_code == 200
        data = resp.json()
        assert "airports" in data
        assert "prefixes" in data
        icaos = [a["icao"] for a in data["airports"]]
        assert "LSGS" in icaos
        assert "LFQA" in icaos

    def test_list_prefixes(self, client):
        resp = client.get("/airports")
        data = resp.json()
        prefixes = [p["prefix"] for p in data["prefixes"]]
        assert "LF" in prefixes
        assert "EG" in prefixes

    def test_airport_detail_lsgs(self, client):
        resp = client.get("/airports/LSGS")
        assert resp.status_code == 200
        data = resp.json()
        assert data["icao"] == "LSGS"
        assert len(data["forms"]) >= 1
        assert data["forms"][0]["id"] == "lsgs"

    def test_airport_detail_prefix_fallback(self, client):
        resp = client.get("/airports/LFOH")
        assert resp.status_code == 200
        data = resp.json()
        form_ids = [f["id"] for f in data["forms"]]
        assert "french_customs" in form_ids

    def test_airport_detail_unknown_gets_default(self, client):
        resp = client.get("/airports/XXXX")
        assert resp.status_code == 200
        data = resp.json()
        assert data["forms"][0]["id"] == "gendec_form"


# ── Validate endpoint ─────────────────────────────────────────────────────────

class TestValidate:
    def _body(self, **overrides):
        base = {
            "airport": "LSGS",
            "form": "lsgs",
            "flight": make_flight(origin="ZZZZ", destination="LSGS").model_dump(),
            "aircraft": make_aircraft().model_dump(),
            "crew": [make_pilot().model_dump()],
            "passengers": [make_passenger().model_dump()],
        }
        base.update(overrides)
        return base

    def test_valid_request(self, client):
        resp = client.post("/validate", json=self._body())
        assert resp.status_code == 200
        data = resp.json()
        assert data["valid"] is True
        assert data["errors"] == []

    def test_unknown_form(self, client):
        resp = client.post("/validate", json=self._body(form="nonexistent"))
        assert resp.status_code == 404

    def test_airport_not_in_route(self, client):
        resp = client.post("/validate", json=self._body(airport="XXXX"))
        # XXXX has no forms → 404
        assert resp.status_code == 404

    def test_missing_crew_field(self, client):
        crew = make_pilot().model_dump()
        crew["last_name"] = ""
        resp = client.post("/validate", json=self._body(crew=[crew]))
        data = resp.json()
        assert data["valid"] is False
        assert any("last_name" in e["field"] for e in data["errors"])


# ── Generate endpoint ─────────────────────────────────────────────────────────

class TestGenerate:
    def _body(self, airport="LSGS", form="lsgs", origin="ZZZZ", destination="LSGS"):
        return {
            "airport": airport,
            "form": form,
            "flight": make_flight(origin=origin, destination=destination).model_dump(),
            "aircraft": make_aircraft().model_dump(),
            "crew": [make_pilot().model_dump()],
            "passengers": [make_passenger().model_dump()],
        }

    def test_generate_lsgs_pdf(self, client):
        resp = client.post("/generate", json=self._body())
        assert resp.status_code == 200
        assert resp.headers["content-type"] == "application/pdf"
        assert "filename=" in resp.headers.get("content-disposition", "")
        assert len(resp.content) > 100

    def test_generate_french_customs(self, client):
        resp = client.post("/generate", json=self._body(
            airport="LFAC", form="french_customs", destination="LFAC",
        ))
        assert resp.status_code == 200
        assert resp.headers["content-type"] == "application/pdf"

    def test_generate_lfqa_pdf(self, client):
        resp = client.post("/generate", json=self._body(
            airport="LFQA", form="lfqa", destination="LFQA",
        ))
        assert resp.status_code == 200
        assert resp.headers["content-type"] == "application/pdf"

    def test_generate_gar_xlsx(self, client):
        body = self._body(airport="EGKA", form="gar", destination="EGKA")
        body["extra_fields"] = {
            "reason_for_visit": "Based",
            "responsible_person": {"name": "Zara K", "address": "7 Birch Lane"},
        }
        resp = client.post("/generate", json=body)
        assert resp.status_code == 200
        assert "spreadsheetml" in resp.headers["content-type"]

    def test_generate_flatten(self, client):
        resp = client.post("/generate?flatten=true", json=self._body())
        assert resp.status_code == 200

    def test_generate_unknown_form(self, client):
        resp = client.post("/generate", json=self._body(form="nonexistent"))
        assert resp.status_code == 404

    def test_generate_validation_error(self, client):
        body = self._body()
        body["aircraft"]["registration"] = ""
        resp = client.post("/generate", json=body)
        assert resp.status_code == 422


# ── Email text endpoint ──────────────────────────────────────────────────────

class TestEmailText:
    def _body(self, airport="LOWS", form="gendec_form", **overrides):
        base = {
            "airport": airport,
            "form": form,
            "origin": "LFQA",
            "destination": airport,
            "departure_date": "2026-03-21",
            "registration": "N122DR",
        }
        base.update(overrides)
        return base

    def test_default_english(self, client):
        resp = client.post("/email-text", json=self._body())
        assert resp.status_code == 200
        data = resp.json()
        assert "N122DR" in data["subject_en"]
        assert "General Declaration" in data["subject_en"]
        assert "LFQA" in data["body_en"]
        assert "LOWS" in data["body_en"]

    def test_local_german_for_austria(self, client):
        resp = client.post("/email-text", json=self._body(airport="LOWS"))
        data = resp.json()
        # Local should be German for Austrian airport
        assert "Flug" in data["body_local"] or "Luftfahrzeug" in data["body_local"]
        # English should still be English
        assert "attached" in data["body_en"]

    def test_local_french_for_lfqa(self, client):
        resp = client.post("/email-text", json=self._body(
            airport="LFQA", form="lfqa", destination="LFQA",
        ))
        data = resp.json()
        assert "vol" in data["body_local"] or "a\u00e9ronef" in data["body_local"]

    def test_english_country_matches(self, client):
        """English-speaking airports should have local == English."""
        resp = client.post("/email-text", json=self._body(
            airport="EGKA", form="gar", destination="EGKA",
        ))
        data = resp.json()
        assert data["subject_local"] == data["subject_en"]
        assert data["body_local"] == data["body_en"]

    def test_unknown_form_404(self, client):
        resp = client.post("/email-text", json=self._body(form="nonexistent"))
        assert resp.status_code == 404

    def test_date_formatted(self, client):
        resp = client.post("/email-text", json=self._body())
        data = resp.json()
        # gendec_form uses %d/%m/%Y format
        assert "21/03/2026" in data["subject_en"]
