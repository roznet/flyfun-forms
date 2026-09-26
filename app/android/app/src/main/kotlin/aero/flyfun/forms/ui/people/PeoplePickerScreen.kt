package aero.flyfun.forms.ui.people

import aero.flyfun.forms.data.PersonEntity
import aero.flyfun.forms.data.PersonWithDocuments
import aero.flyfun.forms.logic.FlightPeople
import aero.flyfun.forms.logic.PeopleRanking
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.PersonAdd
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
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
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

/**
 * Who is on the flight, chosen on a full screen. Port of iOS
 * `PeoplePickerView`: search, crew/passenger toggle per person, usual crew
 * first, "Frequent with" groups, and a way to add someone not in the app yet.
 *
 * Android adds reordering: crew is in seat order, and the first crew member is
 * the pilot in command on every form, so the order is the pilot's to set.
 *
 * Edits go straight to the flight's draft; Done only closes. The flight is
 * stored, as ever, by its own Save.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PeoplePickerScreen(
    people: List<PersonWithDocuments>,
    lastFlights: Map<String, Instant>,
    flightPeople: List<FlightPeople>,
    crew: List<PersonEntity>,
    passengers: List<PersonEntity>,
    onChange: (crew: List<PersonEntity>, passengers: List<PersonEntity>) -> Unit,
    add: AddPersonActions,
    /** Store someone under the name a search did not find, put them on the flight and open them. */
    onAddNamed: (String) -> Unit,
    onDone: () -> Unit,
) {
    BackHandler(onBack = onDone)
    var query by rememberSaveable { mutableStateOf("") }
    var addMenu by remember { mutableStateOf(false) }
    val selectedIds = (crew + passengers).map { it.id }.toSet()

    fun addPerson(person: PersonEntity) {
        if (person.id in selectedIds) return
        // As on iOS: usual crew join the crew, everyone else the passengers.
        if (person.isUsualCrew) onChange(crew + person, passengers) else onChange(crew, passengers + person)
    }

    val everyone = people.map { it.person }
    val byId = everyone.associateBy { it.id }
    val matching = remember(everyone, lastFlights, query) {
        PeopleRanking.forPicker(
            everyone.filter { PeopleRanking.matches(query, it.firstName, it.lastName) }.map { it.ranked(lastFlights) },
        ).mapNotNull { byId[it.id] }
    }
    val group: Pair<String, List<PersonEntity>>? = remember(crew, passengers, everyone, flightPeople) {
        val anchor = crew.firstOrNull() ?: passengers.firstOrNull()
        if (anchor == null) {
            everyone.filter { it.isUsualCrew }.takeIf { it.isNotEmpty() }?.let { "Usual Crew" to it }
        } else {
            PeopleRanking.coTravelers(anchor.id, flightPeople)
                .mapNotNull { byId[it] }
                .filter { it.id !in selectedIds }
                .takeIf { it.isNotEmpty() }
                ?.let { "Frequent with ${anchor.displayName}" to it }
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Crew & Passengers") },
                navigationIcon = {
                    IconButton(onClick = onDone) { Icon(Icons.Default.Close, contentDescription = "Close") }
                },
                actions = {
                    Box {
                        IconButton(onClick = { addMenu = true }) {
                            Icon(Icons.Default.Add, contentDescription = "Add person")
                        }
                        DropdownMenu(expanded = addMenu, onDismissRequest = { addMenu = false }) {
                            AddPersonMenuItems(add) { addMenu = false }
                        }
                    }
                    TextButton(onClick = onDone) { Text("Done") }
                },
            )
        },
    ) { padding ->
        Column(Modifier.fillMaxSize().padding(padding)) {
            SearchField(query, { query = it }, "Search people")
            LazyColumn(Modifier.fillMaxSize()) {
                if (crew.isNotEmpty() || passengers.isNotEmpty()) {
                    header("Selected")
                    crew.forEachIndexed { index, person ->
                        item(key = "crew:${person.id}") {
                            SelectedRow(
                                person = person,
                                isCrew = true,
                                isPic = index == 0,
                                onToggle = { onChange(crew - person, passengers + person) },
                                onRemove = { onChange(crew - person, passengers) },
                                onUp = if (index > 0) { { onChange(crew.swap(index, index - 1), passengers) } } else null,
                                onDown = if (index < crew.lastIndex) { { onChange(crew.swap(index, index + 1), passengers) } } else null,
                            )
                        }
                    }
                    items(passengers, key = { "pax:${it.id}" }) { person ->
                        SelectedRow(
                            person = person,
                            isCrew = false,
                            isPic = false,
                            onToggle = { onChange(crew + person, passengers - person) },
                            onRemove = { onChange(crew, passengers - person) },
                        )
                    }
                }

                // The groups widen a selection, so they give way to a search.
                if (group != null && query.isBlank()) {
                    header("Groups")
                    item(key = "group") {
                        ListItem(
                            headlineContent = { Text(group.first) },
                            supportingContent = { Text(group.second.joinToString(", ") { it.displayName }, maxLines = 2) },
                            trailingContent = { Icon(Icons.Default.Add, contentDescription = "Add all") },
                            modifier = Modifier.clickable {
                                val (addCrew, addPax) = group.second.partition { it.isUsualCrew }
                                onChange(crew + addCrew, passengers + addPax)
                            },
                        )
                    }
                }

                if (matching.isNotEmpty()) {
                    header("People")
                    items(matching, key = { "person:${it.id}" }) { person ->
                        val selected = person.id in selectedIds
                        ListItem(
                            headlineContent = { Text(person.displayName.ifBlank { "New Person" }) },
                            supportingContent = lastFlights[person.id]?.let { { Text("Flew ${dayFormat.format(it)}") } },
                            leadingContent = if (person.isUsualCrew) { { CrewPill() } } else null,
                            trailingContent = if (selected) {
                                { Icon(Icons.Default.Check, contentDescription = "On this flight") }
                            } else {
                                null
                            },
                            modifier = Modifier.clickable(enabled = !selected) { addPerson(person) },
                        )
                    }
                }

                val name = query.trim()
                if (name.isNotEmpty() && matching.isEmpty()) {
                    item(key = "add-named") {
                        ListItem(
                            headlineContent = { Text("Add “$name” as new person") },
                            leadingContent = { Icon(Icons.Default.PersonAdd, contentDescription = null) },
                            modifier = Modifier.clickable {
                                query = ""
                                onAddNamed(name)
                            },
                        )
                    }
                }
            }
        }
    }
}

private fun LazyListScope.header(text: String) {
    item(key = "header:$text") {
        Text(
            text,
            style = MaterialTheme.typography.labelLarge,
            color = MaterialTheme.colorScheme.primary,
            modifier = Modifier.padding(start = 16.dp, top = 16.dp, bottom = 4.dp),
        )
    }
}

@Composable
private fun SelectedRow(
    person: PersonEntity,
    isCrew: Boolean,
    isPic: Boolean,
    onToggle: () -> Unit,
    onRemove: () -> Unit,
    onUp: (() -> Unit)? = null,
    onDown: (() -> Unit)? = null,
) {
    ListItem(
        headlineContent = { Text(person.displayName.ifBlank { "New Person" }) },
        supportingContent = {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                // Tap to move between crew and passengers; one person is never both.
                FilterChip(
                    selected = isCrew,
                    onClick = onToggle,
                    label = { Text(if (isCrew) "Crew" else "Passenger") },
                )
                if (isPic) Text("Pilot in command", style = MaterialTheme.typography.bodySmall)
            }
        },
        trailingContent = {
            Row {
                if (isCrew) {
                    IconButton(onClick = { onUp?.invoke() }, enabled = onUp != null) {
                        Icon(Icons.Default.KeyboardArrowUp, contentDescription = "Move up")
                    }
                    IconButton(onClick = { onDown?.invoke() }, enabled = onDown != null) {
                        Icon(Icons.Default.KeyboardArrowDown, contentDescription = "Move down")
                    }
                }
                IconButton(onClick = onRemove) { Icon(Icons.Default.Close, contentDescription = "Remove") }
            }
        },
    )
    HorizontalDivider()
}

private fun <T> List<T>.swap(i: Int, j: Int): List<T> =
    toMutableList().also { val t = it[i]; it[i] = it[j]; it[j] = t }

private val dayFormat: DateTimeFormatter = DateTimeFormatter.ofPattern("d MMM yyyy").withZone(ZoneId.systemDefault())
