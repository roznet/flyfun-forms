package aero.flyfun.forms.ui.aircraft

import aero.flyfun.forms.R
import aero.flyfun.forms.data.AircraftEntity
import aero.flyfun.forms.data.PersonEntity
import aero.flyfun.forms.ui.common.ChoiceField
import aero.flyfun.forms.ui.flights.AirportLookup
import aero.flyfun.forms.ui.flights.AirportPickerScreen
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
import androidx.compose.material3.ListItemDefaults
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
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AircraftListScreen(
    aircraft: List<AircraftEntity>,
    onOpen: (String) -> Unit,
    onAdd: () -> Unit,
    onDelete: (AircraftEntity) -> Unit,
    /** The aircraft open beside the list, on a screen wide enough for both. */
    selectedId: String? = null,
) {
    Scaffold(
        topBar = { TopAppBar(title = { Text(stringResource(R.string.aircraft_title)) }) },
        floatingActionButton = {
            FloatingActionButton(onClick = onAdd) {
                Icon(Icons.Default.Add, contentDescription = stringResource(R.string.aircraft_add))
            }
        },
    ) { padding ->
        if (aircraft.isEmpty()) {
            Column(
                modifier = Modifier.fillMaxSize().padding(padding).padding(32.dp),
                verticalArrangement = Arrangement.Center,
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Text(stringResource(R.string.aircraft_empty_title), style = MaterialTheme.typography.titleMedium)
                Text(
                    stringResource(R.string.aircraft_empty_message),
                    style = MaterialTheme.typography.bodyMedium,
                )
            }
        } else {
            val newAircraft = stringResource(R.string.aircraft_new_aircraft)
            LazyColumn(Modifier.fillMaxSize().padding(padding)) {
                items(aircraft, key = { "${it.id}:${it.updatedAt}" }) { a ->
                    SwipeToDelete(onDelete = { onDelete(a) }) {
                        ListItem(
                            headlineContent = { Text(a.registration.ifBlank { newAircraft }) },
                            supportingContent = {
                                Text(listOfNotNull(a.type.ifBlank { null }, a.usualBase).joinToString(" · "))
                            },
                            colors = if (a.id == selectedId) {
                                ListItemDefaults.colors(containerColor = MaterialTheme.colorScheme.secondaryContainer)
                            } else {
                                ListItemDefaults.colors()
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
    airports: AirportLookup,
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
    var pickingBase by rememberSaveable { mutableStateOf(false) }
    var baseName by remember(usualBase) { mutableStateOf<String?>(null) }
    LaunchedEffect(usualBase) { baseName = airports.airport(usualBase)?.name }

    if (pickingBase) {
        AirportPickerScreen(
            title = stringResource(R.string.aircraft_usual_base),
            selected = usualBase,
            lookup = airports,
            onPick = { usualBase = it },
            onDone = { pickingBase = false },
        )
        return
    }

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
                title = { Text(if (initial == null) stringResource(R.string.aircraft_new_aircraft) else stringResource(R.string.aircraft_edit_aircraft)) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.Default.ArrowBack, contentDescription = stringResource(R.string.common_back))
                    }
                },
                actions = {
                    TextButton(enabled = registration.isNotBlank(), onClick = { onSave(edited()) }) { Text(stringResource(R.string.common_save)) }
                    onDelete?.let { DeleteOverflowMenu(onDelete = it) }
                },
            )
        },
    ) { padding ->
        Column(
            Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState()).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(stringResource(R.string.aircraft_title), style = MaterialTheme.typography.titleMedium)
            OutlinedTextField(
                registration, { registration = it }, label = { Text(stringResource(R.string.aircraft_registration)) },
                singleLine = true, modifier = Modifier.fillMaxWidth(),
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Characters),
            )
            OutlinedTextField(
                type, { type = it }, label = { Text(stringResource(R.string.aircraft_type_hint)) },
                singleLine = true, modifier = Modifier.fillMaxWidth(),
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Characters),
            )
            SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                listOf(true to stringResource(R.string.aircraft_airplane), false to stringResource(R.string.aircraft_helicopter)).forEachIndexed { index, (value, label) ->
                    SegmentedButton(
                        selected = isAirplane == value,
                        onClick = { isAirplane = value },
                        shape = SegmentedButtonDefaults.itemShape(index = index, count = 2),
                    ) { Text(label) }
                }
            }

            Text(stringResource(R.string.aircraft_operator), style = MaterialTheme.typography.titleMedium)
            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(stringResource(R.string.aircraft_company_operator), style = MaterialTheme.typography.bodyLarge)
                Switch(checked = useCompanyOperator, onCheckedChange = { useCompanyOperator = it })
            }
            if (useCompanyOperator) {
                OutlinedTextField(
                    operatorName, { operatorName = it }, label = { Text(stringResource(R.string.aircraft_company_name_address)) },
                    minLines = 2, maxLines = 4, modifier = Modifier.fillMaxWidth(),
                )
            } else {
                val unnamed = stringResource(R.string.aircraft_unnamed)
                val select = stringResource(R.string.common_select)
                ChoiceField(
                    label = stringResource(R.string.aircraft_owner),
                    selected = ownerPerson,
                    options = listOf<PersonEntity?>(null) + people,
                    display = { it?.displayName?.ifBlank { unnamed } ?: select },
                    onSelect = { ownerPersonId = it?.id },
                )
                if (ownerPerson == null && initial?.ownerPersonId == null && !initial?.owner.isNullOrBlank()) {
                    // Typed before owners were picked from People; kept until one is picked.
                    DetailLine(stringResource(R.string.aircraft_on_file), initial?.owner.orEmpty())
                }
                ownerPerson?.let { person ->
                    person.email?.takeIf { it.isNotBlank() }?.let { DetailLine(stringResource(R.string.aircraft_email), it) }
                    person.phone?.takeIf { it.isNotBlank() }?.let { DetailLine(stringResource(R.string.aircraft_phone), it) }
                    person.address?.takeIf { it.isNotBlank() }?.let { DetailLine(stringResource(R.string.aircraft_address), it) }
                }
                if (people.isEmpty()) {
                    Text(stringResource(R.string.aircraft_add_owner_in_people), style = MaterialTheme.typography.bodySmall)
                }
            }

            Text(stringResource(R.string.aircraft_base), style = MaterialTheme.typography.titleMedium)
            val selectBase = stringResource(R.string.common_select)
            ListItem(
                headlineContent = { Text(stringResource(R.string.aircraft_usual_base)) },
                supportingContent = baseName?.let { { Text(it) } },
                trailingContent = { Text(usualBase.ifBlank { selectBase }, style = MaterialTheme.typography.titleMedium) },
                modifier = Modifier.clickable { pickingBase = true },
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
