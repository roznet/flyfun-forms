"""Form generation endpoint."""

from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import Response
from sqlalchemy.orm import Session

from ..airport_resolver import AirportResolver
from ..db.deps import current_user_id, get_db
from ..db.models import Usage
from ..fillers.docx_filler import fill_docx
from ..fillers.french_customs_filler import fill_french_customs
from ..fillers.pdf_filler import fill_pdf
from ..fillers.xlsx_filler import fill_xlsx
from ..registry import FormMapping, MappingRegistry
from ..validation import validate_request
from .models import GenerateRequest

router = APIRouter()

_registry: MappingRegistry | None = None
_resolver: AirportResolver | None = None

# Content types by filler type
CONTENT_TYPES = {
    "pdf_acroform": "application/pdf",
    "pdf_acroform_french": "application/pdf",
    "docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    "xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
}

EXTENSIONS = {
    "pdf_acroform": "pdf",
    "pdf_acroform_french": "pdf",
    "docx": "docx",
    "xlsx": "xlsx",
}


def configure(registry: MappingRegistry, resolver: AirportResolver):
    global _registry, _resolver
    _registry = registry
    _resolver = resolver


def _generate_form(mapping: FormMapping, request: GenerateRequest, flatten: bool) -> bytes:
    template_path = _registry.get_template_path(mapping)
    if not template_path.exists():
        raise HTTPException(status_code=500, detail=f"Template file not found: {mapping.template}")

    if mapping.filler_type == "pdf_acroform":
        return fill_pdf(template_path, mapping, request, _resolver, flatten)
    elif mapping.filler_type == "pdf_acroform_french":
        return fill_french_customs(template_path, mapping, request, _resolver, flatten)
    elif mapping.filler_type == "docx":
        return fill_docx(template_path, mapping, request, _resolver)
    elif mapping.filler_type == "xlsx":
        return fill_xlsx(template_path, mapping, request, _resolver)
    else:
        raise HTTPException(status_code=500, detail=f"Unknown filler type: {mapping.filler_type}")


@router.post("/generate")
def generate_form(
    request: GenerateRequest,
    flatten: bool = Query(False),
    user_id: str = Depends(current_user_id),
    db: Session = Depends(get_db),
):
    # Look up mapping
    mapping = _registry.get_form(request.airport, request.form)
    if not mapping:
        raise HTTPException(status_code=404, detail=f"No form '{request.form}' for airport {request.airport}")

    # Validate
    errors = validate_request(request, mapping)
    if errors:
        raise HTTPException(status_code=422, detail=[e.model_dump() for e in errors])

    # Generate
    content = _generate_form(mapping, request, flatten)

    # Log usage
    db.add(Usage(
        user_id=user_id,
        endpoint="generate",
        airport_icao=request.airport,
        form_id=request.form,
    ))

    # Response
    ext = EXTENSIONS.get(mapping.filler_type, "bin")
    filename = f"{request.flight.departure_date}_{request.airport}_{request.form}.{ext}"
    content_type = CONTENT_TYPES.get(mapping.filler_type, "application/octet-stream")

    return Response(
        content=content,
        media_type=content_type,
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )
