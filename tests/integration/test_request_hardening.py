"""Request hardening: no PII in logs, bounded request bodies.

All person data here is fictional.
"""

import logging
import os

import pytest

from tests.conftest import make_aircraft, make_flight, make_passenger, make_pilot

# A value that must never appear in the server log.
_SENTINEL_DOB = "31.12.1999"


class _NoOpSession:
    def add(self, obj):
        pass

    def commit(self):
        pass

    def flush(self):
        pass

    def close(self):
        pass


@pytest.fixture
def app():
    os.environ.setdefault("ENVIRONMENT", "development")
    os.environ.setdefault("DATABASE_URL", "sqlite:///")
    os.environ.setdefault("JWT_SECRET", "test-secret-key-for-pytest")

    from flightforms.api.app import create_app
    from flyfun_common.db import current_user_id, get_db

    app = create_app()
    app.dependency_overrides[current_user_id] = lambda: "test-user-001"
    app.dependency_overrides[get_db] = lambda: _NoOpSession()
    return app


@pytest.fixture
def client(app):
    from fastapi.testclient import TestClient

    # raise_server_exceptions stays on: an exception escaping the app (and so
    # reaching Starlette's error logging) fails the test.
    return TestClient(app)


def _body(**pilot_overrides):
    pilot = make_pilot().model_dump()
    pilot.update(pilot_overrides)
    return {
        "airport": "LSGS",
        "form": "lsgs",
        "flight": make_flight(origin="ZZZZ", destination="LSGS").model_dump(),
        "aircraft": make_aircraft().model_dump(),
        "crew": [pilot],
        "passengers": [make_passenger().model_dump()],
    }


class TestPersonDates:
    @pytest.mark.parametrize("field", ["dob", "id_expiry"])
    @pytest.mark.parametrize("value", [_SENTINEL_DOB, "2026-02-30", "1999/12/31"])
    def test_malformed_date_is_422_and_not_logged(self, client, caplog, field, value):
        caplog.set_level(logging.DEBUG)
        resp = client.post("/generate", json=_body(**{field: value}))
        assert resp.status_code == 422
        assert value not in caplog.text

    @pytest.mark.parametrize("value", [None, ""])
    def test_blank_dates_still_accepted(self, value):
        # Whether a blank date is acceptable is the form's call (/validate),
        # not the model's.
        from flightforms.api.models import PersonData

        person = PersonData(first_name="A", last_name="B", dob=value, id_expiry=value)
        assert person.dob == value


class TestRedactedErrors:
    def test_unhandled_exception_logs_no_message(self, app, client, caplog):
        @app.get("/boom")
        def boom():
            raise ValueError(f"time data {_SENTINEL_DOB!r} does not match format")

        caplog.set_level(logging.DEBUG)
        resp = client.get("/boom")

        assert resp.status_code == 500
        assert resp.json() == {"detail": "Internal server error"}
        assert _SENTINEL_DOB not in caplog.text
        assert "Unhandled ValueError on GET /boom" in caplog.text


class TestBodySizeLimit:
    def test_declared_oversized_body_is_413(self, client):
        from flightforms.api.middleware import MAX_BODY_BYTES

        resp = client.post(
            "/generate",
            content=b"x" * (MAX_BODY_BYTES + 1),
            headers={"content-type": "application/json"},
        )
        assert resp.status_code == 413

    def test_streamed_oversized_body_is_413(self, client):
        """A chunked body (no Content-Length) is counted as it arrives."""
        from flightforms.api.middleware import MAX_BODY_BYTES

        def chunks():
            chunk = b" " * 65536
            for _ in range(MAX_BODY_BYTES // len(chunk) + 2):
                yield chunk

        resp = client.post(
            "/generate",
            content=chunks(),
            headers={"content-type": "application/json"},
        )
        assert resp.status_code == 413

    def test_normal_request_unaffected(self, client):
        assert client.post("/generate", json=_body()).status_code == 200
