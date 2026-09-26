package aero.flyfun.forms.data

import androidx.room.Room
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
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

/** The whole point of the feature: data must survive leaving the app and coming back. */
@RunWith(AndroidJUnit4::class)
class DataTransferTest {

    private lateinit var source: FlyFunDatabase
    private lateinit var target: FlyFunDatabase

    @Before
    fun setUp() {
        val ctx = InstrumentationRegistry.getInstrumentation().targetContext
        source = Room.inMemoryDatabaseBuilder(ctx, FlyFunDatabase::class.java).build()
        target = Room.inMemoryDatabaseBuilder(ctx, FlyFunDatabase::class.java).build()
    }

    @After
    fun tearDown() {
        source.close()
        target.close()
    }

    private suspend fun populate(db: FlyFunDatabase): Triple<String, String, String> {
        val person = PersonEntity(
            firstName = "Anna", lastName = "Eriksson",
            dateOfBirth = LocalDate.of(1974, 8, 12), isUsualCrew = true,
        )
        db.personDao().upsert(person)
        db.travelDocumentDao().upsert(
            TravelDocumentEntity(
                personId = person.id, docNumber = "L898902C3",
                issuingCountry = "FRA", expiryDate = LocalDate.of(2031, 6, 30),
            ),
        )
        val aircraft = AircraftEntity(registration = "G-ABCD", type = "SR22", usualBase = "EGTF")
        db.aircraftDao().upsert(aircraft)
        val flight = FlightEntity(
            departureInstant = Instant.parse("2026-09-20T08:15:00Z"),
            arrivalInstant = Instant.parse("2026-09-20T10:05:00Z"),
            originICAO = "EGTF", destinationICAO = "LFRM", aircraftId = aircraft.id,
        )
        db.flightDao().upsert(flight)
        db.flightDao().setPeople(flight.id, FlightRole.CREW, listOf(person.id))
        return Triple(person.id, aircraft.id, flight.id)
    }

    @Test
    fun encrypted_round_trip_restores_everything_on_an_empty_device() = runTest {
        val (personId, _, flightId) = populate(source)
        val password = "alpha-bravo-charlie-delta-echo-foxtrot".toCharArray()

        val bytes = DataTransfer(source).exportEncrypted("test", password)

        val incoming = DataTransfer(target)
        val (_, summary) = incoming.preview(bytes, password.copyOf())
        incoming.apply(summary)

        val person = target.personDao().byId(personId)
        assertNotNull(person)
        assertEquals("Eriksson", person!!.person.lastName)
        assertEquals(LocalDate.of(1974, 8, 12), person.person.dateOfBirth)
        // A passport expiry is a calendar day and must not drift through the file
        assertEquals(LocalDate.of(2031, 6, 30), person.documents.single().expiryDate)

        val flight = target.flightDao().byId(flightId)
        assertNotNull(flight)
        assertEquals(Instant.parse("2026-09-20T08:15:00Z"), flight!!.departureInstant)
        assertEquals(listOf("Eriksson"), target.flightDao().crewOn(flightId).map { it.lastName })
    }

    @Test
    fun trip_extra_fields_survive_the_round_trip() = runTest {
        val trip = TripEntity(name = "Alps", extraFieldsJson = """{"reason_for_visit":"Maintenance"}""")
        source.tripDao().upsert(trip)
        // Generated, as the real export does, rather than a literal a secret
        // scanner reads as a hardcoded password.
        val password = aero.flyfun.forms.logic.DataFileCrypto.generatePassphrase().toCharArray()

        val bytes = DataTransfer(source).exportEncrypted("test", password)
        val incoming = DataTransfer(target)
        incoming.preview(bytes, password.copyOf()).let { incoming.apply(it.second) }

        val stored = target.tripDao().byId(trip.id)
        assertNotNull(stored)
        assertEquals(
            mapOf("reason_for_visit" to "Maintenance"),
            aero.flyfun.forms.logic.TripExtras.decode(stored!!.extraFieldsJson),
        )
    }

    @Test
    fun re_importing_the_same_file_changes_nothing() = runTest {
        populate(source)
        val password = "one-two-three-four-five-six".toCharArray()
        val bytes = DataTransfer(source).exportEncrypted("test", password)

        val incoming = DataTransfer(target)
        incoming.preview(bytes, password.copyOf()).let { incoming.apply(it.second) }
        val (_, second) = incoming.preview(bytes, password.copyOf())

        assertEquals(0, second.inserted)
        assertEquals(0, second.updated)
        assertEquals(0, second.removed)
    }

    @Test
    fun import_never_removes_local_records_the_file_does_not_mention() = runTest {
        populate(source)
        val local = PersonEntity(firstName = "Only", lastName = "Here")
        target.personDao().upsert(local)

        val password = "keep-mine-please-and-thanks-ok".toCharArray()
        val bytes = DataTransfer(source).exportEncrypted("test", password)
        val incoming = DataTransfer(target)
        incoming.preview(bytes, password.copyOf()).let { incoming.apply(it.second) }

        assertNotNull(target.personDao().byId(local.id))
        assertEquals(2, target.personDao().observeAllOnce().size)
    }

    @Test
    fun a_deletion_propagates_through_the_file() = runTest {
        val (personId, _, _) = populate(source)
        val password = "delete-should-travel-with-the-file".toCharArray()

        val incoming = DataTransfer(target)
        DataTransfer(source).exportEncrypted("test", password).let { first ->
            incoming.preview(first, password.copyOf()).let { incoming.apply(it.second) }
        }
        assertNotNull(target.personDao().byId(personId))

        // Delete on the source, export again, import again.
        source.personDao().softDelete(personId, Instant.now())
        val second = DataTransfer(source).exportEncrypted("test", password.copyOf())
        incoming.preview(second, password.copyOf()).let { incoming.apply(it.second) }

        val row = target.personDao().byId(personId)
        assertNotNull("the row survives as a tombstone", row)
        assertNotNull("and is marked deleted", row!!.person.deletedAt)
        assertTrue(target.personDao().observeAllOnce().none { it.id == personId })
    }

    @Test
    fun the_wrong_password_fails_before_anything_is_written() = runTest {
        populate(source)
        val bytes = DataTransfer(source).exportEncrypted("test", "correct-horse-battery-staple".toCharArray())

        val incoming = DataTransfer(target)
        runCatching { incoming.preview(bytes, "wrong-password-entirely".toCharArray()) }
            .onSuccess { throw AssertionError("should not have decrypted") }

        assertEquals(0, target.personDao().observeAllOnce().size)
    }

    @Test
    fun the_plaintext_GDPR_export_is_readable_and_imports_the_same_way() = runTest {
        val (personId, _, _) = populate(source)
        val text = DataTransfer(source).exportPlain("test")
        assertTrue(text.contains("flyfun-forms/data"))
        assertTrue(text.contains("Eriksson"))

        val incoming = DataTransfer(target)
        val (_, summary) = incoming.preview(text.toByteArray(), null)
        incoming.apply(summary)
        assertNotNull(target.personDao().byId(personId))
    }

    @Test
    fun a_file_from_the_future_is_refused_rather_than_half_imported() = runTest {
        val bogus = """{"format":"flyfun-forms/data","version":99,"exportedAt":"2026-09-19T00:00:00Z"}"""
        val incoming = DataTransfer(target)
        runCatching { incoming.preview(bogus.toByteArray(), null) }
            .onSuccess { throw AssertionError("should have been refused") }
        assertEquals(0, target.personDao().observeAllOnce().size)
        assertNull(target.flightDao().byId("anything"))
    }
}
