package aero.flyfun.forms.data

import aero.flyfun.forms.net.AircraftPayload
import aero.flyfun.forms.net.FlightPayload
import aero.flyfun.forms.net.GenerateRequest
import aero.flyfun.forms.net.PersonPayload
import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter

/**
 * Turns stored entities into the body `/generate` expects.
 *
 * Kept pure - no DAOs, no Android - so the mapping is unit-testable. Getting
 * this wrong produces a form that is subtly wrong rather than an error, which is
 * the worst failure mode this app has: a pilot hands it to a border officer.
 */
object FormRequestBuilder {

    private val DATE: DateTimeFormatter = DateTimeFormatter.ofPattern("yyyy-MM-dd")
    private val TIME: DateTimeFormatter = DateTimeFormatter.ofPattern("HH:mm")

    /** The wire format splits an instant into a UTC date and a UTC time-of-day. */
    fun utcDate(instant: Instant): String = DATE.format(instant.atOffset(ZoneOffset.UTC))

    fun utcTime(instant: Instant): String = TIME.format(instant.atOffset(ZoneOffset.UTC))

    fun flightPayload(flight: FlightEntity): FlightPayload = FlightPayload(
        origin = flight.originICAO.uppercase(),
        destination = flight.destinationICAO.uppercase(),
        departureDate = utcDate(flight.departureInstant),
        departureTimeUtc = utcTime(flight.departureInstant),
        arrivalDate = utcDate(flight.arrivalInstant),
        arrivalTimeUtc = utcTime(flight.arrivalInstant),
        nature = flight.nature,
        contact = flight.contact,
    )

    fun aircraftPayload(aircraft: AircraftEntity): AircraftPayload = AircraftPayload(
        registration = aircraft.registration,
        type = aircraft.type,
        owner = aircraft.owner?.takeIf { it.isNotBlank() },
        ownerAddress = aircraft.ownerAddress?.takeIf { it.isNotBlank() },
        isAirplane = aircraft.isAirplane,
        usualBase = aircraft.usualBase?.takeIf { it.isNotBlank() },
    )

    /**
     * @param document the document [DocumentResolver] picked for the target
     *   airport. Nationality is taken from its issuing country, never from the
     *   person - a pilot with two passports has no single nationality, which is
     *   the whole reason documents are resolved per airport.
     */
    fun personPayload(
        person: PersonEntity,
        document: TravelDocumentEntity?,
        function: String? = null,
    ): PersonPayload = PersonPayload(
        function = function,
        firstName = person.firstName,
        lastName = person.lastName,
        dob = person.dateOfBirth?.toString(),
        nationality = document?.issuingCountry,
        idNumber = document?.docNumber?.takeIf { it.isNotBlank() },
        idType = document?.docType,
        idIssuingCountry = document?.issuingCountry,
        idExpiry = document?.expiryDate?.toString(),
        sex = person.sex,
        placeOfBirth = person.placeOfBirth?.takeIf { it.isNotBlank() },
        address = person.address?.takeIf { it.isNotBlank() },
    )

    /**
     * @param documentFor resolves the document to use for a person, already
     *   scoped to the target airport
     */
    fun build(
        airport: String,
        formId: String,
        flight: FlightEntity,
        aircraft: AircraftEntity,
        crew: List<PersonEntity>,
        passengers: List<PersonEntity>,
        documentFor: (PersonEntity) -> TravelDocumentEntity?,
    ): GenerateRequest = GenerateRequest(
        airport = airport.uppercase(),
        form = formId,
        flight = flightPayload(flight),
        aircraft = aircraftPayload(aircraft),
        // The first crew member is the one in command. "Pilot", not "PIC":
        // the word is printed as-is on the gendec and LSGS forms, and it is
        // what iOS sends.
        crew = crew.mapIndexed { i, p ->
            personPayload(p, documentFor(p), function = if (i == 0) "Pilot" else "Crew")
        },
        passengers = passengers.map { personPayload(it, documentFor(it)) },
        observations = flight.observations?.takeIf { it.isNotBlank() },
    )
}
