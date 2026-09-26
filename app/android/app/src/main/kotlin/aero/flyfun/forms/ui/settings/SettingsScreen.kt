package aero.flyfun.forms.ui.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import java.io.File

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
) {
    Scaffold(topBar = { TopAppBar(title = { Text("Settings") }) }) { padding ->
        Column(
            Modifier.fillMaxSize().padding(padding).padding(16.dp).verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
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

            if (signedIn) {
                OutlinedButton(onClick = onSignOut) { Text("Sign out") }
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

    when (state) {
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
