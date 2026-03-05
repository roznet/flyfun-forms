"""Validation endpoint — dry-run of /generate."""

from fastapi import APIRouter, Depends, HTTPException

from ..db.deps import current_user_id
from ..registry import MappingRegistry
from ..validation import validate_request
from .models import GenerateRequest, ValidateResponse

router = APIRouter()

_registry: MappingRegistry | None = None


def configure(registry: MappingRegistry):
    global _registry
    _registry = registry


@router.post("/validate", response_model=ValidateResponse)
def validate_form(
    request: GenerateRequest,
    user_id: str = Depends(current_user_id),
):
    mapping = _registry.get_form(request.airport, request.form)
    if not mapping:
        raise HTTPException(status_code=404, detail=f"No form '{request.form}' for airport {request.airport}")

    errors = validate_request(request, mapping)
    return ValidateResponse(valid=len(errors) == 0, errors=errors)
