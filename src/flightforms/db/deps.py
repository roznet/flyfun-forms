"""FastAPI dependencies: DB session and auth."""

import os
from typing import Generator

from fastapi import Depends, HTTPException, Request
from sqlalchemy.orm import Session

from .engine import DEV_USER_ID, SessionLocal, is_dev
from .models import User


def get_db() -> Generator[Session, None, None]:
    session = SessionLocal()
    try:
        yield session
        session.commit()
    except Exception:
        session.rollback()
        raise
    finally:
        session.close()


def current_user_id(request: Request, db: Session = Depends(get_db)) -> str:
    if is_dev():
        return DEV_USER_ID

    # Try JWT cookie
    token = request.cookies.get("ff_auth")
    if not token:
        # Try Bearer token
        auth_header = request.headers.get("Authorization", "")
        if auth_header.startswith("Bearer "):
            token = auth_header[7:]

    if not token:
        raise HTTPException(status_code=401, detail="Not authenticated")

    # Check static API key
    api_key = os.environ.get("API_KEY")
    if api_key and token == api_key:
        # API key auth — use a fixed user
        user = db.query(User).filter_by(provider="api").first()
        if user:
            return user.id
        raise HTTPException(status_code=401, detail="API key user not configured")

    # JWT auth (Phase 2)
    try:
        import jwt
        secret = os.environ.get("JWT_SECRET", "dev-secret-not-for-production")
        payload = jwt.decode(token, secret, algorithms=["HS256"])
        user_id = payload.get("sub")
        if not user_id:
            raise HTTPException(status_code=401, detail="Invalid token")

        user = db.query(User).filter_by(id=user_id).first()
        if not user:
            raise HTTPException(status_code=401, detail="User not found")
        if not user.approved:
            raise HTTPException(status_code=403, detail="Account suspended")
        return user.id
    except jwt.ExpiredSignatureError:
        raise HTTPException(status_code=401, detail="Token expired")
    except (jwt.InvalidTokenError, Exception):
        raise HTTPException(status_code=401, detail="Invalid token")
