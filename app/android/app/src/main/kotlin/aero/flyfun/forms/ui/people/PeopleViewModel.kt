package aero.flyfun.forms.ui.people

import aero.flyfun.forms.data.PersonEntity
import aero.flyfun.forms.data.PersonWithDocuments
import aero.flyfun.forms.data.PeopleRepository
import aero.flyfun.forms.data.TravelDocumentEntity
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import java.time.LocalDate

class PeopleViewModel(private val repository: PeopleRepository) : ViewModel() {

    val people: StateFlow<List<PersonWithDocuments>> =
        repository.observePeople()
            .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    fun save(person: PersonEntity) = viewModelScope.launch { repository.save(person) }

    fun delete(id: String) = viewModelScope.launch { repository.deletePerson(id) }

    fun addDocument(
        personId: String,
        docType: String,
        docNumber: String,
        issuingCountry: String?,
        expiry: LocalDate?,
    ) = viewModelScope.launch {
        repository.saveDocument(
            TravelDocumentEntity(
                personId = personId,
                docType = docType,
                docNumber = docNumber,
                issuingCountry = issuingCountry?.uppercase()?.takeIf { it.isNotBlank() },
                expiryDate = expiry,
            ),
        )
    }

    fun deleteDocument(id: String) = viewModelScope.launch { repository.deleteDocument(id) }
}
