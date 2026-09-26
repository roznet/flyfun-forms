package aero.flyfun.forms.ui.people

import aero.flyfun.forms.data.PersonEntity
import aero.flyfun.forms.data.PersonWithDocuments
import aero.flyfun.forms.data.PeopleRepository
import aero.flyfun.forms.data.TravelDocumentEntity
import aero.flyfun.forms.logic.MRZFormat
import aero.flyfun.forms.logic.MRZScanResult
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

class PeopleViewModel(private val repository: PeopleRepository) : ViewModel() {

    val people: StateFlow<List<PersonWithDocuments>> =
        repository.observePeople()
            .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

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
