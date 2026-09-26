package aero.flyfun.forms.ui.flights

import aero.flyfun.forms.data.AircraftEntity
import aero.flyfun.forms.data.FlightEntity
import aero.flyfun.forms.data.PersonEntity
import aero.flyfun.forms.net.FormInfo
import aero.flyfun.forms.net.displayField
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter

private val DAY: DateTimeFormatter = DateTimeFormatter.ofPattern("d MMM yyyy").withZone(ZoneOffset.UTC)
private val HHMM: DateTimeFormatter = DateTimeFormatter.ofPattern("HH:mm").withZone(ZoneOffset.UTC)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FlightListScreen(
    flights: List<FlightEntity>,
    onOpen: (String) -> Unit,
    onAdd: () -> Unit,
) {
    val now = Instant.now()
    val upcoming = flights.filter { !it.departureInstant.isBefore(now) }.sortedBy { it.departureInstant }
    val past = flights.filter { it.departureInstant.isBefore(now) }

    Scaffold(
        topBar = { TopAppBar(title = { Text("Flights") }) },
        floatingActionButton = {
            FloatingActionButton(onClick = onAdd) {
                Icon(Icons.Default.Add, contentDescription = "Add flight")
            }
        },
    ) { padding ->
        if (flights.isEmpty()) {
            Column(
                Modifier.fillMaxSize().padding(padding).padding(32.dp),
                verticalArrangement = Arrangement.Center,
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Text("No flights yet", style = MaterialTheme.typography.titleMedium)
                Text(
                    "Add a flight to generate its customs and immigration forms.",
                    style = MaterialTheme.typography.bodyMedium,
                )
            }
        } else {
            LazyColumn(Modifier.fillMaxSize().padding(padding)) {
                if (upcoming.isNotEmpty()) {
                    item { SectionHeader("Upcoming") }
                    items(upcoming, key = { it.id }) { FlightRow(it, onOpen) }
                }
                if (past.isNotEmpty()) {
                    item { SectionHeader("Past") }
                    items(past, key = { it.id }) { FlightRow(it, onOpen) }
                }
            }
        }
    }
}

@Composable
private fun SectionHeader(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.labelLarge,
        modifier = Modifier.padding(start = 16.dp, top = 16.dp, bottom = 4.dp),
    )
}

@Composable
private fun FlightRow(flight: FlightEntity, onOpen: (String) -> Unit) {
    ListItem(
        headlineContent = {
            Text("${flight.originICAO.ifBlank { "????" }} → ${flight.destinationICAO.ifBlank { "????" }}")
        },
        supportingContent = {
            Text("${DAY.format(flight.departureInstant)} · ${HHMM.format(flight.departureInstant)}Z")
        },
        modifier = Modifier.clickable { onOpen(flight.id) },
    )
    HorizontalDivider()
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FlightEditScreen(
    detail: FlightDetail?,
    hasUnsavedChanges: Boolean,
    aircraftOptions: List<AircraftEntity>,
    people: List<PersonEntity>,
    airportForms: List<AirportForms>,
    generateState: GenerateState,
    onEditFlight: ((FlightEntity) -> FlightEntity) -> Unit,
    onSetAircraft: (String?) -> Unit,
    onSetCrew: (List<PersonEntity>) -> Unit,
    onSetPassengers: (List<PersonEntity>) -> Unit,
    onSave: () -> Unit,
    /** Save, and leave once it is stored: leaving first would cancel the write. */
    onSaveAndBack: () -> Unit,
    onGenerate: (String, FormInfo) -> Unit,
    onOpenWebForm: (String, FormInfo) -> Unit,
    onShare: (java.io.File) -> Unit,
    onDismissGenerate: () -> Unit,
    onBack: () -> Unit,
) {
    if (detail == null) {
        Scaffold(topBar = { TopAppBar(title = { Text("Flight") }) }) { p ->
            Column(Modifier.fillMaxSize().padding(p), Arrangement.Center, Alignment.CenterHorizontally) {
                CircularProgressIndicator()
            }
        }
        return
    }
    val flight = detail.flight
    // Local text state so typing does not round-trip through the ViewModel;
    // keyed on the flight so a different leg starts from its own values.
    var origin by remember(flight.id) { mutableStateOf(flight.originICAO) }
    var destination by remember(flight.id) { mutableStateOf(flight.destinationICAO) }
    var observations by remember(flight.id) { mutableStateOf(flight.observations.orEmpty()) }
    var confirmDiscard by remember { mutableStateOf(false) }

    // Back with edits asks first, whether it came from the arrow or the system.
    val leave = { if (hasUnsavedChanges) confirmDiscard = true else onBack() }
    BackHandler(enabled = hasUnsavedChanges) { confirmDiscard = true }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        if (detail.isNew && origin.isBlank() && destination.isBlank()) "New Flight"
                        else "${origin.ifBlank { "????" }} → ${destination.ifBlank { "????" }}",
                    )
                },
                navigationIcon = {
                    IconButton(onClick = leave) {
                        Icon(Icons.Default.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    TextButton(onClick = onSave, enabled = hasUnsavedChanges) { Text("Save") }
                },
            )
        },
    ) { padding ->
        Column(
            Modifier.fillMaxSize().padding(padding).padding(16.dp).verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Row(Modifier.fillMaxWidth(), Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(
                    origin,
                    { value ->
                        if (value.length <= 4) {
                            origin = value.uppercase()
                            onEditFlight { it.copy(originICAO = origin.trim()) }
                        }
                    },
                    label = { Text("From (ICAO)") }, singleLine = true, modifier = Modifier.weight(1f),
                )
                OutlinedTextField(
                    destination,
                    { value ->
                        if (value.length <= 4) {
                            destination = value.uppercase()
                            onEditFlight { it.copy(destinationICAO = destination.trim()) }
                        }
                    },
                    label = { Text("To (ICAO)") }, singleLine = true, modifier = Modifier.weight(1f),
                )
            }

            ScheduleField("Departure", flight.departureInstant) { t -> onEditFlight { it.copy(departureInstant = t) } }
            ScheduleField("Arrival", flight.arrivalInstant) { t -> onEditFlight { it.copy(arrivalInstant = t) } }
            if (flight.arrivalInstant.isBefore(flight.departureInstant)) {
                Text(
                    "Arrival is before departure.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error,
                )
            }

            Text("Aircraft", style = MaterialTheme.typography.titleMedium)
            // Scrolls sideways: a fleet does not fit across a phone.
            Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()), Arrangement.spacedBy(8.dp)) {
                aircraftOptions.forEach { a ->
                    FilterChip(
                        selected = detail.aircraft?.id == a.id,
                        onClick = { onSetAircraft(a.id) },
                        label = { Text(a.registration) },
                    )
                }
            }
            if (aircraftOptions.isEmpty()) {
                Text("Add an aircraft first.", style = MaterialTheme.typography.bodySmall)
            }

            PeoplePicker("Crew", people, detail.crew, onSetCrew)
            PeoplePicker("Passengers", people, detail.passengers, onSetPassengers)

            OutlinedTextField(
                observations,
                { value ->
                    observations = value
                    onEditFlight { it.copy(observations = value.trim().ifBlank { null }) }
                },
                label = { Text("Observations") }, modifier = Modifier.fillMaxWidth(),
            )

            Text("Forms", style = MaterialTheme.typography.titleMedium)
            airportForms.forEach { airport ->
                AirportFormsCard(airport, generateState, onGenerate, onOpenWebForm)
            }
            if (airportForms.isEmpty()) {
                Text(
                    "Enter the route to see which forms these airports need.",
                    style = MaterialTheme.typography.bodySmall,
                )
            }
        }
    }

    if (confirmDiscard) {
        AlertDialog(
            onDismissRequest = { confirmDiscard = false },
            title = { Text(if (detail.isNew) "Save this flight?" else "Save your changes?") },
            text = { Text("Leaving now discards what you have not saved.") },
            confirmButton = {
                TextButton(onClick = { confirmDiscard = false; onSaveAndBack() }) { Text("Save") }
            },
            dismissButton = {
                TextButton(onClick = { confirmDiscard = false; onBack() }) { Text("Discard") }
            },
        )
    }

    GenerateFeedback(generateState, onShare, onDismissGenerate)
}

/**
 * Chips for everyone, wrapping onto as many lines as they need rather than one
 * chip per line. The full picker (search, crew/passenger toggle) is PR 2.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun PeoplePicker(
    title: String,
    all: List<PersonEntity>,
    selected: List<PersonEntity>,
    onChange: (List<PersonEntity>) -> Unit,
) {
    Text(title, style = MaterialTheme.typography.titleMedium)
    if (all.isEmpty()) {
        Text("Add people first.", style = MaterialTheme.typography.bodySmall)
        return
    }
    val selectedIds = selected.map { it.id }.toSet()
    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        all.forEach { person ->
            val isSelected = person.id in selectedIds
            FilterChip(
                selected = isSelected,
                onClick = {
                    onChange(if (isSelected) selected.filterNot { it.id == person.id } else selected + person)
                },
                label = { Text(person.displayName.ifBlank { "Unnamed" }) },
            )
        }
    }
}

@Composable
private fun AirportFormsCard(
    airport: AirportForms,
    state: GenerateState,
    onGenerate: (String, FormInfo) -> Unit,
    onOpenWebForm: (String, FormInfo) -> Unit,
) {
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(
                buildString {
                    append(airport.icao)
                    if (airport.name.isNotBlank()) append(" · ${airport.name}")
                    append(" · ${airport.direction}")
                },
                style = MaterialTheme.typography.titleSmall,
            )
            when {
                airport.loading -> CircularProgressIndicator(Modifier.padding(4.dp))
                airport.error != null ->
                    Text(airport.error, style = MaterialTheme.typography.bodySmall)
                airport.forms.isEmpty() ->
                    Text("No forms needed here.", style = MaterialTheme.typography.bodySmall)
                else -> airport.forms.forEach { form ->
                    val working = state is GenerateState.Working && state.formId == form.id
                    Row(Modifier.fillMaxWidth(), Arrangement.SpaceBetween, Alignment.CenterVertically) {
                        Column(Modifier.weight(1f)) {
                            Text(form.label)
                            if (form.isWebForm) {
                                Text("Official web form", style = MaterialTheme.typography.bodySmall)
                            }
                        }
                        if (form.isWebForm) {
                            // The airport's own page: prefilled via /prefill and
                            // submitted by the pilot, never by the app.
                            OutlinedButton(
                                enabled = state !is GenerateState.Working,
                                onClick = { onOpenWebForm(airport.icao, form) },
                            ) { Text("Open") }
                        } else {
                            OutlinedButton(
                                enabled = state !is GenerateState.Working,
                                onClick = { onGenerate(airport.icao, form) },
                            ) {
                                if (working) CircularProgressIndicator(Modifier.padding(2.dp))
                                else Text("Generate")
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun GenerateFeedback(
    state: GenerateState,
    onShare: (java.io.File) -> Unit,
    onDismiss: () -> Unit,
) {
    when (state) {
        is GenerateState.Ready -> AlertDialog(
            onDismissRequest = onDismiss,
            title = { Text(state.label) },
            text = { Text("${state.file.name} is ready.") },
            confirmButton = { TextButton(onClick = { onShare(state.file); onDismiss() }) { Text("Share") } },
            dismissButton = { TextButton(onClick = onDismiss) { Text("Close") } },
        )
        is GenerateState.Invalid -> AlertDialog(
            onDismissRequest = onDismiss,
            title = { Text("Missing information") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    state.errors.forEach { Text("${it.displayField}: ${it.error}") }
                }
            },
            confirmButton = { TextButton(onClick = onDismiss) { Text("OK") } },
        )
        is GenerateState.Failed -> AlertDialog(
            onDismissRequest = onDismiss,
            title = { Text("Could not generate") },
            text = { Text(state.message) },
            confirmButton = { TextButton(onClick = onDismiss) { Text("OK") } },
        )
        else -> Unit
    }
}
