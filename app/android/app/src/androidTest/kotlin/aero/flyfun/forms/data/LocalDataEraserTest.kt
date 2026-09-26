package aero.flyfun.forms.data

import androidx.room.Room
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.time.Instant

/** "Delete all data" must leave nothing behind - live rows, tombstones or files. */
@RunWith(AndroidJUnit4::class)
class LocalDataEraserTest {

    private lateinit var db: FlyFunDatabase
    private lateinit var cacheDir: File
    private var webCleared = 0

    @Before
    fun setUp() {
        val ctx = InstrumentationRegistry.getInstrumentation().targetContext
        db = Room.inMemoryDatabaseBuilder(ctx, FlyFunDatabase::class.java).build()
        cacheDir = File(ctx.cacheDir, "eraser-test").apply { deleteRecursively(); mkdirs() }
    }

    @After
    fun tearDown() {
        db.close()
        cacheDir.deleteRecursively()
    }

    private fun eraser() = LocalDataEraser(db, cacheDir) { webCleared++ }

    @Test
    fun erases_every_table_including_tombstones_and_the_form_files() = runTest {
        val pilot = PersonEntity(firstName = "Anna", lastName = "Eriksson")
        val pax = PersonEntity(firstName = "Bo", lastName = "Lindqvist")
        db.personDao().upsertAll(listOf(pilot, pax))
        db.travelDocumentDao().upsert(TravelDocumentEntity(personId = pilot.id, docNumber = "L898902C3"))
        val aircraft = AircraftEntity(registration = "ZZ-ABC", type = "SR22")
        db.aircraftDao().upsert(aircraft)
        val trip = TripEntity(name = "Summer")
        db.tripDao().upsert(trip)
        val flight = FlightEntity(
            departureInstant = Instant.parse("2026-09-20T08:15:00Z"),
            arrivalInstant = Instant.parse("2026-09-20T10:05:00Z"),
            originICAO = "EGTF", destinationICAO = "LFRM",
            aircraftId = aircraft.id, responsiblePersonId = pilot.id, tripId = trip.id,
        )
        db.flightDao().upsert(flight)
        db.flightDao().setPeople(flight.id, FlightRole.CREW, listOf(pilot.id))
        db.flightDao().setPeople(flight.id, FlightRole.PASSENGER, listOf(pax.id))
        // A tombstone is still a passport-holder's name on disk.
        db.personDao().softDelete(pax.id)

        FormFiles.dir(cacheDir).resolve("gendec.pdf").writeText("passport numbers")
        FormFiles.dir(cacheDir).resolve("flyfun-forms-data.ffdata").writeText("export")

        eraser().eraseAll()

        assertTrue(db.personDao().allIncludingDeleted().isEmpty())
        assertTrue(db.travelDocumentDao().allIncludingDeleted().isEmpty())
        assertTrue(db.aircraftDao().allIncludingDeleted().isEmpty())
        assertTrue(db.tripDao().allIncludingDeleted().isEmpty())
        assertTrue(db.flightDao().allIncludingDeleted().isEmpty())
        assertTrue(db.flightDao().allMemberships().isEmpty())
        assertTrue(FormFiles.dir(cacheDir).listFiles().orEmpty().isEmpty())
        assertEquals(1, webCleared)
    }

    @Test
    fun the_database_stays_usable_afterwards() = runTest {
        db.personDao().upsert(PersonEntity(firstName = "Anna", lastName = "Eriksson"))
        eraser().eraseAll()

        db.personDao().upsert(PersonEntity(firstName = "Cleo", lastName = "Marchand"))
        assertEquals(listOf("Marchand"), db.personDao().allIncludingDeleted().map { it.lastName })
    }

    @Test
    fun a_failing_web_clear_does_not_fail_the_erase() = runTest {
        db.personDao().upsert(PersonEntity(firstName = "Anna", lastName = "Eriksson"))
        LocalDataEraser(db, cacheDir) { error("no WebView provider") }.eraseAll()
        assertTrue(db.personDao().allIncludingDeleted().isEmpty())
    }
}
