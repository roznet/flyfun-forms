package aero.flyfun.forms.ui.people

import aero.flyfun.forms.data.FlightRepository
import aero.flyfun.forms.data.PersonEntity
import aero.flyfun.forms.data.PersonWithDocuments
import aero.flyfun.forms.data.PeopleRepository
import aero.flyfun.forms.data.TravelDocumentEntity
import aero.flyfun.forms.logic.MRZFormat
import aero.flyfun.forms.logic.MRZScanResult
import aero.flyfun.forms.logic.FlightPeople
import aero.flyfun.forms.logic.PeopleRanking
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.time.Instant

class PeopleViewModel(
    private val repository: PeopleRepository,
    private val flights: FlightRepository,
) : ViewModel() {

    val people: StateFlow<List<PersonWithDocuments>> =
        repository.observePeople()
            .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    /** When each person last flew, for "Sort by Recent" and the picker's order. */
    val lastFlights: StateFlow<Map<String, Instant>> =
        flights.observeLastFlights()
            .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyMap())

    /** Who flew with whom, for the picker's "Frequent with" groups. */
    val flightPeople: StateFlow<List<FlightPeople>> =
        flights.observeFlightPeople()
            .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    private val _csvResult = MutableStateFlow<CsvResult?>(null)

    /** The outcome of the last CSV import or export, until dismissed. */
    val csvResult: StateFlow<CsvResult?> = _csvResult.asStateFlow()

    fun importCsv(content: String) = viewModelScope.launch {
        _csvResult.value = runCatching { repository.importCsv(content) }.fold(
            onSuccess = { CsvResult("Import Complete", it.summary) },
            onFailure = { CsvResult("Import Failed", it.message ?: "The file could not be read.") },
        )
    }

    suspend fun exportCsv(): String = repository.exportCsv()

    fun reportCsv(title: String, message: String) { _csvResult.value = CsvResult(title, message) }

    fun dismissCsvResult() { _csvResult.value = null }

    /**
     * Store a person under a name typed into a search that found nobody, for
     * the picker's "Add “name” as new person".
     */
    suspend fun addNamed(name: String): PersonEntity {
        val (first, last) = PeopleRanking.splitName(name)
        val person = PersonEntity(firstName = first, lastName = last)
        repository.save(person)
        return person
    }

    /** Returns the job so a caller can wait for the row before navigating on. */
    fun save(person: PersonEntity): Job = viewModelScope.launch { repository.save(person) }

    fun delete(id: String) = viewModelScope.launch { repository.deletePerson(id) }

    fun saveDocument(document: TravelDocumentEntity): Job =
        viewModelScope.launch { repository.saveDocument(document) }

    fun deleteDocument(id: String) = viewModelScope.launch { repository.deleteDocument(id) }

    /**
     * Apply a passport scan to a person, as iOS `MRZResultProcessor` does.
     *
     * The person's own fields are filled only where empty: the pilot may have
     * spelled a name deliberately, and an MRZ is transliterated and
     * upper-cased. A document with the same number is refreshed rather than
     * duplicated, so rescanning a renewed passport is harmless.
     */
    fun applyScan(personId: String, result: MRZScanResult): Job = viewModelScope.launch {
        val row = repository.person(personId) ?: return@launch
        val person = row.person
        repository.save(
            person.copy(
                firstName = person.firstName.ifBlank { result.givenNames },
                lastName = person.lastName.ifBlank { result.surname },
                dateOfBirth = person.dateOfBirth ?: result.dateOfBirth,
                sex = person.sex ?: when (result.gender) {
                    "M" -> "Male"
                    "F" -> "Female"
                    else -> null
                },
            ),
        )
        val same = row.documents.firstOrNull {
            it.deletedAt == null && it.docNumber.equals(result.passportNumber, ignoreCase = true)
        }
        repository.saveDocument(
            (same ?: TravelDocumentEntity(personId = personId)).copy(
                docType = if (result.format == MRZFormat.TD1) "Identity card" else "Passport",
                docNumber = result.passportNumber,
                issuingCountry = result.issuingCountry.uppercase().ifBlank { null },
                expiryDate = result.expiryDate,
                isActive = true,
            ),
        )
    }
}

data class CsvResult(val title: String, val message: String)
