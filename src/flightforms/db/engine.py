"""Database engine setup — mirrors flyfun-weather pattern."""

import logging
import os
from pathlib import Path

from sqlalchemy import create_engine, event, text
from sqlalchemy.orm import sessionmaker

logger = logging.getLogger(__name__)

_engine = None

DATA_DIR = os.environ.get("DATA_DIR", str(Path(__file__).parent.parent.parent.parent / "data"))
DEV_USER_ID = "dev-user-001"


def is_dev() -> bool:
    return os.environ.get("ENVIRONMENT", "development") == "development"


def get_engine():
    global _engine
    if _engine is None:
        if is_dev():
            db_path = Path(DATA_DIR) / "flightforms.db"
            db_path.parent.mkdir(parents=True, exist_ok=True)
            url = f"sqlite:///{db_path}"
            _engine = create_engine(url, connect_args={"check_same_thread": False, "timeout": 30})

            @event.listens_for(_engine, "connect")
            def set_sqlite_pragma(dbapi_connection, _):
                cursor = dbapi_connection.cursor()
                cursor.execute("PRAGMA journal_mode=WAL")
                cursor.execute("PRAGMA foreign_keys=ON")
                cursor.close()

            logger.info("Using SQLite: %s", db_path)
        else:
            url = os.environ["DATABASE_URL"]
            _engine = create_engine(url, pool_pre_ping=True)
            logger.info("Using MySQL")

    return _engine


SessionLocal = sessionmaker(autocommit=False, autoflush=False)


def init_db():
    from .models import Base
    engine = get_engine()
    SessionLocal.configure(bind=engine)
    Base.metadata.create_all(bind=engine)
    logger.info("Database tables created")


def ensure_dev_user():
    if not is_dev():
        return
    from .models import User
    session = SessionLocal()
    try:
        user = session.query(User).filter_by(id=DEV_USER_ID).first()
        if not user:
            user = User(
                id=DEV_USER_ID,
                provider="dev",
                provider_sub="dev",
                display_name="Dev User",
                approved=True,
            )
            session.add(user)
            session.commit()
            logger.info("Dev user created")
    finally:
        session.close()


def reset_engine():
    global _engine
    _engine = None
