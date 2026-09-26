package aero.flyfun.forms.ui.people

import aero.flyfun.forms.R
import aero.flyfun.forms.data.PersonEntity
import aero.flyfun.forms.logic.MRZFormat
import aero.flyfun.forms.logic.ScanContext
import aero.flyfun.forms.logic.ScanDecision
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AddCircleOutline
import androidx.compose.material.icons.filled.Badge
import androidx.compose.material.icons.filled.PersonAdd
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import java.time.format.DateTimeFormatter

/**
 * What a scan will do, chosen before anything is stored. Port of iOS
 * `MRZResultActionView`: the scanned fields, a warning when the document is
 * already on file, and the choices that fit where the scan started.
 *
 * Android adds one choice: a scan of a document the person already holds
 * offers to refresh it (a renewed expiry, say), where iOS offers nothing.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ScanResultSheet(
    decision: ScanDecision,
    people: Map<String, PersonEntity>,
    /** Fill the person from the scan, rename them with [overwriteName], and store the document with [addDocument]. */
    onApply: (personId: String, overwriteName: Boolean, addDocument: Boolean) -> Unit,
    onCreatePerson: () -> Unit,
    onCancel: () -> Unit,
) {
    val result = decision.result
    val duplicate = decision.duplicate
    val scannedName = "${result.givenNames} ${result.surname}".trim()

    ModalBottomSheet(onDismissRequest = onCancel, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
        Column(
            Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.people_scan_result), style = MaterialTheme.typography.titleLarge, modifier = Modifier.weight(1f))
                TextButton(onClick = onCancel) { Text(stringResource(R.string.people_cancel)) }
            }

            Section(stringResource(R.string.people_scanned_document))
            Field(stringResource(R.string.people_name), scannedName)
            Field(
                stringResource(R.string.people_document),
                "${stringResource(if (result.format == MRZFormat.TD1) R.string.people_id_card else R.string.people_doc_type_passport)} ${result.passportNumber}",
            )
            Field(stringResource(R.string.people_nationality), result.nationality)
            Field(stringResource(R.string.people_date_of_birth_title), result.dateOfBirth.format(DAY))
            Field(stringResource(R.string.people_expiry), result.expiryDate.format(DAY))

            if (duplicate != null) {
                Card(
                    colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.tertiaryContainer),
                    modifier = Modifier.fillMaxWidth().padding(16.dp),
                ) {
                    ListItem(
                        leadingContent = { Icon(Icons.Default.Warning, contentDescription = null) },
                        headlineContent = { Text(stringResource(R.string.people_document_already_exists)) },
                        supportingContent = people[duplicate.personId]?.let { { Text(stringResource(R.string.people_assigned_to, it.displayName)) } },
                    )
                }
            }

            when (val context = decision.context) {
                is ScanContext.ForPerson -> {
                    val person = people[context.personId]
                    val name = person?.displayName?.ifBlank { null } ?: stringResource(R.string.people_this_person)
                    val ownDuplicate = duplicate?.personId == context.personId
                    Section(stringResource(if (duplicate != null && !ownDuplicate) R.string.people_actions_document_exists else R.string.people_actions))
                    when {
                        duplicate == null ->
                            Action(Icons.Default.AddCircleOutline, stringResource(R.string.people_add_document_to, name)) { onApply(context.personId, false, true) }
                        ownDuplicate ->
                            Action(Icons.Default.Badge, stringResource(R.string.people_update_document_on, name)) { onApply(context.personId, false, true) }
                    }
                    if (decision.namesMismatch) {
                        if (duplicate == null) {
                            Action(Icons.Default.Badge, stringResource(R.string.people_add_document_update_name, scannedName)) {
                                onApply(context.personId, true, true)
                            }
                        }
                        Action(Icons.Default.PersonAdd, stringResource(R.string.people_create_new_person_instead), onCreatePerson)
                    }
                    if (duplicate != null && !ownDuplicate && !decision.namesMismatch) {
                        Text(
                            stringResource(
                                R.string.people_nothing_to_add,
                                people[duplicate.personId]?.displayName ?: stringResource(R.string.people_its_owner),
                            ),
                            style = MaterialTheme.typography.bodyMedium,
                            modifier = Modifier.padding(horizontal = 16.dp),
                        )
                    }
                }

                is ScanContext.ForDocument -> Unit // Not offered on Android: documents are scanned from their person.

                ScanContext.Standalone -> {
                    val matches = decision.matchingPeople.mapNotNull { people[it] }
                    if (matches.isNotEmpty()) {
                        Section(stringResource(R.string.people_matching_people))
                        matches.forEach { person ->
                            // Their own copy is refreshed; someone else's is not copied onto them.
                            val addDocument = duplicate == null || duplicate.personId == person.id
                            ListItem(
                                headlineContent = { Text(person.displayName) },
                                supportingContent = person.dateOfBirth?.let { { Text(stringResource(R.string.people_born, it.format(DAY))) } },
                                trailingContent = { Icon(Icons.Default.AddCircleOutline, contentDescription = stringResource(R.string.people_use)) },
                                modifier = Modifier.clickable { onApply(person.id, false, addDocument) },
                            )
                        }
                    }
                    Section(stringResource(if (matches.isEmpty()) R.string.people_actions else R.string.people_or))
                    Action(Icons.Default.PersonAdd, stringResource(R.string.people_create_new_person), onCreatePerson)
                }
            }
        }
    }
}

@Composable
private fun Section(title: String) {
    Text(
        title,
        style = MaterialTheme.typography.labelLarge,
        color = MaterialTheme.colorScheme.primary,
        modifier = Modifier.padding(start = 16.dp, top = 12.dp, bottom = 4.dp),
    )
}

@Composable
private fun Field(label: String, value: String) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 2.dp)) {
        Text(label, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f))
        Text(value, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun Action(icon: ImageVector, label: String, onClick: () -> Unit) {
    ListItem(
        leadingContent = { Icon(icon, contentDescription = null) },
        headlineContent = { Text(label, color = MaterialTheme.colorScheme.primary) },
        modifier = Modifier.clickable(onClick = onClick),
    )
}

private val DAY: DateTimeFormatter = DateTimeFormatter.ofPattern("d MMM yyyy")
