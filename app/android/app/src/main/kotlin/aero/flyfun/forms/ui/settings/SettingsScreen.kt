package aero.flyfun.forms.ui.settings

import aero.flyfun.forms.R
import aero.flyfun.forms.auth.SignInProvider
import aero.flyfun.forms.ui.common.SignInButtons
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
import androidx.compose.ui.res.stringResource
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
    onSignIn: (SignInProvider) -> Unit,
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

    Scaffold(topBar = { TopAppBar(title = { Text(stringResource(R.string.settings_title)) }) }) { padding ->
        Column(
            Modifier.fillMaxSize().padding(padding).padding(16.dp).verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Card(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(16.dp)) {
                    Text(stringResource(R.string.settings_languages_you_speak), style = MaterialTheme.typography.titleMedium)
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
                        stringResource(R.string.settings_languages_footer),
                        style = MaterialTheme.typography.bodySmall,
                    )
                }
            }

            Card(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(16.dp), Arrangement.spacedBy(8.dp)) {
                    Text(stringResource(R.string.settings_move_my_data), style = MaterialTheme.typography.titleMedium)
                    Text(
                        stringResource(R.string.settings_move_my_data_footer),
                        style = MaterialTheme.typography.bodySmall,
                    )
                    Button(onClick = onExportEncrypted, enabled = state !is TransferState.Working) {
                        Text(stringResource(R.string.settings_export_encrypted_file))
                    }
                    OutlinedButton(onClick = onPickFile, enabled = state !is TransferState.Working) {
                        Text(stringResource(R.string.settings_import_from_a_file))
                    }
                }
            }

            Card(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(16.dp), Arrangement.spacedBy(8.dp)) {
                    Text(stringResource(R.string.settings_download_copy), style = MaterialTheme.typography.titleMedium)
                    Text(
                        stringResource(R.string.settings_download_copy_footer),
                        style = MaterialTheme.typography.bodySmall,
                    )
                    OutlinedButton(onClick = onExportPlain, enabled = state !is TransferState.Working) {
                        Text(stringResource(R.string.settings_export_unencrypted_json))
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
                OutlinedButton(onClick = onSignOut) { Text(stringResource(R.string.settings_sign_out)) }

                Card(Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(16.dp), Arrangement.spacedBy(8.dp)) {
                        Text(stringResource(R.string.settings_delete_account), style = MaterialTheme.typography.titleMedium)
                        Text(
                            deleteAccountError
                                ?: stringResource(R.string.settings_delete_account_footer),
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
                            ) { Text(stringResource(R.string.settings_delete_account)) }
                            if (deletingAccount) CircularProgressIndicator(Modifier.padding(start = 12.dp))
                        }
                    }
                }
            } else {
                // The way back for a pilot who chose "Enter data without
                // signing in": generating forms needs an account.
                Card(Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(16.dp), Arrangement.spacedBy(8.dp)) {
                        Text(stringResource(R.string.settings_not_signed_in), style = MaterialTheme.typography.titleMedium)
                        Text(
                            stringResource(R.string.settings_not_signed_in_footer),
                            style = MaterialTheme.typography.bodySmall,
                        )
                        SignInButtons(onSignIn)
                    }
                }
            }

            if (state is TransferState.Working) CircularProgressIndicator()
        }
    }

    if (confirmDeleteAccount) {
        AlertDialog(
            onDismissRequest = { confirmDeleteAccount = false },
            title = { Text(stringResource(R.string.settings_delete_account)) },
            text = { Text(stringResource(R.string.settings_delete_account_confirm_message)) },
            confirmButton = {
                TextButton(
                    onClick = { confirmDeleteAccount = false; onDeleteAccount() },
                    colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error),
                ) { Text(stringResource(R.string.settings_delete_my_account)) }
            },
            dismissButton = { TextButton(onClick = { confirmDeleteAccount = false }) { Text(stringResource(R.string.common_cancel)) } },
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
            title = { Text(if (state.passphrase != null) stringResource(R.string.settings_passphrase) else stringResource(R.string.settings_export_ready)) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    if (state.passphrase != null) {
                        Text(stringResource(R.string.settings_passphrase_instructions))
                        SelectionContainer {
                            Text(state.passphrase, style = MaterialTheme.typography.titleMedium)
                        }
                    } else {
                        Text(stringResource(R.string.settings_file_ready_not_encrypted, state.file.name))
                    }
                }
            },
            confirmButton = { TextButton(onClick = { onShare(state.file) }) { Text(stringResource(R.string.settings_share_file)) } },
            dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.common_done)) } },
        )

        is TransferState.NeedsPassword -> {
            var password by remember { mutableStateOf("") }
            AlertDialog(
                onDismissRequest = onDismiss,
                title = { Text(stringResource(R.string.settings_passphrase)) },
                text = {
                    OutlinedTextField(
                        value = password,
                        onValueChange = { password = it },
                        label = { Text(stringResource(R.string.settings_passphrase_from_other_device)) },
                        singleLine = true,
                    )
                },
                confirmButton = {
                    TextButton(
                        enabled = password.isNotBlank(),
                        onClick = { onSubmitPassword(password) },
                    ) { Text(stringResource(R.string.settings_open)) }
                },
                dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.common_cancel)) } },
            )
        }

        is TransferState.Previewed -> AlertDialog(
            onDismissRequest = onDismiss,
            title = { Text(stringResource(R.string.settings_import_this_file)) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(state.summary.describe())
                    Text(
                        stringResource(R.string.settings_import_nothing_removed),
                        style = MaterialTheme.typography.bodySmall,
                    )
                }
            },
            confirmButton = { TextButton(onClick = onConfirmImport) { Text(stringResource(R.string.settings_import)) } },
            dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.common_cancel)) } },
        )

        is TransferState.Imported -> AlertDialog(
            onDismissRequest = onDismiss,
            title = { Text(stringResource(R.string.settings_imported)) },
            text = { Text(state.summary.describe()) },
            confirmButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.common_ok)) } },
        )

        is TransferState.Failed -> AlertDialog(
            onDismissRequest = onDismiss,
            title = { Text(stringResource(R.string.settings_could_not_do_that)) },
            text = { Text(state.message) },
            confirmButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.common_ok)) } },
        )

        else -> Unit
    }
}
