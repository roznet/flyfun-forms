package aero.flyfun.forms.data

import aero.flyfun.forms.net.ExtraFieldInfo
import aero.flyfun.forms.net.ExtraFieldValue
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.time.Instant
import java.time.LocalDate

class FormRequestBuilderTest {

    private val flight = FlightEntity(
        departureInstant = Instant.parse("2026-09-20T08:15:00Z"),
        arrivalInstant = Instant.parse("2026-09-20T23:50:00Z"),
        originICAO = "egtf",
        destinationICAO = "lfrm",
        nature = "private",
        contact = "Anna",
    )
    private val aircraft = AircraftEntity(registration = "G-ABCD", type = "SR22", usualBase = "EGTF")

    private fun person(first: String, last: String) =
        PersonEntity(firstName = first, lastName = last, dateOfBirth = LocalDate.of(1974, 8, 12))

    private fun doc(country: String) = TravelDocumentEntity(
        personId = "p",
        docType = "Passport",
        docNumber = "L898902C3",
        issuingCountry = country,
        expiryDate = LocalDate.of(2031, 6, 30),
    )

    @Test
    fun `instants split into UTC date and time`() {
        val p = FormRequestBuilder.flightPayload(flight)
        assertEquals("2026-09-20", p.departureDate)
        assertEquals("08:15", p.departureTimeUtc)
        assertEquals("2026-09-20", p.arrivalDate)
        assertEquals("23:50", p.arrivalTimeUtc)
    }

    @Test
    fun `an arrival after UTC midnight lands on the next date`() {
        // The pair representation this replaces got exactly this case wrong.
        val late = flight.copy(arrivalInstant = Instant.parse("2026-09-21T00:20:00Z"))
        val p = FormRequestBuilder.flightPayload(late)
        assertEquals("2026-09-20", p.departureDate)
        assertEquals("2026-09-21", p.arrivalDate)
        assertEquals("00:20", p.arrivalTimeUtc)
    }

    @Test
    fun `ICAO codes are upper-cased`() {
        val p = FormRequestBuilder.flightPayload(flight)
        assertEquals("EGTF", p.origin)
        assertEquals("LFRM", p.destination)
    }

    @Test
    fun `nationality comes from the resolved document not the person`() {
        val payload = FormRequestBuilder.personPayload(person("Anna", "Eriksson"), doc("FRA"))
        assertEquals("FRA", payload.nationality)
        assertEquals("FRA", payload.idIssuingCountry)
        assertEquals("L898902C3", payload.idNumber)
        assertEquals("2031-06-30", payload.idExpiry)
        assertEquals("1974-08-12", payload.dob)
    }

    @Test
    fun `a person with no usable document still produces a payload`() {
        // The server validates and returns 422 naming the missing field; the
        // client must not silently drop the person from the manifest.
        val payload = FormRequestBuilder.personPayload(person("Bo", "Lindqvist"), null)
        assertEquals("Bo", payload.firstName)
        assertNull(payload.nationality)
        assertNull(payload.idNumber)
    }

    @Test
    fun `first crew member is Pilot and the rest are crew`() {
        val req = FormRequestBuilder.build(
            airport = "lfrm",
            formId = "customs",
            flight = flight,
            aircraft = aircraft,
            crew = listOf(person("Anna", "Eriksson"), person("Bo", "Lindqvist")),
            passengers = listOf(person("Cleo", "Marchand")),
            documentFor = { doc("FRA") },
        )
        assertEquals("LFRM", req.airport)
        assertEquals(listOf("Pilot", "Crew"), req.crew.map { it.function })
        assertNull(req.passengers.single().function)
        assertEquals("Marchand", req.passengers.single().lastName)
    }

    @Test
    fun `blank optional aircraft fields are omitted rather than sent empty`() {
        val bare = AircraftEntity(registration = "G-ZZZZ", type = "C172", owner = "  ", usualBase = "")
        val p = FormRequestBuilder.aircraftPayload(bare)
        assertNull(p.owner)
        assertNull(p.usualBase)
    }

    private val anna = PersonEntity(
        firstName = "Anna", lastName = "Eriksson",
        phone = "+33 6 00 00 00 00", email = "anna@example.test", address = "1 Rue de Test",
    )

    @Test
    fun `the responsible person names the contact and fills phone and e-mail`() {
        val extras = FormRequestBuilder.extraFields(
            entered = emptyMap(),
            reasonForVisit = "Maintenance",
            responsiblePerson = anna,
        )
        assertEquals(ExtraFieldValue.Text("Maintenance"), extras["reason_for_visit"])
        assertEquals(
            ExtraFieldValue.Person(mapOf("name" to "Anna Eriksson", "address" to "1 Rue de Test")),
            extras["responsible_person"],
        )
        assertEquals(ExtraFieldValue.Text("+33 6 00 00 00 00"), extras["telephone"])
        assertEquals(ExtraFieldValue.Text("anna@example.test"), extras["email"])

        val req = FormRequestBuilder.build(
            airport = "LFRM", formId = "customs", flight = flight, aircraft = aircraft,
            crew = emptyList(), passengers = emptyList(), documentFor = { null },
            responsiblePerson = anna, extraFields = extras,
        )
        assertEquals("Anna Eriksson", req.flight.contact)
    }

    @Test
    fun `a telephone typed for the form wins over the responsible person's`() {
        val extras = FormRequestBuilder.extraFields(
            entered = mapOf("telephone" to ExtraFieldValue.Text("+44 20 0000 0000")),
            reasonForVisit = null,
            responsiblePerson = anna,
        )
        assertEquals(ExtraFieldValue.Text("+44 20 0000 0000"), extras["telephone"])
        assertNull(extras["reason_for_visit"])
    }

    @Test
    fun `without a responsible person the stored contact is sent`() {
        val req = FormRequestBuilder.build(
            airport = "LFRM", formId = "customs", flight = flight, aircraft = aircraft,
            crew = emptyList(), passengers = emptyList(), documentFor = { null },
        )
        assertEquals("Anna", req.flight.contact)
        assertNull(req.extraFields)
    }

    @Test
    fun `an untouched choice sends the option it shows`() {
        val fields = listOf(
            ExtraFieldInfo(key = "purpose", label = "Purpose", type = "choice", options = listOf("Tourism", "Business")),
            ExtraFieldInfo(key = "landing", label = "Landing", type = "choice", options = listOf("A", "B")),
            ExtraFieldInfo(key = "reason_for_visit", label = "Reason", type = "choice", options = listOf("Based")),
            ExtraFieldInfo(key = "notes", label = "Notes", type = "text"),
        )
        val extras = FormRequestBuilder.withChoiceDefaults(fields, mapOf("landing" to ExtraFieldValue.Text("B")))
        assertEquals(
            mapOf("landing" to ExtraFieldValue.Text("B"), "purpose" to ExtraFieldValue.Text("Tourism")),
            extras,
        )
    }

    @Test
    fun `connecting and return legs go on the wire`() {
        val onward = flight.copy(
            id = "onward", originICAO = "LFRM", destinationICAO = "LSGS",
            departureInstant = Instant.parse("2026-09-22T09:00:00Z"),
            arrivalInstant = Instant.parse("2026-09-22T10:30:00Z"),
        )
        val req = FormRequestBuilder.build(
            airport = "LFRM", formId = "customs", flight = flight, aircraft = aircraft,
            crew = emptyList(), passengers = emptyList(), documentFor = { null },
            connectingFlight = onward to "Bo Lindqvist",
            returnFlight = FormRequestBuilder.returnFlightPayload(onward, peopleOnBoard = 3),
        )
        assertEquals("LSGS", req.connectingFlight?.destination)
        assertEquals("09:00", req.connectingFlight?.departureTimeUtc)
        assertEquals("Bo Lindqvist", req.connectingFlight?.contact)
        assertEquals(3, req.returnFlight?.peopleOnBoard)
        assertEquals("2026-09-22", req.returnFlight?.arrivalDate)
    }
}
