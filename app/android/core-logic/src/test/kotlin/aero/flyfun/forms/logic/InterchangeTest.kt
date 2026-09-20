package aero.flyfun.forms.logic

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class InterchangeTest {

    private fun person(id: String, name: String, updated: String, deleted: String? = null) =
        PersonRecord(id = id, firstName = name, lastName = "X", updatedAt = updated, deletedAt = deleted)

    private val t1 = "2026-09-01T10:00:00Z"
    private val t2 = "2026-09-10T10:00:00Z"
    private val t3 = "2026-09-19T10:00:00Z"

    @Test
    fun `a record only in the file is inserted`() {
        val out = InterchangeMerge.merge(emptyList(), listOf(person("a", "Anna", t1)))
        assertEquals(1, out.insert.size)
        assertEquals(0, out.update.size)
    }

    @Test
    fun `the newer updatedAt wins`() {
        val local = listOf(person("a", "Old", t1))
        val out = InterchangeMerge.merge(local, listOf(person("a", "New", t2)))
        assertEquals("New", out.update.single().firstName)
    }

    @Test
    fun `an older incoming record is ignored`() {
        val local = listOf(person("a", "Current", t2))
        val out = InterchangeMerge.merge(local, listOf(person("a", "Stale", t1)))
        assertEquals(0, out.update.size)
        assertEquals(1, out.unchanged)
    }

    @Test
    fun `an identical timestamp is treated as unchanged rather than rewritten`() {
        val local = listOf(person("a", "Same", t2))
        val out = InterchangeMerge.merge(local, listOf(person("a", "Same", t2)))
        assertEquals(1, out.unchanged)
        assertEquals(0, out.update.size)
    }

    @Test
    fun `a local record the file does not mention is never deleted`() {
        val local = listOf(person("a", "Anna", t1), person("b", "Bo", t1))
        val out = InterchangeMerge.merge(local, listOf(person("a", "Anna", t2)))
        assertEquals(0, out.remove.size)
        assertEquals(1, out.update.size)
    }

    @Test
    fun `a newer tombstone removes the local record`() {
        val local = listOf(person("a", "Anna", t1))
        val out = InterchangeMerge.merge(local, listOf(person("a", "Anna", t2, deleted = t2)))
        assertEquals(1, out.remove.size)
        assertEquals(0, out.update.size)
    }

    @Test
    fun `an older tombstone does not resurrect as a delete`() {
        // Local edited after the other device deleted it: the edit wins.
        val local = listOf(person("a", "Anna", t3))
        val out = InterchangeMerge.merge(local, listOf(person("a", "Anna", t2, deleted = t2)))
        assertEquals(0, out.remove.size)
        assertEquals(1, out.unchanged)
    }

    @Test
    fun `a tombstone for a record we never had is not an insert`() {
        val out = InterchangeMerge.merge(emptyList(), listOf(person("a", "Anna", t2, deleted = t2)))
        assertEquals(0, out.insert.size)
        assertEquals(1, out.unchanged)
    }

    @Test
    fun `round trip through encode and decode preserves everything`() {
        val doc = InterchangeDocument(
            exportedAt = t3,
            people = listOf(person("a", "Anna", t1)),
            flights = listOf(
                FlightRecord(
                    id = "f", originICAO = "EGTF", destinationICAO = "LFRM",
                    departureInstant = t1, arrivalInstant = t2, updatedAt = t1,
                ),
            ),
            flightPeople = listOf(FlightPersonRecord("f", "a", "crew")),
        )
        val decoded = InterchangeMerge.decode(InterchangeMerge.encode(doc))
        assertEquals(doc, decoded)
    }

    @Test
    fun `calendar days stay plain dates and instants keep their Z`() {
        val doc = InterchangeDocument(
            exportedAt = t3,
            travelDocuments = listOf(
                TravelDocumentRecord(
                    id = "d", personId = "a", docNumber = "X",
                    expiryDate = "2031-06-30", updatedAt = t1,
                ),
            ),
        )
        val text = InterchangeMerge.encode(doc)
        assertTrue(text.contains("\"expiryDate\": \"2031-06-30\""))
        assertTrue(text.contains("\"updatedAt\": \"2026-09-01T10:00:00Z\""))
    }

    @Test
    fun `a foreign file is refused rather than half-imported`() {
        val e = assertThrows(IllegalArgumentException::class.java) {
            InterchangeMerge.decode("""{"format":"something/else","version":1,"exportedAt":"$t1"}""")
        }
        assertTrue(e.message!!.contains("not a FlyFun Forms data file"))
    }

    @Test
    fun `a newer format version is refused`() {
        val e = assertThrows(IllegalArgumentException::class.java) {
            InterchangeMerge.decode(
                """{"format":"flyfun-forms/data","version":99,"exportedAt":"$t1"}""",
            )
        }
        assertTrue(e.message!!.contains("newer version"))
    }

    @Test
    fun `garbage is refused`() {
        assertThrows(IllegalArgumentException::class.java) { InterchangeMerge.decode("not json") }
    }

    @Test
    fun `membership only rides with flights the merge writes`() {
        val local = InterchangeMerge.LocalSnapshot(
            flights = listOf(
                FlightRecord(id = "kept", departureInstant = t1, arrivalInstant = t1, updatedAt = t3),
            ),
        )
        val doc = InterchangeDocument(
            exportedAt = t3,
            flights = listOf(
                // stale - will not be written
                FlightRecord(id = "kept", departureInstant = t1, arrivalInstant = t1, updatedAt = t1),
                // new - will be inserted
                FlightRecord(id = "new", departureInstant = t1, arrivalInstant = t1, updatedAt = t2),
            ),
            flightPeople = listOf(
                FlightPersonRecord("kept", "p1", "crew"),
                FlightPersonRecord("new", "p2", "crew"),
            ),
        )
        val summary = InterchangeMerge.summarise(local, doc)
        assertEquals(listOf("new"), summary.flightPeople.map { it.flightId })
    }

    @Test
    fun `summary reads as a sentence`() {
        val local = InterchangeMerge.LocalSnapshot(people = listOf(person("a", "Anna", t1)))
        val doc = InterchangeDocument(
            exportedAt = t3,
            people = listOf(person("a", "Anna Updated", t2), person("b", "Bo", t2)),
        )
        val summary = InterchangeMerge.summarise(local, doc)
        assertEquals(1, summary.inserted)
        assertEquals(1, summary.updated)
        assertTrue(summary.describe().contains("1 new"))
    }
}

class InterchangeTimestampTest {
    @Test
    fun `timestamps compare as instants not as strings`() {
        // Instant.toString() drops the fraction when it is zero, so a naive
        // string compare gets this pair backwards.
        assertTrue(InterchangeMerge.isNewer("2026-09-19T18:00:13Z", "2026-09-19T18:00:12.500Z"))
        assertTrue(!InterchangeMerge.isNewer("2026-09-19T18:00:12Z", "2026-09-19T18:00:12.500Z"))
        assertTrue(InterchangeMerge.isNewer("2026-09-19T18:00:12.750Z", "2026-09-19T18:00:12.500Z"))
        assertTrue(!InterchangeMerge.isNewer("2026-09-19T18:00:12Z", "2026-09-19T18:00:12Z"))
    }
}
