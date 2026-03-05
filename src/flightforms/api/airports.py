"""Airport discovery endpoints."""

from fastapi import APIRouter, Depends, HTTPException

from ..airport_resolver import PREFIX_COUNTRIES, AirportResolver
from ..db.deps import current_user_id
from ..registry import MappingRegistry
from .models import AirportDetail, AirportInfo, AirportsResponse, FormInfo, PrefixInfo

router = APIRouter()

# These are set by app.py at startup
_registry: MappingRegistry | None = None
_resolver: AirportResolver | None = None


def configure(registry: MappingRegistry, resolver: AirportResolver):
    global _registry, _resolver
    _registry = registry
    _resolver = resolver


@router.get("/airports", response_model=AirportsResponse)
def list_airports(user_id: str = Depends(current_user_id)):
    airports = []
    for icao, mappings in _registry.all_airports().items():
        airports.append(AirportInfo(
            icao=icao,
            name=_resolver.get_name(icao),
            forms=[m.id for m in mappings],
        ))

    prefixes = []
    for prefix, mappings in _registry.all_prefixes().items():
        country = PREFIX_COUNTRIES.get(prefix, prefix)
        prefixes.append(PrefixInfo(
            prefix=prefix,
            country=country,
            forms=[m.id for m in mappings],
        ))

    return AirportsResponse(airports=airports, prefixes=prefixes)


@router.get("/airports/{icao}", response_model=AirportDetail)
def get_airport(icao: str, user_id: str = Depends(current_user_id)):
    mappings = _registry.get_forms_for_airport(icao)
    if not mappings:
        raise HTTPException(status_code=404, detail=f"No forms available for {icao}")

    forms = []
    for m in mappings:
        extra = []
        for ef in m.extra_fields:
            if isinstance(ef, str):
                extra.append({"key": ef, "label": ef.replace("_", " ").title(), "type": "text"})
            else:
                extra.append(ef)

        forms.append(FormInfo(
            id=m.id,
            label=m.label,
            version=m.version,
            required_fields=m.required_fields,
            extra_fields=extra,
            max_crew=m.max_crew,
            max_passengers=m.max_passengers,
            has_connecting_flight=m.has_connecting_flight,
            time_reference=m.time_reference,
            send_to=m.send_to,
        ))

    return AirportDetail(
        icao=icao,
        name=_resolver.get_name(icao),
        forms=forms,
    )
