package aero.flyfun.forms.ui.flights

import aero.flyfun.forms.data.AircraftEntity
import aero.flyfun.forms.data.FlightEntity
import aero.flyfun.forms.data.PersonEntity
import aero.flyfun.forms.ui.common.ChoiceField
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Cloud
import androidx.compose.material.icons.filled.GroupAdd
import androidx.compose.material.icons.filled.History
import androidx.compose.material3.Card
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

/** The two steps of a new flight. Port of iOS `NewFlightFlow`. */
enum class NewFlightStep { ROUTE, PEOPLE }

/** The people step's one-tap suggestion, ready to show. */
class SuggestionChoice(
    val label: String,
    val summary: String,
    val crew: List<PersonEntity>,
    val passengers: List<PersonEntity>,
)

/**
 * A new flight in two steps: route, schedule and aircraft, then people.
 * The draft is the flight screen's; "Create Flight" stores it and the full
 * editor takes over. Nothing is stored before that, as with every draft.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NewFlightScreen(
    step: NewFlightStep,
    detail: FlightDetail,
    aircraftOptions: List<AircraftEntity>,
    airportInfo: Map<String, AirportDetails>,
    importSummary: String?,
    hasPreviousFlights: Boolean,
    /** FlyFun Weather needs the account; offered greyed with the reason otherwise. */
    signedIn: Boolean,
    suggestion: SuggestionChoice?,
    hasCrewSources: Boolean,
    onImportPrevious: () -> Unit,
    onImportWeather: () -> Unit,
    onOpenRoutePicker: () -> Unit,
    onSetDeparture: (Instant) -> Unit,
    onSetArrival: (Instant) -> Unit,
    onSetAircraft: (String?) -> Unit,
    onApplySuggestion: (SuggestionChoice) -> Unit,
    onOpenCrewSources: () -> Unit,
    onOpenPeoplePicker: () -> Unit,
    onNext: () -> Unit,
    onBack: () -> Unit,
    onCancel: () -> Unit,
    onCreate: () -> Unit,
) {
    val flight = detail.flight
    val steps = rememberSaveableStateHolder()
    BackHandler { if (step == NewFlightStep.PEOPLE) onBack() else onCancel() }
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(if (step == NewFlightStep.ROUTE) "New Flight" else "Add People") },
                navigationIcon = {
                    if (step == NewFlightStep.PEOPLE) {
                        IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back") }
                    } else {
                        IconButton(onClick = onCancel) { Icon(Icons.Default.Close, contentDescription = "Cancel") }
                    }
                },
                actions = {
                    if (step == NewFlightStep.ROUTE) {
                        TextButton(
                            onClick = onNext,
                            enabled = flight.originICAO.isNotBlank() || flight.destinationICAO.isNotBlank(),
                        ) { Text("Next") }
                    } else {
                        TextButton(onClick = onCreate) { Text("Create Flight") }
                    }
                },
            )
        },
    ) { padding ->
        Column(
            Modifier.fillMaxSize().padding(padding).padding(16.dp).verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            // Per step: going back to the route keeps a schedule's chosen zone.
            steps.SaveableStateProvider(step) {
                when (step) {
                    NewFlightStep.ROUTE -> {
                        // Every method listed, an unusable one greyed with its
                        // reason, as iOS's import list (FlightImportMethod).
                        Text("Import", style = MaterialTheme.typography.titleMedium)
                        ImportMethod(
                            icon = Icons.Default.History,
                            title = "Previous Flight",
                            subtitle = if (hasPreviousFlights) "Repeat a flight with the same crew, rescheduled" else "No earlier flights yet",
                            enabled = hasPreviousFlights,
                            onClick = onImportPrevious,
                        )
                        ImportMethod(
                            icon = Icons.Default.Cloud,
                            title = "FlyFun Weather",
                            subtitle = if (signedIn) "A flight you planned in FlyFun Weather" else "Sign in to import",
                            enabled = signedIn,
                            onClick = onImportWeather,
                        )
                        importSummary?.let { Text(it, style = MaterialTheme.typography.bodySmall) }

                        Text("Route", style = MaterialTheme.typography.titleMedium)
                        ListItem(
                            headlineContent = { Text("Route") },
                            trailingContent = {
                                Text(
                                    if (flight.originICAO.isBlank() && flight.destinationICAO.isBlank()) "Tap to select"
                                    else "${flight.originICAO.ifBlank { "----" }} → ${flight.destinationICAO.ifBlank { "----" }}",
                                )
                            },
                            modifier = Modifier.clickable(onClick = onOpenRoutePicker),
                        )

                        Text("Schedule", style = MaterialTheme.typography.titleMedium)
                        val zones = listOfNotNull(
                            airportInfo[flight.originICAO]?.timeZone,
                            airportInfo[flight.destinationICAO]?.timeZone,
                        ).distinct()
                        ScheduleField("Departure", flight.departureInstant, onSetDeparture, zones, airportInfo[flight.originICAO]?.timeZone)
                        ScheduleField("Arrival", flight.arrivalInstant, onSetArrival, zones, airportInfo[flight.destinationICAO]?.timeZone)

                        Text("Aircraft", style = MaterialTheme.typography.titleMedium)
                        ChoiceField(
                            label = "Aircraft",
                            selected = detail.aircraft,
                            options = listOf<AircraftEntity?>(null) + aircraftOptions,
                            display = { a -> a?.let { "${it.registration} (${it.type.ifBlank { "?" }})" } ?: "None" },
                            onSelect = { onSetAircraft(it?.id) },
                        )
                    }

                    NewFlightStep.PEOPLE -> {
                        // Only while nobody is chosen: an import that brought people hides it.
                        if (suggestion != null && detail.crew.isEmpty() && detail.passengers.isEmpty()) {
                            Text("Suggestion", style = MaterialTheme.typography.titleMedium)
                            Card(Modifier.fillMaxWidth().clickable { onApplySuggestion(suggestion) }) {
                                ListItem(
                                    leadingContent = { Icon(Icons.Default.GroupAdd, contentDescription = null) },
                                    headlineContent = { Text(suggestion.label) },
                                    supportingContent = { Text(suggestion.summary) },
                                )
                            }
                        }
                        if (hasCrewSources) {
                            TextButton(onClick = onOpenCrewSources) {
                                Icon(Icons.AutoMirrored.Filled.List, contentDescription = null)
                                Text("Choose another flight…", Modifier.padding(start = 8.dp))
                            }
                        }
                        Text("Crew", style = MaterialTheme.typography.titleMedium)
                        if (detail.crew.isEmpty()) Hint("No crew selected")
                        detail.crew.forEach { Text(it.displayName) }
                        Text("Passengers", style = MaterialTheme.typography.titleMedium)
                        if (detail.passengers.isEmpty()) Hint("No passengers selected")
                        detail.passengers.forEach { Text(it.displayName) }
                        OutlinedButton(onClick = onOpenPeoplePicker) {
                            Icon(Icons.Default.GroupAdd, contentDescription = null)
                            Text("Select People", Modifier.padding(start = 8.dp))
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun ImportMethod(icon: ImageVector, title: String, subtitle: String, enabled: Boolean, onClick: () -> Unit) {
    val alpha = if (enabled) 1f else 0.38f
    ListItem(
        leadingContent = { Icon(icon, contentDescription = null, Modifier.alpha(alpha)) },
        headlineContent = { Text(title, Modifier.alpha(alpha)) },
        supportingContent = { Text(subtitle, Modifier.alpha(alpha)) },
        modifier = Modifier.clickable(enabled = enabled, onClick = onClick),
    )
}

@Composable
private fun Hint(text: String) {
    Text(text, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
}

/** One earlier flight in a pick list: route, date and aircraft, and who was on board. */
class PastFlightRow(val flight: FlightEntity, val registration: String?, val people: List<String>)

/**
 * A list of earlier flights to take something from: the whole flight
 * ("Previous Flight", iOS `PreviousFlightPickerView`) or only its people
 * ("Copy Crew From", iOS `CrewSourcePickerView`).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PastFlightPickerScreen(
    title: String,
    emptyText: String,
    rows: List<PastFlightRow>,
    onPick: (FlightEntity) -> Unit,
    onCancel: () -> Unit,
) {
    BackHandler(onBack = onCancel)
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(title) },
                navigationIcon = { IconButton(onClick = onCancel) { Icon(Icons.Default.Close, contentDescription = "Cancel") } },
            )
        },
    ) { padding ->
        if (rows.isEmpty()) {
            Column(Modifier.fillMaxSize().padding(padding).padding(32.dp), Arrangement.Center, Alignment.CenterHorizontally) {
                Text(emptyText, style = MaterialTheme.typography.bodyMedium)
            }
        } else {
            LazyColumn(Modifier.fillMaxSize().padding(padding)) {
                items(rows, key = { it.flight.id }) { row ->
                    ListItem(
                        headlineContent = {
                            Text("${row.flight.originICAO.ifBlank { "????" }} → ${row.flight.destinationICAO.ifBlank { "????" }}")
                        },
                        supportingContent = {
                            Column {
                                if (row.people.isNotEmpty()) Text(row.people.joinToString(", "))
                                Text(
                                    listOfNotNull(DAY.format(row.flight.departureInstant), row.registration?.ifBlank { null })
                                        .joinToString(" · "),
                                    style = MaterialTheme.typography.bodySmall,
                                )
                            }
                        },
                        modifier = Modifier.clickable { onPick(row.flight) },
                    )
                    HorizontalDivider()
                }
            }
        }
    }
}

private val DAY: DateTimeFormatter = DateTimeFormatter.ofPattern("d MMM yyyy").withZone(ZoneId.systemDefault())
