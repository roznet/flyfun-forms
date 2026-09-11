"""Web form prefill endpoint."""

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from ..airport_resolver import AirportResolver
from flyfun_common.costs import record_cost
from flyfun_common.db import current_user_id, get_db

from ..db.models import Usage
from ..fillers.web_form import build_fill_plan
from ..registry import MappingRegistry
from ..validation import validate_request
from .models import FillPlan, GenerateRequest

router = APIRouter()

_registry: MappingRegistry | None = None
_resolver: AirportResolver | None = None


def configure(registry: MappingRegistry, resolver: AirportResolver):
    global _registry, _resolver
    _registry = registry
    _resolver = resolver


@router.post("/prefill", response_model=FillPlan)
def prefill_web_form(
    request: GenerateRequest,
    user_id: str = Depends(current_user_id),
    db: Session = Depends(get_db),
):
    """Fill plan for an official web form, from the same body as /generate.

    The client opens the page and applies the plan; the pilot then submits
    it on the airport's own site.
    """
    mapping = _registry.get_form(request.airport, request.form)
    if not mapping:
        raise HTTPException(status_code=404, detail=f"No form '{request.form}' for airport {request.airport}")
    if not mapping.is_web_form:
        raise HTTPException(status_code=400, detail=f"Form '{request.form}' is a document; use /generate")

    errors = validate_request(request, mapping)
    if errors:
        raise HTTPException(status_code=422, detail=[e.model_dump() for e in errors])

    plan = build_fill_plan(mapping, request, _resolver)

    db.add(Usage(
        user_id=user_id,
        endpoint="prefill",
        airport_icao=request.airport,
        form_id=request.form,
    ))
    record_cost(
        db, user_id,
        service="flyfun-forms",
        action="prefill",
        cost=0.01,
        metadata={"airport": request.airport, "form": request.form},
    )

    return plan
