"""Backwards-compat shim — everything now comes from flyfun_common.db."""

from flyfun_common.db import current_user_id, get_db

__all__ = ["current_user_id", "get_db"]
