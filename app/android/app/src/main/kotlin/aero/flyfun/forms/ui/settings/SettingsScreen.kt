package aero.flyfun.forms.ui.settings

import aero.flyfun.forms.logic.SpokenLanguages
import aero.flyfun.forms.net.ApiConfig
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
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
import java.io.File

/**
 * What a pilot can hand a passenger (GDPR Art. 14): their details reach the app
 * from the pilot, not from them, so the duty to tell them sits with the pilot.
 * See legal/GDPR.md §1. "Not backed up or synced" holds because
 * data_extraction_rules excludes everything from cloud backup and device
 * transfer; keep the two in step.
 */
const val PASSENGER_PRIVACY_NOTE = """How I use your details for this flight

I keep your name and travel-document details in the FlightForms app on my phone. They are not backed up or synced anywhere. I use them only to fill in the customs, immigration and airport forms this flight requires, and I send those forms to the authorities that ask for them. The FlightForms server fills each form and keeps no copy. Ask me any time to see, correct or delete your details.

More: ${ApiConfig.PRIVACY_URL}#passengers"""

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    state: TransferState,
    signedIn: Boolean,
    onSignIn: () -> Unit,
    onExportEncrypted: () -> Unit,
    onExportPlain: () -> Unit,
    onPickFile: () -> Unit,
    onSubmitPassword: (String) -> Unit,
    onConfirmImport: () -> Unit,
    onShare: (File) -> Unit,
    onSignOut: () -> Unit,
    onDismiss: () -> Unit,
    spokenLanguages: Set<String>,
    onSetSpeaks: (code: String, speaks: Boolean) -> Unit,
    deletingAccount: Boolean,
    deleteAccountError: String?,
    onDeleteAccount: () -> Unit,
    onOpenPrivacyPolicy: () -> Unit,
    onSharePassengerNote: () -> Unit,
    onEraseAll: () -> Unit,
) {
    var confirmDeleteAccount by remember { mutableStateOf(false) }
    var confirmEraseAll by remember { mutableStateOf(false) }

    Scaffold(topBar = { TopAppBar(title = { Text("Settings") }) }) { padding ->
        Column(
            Modifier.fillMaxSize().padding(padding).padding(16.dp).verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Card(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(16.dp)) {
                    Text("Languages you speak", style = MaterialTheme.typography.titleMedium)
                    SpokenLanguages.ALL.forEach { (code, name) ->
                        Row(
                            Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Text(name, style = MaterialTheme.typography.bodyLarge)
                            Switch(checked = code in spokenLanguages, onCheckedChange = { onSetSpeaks(code, it) })
                        }
                    }
                    Text(
                        "When an airport's local language matches one you speak, emails are written " +
                            "in that language. Otherwise English is used.",
                        style = MaterialTheme.typography.bodySmall,
                    )
                }
            }

            Card(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(16.dp), Arrangement.spacedBy(8.dp)) {
                    Text("Move my data", style = MaterialTheme.typography.titleMedium)
                    Text(
                        "Creates one encrypted file holding your people, aircraft and flights, " +
                            "protected by a passphrase shown once. Use it to move everything to " +
                            "another device.",
                        style = MaterialTheme.typography.bodySmall,
                    )
                    Button(onClick = onExportEncrypted, enabled = state !is TransferState.Working) {
                        Text("Export encrypted file")
                    }
                    OutlinedButton(onClick = onPickFile, enabled = state !is TransferState.Working) {
                        Text("Import from a file")
                    }
                }
            }

            Card(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(16.dp), Arrangement.spacedBy(8.dp)) {
                    Text("Download a copy of my data", style = MaterialTheme.typography.titleMedium)
                    Text(
                        "A plain JSON copy of everything this app holds about you, for your own " +
                            "records. It is NOT encrypted, and it contains passport details - " +
                            "keep it somewhere safe.",
                        style = MaterialTheme.typography.bodySmall,
                    )
                    OutlinedButton(onClick = onExportPlain, enabled = state !is TransferState.Working) {
                        Text("Export unencrypted JSON")
                    }
                }
            }

            Card(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(16.dp), Arrangement.spacedBy(8.dp)) {
                    Text("Privacy", style = MaterialTheme.typography.titleMedium)
                    OutlinedButton(onClick = onOpenPrivacyPolicy) { Text("Privacy policy") }
                    OutlinedButton(onClick = onSharePassengerNote) { Text("Privacy note for passengers") }
                    Text(
                        "Your passengers' details come from you, not from them. Share this note " +
                            "so they know how their details are used.",
                        style = MaterialTheme.typography.bodySmall,
                    )
                }
            }

            Card(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(16.dp), Arrangement.spacedBy(8.dp)) {
                    Text("Delete all data", style = MaterialTheme.typography.titleMedium)
                    Text(
                        "Removes every person, document, aircraft, flight and trip from this phone, " +
                            "with any generated forms and exports. You stay signed in.",
                        style = MaterialTheme.typography.bodySmall,
                    )
                    OutlinedButton(
                        onClick = { confirmEraseAll = true },
                        enabled = state !is TransferState.Working,
                        colors = ButtonDefaults.outlinedButtonColors(
                            contentColor = MaterialTheme.colorScheme.error,
                        ),
                    ) { Text("Delete all data") }
                }
            }

            if (signedIn) {
                OutlinedButton(onClick = onSignOut) { Text("Sign out") }

                Card(Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(16.dp), Arrangement.spacedBy(8.dp)) {
                        Text("Delete account", style = MaterialTheme.typography.titleMedium)
                        Text(
                            deleteAccountError
                                ?: "Permanently deletes your FlightForms account and its usage records " +
                                "on the server. People, aircraft, flights and trips stay on this phone - " +
                                "use Delete all data to remove them.",
                            style = MaterialTheme.typography.bodySmall,
                            color = if (deleteAccountError != null) MaterialTheme.colorScheme.error
                            else MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            OutlinedButton(
                                onClick = { confirmDeleteAccount = true },
                                enabled = !deletingAccount,
                                colors = ButtonDefaults.outlinedButtonColors(
                                    contentColor = MaterialTheme.colorScheme.error,
                                ),
                            ) { Text("Delete account") }
                            if (deletingAccount) CircularProgressIndicator(Modifier.padding(start = 12.dp))
                        }
                    }
                }
            } else {
                // The way back for a pilot who chose "Enter data without
                // signing in": generating forms needs an account.
                Card(Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(16.dp), Arrangement.spacedBy(8.dp)) {
                        Text("Not signed in", style = MaterialTheme.typography.titleMedium)
                        Text(
                            "Sign in to load each airport's forms and generate them. " +
                                "Your people, aircraft and flights stay on this device either way.",
                            style = MaterialTheme.typography.bodySmall,
                        )
                        Button(onClick = onSignIn) { Text("Sign in with Google") }
                    }
                }
            }

            if (state is TransferState.Working) CircularProgressIndicator()
        }
    }

    if (confirmDeleteAccount) {
        AlertDialog(
            onDismissRequest = { confirmDeleteAccount = false },
            title = { Text("Delete account") },
            text = {
                Text(
                    "Deletes your FlightForms account and its usage records on the server. " +
                        "This cannot be undone.\n\nPeople, aircraft, flights and trips stay on this " +
                        "phone. To remove them too, use Delete all data.",
                )
            },
            confirmButton = {
                TextButton(
                    onClick = { confirmDeleteAccount = false; onDeleteAccount() },
                    colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error),
                ) { Text("Delete my account") }
            },
            dismissButton = { TextButton(onClick = { confirmDeleteAccount = false }) { Text("Cancel") } },
        )
    }

    if (confirmEraseAll) {
        AlertDialog(
            onDismissRequest = { confirmEraseAll = false },
            title = { Text("Delete all data?") },
            text = {
                Text(
                    "Deletes all people, documents, aircraft, flights and trips from this phone. " +
                        "This cannot be undone. Your FlightForms account is not affected.",
                )
            },
            confirmButton = {
                TextButton(
                    onClick = { confirmEraseAll = false; onEraseAll() },
                    colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error),
                ) { Text("Delete all data") }
            },
            dismissButton = { TextButton(onClick = { confirmEraseAll = false }) { Text("Cancel") } },
        )
    }

    when (state) {
        TransferState.Erased -> AlertDialog(
            onDismissRequest = onDismiss,
            title = { Text("Data deleted") },
            text = { Text("All people, documents, aircraft, flights and trips have been removed from this phone.") },
            confirmButton = { TextButton(onClick = onDismiss) { Text("OK") } },
        )

        is TransferState.Exported -> AlertDialog(
            onDismissRequest = onDismiss,
            title = { Text(if (state.passphrase != null) "Passphrase" else "Export ready") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    if (state.passphrase != null) {
                        Text("Type this on the other device to open the file. It is not stored anywhere, so write it down now.")
                        SelectionContainer {
                            Text(state.passphrase, style = MaterialTheme.typography.titleMedium)
                        }
                    } else {
                        Text("${state.file.name} is ready. It is not encrypted.")
                    }
                }
            },
            confirmButton = { TextButton(onClick = { onShare(state.file) }) { Text("Share file") } },
            dismissButton = { TextButton(onClick = onDismiss) { Text("Done") } },
        )

        is TransferState.NeedsPassword -> {
            var password by remember { mutableStateOf("") }
            AlertDialog(
                onDismissRequest = onDismiss,
                title = { Text("Passphrase") },
                text = {
                    OutlinedTextField(
                        value = password,
                        onValueChange = { password = it },
                        label = { Text("Passphrase from the other device") },
                        singleLine = true,
                    )
                },
                confirmButton = {
                    TextButton(
                        enabled = password.isNotBlank(),
                        onClick = { onSubmitPassword(password) },
                    ) { Text("Open") }
                },
                dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
            )
        }

        is TransferState.Previewed -> AlertDialog(
            onDismissRequest = onDismiss,
            title = { Text("Import this file?") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(state.summary.describe())
                    Text(
                        "Nothing already on this device is removed unless the file says it was deleted.",
                        style = MaterialTheme.typography.bodySmall,
                    )
                }
            },
            confirmButton = { TextButton(onClick = onConfirmImport) { Text("Import") } },
            dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
        )

        is TransferState.Imported -> AlertDialog(
            onDismissRequest = onDismiss,
            title = { Text("Imported") },
            text = { Text(state.summary.describe()) },
            confirmButton = { TextButton(onClick = onDismiss) { Text("OK") } },
        )

        is TransferState.Failed -> AlertDialog(
            onDismissRequest = onDismiss,
            title = { Text("Could not do that") },
            text = { Text(state.message) },
            confirmButton = { TextButton(onClick = onDismiss) { Text("OK") } },
        )

        else -> Unit
    }
}
