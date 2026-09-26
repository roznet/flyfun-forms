package aero.flyfun.forms.ui.people

import aero.flyfun.forms.data.FlightRepository
import aero.flyfun.forms.data.PersonEntity
import aero.flyfun.forms.data.PersonWithDocuments
import aero.flyfun.forms.data.PeopleRepository
import aero.flyfun.forms.data.TravelDocumentEntity
import aero.flyfun.forms.logic.MRZResultProcessor
import aero.flyfun.forms.logic.MRZScanResult
import aero.flyfun.forms.logic.ScanContext
import aero.flyfun.forms.logic.ScanDecision
import aero.flyfun.forms.logic.ScanDocument
import aero.flyfun.forms.logic.ScanPerson
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
import kotlinx.coroutines.flow.first
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

    private val _scanDecision = MutableStateFlow<ScanDecision?>(null)

    /** What the last scan means for the stored people, until the pilot picks an action or cancels. */
    val scanDecision: StateFlow<ScanDecision?> = _scanDecision.asStateFlow()
    private var deciding = false

    /**
     * Work out what [result] means from where it was scanned: a duplicate
     * document on anyone, a name that is not the person's, or people it might
     * belong to. Port of iOS `MRZResultProcessor.process`. A second read while
     * one is on screen is ignored.
     */
    fun decide(result: MRZScanResult, context: ScanContext) {
        if (deciding || _scanDecision.value != null) return
        deciding = true
        viewModelScope.launch {
            val rows = repository.observePeople().first()
            _scanDecision.value = MRZResultProcessor.process(
                result,
                context,
                people = rows.map { it.person.toScanPerson() },
                documents = rows.flatMap { row ->
                    row.documents.filter { it.deletedAt == null }.map { ScanDocument(it.id, it.personId, it.docNumber) }
                },
            )
            deciding = false
        }
    }

    fun dismissScan() { _scanDecision.value = null }

    /**
     * Fill the person's empty fields from the scan (the name too, with
     * [overwriteName]) and, with [addDocument], store the document on them.
     * A document of theirs with the same number is refreshed rather than
     * duplicated, so rescanning a passport is harmless.
     */
    suspend fun applyScanTo(personId: String, result: MRZScanResult, overwriteName: Boolean, addDocument: Boolean) {
        val row = repository.person(personId) ?: return
        val fill = MRZResultProcessor.fillPerson(row.person.toScanPerson(), result, overwriteName)
        repository.save(
            row.person.copy(
                firstName = fill.firstName,
                lastName = fill.lastName,
                dateOfBirth = fill.dateOfBirth,
                sex = fill.sex,
            ),
        )
        if (addDocument) {
            val same = row.documents.firstOrNull {
                it.deletedAt == null && it.docNumber.equals(result.passportNumber, ignoreCase = true)
            }
            repository.saveDocument(scannedDocument(same ?: TravelDocumentEntity(personId = personId), result))
        }
        _scanDecision.value = null
    }

    /** A new person with the scanned name and document; returns them. */
    suspend fun createScannedPerson(result: MRZScanResult): PersonEntity {
        val fill = MRZResultProcessor.fillPerson(ScanPerson("", "", ""), result, overwriteName = true)
        val person = PersonEntity(
            firstName = fill.firstName,
            lastName = fill.lastName,
            dateOfBirth = fill.dateOfBirth,
            sex = fill.sex,
        )
        repository.save(person)
        repository.saveDocument(scannedDocument(TravelDocumentEntity(personId = person.id), result))
        _scanDecision.value = null
        return person
    }

    private fun scannedDocument(base: TravelDocumentEntity, result: MRZScanResult) = base.copy(
        docType = MRZResultProcessor.docType(result),
        docNumber = result.passportNumber,
        issuingCountry = result.issuingCountry.uppercase().ifBlank { null },
        expiryDate = result.expiryDate,
        isActive = true,
    )
}

data class CsvResult(val title: String, val message: String)

private fun PersonEntity.toScanPerson() = ScanPerson(id, firstName, lastName, dateOfBirth, sex)
