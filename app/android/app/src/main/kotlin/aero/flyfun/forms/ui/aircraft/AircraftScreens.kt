package aero.flyfun.forms.ui.aircraft

import aero.flyfun.forms.data.AircraftEntity
import aero.flyfun.forms.data.PersonEntity
import aero.flyfun.forms.ui.common.ChoiceField
import aero.flyfun.forms.ui.common.DeleteOverflowMenu
import aero.flyfun.forms.ui.common.SwipeToDelete
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Switch
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
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AircraftListScreen(
    aircraft: List<AircraftEntity>,
    onOpen: (String) -> Unit,
    onAdd: () -> Unit,
    onDelete: (AircraftEntity) -> Unit,
) {
    Scaffold(
        topBar = { TopAppBar(title = { Text("Aircraft") }) },
        floatingActionButton = {
            FloatingActionButton(onClick = onAdd) {
                Icon(Icons.Default.Add, contentDescription = "Add aircraft")
            }
        },
    ) { padding ->
        if (aircraft.isEmpty()) {
            Column(
                modifier = Modifier.fillMaxSize().padding(padding).padding(32.dp),
                verticalArrangement = Arrangement.Center,
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Text("No aircraft yet", style = MaterialTheme.typography.titleMedium)
                Text(
                    "Add the aircraft you fly so forms can carry its registration and type.",
                    style = MaterialTheme.typography.bodyMedium,
                )
            }
        } else {
            LazyColumn(Modifier.fillMaxSize().padding(padding)) {
                items(aircraft, key = { "${it.id}:${it.updatedAt}" }) { a ->
                    SwipeToDelete(onDelete = { onDelete(a) }) {
                        ListItem(
                            headlineContent = { Text(a.registration.ifBlank { "New Aircraft" }) },
                            supportingContent = {
                                Text(listOfNotNull(a.type.ifBlank { null }, a.usualBase).joinToString(" · "))
                            },
                            modifier = Modifier.clickable { onOpen(a.id) },
                        )
                    }
                    HorizontalDivider()
                }
            }
        }
    }
}

/**
 * Port of iOS `AircraftEditView`: category, who operates it (a company, or an
 * owner picked from People), and where it usually lives.
 *
 * `owner` and `ownerAddress` are what forms send, so they are kept in step
 * with the choice here, as iOS does in its `onChange` handlers: the owner
 * person's name and address, or the company's name and address with no
 * separate address.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AircraftEditScreen(
    initial: AircraftEntity?,
    people: List<PersonEntity>,
    onSave: (AircraftEntity) -> Unit,
    onBack: () -> Unit,
    /** Null for an aircraft not stored yet. */
    onDelete: (() -> Unit)? = null,
) {
    var registration by remember { mutableStateOf(initial?.registration.orEmpty()) }
    var type by remember { mutableStateOf(initial?.type.orEmpty()) }
    var usualBase by remember { mutableStateOf(initial?.usualBase.orEmpty()) }
    var isAirplane by remember { mutableStateOf(initial?.isAirplane ?: true) }
    var useCompanyOperator by remember { mutableStateOf(initial?.useCompanyOperator ?: false) }
    var operatorName by remember { mutableStateOf(initial?.operatorName.orEmpty()) }
    var ownerPersonId by remember { mutableStateOf(initial?.ownerPersonId) }
    val ownerPerson = people.firstOrNull { it.id == ownerPersonId }

    fun edited(): AircraftEntity {
        val base = (initial ?: AircraftEntity()).copy(
            registration = registration.trim().uppercase(),
            type = type.trim(),
            usualBase = usualBase.trim().uppercase().ifBlank { null },
            isAirplane = isAirplane,
            useCompanyOperator = useCompanyOperator,
            operatorName = operatorName.trim().ifBlank { null },
            ownerPersonId = ownerPersonId,
        )
        return when {
            useCompanyOperator -> base.copy(owner = base.operatorName, ownerAddress = null)
            ownerPerson != null -> base.copy(owner = ownerPerson.displayName, ownerAddress = ownerPerson.address)
            // Owner typed on an older build, before it was picked from People: keep it.
            ownerPersonId == null && initial?.ownerPersonId == null && initial?.useCompanyOperator != true -> base
            else -> base.copy(owner = null, ownerAddress = null)
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(if (initial == null) "New Aircraft" else "Edit Aircraft") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.Default.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    TextButton(enabled = registration.isNotBlank(), onClick = { onSave(edited()) }) { Text("Save") }
                    onDelete?.let { DeleteOverflowMenu(onDelete = it) }
                },
            )
        },
    ) { padding ->
        Column(
            Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState()).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text("Aircraft", style = MaterialTheme.typography.titleMedium)
            OutlinedTextField(
                registration, { registration = it }, label = { Text("Registration") },
                singleLine = true, modifier = Modifier.fillMaxWidth(),
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Characters),
            )
            OutlinedTextField(
                type, { type = it }, label = { Text("Type (e.g. SR22)") },
                singleLine = true, modifier = Modifier.fillMaxWidth(),
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Characters),
            )
            SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                listOf(true to "Airplane", false to "Helicopter").forEachIndexed { index, (value, label) ->
                    SegmentedButton(
                        selected = isAirplane == value,
                        onClick = { isAirplane = value },
                        shape = SegmentedButtonDefaults.itemShape(index = index, count = 2),
                    ) { Text(label) }
                }
            }

            Text("Operator", style = MaterialTheme.typography.titleMedium)
            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text("Company operator", style = MaterialTheme.typography.bodyLarge)
                Switch(checked = useCompanyOperator, onCheckedChange = { useCompanyOperator = it })
            }
            if (useCompanyOperator) {
                OutlinedTextField(
                    operatorName, { operatorName = it }, label = { Text("Company name & address") },
                    minLines = 2, maxLines = 4, modifier = Modifier.fillMaxWidth(),
                )
            } else {
                ChoiceField(
                    label = "Owner",
                    selected = ownerPerson,
                    options = listOf<PersonEntity?>(null) + people,
                    display = { it?.displayName?.ifBlank { "Unnamed" } ?: "Select…" },
                    onSelect = { ownerPersonId = it?.id },
                )
                if (ownerPerson == null && initial?.ownerPersonId == null && !initial?.owner.isNullOrBlank()) {
                    // Typed before owners were picked from People; kept until one is picked.
                    DetailLine("On file", initial?.owner.orEmpty())
                }
                ownerPerson?.let { person ->
                    person.email?.takeIf { it.isNotBlank() }?.let { DetailLine("Email", it) }
                    person.phone?.takeIf { it.isNotBlank() }?.let { DetailLine("Phone", it) }
                    person.address?.takeIf { it.isNotBlank() }?.let { DetailLine("Address", it) }
                }
                if (people.isEmpty()) {
                    Text("Add the owner in People to pick them here.", style = MaterialTheme.typography.bodySmall)
                }
            }

            Text("Base", style = MaterialTheme.typography.titleMedium)
            OutlinedTextField(
                usualBase, { if (it.length <= 4) usualBase = it.uppercase() }, label = { Text("Usual base (ICAO)") },
                singleLine = true, modifier = Modifier.fillMaxWidth(),
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Characters),
            )
        }
    }
}

@Composable
private fun DetailLine(label: String, value: String) {
    Row(Modifier.fillMaxWidth(), Arrangement.SpaceBetween) {
        Text(label, style = MaterialTheme.typography.bodyMedium)
        Text(value, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}
