"""Per-user form-fill rate limit, counted over the usage log."""

from datetime import datetime, timedelta, timezone

import pytest
from fastapi import HTTPException
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from flightforms.api import rate_limit
from flightforms.db.models import AppBase, Usage


@pytest.fixture
def db(monkeypatch):
    # The limit is skipped in dev mode, which is how the rest of the suite runs
    monkeypatch.setattr(rate_limit, "is_dev_mode", lambda: False)
    engine = create_engine("sqlite:///:memory:")
    AppBase.metadata.create_all(engine)
    session = sessionmaker(bind=engine)()
    yield session
    session.close()


def _log(db, user_id, n, endpoint="generate", age=timedelta(0)):
    when = datetime.now(timezone.utc) - age
    for _ in range(n):
        db.add(Usage(user_id=user_id, endpoint=endpoint, airport_icao="ZZZZ", form_id="gar", timestamp=when))
    db.flush()


def test_allows_under_limit(db):
    _log(db, "user-a", 2)
    assert rate_limit.check_fill_rate(db, "user-a", limit=3)


def test_blocks_at_limit(db):
    _log(db, "user-a", 3)
    assert not rate_limit.check_fill_rate(db, "user-a", limit=3)


def test_prefill_counts_towards_the_same_limit(db):
    _log(db, "user-a", 2)
    _log(db, "user-a", 1, endpoint="prefill")
    assert not rate_limit.check_fill_rate(db, "user-a", limit=3)


def test_other_endpoints_do_not_count(db):
    _log(db, "user-a", 3, endpoint="validate")
    assert rate_limit.check_fill_rate(db, "user-a", limit=3)


def test_rows_outside_window_do_not_count(db):
    _log(db, "user-a", 3, age=timedelta(hours=2))
    assert rate_limit.check_fill_rate(db, "user-a", limit=3, window=timedelta(hours=1))


def test_limit_is_per_user(db):
    _log(db, "user-a", 3)
    assert rate_limit.check_fill_rate(db, "user-b", limit=3)


def test_enforce_raises_429_with_retry_after(db):
    _log(db, "user-a", rate_limit.FILL_LIMIT)
    with pytest.raises(HTTPException) as exc:
        rate_limit.enforce_fill_rate(db, "user-a")
    assert exc.value.status_code == 429
    assert exc.value.headers["Retry-After"] == "3600"


def test_dev_mode_skips_limit(db, monkeypatch):
    monkeypatch.setattr(rate_limit, "is_dev_mode", lambda: True)
    _log(db, "user-a", 5)
    assert rate_limit.check_fill_rate(db, "user-a", limit=1)
