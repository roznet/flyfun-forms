package aero.flyfun.forms.logic

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class TripExtrasTest {

    @Test
    fun `round trips a map`() {
        val extras = mapOf("reason_for_visit" to "Maintenance", "telephone" to "+44 1234")
        assertEquals(extras, TripExtras.decode(TripExtras.encode(extras)))
    }

    @Test
    fun `empty map is stored as null`() {
        assertNull(TripExtras.encode(emptyMap()))
    }

    @Test
    fun `null, blank and unreadable columns read as empty`() {
        assertEquals(emptyMap<String, String>(), TripExtras.decode(null))
        assertEquals(emptyMap<String, String>(), TripExtras.decode(""))
        assertEquals(emptyMap<String, String>(), TripExtras.decode("not json"))
    }

    @Test
    fun `reads what iOS JSONEncoder writes`() {
        assertEquals(mapOf("a" to "b"), TripExtras.decode("""{"a":"b"}"""))
    }
}
