package aero.flyfun.forms.net

import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The wire format is the contract with a server this app does not control, so
 * these assert exact key names. Mirrors the API tests in the Swift suite.
 */
class ApiTypesTest {

    private val json = Json { ignoreUnknownKeys = true; explicitNulls = false; encodeDefaults = true }

    private fun request() = GenerateRequest(
        airport = "LSGS",
        form = "immigration",
        flight = FlightPayload(
            origin = "EGTF",
            destination = "LSGS",
            departureDate = "2026-09-20",
            departureTimeUtc = "08:15",
            arrivalDate = "2026-09-20",
            arrivalTimeUtc = "10:05",
            nature = "private",
        ),
        aircraft = AircraftPayload(registration = "G-ABCD", type = "SR22", usualBase = "EGTF"),
        crew = listOf(PersonPayload(firstName = "Anna", lastName = "Eriksson", dob = "1974-08-12")),
        passengers = emptyList(),
    )

    @Test
    fun `GenerateRequest encodes snake_case keys`() {
        val encoded = json.encodeToString(GenerateRequest.serializer(), request())
        listOf(
            "\"departure_date\"", "\"departure_time_utc\"",
            "\"arrival_date\"", "\"arrival_time_utc\"",
            "\"usual_base\"", "\"first_name\"", "\"last_name\"",
        ).forEach { assertTrue("missing $it in $encoded", encoded.contains(it)) }
        // and never the camelCase spellings
        listOf("departureDate", "departureTimeUtc", "usualBase", "firstName").forEach {
            assertTrue("leaked camelCase $it", !encoded.contains("\"$it\""))
        }
    }

    @Test
    fun `null optionals are omitted rather than sent as null`() {
        val encoded = json.encodeToString(GenerateRequest.serializer(), request())
        assertTrue(!encoded.contains("\"connecting_flight\""))
        assertTrue(!encoded.contains("\"return_flight\""))
        assertTrue(!encoded.contains("null"))
    }

    @Test
    fun `PersonPayload encodes every snake_case field`() {
        val p = PersonPayload(
            function = "PIC",
            firstName = "Anna",
            lastName = "Eriksson",
            dob = "1974-08-12",
            nationality = "FRA",
            idNumber = "L898902C3",
            idType = "Passport",
            idIssuingCountry = "FRA",
            idExpiry = "2031-06-30",
            sex = "F",
            placeOfBirth = "Paris",
            address = "1 Rue de Test",
        )
        val encoded = json.encodeToString(PersonPayload.serializer(), p)
        listOf(
            "first_name", "last_name", "id_number", "id_type",
            "id_issuing_country", "id_expiry", "place_of_birth",
        ).forEach { assertTrue("missing $it", encoded.contains("\"$it\"")) }
    }

    @Test
    fun `ExtraFieldValue round-trips both shapes`() {
        val text: ExtraFieldValue = ExtraFieldValue.Text("business")
        val encodedText = json.encodeToString(ExtraFieldValueSerializer, text)
        assertEquals("\"business\"", encodedText)
        assertEquals(text, json.decodeFromString(ExtraFieldValueSerializer, encodedText))

        val person: ExtraFieldValue = ExtraFieldValue.Person(mapOf("name" to "Anna", "phone" to "+44"))
        val encodedPerson = json.encodeToString(ExtraFieldValueSerializer, person)
        assertTrue(encodedPerson.startsWith("{"))
        assertEquals(person, json.decodeFromString(ExtraFieldValueSerializer, encodedPerson))
    }

    @Test
    fun `AirportDetailResponse decodes server JSON`() {
        val body = """
        {"icao":"LSGS","name":"Sion","forms":[
          {"id":"immigration","label":"Immigration","version":"1",
           "required_fields":{"flight":["origin"],"aircraft":["registration"],"crew":[],"passengers":[]},
           "extra_fields":[{"key":"reason","label":"Reason","type":"choice","options":["business"],"maps_to":{"business":"B"}}],
           "max_crew":2,"max_passengers":4,"has_connecting_flight":false,
           "time_reference":"utc","send_to":"a@b.c","kind":"document","direction":"arrival"}
        ]}
        """.trimIndent()
        val r = json.decodeFromString(AirportDetailResponse.serializer(), body)
        assertEquals("LSGS", r.icao)
        val form = r.forms.single()
        assertEquals("immigration", form.id)
        assertEquals(2, form.maxCrew)
        assertEquals("arrival", form.direction)
        assertTrue(!form.isWebForm)
        assertEquals("business", form.extraFields.single().options?.single())
        assertEquals("B", form.extraFields.single().mapsTo?.get("business"))
    }

    @Test
    fun `an older server without kind or has_return_flight still parses`() {
        val body = """
        {"icao":"EGTF","name":"Fairoaks","forms":[
          {"id":"gar","label":"GAR","version":"1",
           "required_fields":{"flight":[],"aircraft":[],"crew":[],"passengers":[]},
           "extra_fields":[],"max_crew":1,"max_passengers":3,
           "has_connecting_flight":false,"time_reference":"utc"}
        ]}
        """.trimIndent()
        val form = json.decodeFromString(AirportDetailResponse.serializer(), body).forms.single()
        assertNull(form.kind)
        assertNull(form.hasReturnFlight)
        assertTrue(!form.isWebForm)
    }

    @Test
    fun `web forms are recognised`() {
        val body = """{"form":"bookout","label":"Book out","url":"https://x/y","scope":"#f",
          "fields":[{"name":"reg","value":"G-ABCD","type":"text"},{"name":"ack","value":"true","type":"checkbox"}]}"""
        val plan = json.decodeFromString(FillPlan.serializer(), body)
        assertEquals(2, plan.fields.size)
        assertEquals("checkbox", plan.fields[1].type)
    }

    @Test
    fun `validation errors become readable field labels`() {
        val body = """{"detail":[
          {"field":"crew[0].id_number","error":"required"},
          {"field":"flight.departure_time_utc","error":"bad format","value":"25:00"},
          {"field":"airport","error":"unknown"}
        ]}"""
        val errors = json.decodeFromString(ValidationErrorEnvelope.serializer(), body).detail
        assertEquals("Crew 1 - ID Number", errors[0].displayField)
        assertEquals("Departure Time UTC", errors[1].displayField)
        assertEquals("Airport", errors[2].displayField)
        assertEquals("25:00", errors[1].value)
    }
}
