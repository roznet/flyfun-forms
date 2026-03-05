"""FastAPI app factory — mirrors flyfun-weather pattern."""

import logging
import os
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI
from starlette.middleware.sessions import SessionMiddleware

from ..airport_resolver import AirportResolver
from ..db.engine import ensure_dev_user, init_db, is_dev
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
    init_db()
    if is_dev():
        ensure_dev_user()
    logger.info("FlightForms API started (env=%s)", os.environ.get("ENVIRONMENT", "development"))
    yield


def create_app() -> FastAPI:
    app = FastAPI(
        title="FlightForms API",
        version="0.1.0",
        docs_url="/docs" if is_dev() else None,
        redoc_url=None,
        lifespan=lifespan,
    )

    # Middleware
    app.add_middleware(
        SessionMiddleware,
        secret_key=os.environ.get("JWT_SECRET", "dev-secret-not-for-production"),
    )

    if is_dev():
        from starlette.middleware.cors import CORSMiddleware
        app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

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
