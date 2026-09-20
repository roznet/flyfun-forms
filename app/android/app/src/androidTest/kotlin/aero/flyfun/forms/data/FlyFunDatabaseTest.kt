package aero.flyfun.forms.data

import androidx.room.Room
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.time.Instant
import java.time.LocalDate

@RunWith(AndroidJUnit4::class)
class FlyFunDatabaseTest {

    private lateinit var db: FlyFunDatabase
    private lateinit var people: PersonDao
    private lateinit var docs: TravelDocumentDao
    private lateinit var aircraft: AircraftDao
    private lateinit var flights: FlightDao

    @Before
    fun setUp() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        db = Room.inMemoryDatabaseBuilder(context, FlyFunDatabase::class.java).build()
        people = db.personDao()
        docs = db.travelDocumentDao()
        aircraft = db.aircraftDao()
        flights = db.flightDao()
    }

    @After
    fun tearDown() = db.close()

    private val dep: Instant = Instant.parse("2026-09-20T08:15:00Z")
    private val arr: Instant = Instant.parse("2026-09-20T10:05:00Z")

    private suspend fun person(first: String, last: String): PersonEntity =
        PersonEntity(firstName = first, lastName = last).also { people.upsert(it) }

    @Test
    fun flight_round_trips_with_crew_and_passengers_in_the_right_roles() = runTest {
        val pilot = person("Anna", "Eriksson")
        val paxA = person("Bo", "Lindqvist")
        val paxB = person("Cleo", "Marchand")

        val ac = AircraftEntity(registration = "G-ABCD", type = "SR22").also { aircraft.upsert(it) }
        val flight = FlightEntity(
            departureInstant = dep,
            arrivalInstant = arr,
            originICAO = "EGTF",
            destinationICAO = "LFRM",
            aircraftId = ac.id,
            responsiblePersonId = pilot.id,
        ).also { flights.upsert(it) }

        flights.setPeople(flight.id, FlightRole.CREW, listOf(pilot.id))
        flights.setPeople(flight.id, FlightRole.PASSENGER, listOf(paxA.id, paxB.id))

        val crew = flights.crewOn(flight.id)
        val pax = flights.passengersOn(flight.id)

        assertEquals(listOf("Eriksson"), crew.map { it.lastName })
        // seatOrder preserves the order they were added, not alphabetical
        assertEquals(listOf("Lindqvist", "Marchand"), pax.map { it.lastName })

        val stored = flights.byId(flight.id)
        assertNotNull(stored)
        assertEquals(dep, stored!!.departureInstant)
        assertEquals(arr, stored.arrivalInstant)
        assertEquals("EGTF", stored.originICAO)
    }

    @Test
    fun a_person_can_be_crew_on_one_flight_and_passenger_on_another() = runTest {
        val p = person("Dana", "Novak")
        val f1 = FlightEntity(departureInstant = dep, arrivalInstant = arr).also { flights.upsert(it) }
        val f2 = FlightEntity(departureInstant = dep.plusSeconds(86_400), arrivalInstant = arr.plusSeconds(86_400))
            .also { flights.upsert(it) }

        flights.setPeople(f1.id, FlightRole.CREW, listOf(p.id))
        flights.setPeople(f2.id, FlightRole.PASSENGER, listOf(p.id))

        assertEquals(1, flights.crewOn(f1.id).size)
        assertEquals(0, flights.passengersOn(f1.id).size)
        assertEquals(0, flights.crewOn(f2.id).size)
        assertEquals(1, flights.passengersOn(f2.id).size)
    }

    @Test
    fun setPeople_replaces_rather_than_appends() = runTest {
        val a = person("Eve", "Adams")
        val b = person("Finn", "Bauer")
        val f = FlightEntity(departureInstant = dep, arrivalInstant = arr).also { flights.upsert(it) }

        flights.setPeople(f.id, FlightRole.PASSENGER, listOf(a.id, b.id))
        assertEquals(2, flights.passengersOn(f.id).size)

        flights.setPeople(f.id, FlightRole.PASSENGER, listOf(b.id))
        assertEquals(listOf("Bauer"), flights.passengersOn(f.id).map { it.lastName })
    }

    @Test
    fun tombstoned_person_disappears_from_lists_but_the_row_survives() = runTest {
        val p = person("Gita", "Rao")
        assertEquals(1, people.observeAll().first().size)

        people.softDelete(p.id, Instant.parse("2026-09-19T12:00:00Z"))

        assertTrue(people.observeAll().first().isEmpty())
        val row = people.byId(p.id)
        assertNotNull("tombstone must keep the row so the deletion can be exported", row)
        assertEquals(Instant.parse("2026-09-19T12:00:00Z"), row!!.person.deletedAt)
    }

    @Test
    fun documents_come_back_with_their_person_and_calendar_dates_survive() = runTest {
        val p = person("Hugo", "Silva")
        docs.upsert(
            TravelDocumentEntity(
                personId = p.id,
                docNumber = "PP-FRA-001",
                issuingCountry = "FRA",
                expiryDate = LocalDate.of(2031, 6, 30),
            ),
        )
        val withDocs = people.byId(p.id)!!
        assertEquals(1, withDocs.documents.size)
        // A passport expiry is a calendar day; it must not drift through storage.
        assertEquals(LocalDate.of(2031, 6, 30), withDocs.documents[0].expiryDate)
    }

    @Test
    fun deleting_a_person_cascades_to_their_documents() = runTest {
        val p = person("Iris", "Toft")
        docs.upsert(TravelDocumentEntity(personId = p.id, docNumber = "X1"))
        assertEquals(1, docs.forPerson(p.id).size)

        people.hardDelete(p)
        assertEquals(0, docs.forPerson(p.id).size)
    }

    @Test
    fun deleting_an_aircraft_nulls_the_flight_link_instead_of_removing_the_flight() = runTest {
        val ac = AircraftEntity(registration = "G-ZZZZ").also { aircraft.upsert(it) }
        val f = FlightEntity(departureInstant = dep, arrivalInstant = arr, aircraftId = ac.id)
            .also { flights.upsert(it) }

        db.compileStatement("DELETE FROM aircraft WHERE id = '${ac.id}'").executeUpdateDelete()

        val stored = flights.byId(f.id)
        assertNotNull("the flight must survive losing its aircraft", stored)
        assertNull(stored!!.aircraftId)
    }

    @Test
    fun registration_lookup_normalises_dashes_and_case() = runTest {
        aircraft.upsert(AircraftEntity(registration = "G-ABCD", type = "SR22"))
        assertNotNull(aircraft.byNormalisedRegistration("GABCD"))
        assertNull(aircraft.byNormalisedRegistration("GWXYZ"))
    }

    @Test
    fun upcoming_and_past_split_on_the_departure_instant() = runTest {
        val now = Instant.parse("2026-09-19T00:00:00Z")
        flights.upsert(FlightEntity(departureInstant = now.minusSeconds(86_400), arrivalInstant = now, originICAO = "PAST"))
        flights.upsert(FlightEntity(departureInstant = now.plusSeconds(86_400), arrivalInstant = now, originICAO = "FUTURE"))

        assertEquals(listOf("FUTURE"), flights.observeUpcoming(now).first().map { it.originICAO })
        assertEquals(listOf("PAST"), flights.observePast(now).first().map { it.originICAO })
    }

    @Test
    fun default_aircraft_prefers_the_last_flown_over_the_only_one_on_file() {
        val older = AircraftEntity(registration = "G-OLD")
        val newer = AircraftEntity(registration = "G-NEW")

        assertEquals(newer.id, defaultAircraftForNewFlight(newer.id, listOf(older, newer))?.id)
        // Nothing flown yet, one aircraft on file -> use it
        assertEquals(older.id, defaultAircraftForNewFlight(null, listOf(older))?.id)
        // Nothing flown, several on file -> no guess
        assertNull(defaultAircraftForNewFlight(null, listOf(older, newer)))
    }
}
