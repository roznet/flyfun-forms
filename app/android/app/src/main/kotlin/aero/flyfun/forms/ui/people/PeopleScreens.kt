package aero.flyfun.forms.ui.people

import aero.flyfun.forms.data.PersonEntity
import aero.flyfun.forms.data.PersonWithDocuments
import aero.flyfun.forms.data.TravelDocumentEntity
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.Card
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
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import java.time.LocalDate
import java.time.format.DateTimeFormatter

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PeopleListScreen(
    people: List<PersonWithDocuments>,
    onOpen: (String) -> Unit,
    onAdd: () -> Unit,
) {
    Scaffold(
        topBar = { TopAppBar(title = { Text("People") }) },
        floatingActionButton = {
            FloatingActionButton(onClick = onAdd) {
                Icon(Icons.Default.Add, contentDescription = "Add person")
            }
        },
    ) { padding ->
        if (people.isEmpty()) {
            Column(
                modifier = Modifier.fillMaxSize().padding(padding).padding(32.dp),
                verticalArrangement = Arrangement.Center,
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Text("No crew or passengers yet", style = MaterialTheme.typography.titleMedium)
                Spacer(Modifier.height(8.dp))
                Text(
                    "Add the people you fly with, and their passports, so forms fill themselves.",
                    style = MaterialTheme.typography.bodyMedium,
                )
            }
        } else {
            LazyColumn(modifier = Modifier.fillMaxSize().padding(padding)) {
                items(people, key = { it.person.id }) { row ->
                    ListItem(
                        headlineContent = { Text(row.person.displayName.ifBlank { "New Person" }) },
                        supportingContent = {
                            val active = row.documents.count { it.isActive && it.deletedAt == null }
                            Text(
                                buildString {
                                    if (row.person.isUsualCrew) append("Usual crew")
                                    if (row.person.isUsualCrew && active > 0) append(" · ")
                                    if (active > 0) append("$active document${if (active == 1) "" else "s"}")
                                    if (isEmpty()) append("No documents")
                                },
                            )
                        },
                        modifier = Modifier.clickable { onOpen(row.person.id) },
                    )
                    HorizontalDivider()
                }
            }
        }
    }
}

private val dateFormat: DateTimeFormatter = DateTimeFormatter.ofPattern("d MMM yyyy")

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PersonEditScreen(
    initial: PersonWithDocuments?,
    onSave: (PersonEntity) -> Unit,
    onAddDocument: (String, String, String?, LocalDate?) -> Unit,
    onDeleteDocument: (String) -> Unit,
    onBack: () -> Unit,
) {
    val existing = initial?.person
    var firstName by remember { mutableStateOf(existing?.firstName.orEmpty()) }
    var lastName by remember { mutableStateOf(existing?.lastName.orEmpty()) }
    var email by remember { mutableStateOf(existing?.email.orEmpty()) }
    var phone by remember { mutableStateOf(existing?.phone.orEmpty()) }
    var usualCrew by remember { mutableStateOf(existing?.isUsualCrew ?: false) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(if (existing == null) "New Person" else "Edit Person") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.Default.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    TextButton(onClick = {
                        onSave(
                            (existing ?: PersonEntity()).copy(
                                firstName = firstName.trim(),
                                lastName = lastName.trim(),
                                email = email.trim().ifBlank { null },
                                phone = phone.trim().ifBlank { null },
                                isUsualCrew = usualCrew,
                            ),
                        )
                    }) { Text("Save") }
                },
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier.fillMaxSize().padding(padding).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            OutlinedTextField(
                value = firstName,
                onValueChange = { firstName = it },
                label = { Text("First name") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )
            OutlinedTextField(
                value = lastName,
                onValueChange = { lastName = it },
                label = { Text("Last name") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )
            OutlinedTextField(
                value = email,
                onValueChange = { email = it },
                label = { Text("Email") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )
            OutlinedTextField(
                value = phone,
                onValueChange = { phone = it },
                label = { Text("Phone") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text("Usual crew", style = MaterialTheme.typography.bodyLarge)
                Switch(checked = usualCrew, onCheckedChange = { usualCrew = it })
            }

            if (existing != null) {
                Spacer(Modifier.height(8.dp))
                Text("Travel documents", style = MaterialTheme.typography.titleMedium)
                DocumentSection(
                    documents = initial.documents.filter { it.deletedAt == null },
                    onAdd = { type, number, country, expiry ->
                        onAddDocument(type, number, country, expiry)
                    },
                    onDelete = onDeleteDocument,
                )
            } else {
                Text(
                    "Save this person first, then add their passport or ID card.",
                    style = MaterialTheme.typography.bodySmall,
                )
            }
        }
    }
}

@Composable
private fun DocumentSection(
    documents: List<TravelDocumentEntity>,
    onAdd: (String, String, String?, LocalDate?) -> Unit,
    onDelete: (String) -> Unit,
) {
    var number by remember { mutableStateOf("") }
    var country by remember { mutableStateOf("") }

    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        documents.forEach { doc ->
            Card(modifier = Modifier.fillMaxWidth()) {
                ListItem(
                    headlineContent = {
                        Text("${doc.docType} (${doc.issuingCountry ?: "?"})")
                    },
                    supportingContent = {
                        Text(
                            buildString {
                                append(doc.docNumber)
                                doc.expiryDate?.let { append(" · expires ${it.format(dateFormat)}") }
                                if (!doc.isActive) append(" · inactive")
                            },
                        )
                    },
                    trailingContent = {
                        IconButton(onClick = { onDelete(doc.id) }) {
                            Icon(Icons.Default.Delete, contentDescription = "Remove document")
                        }
                    },
                )
            }
        }

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            OutlinedTextField(
                value = number,
                onValueChange = { number = it },
                label = { Text("Document number") },
                singleLine = true,
                modifier = Modifier.weight(2f),
            )
            OutlinedTextField(
                value = country,
                onValueChange = { if (it.length <= 3) country = it.uppercase() },
                label = { Text("ISO-3") },
                singleLine = true,
                modifier = Modifier.weight(1f),
            )
        }
        TextButton(
            enabled = number.isNotBlank(),
            onClick = {
                onAdd("Passport", number.trim(), country.trim().ifBlank { null }, null)
                number = ""
                country = ""
            },
        ) { Text("Add passport") }
    }
}
