package aero.flyfun.forms.ui.flights

import aero.flyfun.forms.R
import aero.flyfun.forms.data.AircraftEntity
import aero.flyfun.forms.data.FlightEntity
import aero.flyfun.forms.data.PersonEntity
import aero.flyfun.forms.data.TravelDocumentEntity
import aero.flyfun.forms.data.toResolvable
import aero.flyfun.forms.logic.DocumentResolver
import aero.flyfun.forms.ui.people.CrewPill
import aero.flyfun.forms.net.FormInfo
import aero.flyfun.forms.net.displayField
import aero.flyfun.forms.data.FormRequestBuilder
import aero.flyfun.forms.logic.FormSides
import aero.flyfun.forms.net.ExtraFieldValue
import aero.flyfun.forms.ui.common.ChoiceField
import aero.flyfun.forms.ui.common.DeleteOverflowMenu
import aero.flyfun.forms.ui.common.SwipeToDelete
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
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
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.automirrored.filled.Undo
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.Badge
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedCard
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter

private val DAY: DateTimeFormatter = DateTimeFormatter.ofPattern("d MMM yyyy").withZone(ZoneOffset.UTC)
private val HHMM: DateTimeFormatter = DateTimeFormatter.ofPattern("HH:mm").withZone(ZoneOffset.UTC)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FlightListScreen(
    flights: List<FlightEntity>,
    aircraft: List<AircraftEntity>,
    onOpen: (String) -> Unit,
    onAdd: () -> Unit,
    onDelete: (FlightEntity) -> Unit,
    /** The flight open beside the list, on a screen wide enough for both. */
    selectedId: String? = null,
) {
    // Split at the start of today, as iOS does: a flight earlier today is
    // still one the pilot is working on.
    val startOfToday = LocalDate.now().atStartOfDay(ZoneId.systemDefault()).toInstant()
    val upcoming = flights.filter { !it.departureInstant.isBefore(startOfToday) }.sortedBy { it.departureInstant }
    val past = flights.filter { it.departureInstant.isBefore(startOfToday) }.sortedByDescending { it.departureInstant }
    val registrations = aircraft.associate { it.id to it.registration }
    var showPast by rememberSaveable { mutableStateOf(false) }

    Scaffold(
        topBar = { TopAppBar(title = { Text(stringResource(R.string.flights_title)) }) },
        floatingActionButton = {
            FloatingActionButton(onClick = onAdd) {
                Icon(Icons.Default.Add, contentDescription = stringResource(R.string.flights_add_flight))
            }
        },
    ) { padding ->
        if (flights.isEmpty()) {
            Column(
                Modifier.fillMaxSize().padding(padding).padding(32.dp),
                verticalArrangement = Arrangement.Center,
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Text(stringResource(R.string.flights_no_flights_yet), style = MaterialTheme.typography.titleMedium)
                Text(
                    stringResource(R.string.flights_empty_message),
                    style = MaterialTheme.typography.bodyMedium,
                )
            }
        } else {
            LazyColumn(Modifier.fillMaxSize().padding(padding)) {
                item { SectionHeader(stringResource(R.string.flights_upcoming)) }
                if (upcoming.isEmpty()) {
                    item {
                        Text(
                            stringResource(R.string.flights_no_upcoming),
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                        )
                    }
                }
                items(upcoming, key = { "${it.id}:${it.updatedAt}" }) {
                    FlightRow(it, registrations[it.aircraftId], it.id == selectedId, onOpen, onDelete)
                }
                if (past.isNotEmpty()) {
                    // Collapsed by default: the list is for what is coming up.
                    item {
                        ListItem(
                            headlineContent = { Text(stringResource(R.string.flights_past_flights_count, past.size)) },
                            trailingContent = {
                                Icon(
                                    if (showPast) Icons.Default.ExpandLess else Icons.Default.ExpandMore,
                                    contentDescription = stringResource(if (showPast) R.string.flights_hide_past else R.string.flights_show_past),
                                )
                            },
                            modifier = Modifier.clickable { showPast = !showPast },
                        )
                    }
                    if (showPast) {
                        items(past, key = { "${it.id}:${it.updatedAt}" }) {
                            FlightRow(it, registrations[it.aircraftId], it.id == selectedId, onOpen, onDelete)
                        }
                    }
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
private fun FlightRow(
    flight: FlightEntity,
    registration: String?,
    selected: Boolean,
    onOpen: (String) -> Unit,
    onDelete: (FlightEntity) -> Unit,
) {
    SwipeToDelete(onDelete = { onDelete(flight) }) {
        ListItem(
            headlineContent = {
                Text("${flight.originICAO.ifBlank { "????" }} → ${flight.destinationICAO.ifBlank { "????" }}")
            },
            supportingContent = {
                Text(
                    listOfNotNull(
                        DAY.format(flight.departureInstant),
                        "${HHMM.format(flight.departureInstant)}Z",
                        registration?.takeIf { it.isNotBlank() },
                    ).joinToString(" · "),
                )
            },
            colors = if (selected) ListItemDefaults.colors(containerColor = MaterialTheme.colorScheme.secondaryContainer) else ListItemDefaults.colors(),
            modifier = Modifier.clickable { onOpen(flight.id) },
        )
    }
    HorizontalDivider()
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FlightEditScreen(
    detail: FlightDetail?,
    hasUnsavedChanges: Boolean,
    aircraftOptions: List<AircraftEntity>,
    people: List<PersonEntity>,
    /** Each person's active documents, by id: a per-flight choice is offered when there are several. */
    documents: Map<String, List<TravelDocumentEntity>>,
    airportForms: List<AirportForms>,
    /** Name, zone and notice of each airport on the route, by ICAO. */
    airportInfo: Map<String, AirportDetails>,
    onOpenRoutePicker: () -> Unit,
    generateState: GenerateState,
    onEditFlight: ((FlightEntity) -> FlightEntity) -> Unit,
    onSetDeparture: (java.time.Instant) -> Unit,
    onSetAircraft: (String?) -> Unit,
    onSetCrew: (List<PersonEntity>) -> Unit,
    onSetPassengers: (List<PersonEntity>) -> Unit,
    onSetResponsiblePerson: (PersonEntity?) -> Unit,
    onChooseDocument: (PersonEntity, TravelDocumentEntity?) -> Unit,
    onOpenPeoplePicker: () -> Unit,
    extraValues: Map<String, Map<String, ExtraFieldValue>>,
    onSetExtra: (airport: String, formId: String, key: String, value: ExtraFieldValue?) -> Unit,
    onSave: () -> Unit,
    /** Save, and leave once it is stored: leaving first would cancel the write. */
    onSaveAndBack: () -> Unit,
    onGenerate: (String, FormInfo) -> Unit,
    onEmail: (String, FormInfo) -> Unit,
    onOpenWebForm: (String, FormInfo) -> Unit,
    onShare: (java.io.File) -> Unit,
    onDismissGenerate: () -> Unit,
    onBack: () -> Unit,
    onDelete: () -> Unit,
    onCreateReturn: () -> Unit,
    onCreateNextLeg: () -> Unit,
    onDuplicate: () -> Unit,
) {
    if (detail == null) {
        Scaffold(topBar = { TopAppBar(title = { Text(stringResource(R.string.flights_flight)) }) }) { p ->
            Column(Modifier.fillMaxSize().padding(p), Arrangement.Center, Alignment.CenterHorizontally) {
                CircularProgressIndicator()
            }
        }
        return
    }
    val flight = detail.flight
    val origin = flight.originICAO
    val destination = flight.destinationICAO
    // Local text state so typing does not round-trip through the ViewModel;
    // keyed on the flight so a different leg starts from its own values.
    var observations by remember(flight.id) { mutableStateOf(flight.observations.orEmpty()) }
    var confirmDiscard by remember { mutableStateOf(false) }
    val unnamed = stringResource(R.string.flights_unnamed)
    val commercialLabel = stringResource(R.string.flights_commercial)
    val privateLabel = stringResource(R.string.flights_private)

    // Back with edits asks first, whether it came from the arrow or the system.
    val leave = { if (hasUnsavedChanges) confirmDiscard = true else onBack() }
    BackHandler(enabled = hasUnsavedChanges) { confirmDiscard = true }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        if (detail.isNew && origin.isBlank() && destination.isBlank()) stringResource(R.string.flights_new_flight)
                        else "${origin.ifBlank { "????" }} → ${destination.ifBlank { "????" }}",
                    )
                },
                navigationIcon = {
                    IconButton(onClick = leave) {
                        Icon(Icons.Default.ArrowBack, contentDescription = stringResource(R.string.flights_back))
                    }
                },
                actions = {
                    TextButton(onClick = onSave, enabled = hasUnsavedChanges) { Text(stringResource(R.string.flights_save)) }
                    // A draft has nothing stored to delete; Back discards it.
                    if (!detail.isNew) DeleteOverflowMenu(onDelete = onDelete)
                },
            )
        },
    ) { padding ->
        Column(
            Modifier.fillMaxSize().padding(padding).padding(16.dp).verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            RouteCard(origin, destination, airportInfo, onOpenRoutePicker)
            AirportNotice(stringResource(R.string.flights_departure), origin, airportInfo)
            if (destination != origin) AirportNotice(stringResource(R.string.flights_arrival), destination, airportInfo)

            // Zones in route order, once each: a local flight has one.
            val zones = listOfNotNull(airportInfo[origin]?.timeZone, airportInfo[destination]?.timeZone).distinct()
            ScheduleField(
                stringResource(R.string.flights_departure), flight.departureInstant, onSetDeparture,
                zones = zones, preferredZone = airportInfo[origin]?.timeZone,
            )
            ScheduleField(
                stringResource(R.string.flights_arrival), flight.arrivalInstant, { t -> onEditFlight { it.copy(arrivalInstant = t) } },
                zones = zones, preferredZone = airportInfo[destination]?.timeZone,
            )
            if (flight.arrivalInstant.isBefore(flight.departureInstant)) {
                Text(
                    stringResource(R.string.flights_arrival_before_departure),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error,
                )
            }

            Text(stringResource(R.string.flights_aircraft), style = MaterialTheme.typography.titleMedium)
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
                Text(stringResource(R.string.flights_add_aircraft_first), style = MaterialTheme.typography.bodySmall)
            }

            ChoiceField(
                label = stringResource(R.string.flights_nature),
                selected = flight.nature,
                options = listOf("private", "commercial"),
                display = { if (it == "commercial") commercialLabel else privateLabel },
                onSelect = { value -> onEditFlight { it.copy(nature = value) } },
            )
            ChoiceField(
                label = stringResource(R.string.flights_reason_for_visit),
                selected = flight.reasonForVisit.orEmpty(),
                options = listOf("") + REASONS_FOR_VISIT,
                display = { it.ifBlank { "—" } },
                onSelect = { value -> onEditFlight { it.copy(reasonForVisit = value.ifBlank { null }) } },
            )
            ChoiceField(
                label = stringResource(R.string.flights_responsible_person),
                selected = detail.responsiblePerson,
                options = listOf<PersonEntity?>(null) + people,
                display = { it?.displayName?.ifBlank { unnamed } ?: "—" },
                onSelect = onSetResponsiblePerson,
            )
            detail.responsiblePerson?.let { person ->
                person.phone?.takeIf { it.isNotBlank() }?.let { DetailLine(stringResource(R.string.flights_phone), it) }
                person.address?.takeIf { it.isNotBlank() }?.let { DetailLine(stringResource(R.string.flights_address), it) }
            }

            PeopleOnBoard(
                detail = detail,
                documents = documents,
                onRemoveCrew = { person -> onSetCrew(detail.crew - person) },
                onRemovePassenger = { person -> onSetPassengers(detail.passengers - person) },
                onChooseDocument = onChooseDocument,
                onOpenPicker = onOpenPeoplePicker,
            )

            OutlinedTextField(
                observations,
                { value ->
                    observations = value
                    onEditFlight { it.copy(observations = value.trim().ifBlank { null }) }
                },
                label = { Text(stringResource(R.string.flights_observations)) }, modifier = Modifier.fillMaxWidth(),
            )

            Text(stringResource(R.string.flights_forms), style = MaterialTheme.typography.titleMedium)
            val rowContext = FormRowContext(
                state = generateState,
                flightPeople = detail.crew + detail.passengers,
                responsiblePerson = detail.responsiblePerson,
                extraValues = extraValues,
                onSetExtra = onSetExtra,
                onGenerate = onGenerate,
                onEmail = onEmail,
                onOpenWebForm = onOpenWebForm,
            )
            airportForms.forEach { airport -> AirportFormsCard(airport, rowContext) }
            if (airportForms.isEmpty()) {
                Text(
                    stringResource(R.string.flights_enter_route_for_forms),
                    style = MaterialTheme.typography.bodySmall,
                )
            }

            // Each stores this flight first, then opens the new leg.
            Text(stringResource(R.string.flights_actions), style = MaterialTheme.typography.titleMedium)
            LegAction(Icons.AutoMirrored.Filled.Undo, stringResource(R.string.flights_create_return), onCreateReturn)
            LegAction(Icons.AutoMirrored.Filled.ArrowForward, stringResource(R.string.flights_create_next_leg), onCreateNextLeg)
            LegAction(Icons.Default.ContentCopy, stringResource(R.string.flights_duplicate), onDuplicate)
        }
    }

    if (confirmDiscard) {
        AlertDialog(
            onDismissRequest = { confirmDiscard = false },
            title = { Text(stringResource(if (detail.isNew) R.string.flights_save_this_flight else R.string.flights_save_your_changes)) },
            text = { Text(stringResource(R.string.flights_leaving_discards)) },
            confirmButton = {
                TextButton(onClick = { confirmDiscard = false; onSaveAndBack() }) { Text(stringResource(R.string.flights_save)) }
            },
            dismissButton = {
                TextButton(onClick = { confirmDiscard = false; onBack() }) { Text(stringResource(R.string.flights_discard)) }
            },
        )
    }

    GenerateFeedback(generateState, onShare, onDismissGenerate)
}

/** FROM → TO with the airports' names; tapping it opens the route picker. */
@Composable
private fun RouteCard(origin: String, destination: String, info: Map<String, AirportDetails>, onClick: () -> Unit) {
    OutlinedCard(onClick = onClick, modifier = Modifier.fillMaxWidth()) {
        Row(Modifier.fillMaxWidth().padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
            RouteEndLabel(stringResource(R.string.flights_from), origin, info[origin]?.summary?.name, Modifier.weight(1f))
            Icon(Icons.AutoMirrored.Filled.ArrowForward, contentDescription = null)
            RouteEndLabel(stringResource(R.string.flights_to), destination, info[destination]?.summary?.name, Modifier.weight(1f))
            Icon(Icons.Default.Edit, contentDescription = stringResource(R.string.flights_change_route))
        }
    }
}

@Composable
private fun RouteEndLabel(label: String, icao: String, name: String?, modifier: Modifier) {
    Column(modifier.padding(horizontal = 4.dp)) {
        Text(label, style = MaterialTheme.typography.labelSmall)
        Text(
            icao.ifBlank { "----" },
            style = MaterialTheme.typography.titleLarge,
            fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace,
        )
        name?.let { Text(it, style = MaterialTheme.typography.bodySmall, maxLines = 1) }
    }
}

/**
 * The airport's notice (customs notification rules, PPR...) from the maps
 * service, shown under the route as on iOS; tap for the full text.
 */
@Composable
private fun AirportNotice(label: String, icao: String, info: Map<String, AirportDetails>) {
    val notice = info[icao]?.notice ?: return
    val detail = notice.rawText ?: notice.pretty
    var open by rememberSaveable(icao) { mutableStateOf(false) }
    Column(
        Modifier.fillMaxWidth().then(if (detail != null) Modifier.clickable { open = !open } else Modifier),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("$label — $icao", style = MaterialTheme.typography.labelLarge, modifier = Modifier.weight(1f))
            if (detail != null) {
                Icon(if (open) Icons.Default.ExpandLess else Icons.Default.ExpandMore, contentDescription = stringResource(if (open) R.string.flights_less else R.string.flights_more))
            }
        }
        Text(notice.summary.orEmpty(), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        if (open && detail != null) {
            Text(detail, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun LegAction(icon: ImageVector, label: String, onClick: () -> Unit) {
    TextButton(onClick = onClick) {
        Icon(icon, contentDescription = null)
        Text(label, Modifier.padding(start = 8.dp))
    }
}

/** Same vocabulary as iOS `Flight.reasonForVisitOptions`; the server matches on these strings. */
private val REASONS_FOR_VISIT = listOf("Based", "Short Term Visit", "Maintenance", "Permanent Import", "Repair")

@Composable
private fun DetailLine(label: String, value: String) {
    Row(Modifier.fillMaxWidth(), Arrangement.spacedBy(8.dp)) {
        Text(label, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(value, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

/**
 * Crew and passengers, each a row: the name, "PIC" on the first crew member
 * (sent as the pilot on every form), and for someone with several active
 * documents a menu to pick the one for this flight. Port of iOS
 * `FlightEditView.personLabel` (`1173620`, `20065ae`). Who is on board is
 * chosen in [aero.flyfun.forms.ui.people.PeoplePickerScreen].
 */
@Composable
private fun PeopleOnBoard(
    detail: FlightDetail,
    documents: Map<String, List<TravelDocumentEntity>>,
    onRemoveCrew: (PersonEntity) -> Unit,
    onRemovePassenger: (PersonEntity) -> Unit,
    onChooseDocument: (PersonEntity, TravelDocumentEntity?) -> Unit,
    onOpenPicker: () -> Unit,
) {
    val chosen = detail.flight.chosenDocNumbers.orEmpty()
    val pic = stringResource(R.string.flights_pic)
    Text(stringResource(R.string.flights_crew), style = MaterialTheme.typography.titleMedium)
    if (detail.crew.isEmpty()) Text(stringResource(R.string.flights_no_crew_yet), style = MaterialTheme.typography.bodySmall)
    detail.crew.forEachIndexed { index, person ->
        OnBoardRow(person, if (index == 0) pic else null, documents[person.id].orEmpty(), chosen,
            { onChooseDocument(person, it) }, { onRemoveCrew(person) })
    }
    Text(stringResource(R.string.flights_passengers), style = MaterialTheme.typography.titleMedium)
    if (detail.passengers.isEmpty()) Text(stringResource(R.string.flights_no_passengers), style = MaterialTheme.typography.bodySmall)
    detail.passengers.forEach { person ->
        OnBoardRow(person, null, documents[person.id].orEmpty(), chosen,
            { onChooseDocument(person, it) }, { onRemovePassenger(person) })
    }
    OutlinedButton(onClick = onOpenPicker) {
        Icon(Icons.Default.Groups, contentDescription = null)
        Text(stringResource(R.string.flights_choose_crew_passengers), Modifier.padding(start = 8.dp))
    }
}

@Composable
private fun OnBoardRow(
    person: PersonEntity,
    tag: String?,
    documents: List<TravelDocumentEntity>,
    chosenDocNumbers: List<String>,
    onChoose: (TravelDocumentEntity?) -> Unit,
    onRemove: () -> Unit,
) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(person.displayName.ifBlank { stringResource(R.string.flights_unnamed) }, style = MaterialTheme.typography.bodyLarge)
                tag?.let { CrewPill(it) }
            }
            if (documents.size > 1) {
                val chosen = DocumentResolver.chosen(documents.map { it.toResolvable() }, chosenDocNumbers)
                    ?.let { c -> documents.first { it.id == c.id } }
                var open by remember { mutableStateOf(false) }
                Box {
                    TextButton(onClick = { open = true }) {
                        Icon(Icons.Default.Badge, contentDescription = null)
                        Text(chosen?.let(::documentLabel) ?: stringResource(R.string.flights_document_automatic), Modifier.padding(start = 4.dp))
                    }
                    DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
                        DropdownMenuItem(text = { Text(stringResource(R.string.flights_automatic)) }, onClick = { open = false; onChoose(null) })
                        documents.filter { it.docNumber.isNotEmpty() }.forEach { doc ->
                            DropdownMenuItem(text = { Text(documentLabel(doc)) }, onClick = { open = false; onChoose(doc) })
                        }
                    }
                }
            }
        }
        IconButton(onClick = onRemove) { Icon(Icons.Default.Close, contentDescription = stringResource(R.string.flights_remove_from_flight)) }
    }
}

/** "Passport (FRA) — 123456", as iOS `TravelDocument.displayLabel`. */
private fun documentLabel(doc: TravelDocumentEntity): String =
    "${doc.docType} (${doc.issuingCountry ?: "?"})" + if (doc.docNumber.isEmpty()) "" else " — ${doc.docNumber.takeLast(6)}"

/**
 * What a form row needs from the flight screen, bundled so each row does not
 * take a dozen parameters.
 */
class FormRowContext(
    val state: GenerateState,
    /** Crew and passengers: the people a "person" extra field can name. */
    val flightPeople: List<PersonEntity>,
    val responsiblePerson: PersonEntity?,
    val extraValues: Map<String, Map<String, ExtraFieldValue>>,
    val onSetExtra: (airport: String, formId: String, key: String, value: ExtraFieldValue?) -> Unit,
    val onGenerate: (String, FormInfo) -> Unit,
    val onEmail: (String, FormInfo) -> Unit,
    val onOpenWebForm: (String, FormInfo) -> Unit,
)

@Composable
private fun AirportFormsCard(airport: AirportForms, ctx: FormRowContext) {
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
                    Text(stringResource(R.string.flights_no_forms_needed), style = MaterialTheme.typography.bodySmall)
                else -> {
                    val grouped = FormSides.group(airport.forms) { it.isWebForm }
                    grouped.primary?.let { FormRow(airport.icao, it, ctx) }
                    grouped.web.forEach { WebFormRow(airport.icao, it, ctx) }
                    if (grouped.others.isNotEmpty()) {
                        var showOthers by rememberSaveable(airport.icao, airport.direction) { mutableStateOf(false) }
                        TextButton(onClick = { showOthers = !showOthers }) {
                            Text(stringResource(R.string.flights_other_forms_count, grouped.others.size))
                            Icon(
                                if (showOthers) Icons.Default.ExpandLess else Icons.Default.ExpandMore,
                                contentDescription = null,
                            )
                        }
                        if (showOthers) grouped.others.forEach { FormRow(airport.icao, it, ctx) }
                    }
                }
            }
        }
    }
}

@Composable
private fun FormRow(airport: String, form: FormInfo, ctx: FormRowContext) {
    val working = ctx.state is GenerateState.Working && ctx.state.formId == form.id
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(form.label, style = MaterialTheme.typography.titleSmall)
        ExtraFields(airport, form, ctx)
        Row(Modifier.fillMaxWidth(), Arrangement.spacedBy(8.dp, Alignment.End), Alignment.CenterVertically) {
            if (working) CircularProgressIndicator(Modifier.padding(2.dp))
            OutlinedButton(
                enabled = ctx.state !is GenerateState.Working,
                onClick = { ctx.onEmail(airport, form) },
            ) { Text(stringResource(R.string.flights_email)) }
            OutlinedButton(
                enabled = ctx.state !is GenerateState.Working,
                onClick = { ctx.onGenerate(airport, form) },
            ) { Text(stringResource(R.string.flights_generate)) }
        }
    }
}

@Composable
private fun WebFormRow(airport: String, form: FormInfo, ctx: FormRowContext) {
    val working = ctx.state is GenerateState.Working && ctx.state.formId == form.id
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Row(Modifier.fillMaxWidth(), Arrangement.SpaceBetween, Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(form.label, style = MaterialTheme.typography.titleSmall)
                Text(stringResource(R.string.flights_official_web_form), style = MaterialTheme.typography.bodySmall)
            }
            // The airport's own page: prefilled via /prefill and submitted by
            // the pilot, never by the app.
            OutlinedButton(
                enabled = ctx.state !is GenerateState.Working,
                onClick = { ctx.onOpenWebForm(airport, form) },
            ) {
                if (working) CircularProgressIndicator(Modifier.padding(2.dp))
                else Text(stringResource(R.string.flights_open_prefilled))
            }
        }
        if (ctx.responsiblePerson == null &&
            form.extraFields.any { it.key in FormRequestBuilder.PERSON_SUPPLIED_EXTRAS }
        ) {
            Hint(stringResource(R.string.flights_pick_responsible_for_phone_email))
        }
    }
}

/**
 * The form's own questions, from `FormInfo.extraFields`. Port of iOS
 * `extraFieldsView`: reason for visit and the responsible person come from the
 * flight, and phone and e-mail from the responsible person, so those are shown
 * rather than asked.
 */
@Composable
private fun ExtraFields(airport: String, form: FormInfo, ctx: FormRowContext) {
    val values = ctx.extraValues[FlightsViewModel.formKey(airport, form.id)].orEmpty()
    val set = { key: String, value: ExtraFieldValue? -> ctx.onSetExtra(airport, form.id, key, value) }
    val unnamed = stringResource(R.string.flights_unnamed)

    form.extraFields
        .filter { it.key !in FormRequestBuilder.FLIGHT_SUPPLIED_EXTRAS }
        .forEach { field ->
            when {
                field.type == "choice" -> {
                    val options = field.options.orEmpty()
                    ChoiceField(
                        label = field.label,
                        selected = (values[field.key] as? ExtraFieldValue.Text)?.value ?: options.firstOrNull().orEmpty(),
                        options = options,
                        display = { it },
                        onSelect = { set(field.key, ExtraFieldValue.Text(it)) },
                    )
                }

                field.type == "person" -> {
                    val chosen = (values[field.key] as? ExtraFieldValue.Person)?.value.orEmpty()
                    ChoiceField(
                        label = field.label,
                        selected = ctx.flightPeople.firstOrNull { it.displayName == chosen["name"] },
                        options = listOf<PersonEntity?>(null) + ctx.flightPeople,
                        display = { it?.displayName?.ifBlank { unnamed } ?: "—" },
                        onSelect = { person ->
                            set(
                                field.key,
                                person?.let {
                                    ExtraFieldValue.Person(mapOf("name" to it.displayName, "address" to it.address.orEmpty()))
                                },
                            )
                        },
                    )
                    if (chosen.isNotEmpty()) {
                        var address by remember(airport, form.id, field.key, chosen["name"]) {
                            mutableStateOf(chosen["address"].orEmpty())
                        }
                        OutlinedTextField(
                            address,
                            { value ->
                                address = value
                                set(field.key, ExtraFieldValue.Person(chosen + ("address" to value)))
                            },
                            label = { Text(stringResource(R.string.flights_address)) },
                            modifier = Modifier.fillMaxWidth(),
                        )
                    }
                }

                field.key in FormRequestBuilder.PERSON_SUPPLIED_EXTRAS ->
                    ResponsiblePersonValue(field.label, field.key, ctx.responsiblePerson)

                else -> {
                    var text by remember(airport, form.id, field.key) {
                        mutableStateOf((values[field.key] as? ExtraFieldValue.Text)?.value.orEmpty())
                    }
                    OutlinedTextField(
                        text,
                        { value ->
                            text = value
                            set(field.key, value.takeIf { it.isNotBlank() }?.let { ExtraFieldValue.Text(it) })
                        },
                        label = { Text(field.label) },
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
            }
        }
}

/** A phone or e-mail field, read from the responsible person. */
@Composable
private fun ResponsiblePersonValue(label: String, key: String, person: PersonEntity?) {
    val value = when (key) {
        FormRequestBuilder.TELEPHONE -> person?.phone
        FormRequestBuilder.EMAIL -> person?.email
        else -> null
    }
    Row(Modifier.fillMaxWidth().padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(label, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
        when {
            person == null -> Hint(stringResource(R.string.flights_pick_responsible))
            value.isNullOrBlank() -> Hint(stringResource(R.string.flights_set_field_on_person, label.lowercase(), person.displayName))
            else -> Text(value, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

/** Something the pilot has to fix elsewhere before the form fills completely. */
@Composable
private fun Hint(text: String) {
    Text(text, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
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
            text = { Text(stringResource(R.string.flights_file_ready, state.file.name)) },
            confirmButton = { TextButton(onClick = { onShare(state.file); onDismiss() }) { Text(stringResource(R.string.flights_share)) } },
            dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.flights_close)) } },
        )
        is GenerateState.Invalid -> AlertDialog(
            onDismissRequest = onDismiss,
            title = { Text(stringResource(R.string.flights_missing_information)) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    state.errors.forEach { Text("${it.displayField}: ${it.error}") }
                }
            },
            confirmButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.flights_ok)) } },
        )
        is GenerateState.Failed -> AlertDialog(
            onDismissRequest = onDismiss,
            title = { Text(stringResource(R.string.flights_could_not_generate)) },
            text = { Text(state.message) },
            confirmButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.flights_ok)) } },
        )
        else -> Unit
    }
}
