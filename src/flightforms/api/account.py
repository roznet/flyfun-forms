"""Account management endpoints."""

import logging

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from flyfun_common.db import current_user_id, get_db
from flyfun_common.db.models import ApiTokenRow, UserRow

from ..db.models import Usage

logger = logging.getLogger(__name__)

router = APIRouter()


@router.delete("/auth/account", status_code=204)
def delete_account(user_id: str = Depends(current_user_id), db: Session = Depends(get_db)):
    """Delete the authenticated user's account and all associated data."""
    logger.info("Account deletion requested for user %s", user_id)

    # Delete app-specific data
    db.query(Usage).filter(Usage.user_id == user_id).delete()

    # Delete API tokens
    db.query(ApiTokenRow).filter(ApiTokenRow.user_id == user_id).delete()

    # Delete user record
    db.query(UserRow).filter(UserRow.id == user_id).delete()

    db.commit()
    logger.info("Account deleted for user %s", user_id)
