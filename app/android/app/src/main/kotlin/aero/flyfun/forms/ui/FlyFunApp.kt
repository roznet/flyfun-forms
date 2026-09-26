package aero.flyfun.forms.ui

import aero.flyfun.forms.R
import aero.flyfun.forms.auth.AuthService
import aero.flyfun.forms.auth.SignInProvider
import aero.flyfun.forms.ui.common.SignInButtons
import aero.flyfun.forms.auth.TokenStore
import aero.flyfun.forms.data.AircraftEntity
import aero.flyfun.forms.data.FlightEntity
import aero.flyfun.forms.data.FlightRepository
import aero.flyfun.forms.data.FlyFunDatabase
import aero.flyfun.forms.data.PeopleRepository
import aero.flyfun.forms.data.PersonEntity
import aero.flyfun.forms.data.PersonWithDocuments
import aero.flyfun.forms.data.Preferences
import aero.flyfun.forms.data.RoomFlightRepository
import aero.flyfun.forms.data.DataTransfer
import aero.flyfun.forms.data.RoomPeopleRepository
import aero.flyfun.forms.data.TravelDocumentEntity
import aero.flyfun.forms.net.ApiClient
import aero.flyfun.forms.ui.aircraft.AircraftEditScreen
import aero.flyfun.forms.ui.aircraft.AircraftListScreen
import aero.flyfun.forms.ui.aircraft.AircraftViewModel
import aero.flyfun.forms.data.AirportDatabase
import aero.flyfun.forms.ui.flights.AirportLookup
import aero.flyfun.forms.ui.flights.FlightEditScreen
import aero.flyfun.forms.ui.flights.RoutePickerScreen
import aero.flyfun.forms.ui.flights.NewFlightScreen
import aero.flyfun.forms.ui.flights.NewFlightStep
import aero.flyfun.forms.ui.flights.PastFlightPickerScreen
import aero.flyfun.forms.ui.flights.PastFlightRow
import aero.flyfun.forms.ui.flights.WeatherFlightPickerScreen
import aero.flyfun.forms.ui.flights.SuggestionChoice
import aero.flyfun.forms.logic.PeopleSuggestion
import aero.flyfun.forms.ui.flights.FlightListScreen
import aero.flyfun.forms.ui.flights.FlightsViewModel
import aero.flyfun.forms.ui.people.AddPersonActions
import aero.flyfun.forms.ui.people.PeopleListScreen
import aero.flyfun.forms.ui.people.PeoplePickerScreen
import aero.flyfun.forms.ui.people.ScanResultSheet
import aero.flyfun.forms.ui.people.ContactResolveScreen
import aero.flyfun.forms.contacts.ContactReader
import aero.flyfun.forms.logic.ScanContext
import aero.flyfun.forms.ui.people.PeopleViewModel
import aero.flyfun.forms.scan.ScanScreen
import aero.flyfun.forms.ui.webform.WebFormScreen
import aero.flyfun.forms.ui.people.DocumentEditScreen
import aero.flyfun.forms.ui.people.PersonEditScreen
import aero.flyfun.forms.ui.settings.DataTransferViewModel
import aero.flyfun.forms.ui.settings.SettingsScreen
import android.content.Context
import android.content.Intent
import androidx.core.content.FileProvider
import androidx.compose.animation.EnterTransition
import androidx.compose.animation.ExitTransition
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AirplanemodeActive
import androidx.compose.material.icons.filled.Flight
import androidx.compose.material.icons.filled.People
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.adaptive.currentWindowAdaptiveInfo
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteScaffold
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteScaffoldDefaults
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteType
import androidx.compose.material3.SnackbarDuration
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.SnackbarResult
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.annotation.StringRes
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavBackStackEntry
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

/**
 * Hand-rolled factory rather than a DI framework: the graph is one database,
 * three repositories and an API client. Hilt would add more moving parts than
 * the app has objects.
 */
private class Factory(
    private val people: PeopleRepository,
    private val flights: FlightRepository,
    private val api: ApiClient,
    private val cacheDir: File,
    private val transfer: DataTransfer,
    private val appVersion: String,
    private val preferences: Preferences,
    private val airports: AirportDatabase,
    private val resources: android.content.res.Resources,
) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T = when {
        modelClass.isAssignableFrom(PeopleViewModel::class.java) -> PeopleViewModel(people, flights, resources) as T
        modelClass.isAssignableFrom(AircraftViewModel::class.java) -> AircraftViewModel(flights) as T
        modelClass.isAssignableFrom(FlightsViewModel::class.java) ->
            FlightsViewModel(flights, people, api, cacheDir, { preferences.spokenLanguages.value }, airports, resources) as T
        modelClass.isAssignableFrom(DataTransferViewModel::class.java) ->
            DataTransferViewModel(transfer, cacheDir, appVersion, resources) as T
        else -> error("Unknown ViewModel ${modelClass.name}")
    }
}

/**
 * Deletes from anywhere - a swiped row, an edit screen's menu - and offers
 * Undo.
 *
 * Runs on the app's scope with the repositories, not a screen's ViewModel: a
 * delete from an edit screen pops that screen, and its ViewModel's scope goes
 * with it, before the pilot can reach Undo.
 */
private class Deletions(
    private val people: PeopleRepository,
    private val flights: FlightRepository,
    private val scope: CoroutineScope,
    private val snackbar: SnackbarHostState,
    private val resources: android.content.res.Resources,
) {
    fun person(person: PersonEntity) = delete(
        resources.getString(R.string.app_deleted, person.displayName.ifBlank { resources.getString(R.string.app_deleted_person) }),
        { people.deletePerson(person.id) },
        { people.restorePerson(person.id) },
    )

    fun aircraft(aircraft: AircraftEntity) = delete(
        resources.getString(R.string.app_deleted, aircraft.registration.ifBlank { resources.getString(R.string.app_deleted_aircraft) }),
        { flights.deleteAircraft(aircraft.id) },
        { flights.restoreAircraft(aircraft.id) },
    )

    fun flight(flight: FlightEntity) = delete(
        resources.getString(R.string.app_deleted, "${flight.originICAO.ifBlank { "????" }} → ${flight.destinationICAO.ifBlank { "????" }}"),
        { flights.deleteFlight(flight.id) },
        { flights.restoreFlight(flight.id) },
    )

    private fun delete(message: String, remove: suspend () -> Unit, restore: suspend () -> Unit) {
        scope.launch {
            remove()
            // One Undo at a time: a second delete replaces the first's offer.
            snackbar.currentSnackbarData?.dismiss()
            val result = snackbar.showSnackbar(message, actionLabel = resources.getString(R.string.app_undo), duration = SnackbarDuration.Long)
            if (result == SnackbarResult.ActionPerformed) restore()
        }
    }
}

/**
 * Saved-state key on the screen that opened "person/new": the id of the
 * person just created, so a flight's picker can put them on board.
 */
private const val ADDED_PERSON = "addedPersonId"

/** A person from the address book. */
private const val CONTACT_IMPORT = "people/contact"

/** The id in "person/new": a person not stored yet. */
private const val NEW_PERSON = "new"

/** A scan that is not for anyone yet. */
private const val STANDALONE_SCAN = "people/scan"

private enum class Tab(val route: String, @StringRes val label: Int, val icon: ImageVector) {
    FLIGHTS("flights", R.string.app_tab_flights, Icons.Default.Flight),
    PEOPLE("people", R.string.app_tab_people, Icons.Default.People),
    AIRCRAFT("aircraft", R.string.app_tab_aircraft, Icons.Default.AirplanemodeActive),
    SETTINGS("settings", R.string.app_tab_settings, Icons.Default.Settings),
}

@Composable
fun FlyFunApp(
    auth: AuthService,
    tokens: TokenStore,
    api: ApiClient,
    /** Set when the app is opened from a launcher shortcut; cleared once acted on. */
    shortcut: MutableStateFlow<AppShortcut?>,
) {
    val context = LocalContext.current
    val repositories = remember {
        val db = FlyFunDatabase.get(context)
        Triple(
            RoomPeopleRepository(db.personDao(), db.travelDocumentDao()),
            RoomFlightRepository(db.flightDao(), db.aircraftDao()),
            db,
        )
    }
    val preferences = remember { Preferences(context) }
    val factory = remember {
        Factory(
            people = repositories.first,
            flights = repositories.second,
            api = api,
            cacheDir = context.cacheDir,
            transfer = DataTransfer(repositories.third),
            appVersion = runCatching {
                context.packageManager.getPackageInfo(context.packageName, 0).versionName.orEmpty()
            }.getOrDefault(""),
            preferences = preferences,
            airports = AirportDatabase.get(context),
            // The application's: ViewModels outlive the activity.
            resources = context.applicationContext.resources,
        )
    }
    val signedIn by tokens.signedIn.collectAsState()
    // Saveable so a process death while the Custom Tab is open does not drop a
    // pilot who chose to carry on offline back onto the sign-in screen.
    var skippedSignIn by rememberSaveable { mutableStateOf(false) }
    // Signing in clears the skip, so a later sign-out or an expired token (a
    // 401 clears it, see ApiClient) comes back here rather than failing
    // quietly on every form.
    androidx.compose.runtime.LaunchedEffect(signedIn) { if (signedIn) skippedSignIn = false }

    // Above the sign-in screen, so the controller - and the back stack whose
    // entries own the flight draft's ViewModel - outlives a detour to sign in
    // after a token expires mid-edit.
    val navController = rememberNavController()
    val snackbar = remember { SnackbarHostState() }
    val appScope = rememberCoroutineScope()
    val deletions = remember {
        Deletions(repositories.first, repositories.second, appScope, snackbar, context.applicationContext.resources)
    }

    val signInNotice by auth.signInNotice.collectAsState()
    if (!signedIn && !skippedSignIn) {
        SignInScreen(
            notice = signInNotice,
            onSignIn = { auth.startSignIn(it) },
            // Form generation is the only thing that needs the server. Everything
            // else - people, aircraft, flights - is local, so let a pilot get on
            // with data entry rather than blocking the whole app behind a login.
            // Settings offers sign-in again.
            onContinueOffline = { skippedSignIn = true },
        )
        return
    }

    val backStack by navController.currentBackStackEntryAsState()
    val currentRoute = backStack?.destination?.route
    val stack by navController.currentBackStack.collectAsState()
    // The tab whose list the current screen was opened from.
    val currentTab = stack.lastOrNull { entry -> Tab.entries.any { it.route == entry.destination.route } }
        ?.let { entry -> Tab.entries.first { it.route == entry.destination.route } }
    val twoPane = isTwoPane()
    val atTabRoot = Tab.entries.any { it.route == currentRoute }

    // A bar on a phone, a rail on a tablet. The phone's bar shows only on the
    // lists, as before; beside two panes the rail stays, since the list does.
    val defaultLayout = NavigationSuiteScaffoldDefaults.calculateFromAdaptiveInfo(currentWindowAdaptiveInfo())
    NavigationSuiteScaffold(
        layoutType = if (atTabRoot || (twoPane && defaultLayout != NavigationSuiteType.NavigationBar)) {
            defaultLayout
        } else {
            NavigationSuiteType.None
        },
        navigationSuiteItems = {
            Tab.entries.forEach { tab ->
                item(
                    selected = currentTab == tab,
                    onClick = {
                        navController.navigate(tab.route) {
                            popUpTo(Tab.FLIGHTS.route) { saveState = true }
                            launchSingleTop = true
                            restoreState = true
                        }
                    },
                    icon = { Icon(tab.icon, contentDescription = null) },
                    label = { Text(stringResource(tab.label)) },
                )
            }
        },
    ) {
        Box(Modifier.fillMaxSize()) {
            NavHost(
                navController = navController,
                startDestination = Tab.FLIGHTS.route,
                // Beside a list that stays put, only the detail pane should
                // change; a whole-window fade would flash the list too.
                enterTransition = { if (twoPane) EnterTransition.None else fadeIn(tween(700)) },
                exitTransition = { if (twoPane) ExitTransition.None else fadeOut(tween(700)) },
            ) {
                flightRoutes(navController, factory, context, deletions, tokens)
                peopleRoutes(navController, factory, deletions)
                aircraftRoutes(navController, factory, deletions)
                settingsRoute(factory, context, tokens, auth, preferences)
            }
            SnackbarHost(
                snackbar,
                Modifier
                    .align(Alignment.BottomCenter)
                    .windowInsetsPadding(WindowInsets.safeDrawing.only(WindowInsetsSides.Bottom + WindowInsetsSides.Horizontal)),
            )
        }
    }

    // Once the NavHost has set its graph. On top of whatever is open, so
    // an unsaved flight underneath is still there on Back.
    val pendingShortcut by shortcut.collectAsState()
    androidx.compose.runtime.LaunchedEffect(pendingShortcut) {
        val target = pendingShortcut ?: return@LaunchedEffect
        navController.currentBackStackEntryFlow.first()
        when (target) {
            AppShortcut.NEW_FLIGHT -> navController.navigate("flight/${FlightsViewModel.NEW_FLIGHT}")
            AppShortcut.SCAN_DOCUMENT -> navController.navigate(STANDALONE_SCAN)
        }
        shortcut.value = null
    }
}

/** The launcher's long-press shortcuts (res/xml/shortcuts.xml), by intent action. */
enum class AppShortcut(val action: String) {
    NEW_FLIGHT("aero.flyfun.forms.action.NEW_FLIGHT"),
    SCAN_DOCUMENT("aero.flyfun.forms.action.SCAN_DOCUMENT");

    companion object {
        fun from(action: String?): AppShortcut? = entries.firstOrNull { it.action == action }
    }
}

/**
 * Whether [entry] was opened from [tab]'s list, so the list belongs beside it.
 * A person opened from a flight's picker, say, is not: it shows alone.
 */
@Composable
private fun openedFrom(nav: androidx.navigation.NavHostController, entry: NavBackStackEntry, tab: Tab): Boolean {
    val stack by nav.currentBackStack.collectAsState()
    val index = stack.indexOfFirst { it.id == entry.id }
    return index > 0 && stack[index - 1].destination.route == tab.route
}

/** Open an item beside its tab's list, replacing whichever item was open. */
private fun androidx.navigation.NavHostController.openFromList(route: String, tab: Tab) =
    navigate(route) { popUpTo(tab.route) }

private fun androidx.navigation.NavGraphBuilder.flightRoutes(
    nav: androidx.navigation.NavHostController,
    factory: ViewModelProvider.Factory,
    context: Context,
    deletions: Deletions,
    tokens: TokenStore,
) {
    composable(Tab.FLIGHTS.route) {
        val vm: FlightsViewModel = viewModel(factory = factory)
        ListDetail(
            showingDetail = false,
            list = {
                FlightList(vm, deletions, selectedId = null, onOpen = { nav.openFromList("flight/$it", Tab.FLIGHTS) })
            },
            detail = { NothingSelected(stringResource(R.string.app_pick_flight)) },
        )
    }

    composable(
        "flight/{flightId}",
        arguments = listOf(navArgument("flightId") { type = NavType.StringType }),
    ) { entry ->
        val flightId = entry.arguments?.getString("flightId").orEmpty()
        if (!openedFrom(nav, entry, Tab.FLIGHTS)) {
            FlightRoute(entry, flightId, nav, factory, context, deletions, tokens)
            return@composable
        }
        val vm: FlightsViewModel = viewModel(factory = factory)
        val unsaved by vm.hasUnsavedChanges.collectAsState()
        val scope = rememberCoroutineScope()
        // Another flight picked from the list while this one has edits: the
        // same question Back asks.
        var pendingOpen by rememberSaveable { mutableStateOf<String?>(null) }
        ListDetail(
            showingDetail = true,
            list = {
                FlightList(vm, deletions, selectedId = flightId, onOpen = { id ->
                    if (id == flightId) return@FlightList
                    if (unsaved) pendingOpen = id else nav.openFromList("flight/$id", Tab.FLIGHTS)
                })
            },
            detail = { FlightRoute(entry, flightId, nav, factory, context, deletions, tokens) },
        )
        pendingOpen?.let { next ->
            androidx.compose.material3.AlertDialog(
                onDismissRequest = { pendingOpen = null },
                title = { Text(stringResource(R.string.app_save_changes_title)) },
                text = { Text(stringResource(R.string.app_open_other_flight_discards)) },
                confirmButton = {
                    androidx.compose.material3.TextButton(onClick = {
                        pendingOpen = null
                        scope.launch { vm.save().join(); nav.openFromList("flight/$next", Tab.FLIGHTS) }
                    }) { Text(stringResource(R.string.app_save)) }
                },
                dismissButton = {
                    androidx.compose.material3.TextButton(onClick = {
                        pendingOpen = null
                        nav.openFromList("flight/$next", Tab.FLIGHTS)
                    }) { Text(stringResource(R.string.app_discard)) }
                },
            )
        }
    }
}

/** The flight list, as the Flights tab and beside an open flight. */
@Composable
private fun FlightList(
    vm: FlightsViewModel,
    deletions: Deletions,
    selectedId: String?,
    onOpen: (String) -> Unit,
) {
    val flights by vm.allFlights.collectAsState()
    val aircraft by vm.aircraft.collectAsState()
    FlightListScreen(
        flights = flights,
        aircraft = aircraft,
        onOpen = onOpen,
        // A draft, not a row: backing out of it leaves nothing behind.
        onAdd = { onOpen(FlightsViewModel.NEW_FLIGHT) },
        onDelete = { deletions.flight(it) },
        selectedId = selectedId,
    )
}

/**
 * One flight: the two-step flow for a new one, the editor otherwise, and the
 * pickers and web form that take its place while they are open.
 */
@Composable
private fun FlightRoute(
    entry: NavBackStackEntry,
    flightId: String,
    nav: androidx.navigation.NavHostController,
    factory: ViewModelProvider.Factory,
    context: Context,
    deletions: Deletions,
    tokens: TokenStore,
) {
    val vm: FlightsViewModel = viewModel(viewModelStoreOwner = entry, factory = factory)
    val signedIn by tokens.signedIn.collectAsState()
    val stagedAircraft by vm.stagedAircraft.collectAsState()
    val peopleVm: PeopleViewModel = viewModel(factory = factory)
    val detail by vm.detail.collectAsState()
    val unsaved by vm.hasUnsavedChanges.collectAsState()
    val aircraft by vm.aircraft.collectAsState()
    val people by peopleVm.people.collectAsState()
    val forms by vm.airportForms.collectAsState()
    val generate by vm.generate.collectAsState()
    val extraValues by vm.extraValues.collectAsState()
    val lastFlights by peopleVm.lastFlights.collectAsState()
    val flightPeople by peopleVm.flightPeople.collectAsState()
    val scope = rememberCoroutineScope()
    var pickingPeople by rememberSaveable { mutableStateOf(false) }
    var pickingRoute by rememberSaveable { mutableStateOf(false) }
    // The pickers below replace the flight screen, which drops its saveable
    // state (a schedule's chosen zone, say); the holder keeps it for the return.
    val screens = rememberSaveableStateHolder()
    val airportInfo by vm.airportInfo.collectAsState()
    // + opens the two-step flow; a leg made from another flight opens the editor.
    var newFlow by rememberSaveable { mutableStateOf(flightId == FlightsViewModel.NEW_FLIGHT) }
    var newStep by rememberSaveable { mutableStateOf(NewFlightStep.ROUTE) }
    var pickingPrevious by rememberSaveable { mutableStateOf(false) }
    var pickingWeather by rememberSaveable { mutableStateOf(false) }
    var pickingCrewSource by rememberSaveable { mutableStateOf(false) }
    val importSummary by vm.importSummary.collectAsState()
    val allFlights by vm.allFlights.collectAsState()

    androidx.compose.runtime.LaunchedEffect(flightId) { vm.open(flightId) }

    // Someone edited from here (opened from the picker, say) comes back
    // with their stored details, which is what forms are built from.
    androidx.compose.runtime.LaunchedEffect(people) {
        vm.refreshPeople(people.associate { it.person.id to it.person })
    }

    // A person created from the picker's + menu joins this flight.
    val added by entry.savedStateHandle.getStateFlow<String?>(ADDED_PERSON, null).collectAsState()
    androidx.compose.runtime.LaunchedEffect(added, people) {
        val id = added ?: return@LaunchedEffect
        val person = people.firstOrNull { it.person.id == id }?.person ?: return@LaunchedEffect
        entry.savedStateHandle[ADDED_PERSON] = null
        vm.addPerson(person)
    }

    // Sent once: the state is cleared as soon as the mail app is asked.
    (generate as? aero.flyfun.forms.ui.flights.GenerateState.EmailReady)?.let { email ->
        androidx.compose.runtime.LaunchedEffect(email) {
            emailFile(context, email)
            vm.clearGenerateState()
        }
    }

    // A fetched fill plan takes over the screen until it is dismissed.
    (generate as? aero.flyfun.forms.ui.flights.GenerateState.WebPlan)?.let { web ->
        WebFormScreen(plan = web.plan, onBack = { vm.clearGenerateState() })
        return
    }

    if (pickingRoute) {
        detail?.let { current ->
            RoutePickerScreen(
                origin = current.flight.originICAO,
                destination = current.flight.destinationICAO,
                lookup = AirportLookup(vm::searchAirports, vm::airport),
                recentRoutes = vm::recentRoutes,
                onChange = { origin, destination ->
                    vm.editFlight { it.copy(originICAO = origin, destinationICAO = destination) }
                },
                onDone = { pickingRoute = false },
            )
            return
        }
    }

    if (pickingPeople) {
        detail?.let { current ->
            PeoplePickerScreen(
                people = people,
                lastFlights = lastFlights,
                flightPeople = flightPeople,
                crew = current.crew,
                passengers = current.passengers,
                onChange = { crew, passengers -> vm.setPeople(crew, passengers) },
                add = AddPersonActions(
                    onAdd = { nav.navigate("person/new") },
                    onScan = { nav.navigate(STANDALONE_SCAN) },
                    onFromContact = { nav.navigate(CONTACT_IMPORT) },
                ),
                onAddNamed = { name ->
                    scope.launch {
                        val person = peopleVm.addNamed(name)
                        vm.addPerson(person)
                        nav.navigate("person/${person.id}")
                    }
                },
                onDone = { pickingPeople = false },
            )
            return
        }
    }

    val current = detail
    if (newFlow && current != null) {
        val peopleById = people.associate { it.person.id to it.person }
        val flightsById = allFlights.associateBy { it.id }
        val registrations = aircraft.associate { it.id to it.registration }
        val others = flightPeople.filter { it.flightId != current.flight.id }
        fun namesOn(id: String) = others.firstOrNull { it.flightId == id }?.everyone.orEmpty()
            .mapNotNull { peopleById[it]?.displayName }
        fun row(flight: FlightEntity) = PastFlightRow(flight, registrations[flight.aircraftId], namesOn(flight.id))

        if (pickingPrevious) {
            PastFlightPickerScreen(
                title = stringResource(R.string.app_previous_flight),
                emptyText = stringResource(R.string.app_no_earlier_flights),
                rows = allFlights
                    .filter { it.id != current.flight.id && (it.originICAO.isNotBlank() || it.destinationICAO.isNotBlank()) }
                    .sortedByDescending { it.departureInstant }
                    .take(50)
                    .map(::row),
                onPick = { vm.importPreviousFlight(it.id); pickingPrevious = false },
                onCancel = { pickingPrevious = false },
            )
            return
        }
        if (pickingWeather) {
            WeatherFlightPickerScreen(
                load = vm::weatherFlights,
                export = vm::weatherFlight,
                onImport = { vm.importWeather(it); pickingWeather = false },
                onCancel = { pickingWeather = false },
            )
            return
        }
        if (pickingCrewSource) {
            PastFlightPickerScreen(
                title = stringResource(R.string.app_copy_crew_from),
                emptyText = stringResource(R.string.app_copy_crew_empty),
                rows = PeopleSuggestion.crewSources(others).mapNotNull { flightsById[it.flightId] }.map(::row),
                onPick = { flight ->
                    others.firstOrNull { it.flightId == flight.id }?.let { source ->
                        vm.setPeople(source.crew.mapNotNull(peopleById::get), source.passengers.mapNotNull(peopleById::get))
                    }
                    pickingCrewSource = false
                },
                onCancel = { pickingCrewSource = false },
            )
            return
        }

        val usualCrewLabel = stringResource(R.string.app_usual_crew)
        val sameAsFormat = stringResource(R.string.app_same_as)
        val suggestion = PeopleSuggestion.suggest(
            others,
            current.flight.aircraftId,
            people.filter { it.person.isUsualCrew }.map { it.person.id },
        )?.let { s ->
            val crew = s.crew.mapNotNull(peopleById::get)
            val passengers = s.passengers.mapNotNull(peopleById::get)
            if (crew.isEmpty() && passengers.isEmpty()) return@let null
            SuggestionChoice(
                label = s.fromFlightId?.let(flightsById::get)
                    ?.let { sameAsFormat.format("${it.originICAO.ifBlank { "????" }} → ${it.destinationICAO.ifBlank { "????" }}") }
                    ?: usualCrewLabel,
                summary = PeopleSuggestion.summary((crew + passengers).map { it.displayName }),
                crew = crew,
                passengers = passengers,
            )
        }
        screens.SaveableStateProvider("new-flight") {
            NewFlightScreen(
                step = newStep,
                detail = current,
                // With the aircraft an import named, until the flight stores it.
                aircraftOptions = aircraft + listOfNotNull(stagedAircraft),
                airportInfo = airportInfo,
                importSummary = importSummary,
                hasPreviousFlights = allFlights.any { it.id != current.flight.id },
                signedIn = signedIn,
                suggestion = suggestion,
                hasCrewSources = others.any { it.everyone.isNotEmpty() },
                onImportPrevious = { pickingPrevious = true },
                onImportWeather = { pickingWeather = true },
                onOpenRoutePicker = { pickingRoute = true },
                onSetDeparture = { vm.setDeparture(it) },
                onSetArrival = { t -> vm.editFlight { it.copy(arrivalInstant = t) } },
                onSetAircraft = { vm.setAircraft(it) },
                onApplySuggestion = { vm.setPeople(it.crew, it.passengers) },
                onOpenCrewSources = { pickingCrewSource = true },
                onOpenPeoplePicker = { pickingPeople = true },
                onNext = { newStep = NewFlightStep.PEOPLE },
                onBack = { newStep = NewFlightStep.ROUTE },
                onCancel = { nav.popBackStack() },
                onCreate = { scope.launch { vm.save().join(); newFlow = false } },
            )
        }
        return
    }

    screens.SaveableStateProvider("flight-edit") {
        FlightEditScreen(
            detail = detail,
            hasUnsavedChanges = unsaved,
            aircraftOptions = aircraft,
            people = people.map { it.person },
            documents = people.associate { row ->
                row.person.id to row.documents.filter { it.isActive && it.deletedAt == null }
            },
            onChooseDocument = { person, document ->
                vm.chooseDocument(
                    person,
                    people.firstOrNull { it.person.id == person.id }?.documents.orEmpty().filter { it.deletedAt == null },
                    document,
                )
            },
            onOpenPeoplePicker = { pickingPeople = true },
            airportInfo = airportInfo,
            onOpenRoutePicker = { pickingRoute = true },
            airportForms = forms,
            generateState = generate,
            onEditFlight = { vm.editFlight(it) },
            onSetDeparture = { vm.setDeparture(it) },
            onSetAircraft = { vm.setAircraft(it) },
            onSetCrew = { vm.setCrew(it) },
            onSetPassengers = { vm.setPassengers(it) },
            onSetResponsiblePerson = { vm.setResponsiblePerson(it) },
            extraValues = extraValues,
            onSetExtra = { airport, formId, key, value -> vm.setExtra(airport, formId, key, value) },
            onSave = { vm.save() },
            onSaveAndBack = { scope.launch { vm.save().join(); nav.popBackStack() } },
            onGenerate = { airport, form -> vm.generateForm(airport, form) },
            onEmail = { airport, form -> vm.emailForm(airport, form) },
            onOpenWebForm = { airport, form -> vm.prefillWebForm(airport, form) },
            onShare = { shareFile(context, it) },
            onDismissGenerate = { vm.clearGenerateState() },
            onBack = { nav.popBackStack() },
            onDelete = {
                detail?.flight?.let { deletions.flight(it) }
                nav.popBackStack()
            },
            onCreateReturn = { vm.createReturnFlight() },
            onCreateNextLeg = { vm.createNextLeg() },
            onDuplicate = { vm.duplicateFlight() },
        )
    }
}

private fun androidx.navigation.NavGraphBuilder.peopleRoutes(
    nav: androidx.navigation.NavHostController,
    factory: ViewModelProvider.Factory,
    deletions: Deletions,
) {
    composable(Tab.PEOPLE.route) {
        ListDetail(
            showingDetail = false,
            list = {
                PeopleList(nav, factory, deletions, selectedId = null, onOpen = { nav.openFromList("person/$it", Tab.PEOPLE) })
            },
            detail = { NothingSelected(stringResource(R.string.app_pick_person)) },
        )
    }
    composable("person/$NEW_PERSON") { entry ->
        val beside = openedFrom(nav, entry, Tab.PEOPLE)
        WithList(beside, list = {
            PeopleList(nav, factory, deletions, selectedId = null, onOpen = { nav.openFromList("person/$it", Tab.PEOPLE) })
        }) {
        val vm: PeopleViewModel = viewModel(factory = factory)
        val scope = rememberCoroutineScope()
        // Tell whoever opened this - a flight's picker - who was created.
        fun announce(person: PersonEntity) {
            nav.previousBackStackEntry?.savedStateHandle?.set(ADDED_PERSON, person.id)
        }
        // A document needs its person to exist, so opening one saves the new
        // person and swaps this screen for the stored person's before going on.
        fun persistThen(person: PersonEntity, next: String) = scope.launch {
            vm.save(person).join()
            announce(person)
            nav.navigate("person/${person.id}") { popUpTo("person/new") { inclusive = true } }
            nav.navigate(next)
        }
        PersonEditScreen(
            initial = null,
            onSave = { person -> scope.launch { vm.save(person).join(); announce(person); nav.popBackStack() } },
            onOpenDocument = { person, _ -> persistThen(person, "person/${person.id}/document/new") },
            onDeleteDocument = {},
            onBack = { nav.popBackStack() },
            onScan = { person -> persistThen(person, "person/${person.id}/scan") },
        )
        }
    }
    // A contact from the address book: the system picker first, then create or merge.
    composable(CONTACT_IMPORT) {
        val vm: PeopleViewModel = viewModel(factory = factory)
        val people by vm.people.collectAsState()
        val contact by vm.pickedContact.collectAsState()
        val context = LocalContext.current
        val scope = rememberCoroutineScope()
        var launched by rememberSaveable { mutableStateOf(false) }
        val pick = androidx.activity.compose.rememberLauncherForActivityResult(
            androidx.activity.result.contract.ActivityResultContracts.PickContact(),
        ) { uri ->
            if (uri == null) {
                nav.popBackStack()
                return@rememberLauncherForActivityResult
            }
            scope.launch {
                val read = ContactReader.read(context, uri)
                if (read == null) {
                    android.widget.Toast.makeText(context, "That contact has no name to import.", android.widget.Toast.LENGTH_LONG).show()
                    nav.popBackStack()
                } else {
                    vm.setPickedContact(read)
                }
            }
        }
        androidx.compose.runtime.LaunchedEffect(Unit) {
            if (!launched) {
                launched = true
                pick.launch(null)
            }
        }
        contact?.let { picked ->
            ContactResolveScreen(
                contact = picked,
                people = people.map { it.person },
                onResult = { person ->
                    scope.launch {
                        vm.save(person).join()
                        vm.setPickedContact(null)
                        // A flight's picker puts them on board.
                        nav.previousBackStackEntry?.savedStateHandle?.set(ADDED_PERSON, person.id)
                        nav.navigate("person/${person.id}") { popUpTo(CONTACT_IMPORT) { inclusive = true } }
                    }
                },
                onCancel = { vm.setPickedContact(null); nav.popBackStack() },
            )
        }
    }
    // A scan from the People list or a flight's picker: whose document it is
    // is the question, and the person it ends with is opened.
    composable(STANDALONE_SCAN) {
        val vm: PeopleViewModel = viewModel(factory = factory)
        val scope = rememberCoroutineScope()
        val people by vm.people.collectAsState()
        val decision by vm.scanDecision.collectAsState()
        fun open(person: PersonEntity) {
            // A flight's picker puts them on board.
            nav.previousBackStackEntry?.savedStateHandle?.set(ADDED_PERSON, person.id)
            nav.navigate("person/${person.id}") { popUpTo(STANDALONE_SCAN) { inclusive = true } }
        }
        ScanScreen(
            onScanned = { vm.decide(it, ScanContext.Standalone) },
            onBack = { nav.popBackStack() },
        )
        decision?.let { current ->
            ScanResultSheet(
                decision = current,
                people = people.associate { it.person.id to it.person },
                onApply = { personId, overwriteName, addDocument ->
                    scope.launch {
                        vm.applyScanTo(personId, current.result, overwriteName, addDocument)
                        people.firstOrNull { it.person.id == personId }?.let { open(it.person) }
                    }
                },
                onCreatePerson = { scope.launch { open(vm.createScannedPerson(current.result)) } },
                onCancel = { vm.dismissScan(); nav.popBackStack() },
            )
        }
    }
    composable(
        "person/{personId}/scan",
        arguments = listOf(navArgument("personId") { type = NavType.StringType }),
    ) { entry ->
        val personId = entry.arguments?.getString("personId").orEmpty()
        val vm: PeopleViewModel = viewModel(factory = factory)
        val scope = rememberCoroutineScope()
        val people by vm.people.collectAsState()
        val decision by vm.scanDecision.collectAsState()
        ScanScreen(
            onScanned = { vm.decide(it, ScanContext.ForPerson(personId)) },
            onBack = { nav.popBackStack() },
        )
        decision?.let { current ->
            ScanResultSheet(
                decision = current,
                people = people.associate { it.person.id to it.person },
                onApply = { id, overwriteName, addDocument ->
                    scope.launch {
                        vm.applyScanTo(id, current.result, overwriteName, addDocument)
                        nav.popBackStack()
                    }
                },
                // The scan was someone else's: open them instead of this person.
                onCreatePerson = {
                    scope.launch {
                        val created = vm.createScannedPerson(current.result)
                        nav.navigate("person/${created.id}") { popUpTo("person/{personId}") { inclusive = true } }
                    }
                },
                onCancel = { vm.dismissScan(); nav.popBackStack() },
            )
        }
    }
    composable(
        "person/{personId}/document/{documentId}",
        arguments = listOf(
            navArgument("personId") { type = NavType.StringType },
            navArgument("documentId") { type = NavType.StringType },
        ),
    ) { entry ->
        val personId = entry.arguments?.getString("personId").orEmpty()
        val documentId = entry.arguments?.getString("documentId").orEmpty()
        val vm: PeopleViewModel = viewModel(factory = factory)
        val scope = rememberCoroutineScope()
        val people by vm.people.collectAsState()
        val isNew = documentId == "new"
        val newDocument = remember { TravelDocumentEntity(personId = personId) }
        val document = if (isNew) {
            newDocument
        } else {
            people.firstOrNull { it.person.id == personId }
                ?.documents?.firstOrNull { it.id == documentId }
        }
        document?.let { doc ->
            DocumentEditScreen(
                initial = doc,
                isNew = isNew,
                onSave = { updated -> scope.launch { vm.saveDocument(updated).join(); nav.popBackStack() } },
                onDelete = { vm.deleteDocument(doc.id); nav.popBackStack() },
                onBack = { nav.popBackStack() },
            )
        }
    }

    composable(
        "person/{personId}",
        arguments = listOf(navArgument("personId") { type = NavType.StringType }),
    ) { entry ->
        val personId = entry.arguments?.getString("personId").orEmpty()
        val vm: PeopleViewModel = viewModel(factory = factory)
        val scope = rememberCoroutineScope()
        val people by vm.people.collectAsState()
        val row: PersonWithDocuments? = people.firstOrNull { it.person.id == personId }
        val beside = openedFrom(nav, entry, Tab.PEOPLE)
        // Unsaved edits are stored before leaving for a document or the
        // scanner; see PersonEditScreen.
        fun persistThen(person: PersonEntity, next: String) = scope.launch {
            vm.save(person).join()
            nav.navigate(next)
        }
        WithList(beside, list = {
            PeopleList(nav, factory, deletions, selectedId = personId, onOpen = { nav.openFromList("person/$it", Tab.PEOPLE) })
        }) {
        row?.let {
            PersonEditScreen(
                initial = it,
                onSave = { updated -> scope.launch { vm.save(updated).join(); nav.popBackStack() } },
                onOpenDocument = { person, docId ->
                    persistThen(person, "person/$personId/document/${docId ?: "new"}")
                },
                onDeleteDocument = { id -> vm.deleteDocument(id) },
                onBack = { nav.popBackStack() },
                onScan = { person -> persistThen(person, "person/$personId/scan") },
                onDelete = { deletions.person(it.person); nav.popBackStack() },
            )
        }
        }
    }
}

/** The people list, as the People tab and beside an open person. */
@Composable
private fun PeopleList(
    nav: androidx.navigation.NavHostController,
    factory: ViewModelProvider.Factory,
    deletions: Deletions,
    selectedId: String?,
    /** A person's id, or [NEW_PERSON]. */
    onOpen: (String) -> Unit,
) {
    val vm: PeopleViewModel = viewModel(factory = factory)
    val people by vm.people.collectAsState()
    val lastFlights by vm.lastFlights.collectAsState()
    val csvResult by vm.csvResult.collectAsState()
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    // SAF both ways: no storage permission, and only the file picked.
    val importCsv = androidx.activity.compose.rememberLauncherForActivityResult(
        androidx.activity.result.contract.ActivityResultContracts.OpenDocument(),
    ) { uri ->
        uri ?: return@rememberLauncherForActivityResult
        scope.launch {
            // Off the main thread: a cloud provider may download the file here.
            val text = withContext(Dispatchers.IO) {
                runCatching {
                    context.contentResolver.openInputStream(uri)?.use { it.readBytes().decodeToString() }
                }.getOrNull()
            }
            if (text == null) {
                vm.reportCsv(context.getString(R.string.app_import_failed), context.getString(R.string.app_could_not_read_file))
            } else {
                vm.importCsv(text)
            }
        }
    }
    val exportCsv = androidx.activity.compose.rememberLauncherForActivityResult(
        androidx.activity.result.contract.ActivityResultContracts.CreateDocument("text/csv"),
    ) { uri ->
        uri ?: return@rememberLauncherForActivityResult
        scope.launch {
            runCatching {
                val csv = vm.exportCsv()
                withContext(Dispatchers.IO) {
                    context.contentResolver.openOutputStream(uri)?.use { it.write(csv.toByteArray()) }
                } ?: error(context.getString(R.string.app_could_not_write_file))
            }.onSuccess {
                android.widget.Toast.makeText(context, context.getString(R.string.app_people_exported), android.widget.Toast.LENGTH_SHORT).show()
            }.onFailure {
                vm.reportCsv(context.getString(R.string.app_export_failed), it.message ?: context.getString(R.string.app_could_not_write_file))
            }
        }
    }

    PeopleListScreen(
        people = people,
        lastFlights = lastFlights,
        onOpen = onOpen,
        add = AddPersonActions(
            onAdd = { onOpen(NEW_PERSON) },
            onScan = { nav.navigate(STANDALONE_SCAN) },
            onFromContact = { nav.navigate(CONTACT_IMPORT) },
            onImportCsv = { importCsv.launch(arrayOf("text/*", "application/csv")) },
        ),
        onExportCsv = { exportCsv.launch("people.csv") },
        onDelete = { deletions.person(it) },
        selectedId = selectedId,
    )
    csvResult?.let { result ->
        androidx.compose.material3.AlertDialog(
            onDismissRequest = { vm.dismissCsvResult() },
            title = { Text(result.title) },
            text = { Text(result.message) },
            confirmButton = { androidx.compose.material3.TextButton(onClick = { vm.dismissCsvResult() }) { Text(stringResource(R.string.app_ok)) } },
        )
    }
}

private fun androidx.navigation.NavGraphBuilder.aircraftRoutes(
    nav: androidx.navigation.NavHostController,
    factory: ViewModelProvider.Factory,
    deletions: Deletions,
) {
    composable(Tab.AIRCRAFT.route) {
        ListDetail(
            showingDetail = false,
            list = { AircraftList(factory, deletions, selectedId = null) { nav.openFromList("aircraft/$it", Tab.AIRCRAFT) } },
            detail = { NothingSelected(stringResource(R.string.app_pick_aircraft)) },
        )
    }
    composable("aircraft/new") { entry ->
        WithList(openedFrom(nav, entry, Tab.AIRCRAFT), list = {
            AircraftList(factory, deletions, selectedId = null) { nav.openFromList("aircraft/$it", Tab.AIRCRAFT) }
        }) {
        val vm: AircraftViewModel = viewModel(factory = factory)
        val peopleVm: PeopleViewModel = viewModel(factory = factory)
        val people by peopleVm.people.collectAsState()
        AircraftEditScreen(
            null,
            people = people.map { it.person },
            airports = airportLookup(nav.context),
            onSave = { vm.save(it); nav.popBackStack() },
            onBack = { nav.popBackStack() },
        )
        }
    }
    composable(
        "aircraft/{aircraftId}",
        arguments = listOf(navArgument("aircraftId") { type = NavType.StringType }),
    ) { entry ->
        val id = entry.arguments?.getString("aircraftId").orEmpty()
        val vm: AircraftViewModel = viewModel(factory = factory)
        val aircraft by vm.aircraft.collectAsState()
        val existing: AircraftEntity? = aircraft.firstOrNull { it.id == id }
        val peopleVm: PeopleViewModel = viewModel(factory = factory)
        val people by peopleVm.people.collectAsState()
        WithList(openedFrom(nav, entry, Tab.AIRCRAFT), list = {
            AircraftList(factory, deletions, selectedId = id) { nav.openFromList("aircraft/$it", Tab.AIRCRAFT) }
        }) {
        existing?.let {
            AircraftEditScreen(
                it,
                people = people.map { row -> row.person },
                airports = airportLookup(nav.context),
                onSave = { u -> vm.save(u); nav.popBackStack() },
                onBack = { nav.popBackStack() },
                onDelete = { deletions.aircraft(it); nav.popBackStack() },
            )
        }
        }
    }
}

/** The aircraft list, as the Aircraft tab and beside an open aircraft. */
@Composable
private fun AircraftList(
    factory: ViewModelProvider.Factory,
    deletions: Deletions,
    selectedId: String?,
    /** An aircraft's id, or "new". */
    onOpen: (String) -> Unit,
) {
    val vm: AircraftViewModel = viewModel(factory = factory)
    val aircraft by vm.aircraft.collectAsState()
    AircraftListScreen(
        aircraft = aircraft,
        onOpen = onOpen,
        onAdd = { onOpen("new") },
        onDelete = { deletions.aircraft(it) },
        selectedId = selectedId,
    )
}

/** [content] with [list] beside it when [beside], alone otherwise. */
@Composable
private fun WithList(beside: Boolean, list: @Composable () -> Unit, content: @Composable () -> Unit) {
    if (beside) ListDetail(showingDetail = true, list = list, detail = content) else content()
}

private fun airportLookup(context: Context): AirportLookup {
    val db = AirportDatabase.get(context)
    return AirportLookup(db::search, db::airport)
}

@Composable
private fun SignInScreen(notice: String?, onSignIn: (SignInProvider) -> Unit, onContinueOffline: () -> Unit) {
    Column(
        Modifier.fillMaxSize().padding(32.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(stringResource(R.string.app_name), style = MaterialTheme.typography.headlineMedium)
        Text(
            stringResource(R.string.app_sign_in_intro),
            style = MaterialTheme.typography.bodyMedium,
            modifier = Modifier.padding(vertical = 12.dp),
        )
        if (notice != null) {
            Text(
                notice,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.error,
                textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                modifier = Modifier.padding(bottom = 12.dp),
            )
        }
        SignInButtons(onSignIn)
        androidx.compose.material3.TextButton(onClick = onContinueOffline) {
            Text(stringResource(R.string.app_continue_offline))
        }
    }
}

/**
 * Hands the generated file to another app.
 *
 * FileProvider rather than a file:// URI - those have thrown
 * FileUriExposedException since API 24, and this one is well above that.
 */
private fun shareFile(context: Context, file: File) {
    // Cleared after a while in the background (FormFiles); regenerating is one tap.
    if (!file.exists()) {
        android.widget.Toast.makeText(context, context.getString(R.string.app_file_cleared), android.widget.Toast.LENGTH_LONG).show()
        return
    }
    val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
    val intent = Intent(Intent.ACTION_SEND).apply {
        type = mimeType(file)
        putExtra(Intent.EXTRA_STREAM, uri)
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }
    context.startActivity(Intent.createChooser(intent, context.getString(R.string.app_share_file, file.name)))
}


/**
 * Opens a mail app with the form attached, addressed and written.
 *
 * ACTION_SEND so the attachment goes with it, and a `mailto:` selector so only
 * mail apps answer rather than every app that takes a PDF. With no mail app,
 * falls back to the share sheet, as iOS does without a mail account.
 */
private fun emailFile(context: Context, email: aero.flyfun.forms.ui.flights.GenerateState.EmailReady) {
    val file = email.file
    val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
    val intent = Intent(Intent.ACTION_SEND).apply {
        type = mimeType(file)
        putExtra(Intent.EXTRA_EMAIL, email.to.toTypedArray())
        putExtra(Intent.EXTRA_CC, email.cc.toTypedArray())
        putExtra(Intent.EXTRA_SUBJECT, email.subject)
        putExtra(Intent.EXTRA_TEXT, email.body)
        putExtra(Intent.EXTRA_STREAM, uri)
        // ClipData carries the read grant through the selector to the mail app.
        clipData = android.content.ClipData.newRawUri(file.name, uri)
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        selector = Intent(Intent.ACTION_SENDTO, android.net.Uri.parse("mailto:"))
    }
    try {
        context.startActivity(intent)
    } catch (_: android.content.ActivityNotFoundException) {
        shareFile(context, file)
    }
}

private fun mimeType(file: File): String = when (file.extension.lowercase()) {
    "pdf" -> "application/pdf"
    "docx" -> "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
    "xlsx" -> "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    else -> "application/octet-stream"
}

private fun androidx.navigation.NavGraphBuilder.settingsRoute(
    factory: ViewModelProvider.Factory,
    context: Context,
    tokens: TokenStore,
    auth: AuthService,
    preferences: Preferences,
) {
    composable(Tab.SETTINGS.route) {
        val vm: DataTransferViewModel = viewModel(factory = factory)
        val state by vm.state.collectAsState()
        val signedIn by tokens.signedIn.collectAsState()
        val spokenLanguages by preferences.spokenLanguages.collectAsState()
        var deletingAccount by remember { mutableStateOf(false) }
        var deleteAccountError by remember { mutableStateOf<String?>(null) }
        val scope = rememberCoroutineScope()

        // OpenDocument rather than GetContent: this reads one file the user
        // chose, with no storage permission and no access to anything else.
        val picker = androidx.activity.compose.rememberLauncherForActivityResult(
            androidx.activity.result.contract.ActivityResultContracts.OpenDocument(),
        ) { uri ->
            uri ?: return@rememberLauncherForActivityResult
            scope.launch {
                val bytes = withContext(Dispatchers.IO) {
                    context.contentResolver.openInputStream(uri)?.use { it.readBytes() }
                }
                if (bytes != null) vm.previewImport(bytes)
            }
        }

        SettingsScreen(
            state = state,
            signedIn = signedIn,
            onSignIn = { auth.startSignIn(it) },
            onExportEncrypted = { vm.exportEncrypted() },
            onExportPlain = { vm.exportPlain() },
            onPickFile = { picker.launch(arrayOf("*/*")) },
            onSubmitPassword = { password ->
                val current = state
                if (current is aero.flyfun.forms.ui.settings.TransferState.NeedsPassword) {
                    vm.previewImport(current.bytes, password)
                }
            },
            onConfirmImport = { vm.confirmImport() },
            onShare = { shareFile(context, it) },
            // The sign-in screen follows from the token going; see FlyFunApp.
            onSignOut = { scope.launch { auth.signOut() } },
            onDismiss = { vm.reset() },
            spokenLanguages = spokenLanguages,
            onSetSpeaks = { code, speaks -> preferences.setSpeaks(code, speaks) },
            deletingAccount = deletingAccount,
            deleteAccountError = deleteAccountError,
            onDeleteAccount = {
                scope.launch {
                    deletingAccount = true
                    deleteAccountError = null
                    // Success clears the token, and the sign-in screen follows.
                    auth.deleteAccount().onFailure {
                        deleteAccountError = it.message ?: context.getString(R.string.app_delete_account_failed)
                    }
                    deletingAccount = false
                }
            },
        )
    }
}
