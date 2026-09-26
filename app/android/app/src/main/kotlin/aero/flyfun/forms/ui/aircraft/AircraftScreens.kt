package aero.flyfun.forms.ui.aircraft

import aero.flyfun.forms.data.AircraftEntity
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

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AircraftEditScreen(
    initial: AircraftEntity?,
    onSave: (AircraftEntity) -> Unit,
    onBack: () -> Unit,
    /** Null for an aircraft not stored yet. */
    onDelete: (() -> Unit)? = null,
) {
    var registration by remember { mutableStateOf(initial?.registration.orEmpty()) }
    var type by remember { mutableStateOf(initial?.type.orEmpty()) }
    var owner by remember { mutableStateOf(initial?.owner.orEmpty()) }
    var ownerAddress by remember { mutableStateOf(initial?.ownerAddress.orEmpty()) }
    var usualBase by remember { mutableStateOf(initial?.usualBase.orEmpty()) }
    var isAirplane by remember { mutableStateOf(initial?.isAirplane ?: true) }

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
                    TextButton(
                        enabled = registration.isNotBlank(),
                        onClick = {
                            onSave(
                                (initial ?: AircraftEntity()).copy(
                                    registration = registration.trim().uppercase(),
                                    type = type.trim(),
                                    owner = owner.trim().ifBlank { null },
                                    ownerAddress = ownerAddress.trim().ifBlank { null },
                                    usualBase = usualBase.trim().uppercase().ifBlank { null },
                                    isAirplane = isAirplane,
                                ),
                            )
                        },
                    ) { Text("Save") }
                    onDelete?.let { DeleteOverflowMenu(onDelete = it) }
                },
            )
        },
    ) { padding ->
        Column(
            Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState()).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            OutlinedTextField(registration, { registration = it }, label = { Text("Registration") },
                singleLine = true, modifier = Modifier.fillMaxWidth())
            OutlinedTextField(type, { type = it }, label = { Text("Type (e.g. SR22)") },
                singleLine = true, modifier = Modifier.fillMaxWidth())
            OutlinedTextField(usualBase, { usualBase = it }, label = { Text("Usual base (ICAO)") },
                singleLine = true, modifier = Modifier.fillMaxWidth())
            OutlinedTextField(owner, { owner = it }, label = { Text("Owner") },
                singleLine = true, modifier = Modifier.fillMaxWidth())
            OutlinedTextField(ownerAddress, { ownerAddress = it }, label = { Text("Owner address") },
                modifier = Modifier.fillMaxWidth())
            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text("Airplane", style = MaterialTheme.typography.bodyLarge)
                Switch(checked = isAirplane, onCheckedChange = { isAirplane = it })
            }
        }
    }
}
