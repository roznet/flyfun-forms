package aero.flyfun.forms.ui.flights

import aero.flyfun.forms.R
import aero.flyfun.forms.logic.AirportSummary
import aero.flyfun.forms.logic.RecentRoute
import aero.flyfun.forms.ui.people.SearchField
import androidx.activity.compose.BackHandler
import androidx.annotation.StringRes
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedCard
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.delay
import java.time.ZoneId
import java.time.format.DateTimeFormatter

/** What the pickers need from the airport database. */
class AirportLookup(
    val search: suspend (String) -> List<AirportSummary>,
    val airport: suspend (String) -> AirportSummary?,
)

/**
 * The route, chosen from the bundled airport database. Port of iOS
 * `AirportPickerView`: FROM and TO fields, the active one filled from a search,
 * the next empty one taken over after a pick, and recent routes in one tap.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RoutePickerScreen(
    origin: String,
    destination: String,
    lookup: AirportLookup,
    recentRoutes: (String) -> List<RecentRoute>,
    onChange: (origin: String, destination: String) -> Unit,
    onDone: () -> Unit,
) {
    BackHandler(onBack = onDone)
    var editingOrigin by rememberSaveable { mutableStateOf(origin.isEmpty() || destination.isNotEmpty()) }
    var query by rememberSaveable { mutableStateOf("") }
    val results = rememberAirportSearch(query, lookup)

    fun pick(icao: String) {
        query = ""
        if (editingOrigin) {
            onChange(icao, destination)
            if (destination.isEmpty()) editingOrigin = false
        } else {
            onChange(origin, icao)
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.flights_route)) },
                navigationIcon = { IconButton(onClick = onDone) { Icon(Icons.Default.Close, contentDescription = stringResource(R.string.flights_close)) } },
                actions = { TextButton(onClick = onDone) { Text(stringResource(R.string.flights_done)) } },
            )
        },
    ) { padding ->
        Column(Modifier.fillMaxSize().padding(padding)) {
            Row(
                Modifier.fillMaxWidth().padding(16.dp),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                RouteEnd(stringResource(R.string.flights_route_from), origin, lookup, active = editingOrigin, Modifier.weight(1f)) {
                    editingOrigin = true
                    query = ""
                }
                Icon(Icons.AutoMirrored.Filled.ArrowForward, contentDescription = null)
                RouteEnd(stringResource(R.string.flights_route_to), destination, lookup, active = !editingOrigin, Modifier.weight(1f)) {
                    editingOrigin = false
                    query = ""
                }
            }
            SearchField(query, { query = it }, stringResource(R.string.flights_search_airport))
            LazyColumn(Modifier.fillMaxSize()) {
                airportResults(query, results, if (editingOrigin) origin else destination, ::pick)
                val routes = recentRoutes(query)
                if (routes.isNotEmpty()) {
                    header(R.string.flights_recent_routes)
                    items(routes, key = { "route:${it.origin}-${it.destination}" }) { route ->
                        ListItem(
                            headlineContent = {
                                Text("${route.origin} → ${route.destination}", fontFamily = FontFamily.Monospace, fontWeight = FontWeight.Bold)
                            },
                            trailingContent = { Text(DAY.format(route.date)) },
                            modifier = Modifier.clickable {
                                query = ""
                                onChange(route.origin, route.destination)
                            },
                        )
                    }
                }
            }
        }
    }
}

/**
 * One airport, as for an aircraft's usual base. Port of iOS
 * `SingleAirportPickerView`.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AirportPickerScreen(
    title: String,
    selected: String,
    lookup: AirportLookup,
    onPick: (String) -> Unit,
    onDone: () -> Unit,
) {
    BackHandler(onBack = onDone)
    var query by rememberSaveable { mutableStateOf("") }
    val results = rememberAirportSearch(query, lookup)
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(title) },
                navigationIcon = { IconButton(onClick = onDone) { Icon(Icons.Default.Close, contentDescription = stringResource(R.string.flights_close)) } },
                actions = {
                    if (selected.isNotEmpty()) TextButton(onClick = { onPick(""); onDone() }) { Text(stringResource(R.string.flights_clear)) }
                },
            )
        },
    ) { padding ->
        Column(Modifier.fillMaxSize().padding(padding)) {
            SearchField(query, { query = it }, stringResource(R.string.flights_search_airport))
            LazyColumn(Modifier.fillMaxSize()) {
                airportResults(query, results, selected) { onPick(it); onDone() }
            }
        }
    }
}

/** Searches as the pilot types, a moment after they stop. */
@Composable
private fun rememberAirportSearch(query: String, lookup: AirportLookup): List<AirportSummary> {
    var results by remember { mutableStateOf(emptyList<AirportSummary>()) }
    LaunchedEffect(query) {
        if (query.isBlank()) {
            results = emptyList()
            return@LaunchedEffect
        }
        delay(150)
        results = lookup.search(query)
    }
    return results
}

private fun LazyListScope.airportResults(
    query: String,
    results: List<AirportSummary>,
    selected: String,
    onPick: (String) -> Unit,
) {
    if (results.isNotEmpty()) {
        header(R.string.flights_airports)
        items(results, key = { "airport:${it.icao}" }) { airport ->
            ListItem(
                leadingContent = { Text(airport.icao, fontFamily = FontFamily.Monospace, fontWeight = FontWeight.Bold) },
                headlineContent = { Text(airport.name, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                supportingContent = { Text(listOf(airport.city, airport.country).filter { it.isNotBlank() }.joinToString(", ")) },
                trailingContent = if (airport.icao == selected) {
                    { Icon(Icons.Default.Check, contentDescription = stringResource(R.string.flights_selected)) }
                } else {
                    null
                },
                modifier = Modifier.clickable { onPick(airport.icao) },
            )
        }
    }
    // A strip or a new airfield the bundled database does not know yet.
    val code = query.trim().uppercase()
    if (code.length == 4 && code.all { it.isLetterOrDigit() } && results.none { it.icao == code }) {
        item(key = "use-code") {
            ListItem(
                headlineContent = { Text(stringResource(R.string.flights_use_code, code)) },
                supportingContent = { Text(stringResource(R.string.flights_not_in_database)) },
                modifier = Modifier.clickable { onPick(code) },
            )
        }
    }
}

@Composable
private fun RouteEnd(
    label: String,
    icao: String,
    lookup: AirportLookup,
    active: Boolean,
    modifier: Modifier,
    onClick: () -> Unit,
) {
    var name by remember(icao) { mutableStateOf<String?>(null) }
    LaunchedEffect(icao) { name = lookup.airport(icao)?.name }
    OutlinedCard(
        onClick = onClick,
        modifier = modifier,
        border = BorderStroke(
            if (active) 2.dp else 1.dp,
            if (active) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outlineVariant,
        ),
    ) {
        Column(Modifier.fillMaxWidth().padding(8.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Text(label, style = MaterialTheme.typography.labelSmall)
            Text(
                icao.ifEmpty { "----" },
                style = MaterialTheme.typography.titleLarge,
                fontFamily = FontFamily.Monospace,
                fontWeight = FontWeight.Bold,
            )
            name?.let { Text(it, style = MaterialTheme.typography.bodySmall, maxLines = 1, overflow = TextOverflow.Ellipsis) }
        }
    }
}

private fun LazyListScope.header(@StringRes text: Int) {
    item(key = "header:$text") {
        Text(
            stringResource(text),
            style = MaterialTheme.typography.labelLarge,
            color = MaterialTheme.colorScheme.primary,
            modifier = Modifier.padding(start = 16.dp, top = 16.dp, bottom = 4.dp),
        )
    }
}

private val DAY: DateTimeFormatter = DateTimeFormatter.ofPattern("d MMM yyyy").withZone(ZoneId.systemDefault())
