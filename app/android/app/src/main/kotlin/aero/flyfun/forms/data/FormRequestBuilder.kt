package aero.flyfun.forms.data

import aero.flyfun.forms.net.AircraftPayload
import aero.flyfun.forms.net.ExtraFieldInfo
import aero.flyfun.forms.net.ExtraFieldValue
import aero.flyfun.forms.net.FlightPayload
import aero.flyfun.forms.net.GenerateRequest
import aero.flyfun.forms.net.PersonPayload
import aero.flyfun.forms.net.ReturnFlightPayload
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

    /**
     * @param contactName who to contact about the flight. iOS sends the
     *   responsible person's name and falls back to the stored `contact`.
     */
    fun flightPayload(flight: FlightEntity, contactName: String? = null): FlightPayload = FlightPayload(
        origin = flight.originICAO.uppercase(),
        destination = flight.destinationICAO.uppercase(),
        departureDate = utcDate(flight.departureInstant),
        departureTimeUtc = utcTime(flight.departureInstant),
        arrivalDate = utcDate(flight.arrivalInstant),
        arrivalTimeUtc = utcTime(flight.arrivalInstant),
        nature = flight.nature,
        contact = contactName?.takeIf { it.isNotBlank() } ?: flight.contact,
    )

    fun returnFlightPayload(leg: FlightEntity, peopleOnBoard: Int): ReturnFlightPayload = ReturnFlightPayload(
        origin = leg.originICAO.uppercase(),
        destination = leg.destinationICAO.uppercase(),
        departureDate = utcDate(leg.departureInstant),
        departureTimeUtc = utcTime(leg.departureInstant),
        arrivalDate = utcDate(leg.arrivalInstant),
        arrivalTimeUtc = utcTime(leg.arrivalInstant),
        peopleOnBoard = peopleOnBoard,
    )

    /** Extra fields the flight itself supplies, so the per-form UI does not ask for them. */
    val FLIGHT_SUPPLIED_EXTRAS: Set<String> = setOf(REASON_FOR_VISIT, RESPONSIBLE_PERSON)

    /** Extra fields read from the responsible person rather than typed per form. */
    val PERSON_SUPPLIED_EXTRAS: Set<String> = setOf(TELEPHONE, EMAIL)

    const val REASON_FOR_VISIT = "reason_for_visit"
    const val RESPONSIBLE_PERSON = "responsible_person"
    const val TELEPHONE = "telephone"
    const val EMAIL = "email"

    /**
     * A choice field shows its first option until the pilot picks another, so
     * that option is what gets sent. iOS sends nothing for an untouched
     * choice, which the server rejects as missing when the field is required.
     */
    fun withChoiceDefaults(
        fields: List<ExtraFieldInfo>,
        entered: Map<String, ExtraFieldValue>,
    ): Map<String, ExtraFieldValue> {
        val defaults = fields
            .filter { it.type == "choice" && it.key !in entered && it.key !in FLIGHT_SUPPLIED_EXTRAS }
            .mapNotNull { field -> field.options?.firstOrNull()?.let { field.key to ExtraFieldValue.Text(it) } }
        return entered + defaults
    }

    /**
     * The extra fields sent with a form: what was entered for it, plus what
     * the flight supplies. Port of the injection in iOS `buildRequest`:
     * reason for visit and the responsible person always come from the
     * flight, and the person's phone and e-mail fill `telephone` / `email`
     * unless the form already has them.
     */
    fun extraFields(
        entered: Map<String, ExtraFieldValue>,
        reasonForVisit: String?,
        responsiblePerson: PersonEntity?,
    ): Map<String, ExtraFieldValue> {
        val extras = entered.toMutableMap()
        reasonForVisit?.takeIf { it.isNotBlank() }?.let { extras[REASON_FOR_VISIT] = ExtraFieldValue.Text(it) }
        responsiblePerson?.let { person ->
            extras[RESPONSIBLE_PERSON] = ExtraFieldValue.Person(
                mapOf("name" to person.displayName, "address" to person.address.orEmpty()),
            )
            person.phone?.takeIf { it.isNotBlank() }?.let { extras.putIfAbsent(TELEPHONE, ExtraFieldValue.Text(it)) }
            person.email?.takeIf { it.isNotBlank() }?.let { extras.putIfAbsent(EMAIL, ExtraFieldValue.Text(it)) }
        }
        return extras
    }

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
     * @param extraFields the complete extras, see [extraFields]
     * @param connectingFlight the leg [aero.flyfun.forms.logic.FlightLegs.connecting]
     *   found, with its contact name, for forms that ask for it
     */
    fun build(
        airport: String,
        formId: String,
        flight: FlightEntity,
        aircraft: AircraftEntity,
        crew: List<PersonEntity>,
        passengers: List<PersonEntity>,
        documentFor: (PersonEntity) -> TravelDocumentEntity?,
        responsiblePerson: PersonEntity? = null,
        extraFields: Map<String, ExtraFieldValue> = emptyMap(),
        connectingFlight: Pair<FlightEntity, String?>? = null,
        returnFlight: ReturnFlightPayload? = null,
    ): GenerateRequest = GenerateRequest(
        airport = airport.uppercase(),
        form = formId,
        flight = flightPayload(flight, responsiblePerson?.displayName),
        aircraft = aircraftPayload(aircraft),
        // The first crew member is the one in command. "Pilot", not "PIC":
        // the word is printed as-is on the gendec and LSGS forms, and it is
        // what iOS sends.
        crew = crew.mapIndexed { i, p ->
            personPayload(p, documentFor(p), function = if (i == 0) "Pilot" else "Crew")
        },
        passengers = passengers.map { personPayload(it, documentFor(it)) },
        connectingFlight = connectingFlight?.let { (leg, contact) -> flightPayload(leg, contact) },
        returnFlight = returnFlight,
        extraFields = extraFields.takeIf { it.isNotEmpty() },
        observations = flight.observations?.takeIf { it.isNotBlank() },
    )
}
