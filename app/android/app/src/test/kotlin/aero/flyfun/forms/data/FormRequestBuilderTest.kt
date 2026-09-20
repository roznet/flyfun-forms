package aero.flyfun.forms.data

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
    fun `first crew member is PIC and the rest are crew`() {
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
        assertEquals(listOf("PIC", "Crew"), req.crew.map { it.function })
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

    @Test
    fun `direction is derived from which end the airport is`() {
        assertEquals("departure", FormRequestBuilder.directionFor("EGTF", flight))
        assertEquals("arrival", FormRequestBuilder.directionFor("lfrm", flight))
        assertNull(FormRequestBuilder.directionFor("LSGS", flight))
    }

    @Test
    fun `a local flight counts as arrival at its own airport`() {
        // origin == destination: the destination branch wins, matching the
        // server's own ordering.
        val local = flight.copy(destinationICAO = "EGTF")
        assertEquals("arrival", FormRequestBuilder.directionFor("EGTF", local))
    }
}
