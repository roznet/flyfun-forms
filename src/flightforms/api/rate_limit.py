"""Per-user sliding-window limit on form filling (SECURITY_AUDIT.md §17).

Caps how much a stolen token or a runaway client can do: ``/generate`` and
``/prefill`` together allow ``FILL_LIMIT`` requests per user per rolling
``FILL_WINDOW``. A multi-leg trip from the CLI is a few dozen requests, so the
limit only bites on abuse.

Same strategy as ``flyfun_common.auth.rate_limit``: the ``usage`` table is
already a log of every fill, so the count runs over it — no counter rows.
Skipped in dev mode, like the shared limits.
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone

from fastapi import HTTPException
from flyfun_common.auth import is_dev_mode
from sqlalchemy import func
from sqlalchemy.orm import Session

from ..db.models import Usage

FILL_LIMIT = 100
FILL_WINDOW = timedelta(hours=1)
FILL_ENDPOINTS = ("generate", "prefill")


def check_fill_rate(
    db: Session,
    user_id: str,
    *,
    limit: int = FILL_LIMIT,
    window: timedelta = FILL_WINDOW,
) -> bool:
    """Return True if another form fill is allowed for this user."""
    if is_dev_mode():
        return True
    since = datetime.now(timezone.utc) - window
    count = (
        db.query(func.count(Usage.id))
        .filter(
            Usage.user_id == user_id,
            Usage.endpoint.in_(FILL_ENDPOINTS),
            Usage.timestamp >= since,
        )
        .scalar()
        or 0
    )
    return count < limit


def enforce_fill_rate(db: Session, user_id: str) -> None:
    """Raise 429 when the user is over the fill limit."""
    if not check_fill_rate(db, user_id):
        raise HTTPException(
            status_code=429,
            detail="Too many forms generated in the last hour; try again later",
            headers={"Retry-After": str(int(FILL_WINDOW.total_seconds()))},
        )
