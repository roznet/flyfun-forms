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
        key = ef if isinstance(ef, str) else ef.get("key", "")
        if key and not (request.extra_fields or {}).get(key):
            errors.append(ValidationError(field=f"extra_fields.{key}", error="required for this form"))

    return errors
