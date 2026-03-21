"""Email text endpoint — returns localized subject/body for form emails."""

from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException

from flyfun_common.db import current_user_id

from ..airport_resolver import AirportResolver
from ..registry import MappingRegistry
from .models import EmailTextRequest, EmailTextResponse

router = APIRouter()

_registry: MappingRegistry | None = None
_resolver: AirportResolver | None = None


def configure(registry: MappingRegistry, resolver: AirportResolver):
    global _registry, _resolver
    _registry = registry
    _resolver = resolver


@router.post("/email-text", response_model=EmailTextResponse)
def email_text(
    request: EmailTextRequest,
    user_id: str = Depends(current_user_id),
):
    mapping = _registry.get_form(request.airport, request.form)
    if not mapping:
        raise HTTPException(
            status_code=404,
            detail=f"No form '{request.form}' for airport {request.airport}",
        )

    # Format date using the mapping's date format
    try:
        date_str = datetime.strptime(request.departure_date, "%Y-%m-%d").strftime(
            mapping.date_format
        )
    except ValueError:
        date_str = request.departure_date

    placeholders = {
        "form_label": mapping.label,
        "airport": request.airport,
        "airport_name": _resolver.get_name(request.airport),
        "date": date_str,
        "origin": request.origin,
        "destination": request.destination,
        "registration": request.registration,
        "aircraft_type": request.aircraft_type or "",
    }

    # English
    en_tmpl = _registry.get_email_template(mapping, "en")
    subject_en = en_tmpl["subject"].format_map(placeholders)
    body_en = en_tmpl["body"].format_map(placeholders)

    # Local language
    lang = _resolver.get_language_code(request.airport)
    if lang and lang != "en":
        local_tmpl = _registry.get_email_template(mapping, lang)
        subject_local = local_tmpl["subject"].format_map(placeholders)
        body_local = local_tmpl["body"].format_map(placeholders)
    else:
        subject_local = subject_en
        body_local = body_en

    return EmailTextResponse(
        subject_en=subject_en,
        body_en=body_en,
        subject_local=subject_local,
        body_local=body_local,
    )
