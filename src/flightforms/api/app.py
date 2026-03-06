"""FastAPI app factory — uses flyfun-common for auth and user management."""

import logging
import os
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI
from flyfun_common.auth import create_auth_router, get_jwt_secret, is_dev_mode
from flyfun_common.db import SessionLocal, ensure_dev_user, get_engine, init_shared_db
from starlette.middleware.sessions import SessionMiddleware

from ..airport_resolver import AirportResolver
from ..db.models import AppBase
from ..registry import MappingRegistry
from . import airports, generate, validate

logger = logging.getLogger(__name__)

# Default paths for templates and mappings
_BASE_DIR = Path(__file__).parent.parent
_TEMPLATES_DIR = os.environ.get("TEMPLATES_DIR", str(_BASE_DIR / "templates"))
_MAPPINGS_DIR = os.environ.get("MAPPINGS_DIR", str(_BASE_DIR / "mappings"))
_AIRPORTS_DB = os.environ.get("AIRPORTS_DB", "")


@asynccontextmanager
async def lifespan(app: FastAPI):
    init_shared_db()
    AppBase.metadata.create_all(get_engine())
    if is_dev_mode():
        session = SessionLocal()
        try:
            ensure_dev_user(session)
        finally:
            session.close()
    logger.info("FlightForms API started (env=%s)", os.environ.get("ENVIRONMENT", "development"))
    yield


def create_app() -> FastAPI:
    app = FastAPI(
        title="FlightForms API",
        version="0.1.0",
        docs_url="/docs" if is_dev_mode() else None,
        redoc_url=None,
        lifespan=lifespan,
    )

    # SessionMiddleware required for OAuth state roundtrip
    app.add_middleware(
        SessionMiddleware,
        secret_key=get_jwt_secret(),
    )

    if is_dev_mode():
        from starlette.middleware.cors import CORSMiddleware
        app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

    # Mount shared auth router (Google/Apple OAuth, /auth/me, /auth/logout)
    app.include_router(create_auth_router(), tags=["auth"])

    # Initialize registry and resolver
    registry = MappingRegistry(_MAPPINGS_DIR, _TEMPLATES_DIR)
    resolver = AirportResolver(_AIRPORTS_DB if _AIRPORTS_DB else None)

    # Configure route modules
    airports.configure(registry, resolver)
    generate.configure(registry, resolver)
    validate.configure(registry)

    # Register routes
    app.include_router(airports.router, tags=["airports"])
    app.include_router(generate.router, tags=["generate"])
    app.include_router(validate.router, tags=["validate"])

    @app.get("/health")
    def health():
        return {"status": "ok"}

    return app
