"""App-specific SQLAlchemy models.

Shared models (UserRow, ApiTokenRow) come from flyfun_common.db.
Only app-specific tables live here.
"""

from datetime import datetime, timezone

from sqlalchemy import DateTime, Integer, String
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column


class AppBase(DeclarativeBase):
    pass


class Usage(AppBase):
    __tablename__ = "usage"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    user_id: Mapped[str] = mapped_column(String(64))
    endpoint: Mapped[str] = mapped_column(String(50))
    airport_icao: Mapped[str | None] = mapped_column(String(4), nullable=True)
    form_id: Mapped[str | None] = mapped_column(String(50), nullable=True)
    timestamp: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )
