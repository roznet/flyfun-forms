"""Backwards-compat shim — everything now comes from flyfun_common.db."""

from flyfun_common.db import (
    DEV_USER_ID,
    SessionLocal,
    ensure_dev_user,
    get_engine,
    init_shared_db,
    reset_engine,
)
from flyfun_common.db.engine import is_dev_mode as is_dev

__all__ = [
    "DEV_USER_ID",
    "SessionLocal",
    "ensure_dev_user",
    "get_engine",
    "init_shared_db",
    "reset_engine",
    "is_dev",
]
