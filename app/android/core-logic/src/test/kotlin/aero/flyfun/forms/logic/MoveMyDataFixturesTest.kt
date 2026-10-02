package aero.flyfun.forms.logic

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.io.File

/**
 * Cross-platform "move my data" fixtures, shared with the iOS tests.
 *
 * `app/fixtures/move-my-data/` holds a file written by this code
 * (`android-*`) that the iOS tests decrypt and decode, and a file written by
 * the iOS code (`ios-*`) that these tests decrypt, decode and merge. See the
 * README there for how each is regenerated.
 */
class MoveMyDataFixturesTest {

    private val dir = File("../../fixtures/move-my-data")

    /** NFC-composed on purpose: the "é" checks both platforms normalise alike. */
    private val passphrase = "Fixture-Café-rudder-alpha"

    private val t0 = "2026-09-01T10:00:00Z"
    private val t1 = "2026-09-12T09:01:44.123456Z"
    private val t2 = "2026-09-15T18:30:00Z"

    /** Self-describing dummy data only; see CLAUDE.md. */
    private fun androidDocument() = InterchangeDocument(
        exportedAt = "2026-09-20T07:00:00Z",
        exportedBy = ExportedBy("android", "0.1-fixture"),
        people = listOf(
            PersonRecord(
                id = "00000000-0000-4000-8000-00000000a001", firstName = "Fixture", lastName = "Pilot-One",
                dateOfBirth = "1975-04-12", sex = "Male", placeOfBirth = "Fixture Town",
                phone = "+00 0000 000001", email = "pilot-one@example.invalid", address = "1 Fixture Lane",
                isUsualCrew = true, updatedAt = t1,
            ),
            PersonRecord(
                id = "00000000-0000-4000-8000-00000000a002", firstName = "Fixture", lastName = "Passenger-Two",
                dateOfBirth = "1990-12-31", sex = "Female", updatedAt = t0,
            ),
            // A deleted person, as Android keeps it: a soft-deleted row.
            PersonRecord(
                id = "00000000-0000-4000-8000-00000000a003", firstName = "Fixture", lastName = "Deleted-Three",
                updatedAt = t2, deletedAt = t2,
            ),
        ),
        travelDocuments = listOf(
            TravelDocumentRecord(
                id = "00000000-0000-4000-8000-00000000d001", personId = "00000000-0000-4000-8000-00000000a001",
                docType = "Passport", docNumber = "TESTDOC001", issuingCountry = "FRA",
                expiryDate = "2031-06-30", updatedAt = t1,
            ),
            TravelDocumentRecord(
                id = "00000000-0000-4000-8000-00000000d002", personId = "00000000-0000-4000-8000-00000000a002",
                docType = "Identity card", docNumber = "TESTDOC002", issuingCountry = "GBR",
                expiryDate = "2029-01-01", isActive = false, updatedAt = t0,
            ),
        ),
        aircraft = listOf(
            AircraftRecord(
                id = "00000000-0000-4000-8000-00000000c001", registration = "ZZ-FIXT", type = "FIXT",
                owner = "Fixture Owner", ownerAddress = "1 Fixture Lane", usualBase = "EGTF",
                ownerPersonId = "00000000-0000-4000-8000-00000000a001", updatedAt = t0,
            ),
        ),
        trips = listOf(
            TripRecord(
                id = "00000000-0000-4000-8000-00000000e001", name = "Fixture trip",
                createdAt = t0, extraFields = mapOf("fixtureField" to "fixture value"), updatedAt = t0,
            ),
        ),
        flights = listOf(
            FlightRecord(
                id = "00000000-0000-4000-8000-00000000f001", originICAO = "EGTF", destinationICAO = "LFRM",
                departureInstant = "2026-09-20T08:15:00Z", arrivalInstant = "2026-09-20T10:05:00Z",
                nature = "private", observations = "Fixture observation",
                aircraftId = "00000000-0000-4000-8000-00000000c001",
                responsiblePersonId = "00000000-0000-4000-8000-00000000a001",
                tripId = "00000000-0000-4000-8000-00000000e001", legOrder = 0,
                chosenDocNumbers = listOf("TESTDOC001"), updatedAt = t1,
            ),
            FlightRecord(
                id = "00000000-0000-4000-8000-00000000f002", originICAO = "LFRM", destinationICAO = "EGTF",
                departureInstant = "2026-09-22T23:30:00Z", arrivalInstant = "2026-09-23T01:10:00Z",
                aircraftId = "00000000-0000-4000-8000-00000000c001",
                tripId = "00000000-0000-4000-8000-00000000e001", legOrder = 1, updatedAt = t0,
            ),
        ),
        flightPeople = listOf(
            FlightPersonRecord("00000000-0000-4000-8000-00000000f001", "00000000-0000-4000-8000-00000000a001", "crew", 0),
            FlightPersonRecord("00000000-0000-4000-8000-00000000f001", "00000000-0000-4000-8000-00000000a002", "passenger", 0),
            FlightPersonRecord("00000000-0000-4000-8000-00000000f002", "00000000-0000-4000-8000-00000000a002", "crew", 0),
            FlightPersonRecord("00000000-0000-4000-8000-00000000f002", "00000000-0000-4000-8000-00000000a001", "crew", 1),
        ),
    )

    /**
     * Regenerates the Android fixtures. Skipped unless asked for:
     * `WRITE_MOVE_MY_DATA_FIXTURES=1 ./gradlew :core-logic:test --tests '*MoveMyDataFixturesTest*'`
     */
    @Test
    fun `write the Android fixtures`() {
        assumeTrue(System.getenv("WRITE_MOVE_MY_DATA_FIXTURES") == "1")
        val text = InterchangeMerge.encode(androidDocument())
        File(dir, "android-plain.json").writeText(text + "\n")
        File(dir, "android-encrypted.ffdata").writeBytes(
            DataFileCrypto.encrypt(text + "\n", DataFileCrypto.normalisePassphrase(passphrase)),
        )
    }

    @Test
    fun `the Android fixture still matches what this code writes`() {
        // Guards the fixture against drifting from the format without anyone noticing.
        val text = File(dir, "android-plain.json").readText()
        assertEquals(androidDocument(), InterchangeMerge.decode(text))
        val decrypted = DataFileCrypto.decrypt(
            File(dir, "android-encrypted.ffdata").readBytes(),
            DataFileCrypto.normalisePassphrase(passphrase),
        )
        assertEquals(text, decrypted)
    }

    @Test
    fun `decrypts the file the iOS code encrypted`() {
        val bytes = File(dir, "ios-encrypted.ffdata").readBytes()
        assertTrue(DataFileCrypto.looksEncrypted(bytes))
        val text = DataFileCrypto.decrypt(bytes, DataFileCrypto.normalisePassphrase(passphrase))
        assertArrayEquals(File(dir, "ios-plain.json").readBytes(), text.toByteArray(Charsets.UTF_8))
    }

    @Test
    fun `decodes an iOS file, including its tombstones`() {
        val document = InterchangeMerge.decode(File(dir, "ios-plain.json").readText())
        assertEquals("ios", document.exportedBy.platform)
        assertEquals(2, document.people.size)
        // iOS writes a deleted travel document with an empty personId.
        val docTombstone = document.travelDocuments.single { it.deletedAt != null }
        assertEquals("", docTombstone.personId)
        assertEquals(docTombstone.deletedAt, docTombstone.updatedAt)
        // A flight tombstone fills its required instants with deletedAt.
        val flightTombstone = document.flights.single { it.deletedAt != null }
        assertEquals(flightTombstone.deletedAt, flightTombstone.departureInstant)
        assertEquals(flightTombstone.deletedAt, flightTombstone.arrivalInstant)
        // A record that was never edited since the uuid backfill carries the epoch.
        assertTrue(document.aircraft.any { it.updatedAt == "1970-01-01T00:00:00Z" })
    }

    @Test
    fun `iOS tombstones merge as removals of older local records`() {
        val document = InterchangeMerge.decode(File(dir, "ios-plain.json").readText())
        val docTombstone = document.travelDocuments.single { it.deletedAt != null }
        val flightTombstone = document.flights.single { it.deletedAt != null }
        val tripTombstone = document.trips.single { it.deletedAt != null }
        val local = InterchangeMerge.LocalSnapshot(
            travelDocuments = listOf(
                TravelDocumentRecord(id = docTombstone.id, personId = "someone", docNumber = "OLD", updatedAt = t0),
            ),
            flights = listOf(
                FlightRecord(id = flightTombstone.id, departureInstant = t0, arrivalInstant = t0, updatedAt = t0),
            ),
            trips = listOf(TripRecord(id = tripTombstone.id, createdAt = t0, updatedAt = t0)),
        )
        val summary = InterchangeMerge.summarise(local, document)
        assertEquals(listOf(docTombstone.id), summary.travelDocuments.remove.map { it.id })
        assertEquals(listOf(flightTombstone.id), summary.flights.remove.map { it.id })
        assertEquals(listOf(tripTombstone.id), summary.trips.remove.map { it.id })
        // and they never insert anything on a device that did not have them
        val fresh = InterchangeMerge.summarise(InterchangeMerge.LocalSnapshot(), document)
        assertTrue(fresh.travelDocuments.insert.none { it.deletedAt != null })
        assertTrue(fresh.flights.insert.none { it.deletedAt != null })
        assertTrue(fresh.trips.insert.none { it.deletedAt != null })
    }
}
