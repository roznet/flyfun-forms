package aero.flyfun.forms.ui.flights

import aero.flyfun.forms.R
import aero.flyfun.forms.logic.FlightExchange
import aero.flyfun.forms.logic.WeatherFlightSummary
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Download
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter

private val WHEN: DateTimeFormatter = DateTimeFormatter.ofPattern("d MMM yyyy HH:mm'Z'").withZone(ZoneOffset.UTC)

/**
 * The pilot's FlyFun Weather flights; the one picked comes back as a
 * `FlightExchange`. Port of iOS `WeatherFlightPickerView`.
 *
 * The calls run in this screen's scope, so leaving it mid-import cancels the
 * import rather than filling the flight after the picker has gone.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun WeatherFlightPickerScreen(
    load: suspend () -> List<WeatherFlightSummary>,
    export: suspend (String) -> FlightExchange,
    onImport: (FlightExchange) -> Unit,
    onCancel: () -> Unit,
) {
    var flights by remember { mutableStateOf<List<WeatherFlightSummary>?>(null) }
    var loadError by remember { mutableStateOf<String?>(null) }
    var attempt by remember { mutableIntStateOf(0) }
    var importing by remember { mutableStateOf<String?>(null) }
    var importError by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    val couldNotReach = stringResource(R.string.flights_could_not_reach_weather)
    val couldNotImport = stringResource(R.string.flights_could_not_import)

    LaunchedEffect(attempt) {
        loadError = null
        flights = null
        try {
            flights = load()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            loadError = e.message ?: couldNotReach
        }
    }

    BackHandler(onBack = onCancel)
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.flights_import_from_weather)) },
                navigationIcon = { IconButton(onClick = onCancel) { Icon(Icons.Default.Close, contentDescription = stringResource(R.string.flights_cancel)) } },
            )
        },
    ) { padding ->
        val loaded = flights
        when {
            loadError != null -> Centered(padding) {
                Text(stringResource(R.string.flights_couldnt_load), style = MaterialTheme.typography.titleMedium)
                Text(loadError.orEmpty(), style = MaterialTheme.typography.bodyMedium, textAlign = TextAlign.Center)
                OutlinedButton(onClick = { attempt++ }) { Text(stringResource(R.string.flights_retry)) }
            }
            loaded == null -> Centered(padding) {
                CircularProgressIndicator()
                Text(stringResource(R.string.flights_loading_your_flights), style = MaterialTheme.typography.bodyMedium)
            }
            loaded.isEmpty() -> Centered(padding) {
                Text(stringResource(R.string.flights_no_flights), style = MaterialTheme.typography.titleMedium)
                Text(
                    stringResource(R.string.flights_weather_empty),
                    style = MaterialTheme.typography.bodyMedium,
                    textAlign = TextAlign.Center,
                )
            }
            else -> LazyColumn(Modifier.fillMaxSize().padding(padding)) {
                items(loaded, key = { it.id }) { flight ->
                    ListItem(
                        headlineContent = { Text(flight.routeLabel, fontFamily = FontFamily.Monospace) },
                        supportingContent = { flight.departure?.let { Text(WHEN.format(it)) } },
                        trailingContent = {
                            if (importing == flight.id) {
                                CircularProgressIndicator(Modifier.size(24.dp))
                            } else {
                                Icon(Icons.Default.Download, contentDescription = null)
                            }
                        },
                        modifier = Modifier.clickable(enabled = importing == null) {
                            importing = flight.id
                            scope.launch {
                                try {
                                    onImport(export(flight.id))
                                } catch (e: CancellationException) {
                                    throw e
                                } catch (e: Exception) {
                                    importError = e.message ?: couldNotImport
                                } finally {
                                    importing = null
                                }
                            }
                        },
                    )
                    HorizontalDivider()
                }
            }
        }
    }

    importError?.let { message ->
        AlertDialog(
            onDismissRequest = { importError = null },
            title = { Text(stringResource(R.string.flights_import_failed)) },
            text = { Text(message) },
            confirmButton = { TextButton(onClick = { importError = null }) { Text(stringResource(R.string.flights_ok)) } },
        )
    }
}

@Composable
private fun Centered(padding: androidx.compose.foundation.layout.PaddingValues, content: @Composable () -> Unit) {
    Column(
        Modifier.fillMaxSize().padding(padding).padding(32.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp, Alignment.CenterVertically),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) { content() }
}
