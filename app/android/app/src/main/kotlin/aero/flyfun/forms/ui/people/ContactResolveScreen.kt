package aero.flyfun.forms.ui.people

import aero.flyfun.forms.data.PersonEntity
import aero.flyfun.forms.logic.ContactImport
import aero.flyfun.forms.logic.ImportedContact
import aero.flyfun.forms.ui.common.ChoiceField
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.PersonAdd
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import java.time.format.DateTimeFormatter

/**
 * A contact picked from the address book: create a person from it, or fold
 * it into someone already here. Port of iOS `ContactResolveView`.
 *
 * With several phones, e-mails or addresses the pilot picks the one to keep.
 * Merging either fills only what the person lacks, or overrides everything the
 * contact has.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ContactResolveScreen(
    contact: ImportedContact,
    people: List<PersonEntity>,
    /** Store a new person, or the merged one, and open them. */
    onResult: (PersonEntity) -> Unit,
    onCancel: () -> Unit,
) {
    BackHandler(onBack = onCancel)
    var phone by rememberSaveable { mutableStateOf(contact.phones.firstOrNull().orEmpty()) }
    var email by rememberSaveable { mutableStateOf(contact.emails.firstOrNull().orEmpty()) }
    var address by rememberSaveable { mutableStateOf(contact.addresses.firstOrNull().orEmpty()) }
    var override by rememberSaveable { mutableStateOf(false) }
    val matches = remember(contact, people) {
        val byId = people.associateBy { it.id }
        ContactImport.matches(contact, people.map { ContactImport.Candidate(it.id, it.firstName, it.lastName) })
            .mapNotNull(byId::get)
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Import Contact") },
                navigationIcon = { IconButton(onClick = onCancel) { Icon(Icons.Default.Close, contentDescription = "Cancel") } },
            )
        },
    ) { padding ->
        Column(
            Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Section("Contact")
            Column(Modifier.padding(horizontal = 16.dp)) {
                Line("Name", "${contact.firstName} ${contact.lastName}".trim())
                Pick("Phone", contact.phones, phone) { phone = it }
                Pick("Email", contact.emails, email) { email = it }
                contact.dateOfBirth?.let { Line("Date of Birth", it.format(DAY)) }
                Pick("Address", contact.addresses, address) { address = it }
            }

            ListItem(
                leadingContent = { Icon(Icons.Default.PersonAdd, contentDescription = null) },
                headlineContent = { Text("Create as New Person", color = MaterialTheme.colorScheme.primary) },
                modifier = Modifier.clickable {
                    onResult(
                        PersonEntity(
                            firstName = contact.firstName,
                            lastName = contact.lastName,
                            phone = phone.ifBlank { null },
                            email = email.ifBlank { null },
                            address = address.ifBlank { null },
                            dateOfBirth = contact.dateOfBirth,
                        ),
                    )
                },
            )

            if (matches.isNotEmpty()) {
                Section("Update Existing")
                SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth().padding(horizontal = 16.dp)) {
                    listOf(false to "Fill Missing Only", true to "Override All").forEachIndexed { index, (value, label) ->
                        SegmentedButton(
                            selected = override == value,
                            onClick = { override = value },
                            shape = SegmentedButtonDefaults.itemShape(index = index, count = 2),
                        ) { Text(label) }
                    }
                }
                matches.forEach { person ->
                    ListItem(
                        headlineContent = { Text(person.displayName) },
                        supportingContent = listOfNotNull(person.phone, person.email).joinToString(" · ")
                            .takeIf { it.isNotEmpty() }?.let { { Text(it, maxLines = 1) } },
                        trailingContent = { Icon(Icons.AutoMirrored.Filled.ArrowForward, contentDescription = "Update") },
                        modifier = Modifier.clickable {
                            val merged = ContactImport.merge(
                                person.fields(), contact,
                                phone = phone, email = email, address = address, override = override,
                            )
                            onResult(
                                person.copy(
                                    firstName = merged.firstName,
                                    lastName = merged.lastName,
                                    phone = merged.phone?.ifBlank { null },
                                    email = merged.email?.ifBlank { null },
                                    address = merged.address?.ifBlank { null },
                                    dateOfBirth = merged.dateOfBirth,
                                ),
                            )
                        },
                    )
                }
            }
        }
    }
}

private fun PersonEntity.fields() = aero.flyfun.forms.logic.ContactFields(
    firstName = firstName,
    lastName = lastName,
    phone = phone,
    email = email,
    address = address,
    dateOfBirth = dateOfBirth,
)

@Composable
private fun Section(title: String) {
    Text(
        title,
        style = MaterialTheme.typography.labelLarge,
        color = MaterialTheme.colorScheme.primary,
        modifier = Modifier.padding(start = 16.dp, top = 16.dp, bottom = 4.dp),
    )
}

@Composable
private fun Line(label: String, value: String) {
    Row(Modifier.fillMaxWidth().padding(vertical = 8.dp)) {
        Text(label, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
        Text(value, style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

/** One value shown, or a choice when the contact has several. */
@Composable
private fun Pick(label: String, values: List<String>, selected: String, onSelect: (String) -> Unit) {
    when {
        values.size > 1 -> ChoiceField(label, selected, values, { it }, onSelect)
        values.size == 1 -> Line(label, values.first())
    }
}

private val DAY: DateTimeFormatter = DateTimeFormatter.ofPattern("d MMM yyyy")
