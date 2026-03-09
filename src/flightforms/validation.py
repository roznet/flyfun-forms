"""Shared validation logic for /generate and /validate endpoints."""

from .api.models import GenerateRequest, ValidationError
from .registry import FormMapping


def validate_request(request: GenerateRequest, mapping: FormMapping) -> list[ValidationError]:
    """Validate a generate request against a form mapping. Returns list of errors."""
    errors = []

    # Direction check
    if request.airport != request.flight.origin and request.airport != request.flight.destination:
        errors.append(ValidationError(
            field="airport",
            error="Airport must be either origin or destination of the flight",
        ))

    # Crew count
    if len(request.crew) > mapping.max_crew:
        errors.append(ValidationError(
            field="crew",
            error=f"count {len(request.crew)} exceeds max {mapping.max_crew}",
        ))

    # Passenger count
    if len(request.passengers) > mapping.max_passengers:
        errors.append(ValidationError(
            field="passengers",
            error=f"count {len(request.passengers)} exceeds max {mapping.max_passengers}",
        ))

    # Required fields check
    required = mapping.required_fields
    if required:
        # Flight fields
        for field in required.get("flight", []):
            val = getattr(request.flight, field, None)
            if not val:
                errors.append(ValidationError(field=f"flight.{field}", error="required for this form"))

        # Aircraft fields
        for field in required.get("aircraft", []):
            val = getattr(request.aircraft, field, None)
            if val is None or val == "":
                errors.append(ValidationError(field=f"aircraft.{field}", error="required for this form"))

        # Crew person fields
        for i, crew in enumerate(request.crew):
            for field in required.get("crew", []):
                val = getattr(crew, field, None)
                if val is None or val == "":
                    errors.append(ValidationError(field=f"crew[{i}].{field}", error="required for this form"))

        # Passenger person fields
        for i, pax in enumerate(request.passengers):
            for field in required.get("passengers", []):
                val = getattr(pax, field, None)
                if val is None or val == "":
                    errors.append(ValidationError(field=f"passengers[{i}].{field}", error="required for this form"))

    # Extra fields check
    for ef in mapping.extra_fields:
        ef_def = ef if isinstance(ef, dict) else {"key": ef, "type": "text"}
        key = ef_def.get("key", "")
        ef_type = ef_def.get("type", "text")
        required = ef_def.get("required", True)
        if not key or not required:
            continue

        value = (request.extra_fields or {}).get(key)
        if not value:
            errors.append(ValidationError(field=f"extra_fields.{key}", error="required for this form"))
            continue

        if ef_type == "choice":
            options = ef_def.get("options", [])
            if options and value not in options:
                errors.append(ValidationError(
                    field=f"extra_fields.{key}",
                    error=f"must be one of: {', '.join(options)}",
                ))
        elif ef_type == "person":
            if not isinstance(value, dict) or not value.get("name"):
                errors.append(ValidationError(
                    field=f"extra_fields.{key}",
                    error="must include at least a name",
                ))

    return errors
