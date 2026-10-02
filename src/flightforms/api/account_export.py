"""GET /account/export: GDPR Art. 20 (data portability), server half.

Returns, as a JSON download, everything the server holds about the signed-in
user. The device half (people, documents, aircraft, flights) is the app's own
"Download a Copy of My Data"; none of that is ever on the server.

Coverage rule: **whatever account deletion removes, the export includes.**
Deletion is ``_on_delete_user`` in ``app.py`` plus flyfun-common's
``DELETE /auth/account``. ``EXPORTED_TABLES`` and ``NOT_EXPORTED`` together
classify every table holding a user's rows, and
``tests/integration/test_account_export.py`` fails if deletion touches, or the
schema gains, a table that is in neither.

Follows flyfun-weather's ``api/account_export.py``: every column is exported
except those listed in ``_EXCLUDE`` (secrets and server-internal values). A
test pins each table's column set, so a column added to flyfun-common is a
deliberate export-or-exclude decision rather than a silent leak.

Never log the response or anything about its contents.
"""

from __future__ import annotations

import json
from datetime import date, datetime, timezone
from typing import Any

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import JSONResponse
from flyfun_common.db import current_user_id, get_db
from flyfun_common.db.models import (
    ApiTokenRow,
    CostLedgerRow,
    UserPreferencesRow,
    UserRow,
)
from flyfun_common.oauth.models import OAuthAuthorizationCodeRow, OAuthRefreshTokenRow
from sqlalchemy import inspect as sa_inspect
from sqlalchemy.orm import Session

from ..db.models import Usage

router = APIRouter(prefix="/account", tags=["account"])

EXPORT_FORMAT = "flightforms/account-export"
# Bump when the shape changes materially, so consumers can branch on it.
EXPORT_FORMAT_VERSION = 1
EXPORT_FILENAME = "flightforms-account-export.json"

# The `service` this app writes to the shared cost ledger (generate.py, prefill.py).
COST_SERVICE = "flyfun-forms"

# Tables whose rows for the user appear in the export.
EXPORTED_TABLES = frozenset({
    "users",
    "user_preferences",
    "usage",
    "api_tokens",
    "oauth_refresh_tokens",
    "oauth_authorization_codes",
    # Not deleted with the account (kept, unlinked, for accounting; see
    # PRIVACY.md), but while the account exists the rows are the user's own
    # history. Only rows this app wrote: the ledger is shared with weather.
    "cost_ledger",
})

# Tables that hold rows tied to a user but are deliberately left out. Neither is
# touched by account deletion, so the coverage rule doesn't pull them in.
NOT_EXPORTED: dict[str, str] = {
    "magic_link_tokens": (
        "sign-in secrets keyed by email, valid for minutes; not linked to the "
        "account row"
    ),
    "donation_ledger": (
        "written only by FlyFun Weather (forms has no donation flow); "
        "weather's export is the place for it"
    ),
}

# Per-table columns omitted from the export: a secret, or a server-internal
# value with no meaning to the user. `user_id` is dropped from child rows only
# because `user.id` already carries it.
_EXCLUDE: dict[str, set[str]] = {
    "users": {"provider_sub", "tokens_valid_after"},
    "user_preferences": {"user_id", "encrypted_creds_json"},  # credentials stay secret
    "usage": {"id", "user_id"},
    "api_tokens": {"id", "user_id", "token_hash"},  # the hash would be a credential
    "oauth_refresh_tokens": {"id", "user_id", "token_hash", "access_token_hash"},
    # The code is the primary key and a single-use credential; the PKCE
    # challenge and redirect URI are protocol plumbing.
    "oauth_authorization_codes": {
        "code", "user_id", "code_challenge", "redirect_uri", "access_token_hash",
    },
    "cost_ledger": {"id", "user_id"},
}


def _jsonify(value: Any) -> Any:
    if isinstance(value, (datetime, date)):
        if isinstance(value, datetime) and value.tzinfo is None:
            # SQLite drops tzinfo; every timestamp here is stored as UTC.
            value = value.replace(tzinfo=timezone.utc)
        return value.isoformat()
    return value


def _row_to_dict(row: Any) -> dict[str, Any]:
    """Serialize an ORM row, honouring ``_EXCLUDE``.

    ``*_json`` columns are parsed so the export is one clean JSON document
    rather than JSON strings inside JSON.
    """
    excluded = _EXCLUDE.get(row.__tablename__, set())
    out: dict[str, Any] = {}
    for col in sa_inspect(row).mapper.columns:
        if col.name in excluded:
            continue
        value = getattr(row, col.key)
        if col.name.endswith("_json") and isinstance(value, str) and value:
            try:
                value = json.loads(value)
            except ValueError:
                pass  # keep the raw string if it isn't valid JSON
        out[col.name] = _jsonify(value)
    return out


def build_account_export(db: Session, user_id: str) -> dict[str, Any] | None:
    """The export document for ``user_id``, or None if there is no such user."""
    user = db.get(UserRow, user_id)
    if user is None:
        return None
    prefs = db.get(UserPreferencesRow, user_id)

    def rows(model, *criteria, order_by):
        query = db.query(model).filter(model.user_id == user_id, *criteria)
        return [_row_to_dict(r) for r in query.order_by(order_by).all()]

    return {
        "format": EXPORT_FORMAT,
        "version": EXPORT_FORMAT_VERSION,
        "exportedAt": _jsonify(datetime.now(timezone.utc)),
        "note": (
            "Everything the FlightForms server holds about your account. The "
            "people, documents, aircraft and flights you enter in the app are "
            "never on the server; export them from the app's Settings. "
            "Credentials (API token and sign-in token values, linked-service "
            "passwords) are left out on purpose."
        ),
        "user": _row_to_dict(user),
        "preferences": _row_to_dict(prefs) if prefs else None,
        "usage": rows(Usage, order_by=Usage.timestamp),
        "apiTokens": rows(ApiTokenRow, order_by=ApiTokenRow.created_at),
        "oauthGrants": rows(OAuthRefreshTokenRow, order_by=OAuthRefreshTokenRow.created_at),
        "oauthPendingCodes": rows(
            OAuthAuthorizationCodeRow, order_by=OAuthAuthorizationCodeRow.expires_at
        ),
        "formCosts": rows(
            CostLedgerRow,
            CostLedgerRow.service == COST_SERVICE,
            order_by=CostLedgerRow.created_at,
        ),
    }


@router.get("/export")
def export_account(
    user_id: str = Depends(current_user_id),
    db: Session = Depends(get_db),
):
    export = build_account_export(db, user_id)
    if export is None:
        raise HTTPException(status_code=401, detail="User not found")
    return JSONResponse(
        content=export,
        headers={
            "Content-Disposition": f'attachment; filename="{EXPORT_FILENAME}"',
            "Cache-Control": "no-store",
        },
    )
