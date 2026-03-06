"""Database layer: shared tables from flyfun-common, app tables here."""

from flyfun_common.db import (
    SessionLocal,
    ensure_dev_user,
    get_engine,
    init_shared_db,
)

from .models import AppBase, Usage


# Lazy imports for deps that trigger circular imports when loaded at module level
def __getattr__(name: str):
    if name in ("get_db", "current_user_id"):
        from flyfun_common.db import deps
        return getattr(deps, name)
    raise AttributeError(f"module {__name__!r} has no attribute {name!r}")


__all__ = [
    "SessionLocal",
    "ensure_dev_user",
    "get_db",
    "get_engine",
    "init_shared_db",
    "current_user_id",
    "AppBase",
    "Usage",
]
