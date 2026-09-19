package aero.flyfun.forms.ui.aircraft

import aero.flyfun.forms.data.AircraftEntity
import aero.flyfun.forms.data.FlightRepository
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

class AircraftViewModel(private val repository: FlightRepository) : ViewModel() {

    val aircraft: StateFlow<List<AircraftEntity>> =
        repository.observeAircraft()
            .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    fun save(entity: AircraftEntity) = viewModelScope.launch { repository.saveAircraft(entity) }
    fun delete(id: String) = viewModelScope.launch { repository.deleteAircraft(id) }
}
