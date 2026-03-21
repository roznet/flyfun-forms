"""Pydantic models for API request/response."""

import re

from pydantic import BaseModel, field_validator
from typing import Optional, Union

_ICAO_RE = re.compile(r"^[A-Z]{4}$")
_DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
_TIME_RE = re.compile(r"^\d{2}:\d{2}$")


def _validate_icao(v: str) -> str:
    v = v.upper()
    if not _ICAO_RE.match(v):
        raise ValueError("Invalid ICAO code")
    return v


def _validate_date(v: str) -> str:
    if not _DATE_RE.match(v):
        raise ValueError("Date must be YYYY-MM-DD")
    return v


def _validate_time(v: str) -> str:
    if not _TIME_RE.match(v):
        raise ValueError("Time must be HH:MM")
    return v


class FlightData(BaseModel):
    origin: str
    destination: str
    departure_date: str  # YYYY-MM-DD
    departure_time_utc: str  # HH:MM
    arrival_date: str  # YYYY-MM-DD
    arrival_time_utc: str  # HH:MM
    nature: str = "private"
    contact: Optional[str] = None

    @field_validator("departure_date", "arrival_date")
    @classmethod
    def validate_date(cls, v: str) -> str:
        return _validate_date(v)

    @field_validator("departure_time_utc", "arrival_time_utc")
    @classmethod
    def validate_time(cls, v: str) -> str:
        return _validate_time(v)


class AircraftData(BaseModel):
    registration: str
    type: str
    owner: Optional[str] = None
    owner_address: Optional[str] = None
    is_airplane: bool = True
    usual_base: Optional[str] = None


class PersonData(BaseModel):
    function: Optional[str] = None  # Pilot, Captain, Crew
    first_name: str
    last_name: str
    dob: Optional[str] = None  # YYYY-MM-DD
    nationality: Optional[str] = None  # ISO alpha-3
    id_number: Optional[str] = None
    id_type: Optional[str] = None  # Passport, Identity card
    id_issuing_country: Optional[str] = None
    id_expiry: Optional[str] = None
    sex: Optional[str] = None
    place_of_birth: Optional[str] = None
    address: Optional[str] = None


class ConnectingFlightData(BaseModel):
    origin: str
    destination: str
    departure_date: str
    departure_time_utc: str
    arrival_date: str
    arrival_time_utc: str

    @field_validator("departure_date", "arrival_date")
    @classmethod
    def validate_date(cls, v: str) -> str:
        return _validate_date(v)

    @field_validator("departure_time_utc", "arrival_time_utc")
    @classmethod
    def validate_time(cls, v: str) -> str:
        return _validate_time(v)


class GenerateRequest(BaseModel):
    airport: str
    form: str

    @field_validator("airport")
    @classmethod
    def validate_airport(cls, v: str) -> str:
        return _validate_icao(v)

    flight: FlightData
    aircraft: AircraftData
    crew: list[PersonData]
    passengers: list[PersonData] = []
    connecting_flight: Optional[ConnectingFlightData] = None
    extra_fields: Optional[dict[str, Union[str, dict[str, str]]]] = None
    observations: Optional[str] = None


class ValidationError(BaseModel):
    field: str
    error: str
    value: Optional[str] = None


class ValidateResponse(BaseModel):
    valid: bool
    errors: list[ValidationError] = []


class EmailConfig(BaseModel):
    to: list[str] = []
    cc: list[str] = []


class FormInfo(BaseModel):
    id: str
    label: str
    version: str
    required_fields: dict
    extra_fields: list[dict] = []
    max_crew: int
    max_passengers: int
    has_connecting_flight: bool
    time_reference: str
    send_to: Optional[str] = None
    email: Optional[EmailConfig] = None


class AirportInfo(BaseModel):
    icao: str
    name: str
    forms: list[str]


class AirportDetail(BaseModel):
    icao: str
    name: str
    forms: list[FormInfo]


class PrefixInfo(BaseModel):
    prefix: str
    country: str
    forms: list[str]


class DefaultFormInfo(BaseModel):
    forms: list[str]


class AirportsResponse(BaseModel):
    airports: list[AirportInfo]
    prefixes: list[PrefixInfo]
    defaults: list[DefaultFormInfo] = []


class EmailTextRequest(BaseModel):
    airport: str
    form: str

    @field_validator("airport")
    @classmethod
    def validate_airport(cls, v: str) -> str:
        return _validate_icao(v)

    origin: str
    destination: str
    departure_date: str  # YYYY-MM-DD
    registration: str
    aircraft_type: Optional[str] = None

    @field_validator("departure_date")
    @classmethod
    def validate_date(cls, v: str) -> str:
        return _validate_date(v)


class EmailTextResponse(BaseModel):
    subject_en: str
    body_en: str
    subject_local: str
    body_local: str
