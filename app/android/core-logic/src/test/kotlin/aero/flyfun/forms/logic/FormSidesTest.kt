package aero.flyfun.forms.logic

import aero.flyfun.forms.logic.FormSides.ARRIVAL
import aero.flyfun.forms.logic.FormSides.DEPARTURE
import aero.flyfun.forms.logic.FormSides.Side
import org.junit.Assert.assertEquals
import org.junit.Test

class FormSidesTest {

    private data class Form(val id: String, val web: Boolean = false, val direction: String? = null)

    private fun applicable(forms: List<Form>, direction: String) =
        FormSides.applicable(forms, direction, { it.web }, { it.direction }).map { it.id }

    @Test
    fun `arrival comes before departure`() {
        assertEquals(
            listOf(Side("LFPB", ARRIVAL), Side("EGTF", DEPARTURE)),
            FormSides.of(origin = "EGTF", destination = "LFPB"),
        )
    }

    @Test
    fun `a local flight keeps both sides of the one airport`() {
        assertEquals(
            listOf(Side("LFAC", ARRIVAL), Side("LFAC", DEPARTURE)),
            FormSides.of(origin = "LFAC", destination = "lfac "),
        )
    }

    @Test
    fun `blank and partial codes have no side`() {
        assertEquals(listOf(Side("EGTF", DEPARTURE)), FormSides.of(origin = "EGTF", destination = "LF"))
        assertEquals(emptyList<Side>(), FormSides.of(origin = "", destination = ""))
    }

    @Test
    fun `document forms show on both sides whatever their direction`() {
        val forms = listOf(Form("customs", direction = ARRIVAL), Form("gendec"))
        assertEquals(listOf("customs", "gendec"), applicable(forms, DEPARTURE))
        assertEquals(listOf("customs", "gendec"), applicable(forms, ARRIVAL))
    }

    @Test
    fun `web forms show only on the side they cover`() {
        val forms = listOf(
            Form("bookout", web = true, direction = DEPARTURE),
            Form("ppr", web = true, direction = ARRIVAL),
            Form("either", web = true),
        )
        assertEquals(listOf("bookout", "either"), applicable(forms, DEPARTURE))
        assertEquals(listOf("ppr", "either"), applicable(forms, ARRIVAL))
    }

    @Test
    fun `the first document form is primary, then web forms, then the rest`() {
        val forms = listOf(Form("customs"), Form("bookout", web = true), Form("gendec"), Form("handling"))
        val grouped = FormSides.group(forms) { it.web }
        assertEquals("customs", grouped.primary?.id)
        assertEquals(listOf("bookout"), grouped.web.map { it.id })
        assertEquals(listOf("gendec", "handling"), grouped.others.map { it.id })
    }

    @Test
    fun `web forms alone have no primary`() {
        val grouped = FormSides.group(listOf(Form("ppr", web = true))) { it.web }
        assertEquals(null, grouped.primary)
        assertEquals(emptyList<Form>(), grouped.others)
    }
}
