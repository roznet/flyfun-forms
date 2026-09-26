package aero.flyfun.forms.ui

import aero.flyfun.forms.auth.AuthService
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
import androidx.compose.foundation.layout.Arrangement
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
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
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
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
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
) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T = when {
        modelClass.isAssignableFrom(PeopleViewModel::class.java) -> PeopleViewModel(people, flights) as T
        modelClass.isAssignableFrom(AircraftViewModel::class.java) -> AircraftViewModel(flights) as T
        modelClass.isAssignableFrom(FlightsViewModel::class.java) ->
            FlightsViewModel(flights, people, api, cacheDir, { preferences.spokenLanguages.value }, airports) as T
        modelClass.isAssignableFrom(DataTransferViewModel::class.java) ->
            DataTransferViewModel(transfer, cacheDir, appVersion) as T
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
) {
    fun person(person: PersonEntity) = delete(
        "Deleted ${person.displayName.ifBlank { "person" }}",
        { people.deletePerson(person.id) },
        { people.restorePerson(person.id) },
    )

    fun aircraft(aircraft: AircraftEntity) = delete(
        "Deleted ${aircraft.registration.ifBlank { "aircraft" }}",
        { flights.deleteAircraft(aircraft.id) },
        { flights.restoreAircraft(aircraft.id) },
    )

    fun flight(flight: FlightEntity) = delete(
        "Deleted ${flight.originICAO.ifBlank { "????" }} → ${flight.destinationICAO.ifBlank { "????" }}",
        { flights.deleteFlight(flight.id) },
        { flights.restoreFlight(flight.id) },
    )

    private fun delete(message: String, remove: suspend () -> Unit, restore: suspend () -> Unit) {
        scope.launch {
            remove()
            // One Undo at a time: a second delete replaces the first's offer.
            snackbar.currentSnackbarData?.dismiss()
            val result = snackbar.showSnackbar(message, actionLabel = "Undo", duration = SnackbarDuration.Long)
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

/** A scan that is not for anyone yet. */
private const val STANDALONE_SCAN = "people/scan"

private enum class Tab(val route: String, val label: String, val icon: ImageVector) {
    FLIGHTS("flights", "Flights", Icons.Default.Flight),
    PEOPLE("people", "People", Icons.Default.People),
    AIRCRAFT("aircraft", "Aircraft", Icons.Default.AirplanemodeActive),
    SETTINGS("settings", "Settings", Icons.Default.Settings),
}

@Composable
fun FlyFunApp(auth: AuthService, tokens: TokenStore, api: ApiClient) {
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
        Deletions(repositories.first, repositories.second, appScope, snackbar)
    }

    val signInNotice by auth.signInNotice.collectAsState()
    if (!signedIn && !skippedSignIn) {
        SignInScreen(
            notice = signInNotice,
            onSignIn = { auth.startSignIn() },
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

    Scaffold(
        snackbarHost = { SnackbarHost(snackbar) },
        bottomBar = {
            if (Tab.entries.any { it.route == currentRoute }) {
                NavigationBar {
                    Tab.entries.forEach { tab ->
                        NavigationBarItem(
                            selected = currentRoute == tab.route,
                            onClick = {
                                navController.navigate(tab.route) {
                                    popUpTo(Tab.FLIGHTS.route) { saveState = true }
                                    launchSingleTop = true
                                    restoreState = true
                                }
                            },
                            icon = { Icon(tab.icon, contentDescription = tab.label) },
                            label = { Text(tab.label) },
                        )
                    }
                }
            }
        },
    ) { padding ->
        NavHost(
            navController = navController,
            startDestination = Tab.FLIGHTS.route,
            modifier = Modifier.padding(padding),
        ) {
            flightRoutes(navController, factory, context, deletions)
            peopleRoutes(navController, factory, deletions)
            aircraftRoutes(navController, factory, deletions)
            settingsRoute(factory, context, tokens, auth, preferences)
        }
    }
}

private fun androidx.navigation.NavGraphBuilder.flightRoutes(
    nav: androidx.navigation.NavHostController,
    factory: ViewModelProvider.Factory,
    context: Context,
    deletions: Deletions,
) {
    composable(Tab.FLIGHTS.route) {
        val vm: FlightsViewModel = viewModel(factory = factory)
        val flights by vm.allFlights.collectAsState()
        val aircraft by vm.aircraft.collectAsState()
        FlightListScreen(
            flights = flights,
            aircraft = aircraft,
            onOpen = { nav.navigate("flight/$it") },
            // A draft, not a row: backing out of it leaves nothing behind.
            onAdd = { nav.navigate("flight/${FlightsViewModel.NEW_FLIGHT}") },
            onDelete = { deletions.flight(it) },
        )
    }

    composable(
        "flight/{flightId}",
        arguments = listOf(navArgument("flightId") { type = NavType.StringType }),
    ) { entry ->
        val flightId = entry.arguments?.getString("flightId").orEmpty()
        val vm: FlightsViewModel = viewModel(factory = factory)
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
        val airportInfo by vm.airportInfo.collectAsState()
        // + opens the two-step flow; a leg made from another flight opens the editor.
        var newFlow by rememberSaveable { mutableStateOf(flightId == FlightsViewModel.NEW_FLIGHT) }
        var newStep by rememberSaveable { mutableStateOf(NewFlightStep.ROUTE) }
        var pickingPrevious by rememberSaveable { mutableStateOf(false) }
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
            return@composable
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
                return@composable
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
                return@composable
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
                    title = "Previous Flight",
                    emptyText = "No earlier flights yet.",
                    rows = allFlights
                        .filter { it.id != current.flight.id && (it.originICAO.isNotBlank() || it.destinationICAO.isNotBlank()) }
                        .sortedByDescending { it.departureInstant }
                        .take(50)
                        .map(::row),
                    onPick = { vm.importPreviousFlight(it.id); pickingPrevious = false },
                    onCancel = { pickingPrevious = false },
                )
                return@composable
            }
            if (pickingCrewSource) {
                PastFlightPickerScreen(
                    title = "Copy Crew From",
                    emptyText = "Once a flight has crew or passengers, you can copy them here.",
                    rows = PeopleSuggestion.crewSources(others).mapNotNull { flightsById[it.flightId] }.map(::row),
                    onPick = { flight ->
                        others.firstOrNull { it.flightId == flight.id }?.let { source ->
                            vm.setPeople(source.crew.mapNotNull(peopleById::get), source.passengers.mapNotNull(peopleById::get))
                        }
                        pickingCrewSource = false
                    },
                    onCancel = { pickingCrewSource = false },
                )
                return@composable
            }

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
                        ?.let { "Same as ${it.originICAO.ifBlank { "????" }} → ${it.destinationICAO.ifBlank { "????" }}" }
                        ?: "Usual crew",
                    summary = PeopleSuggestion.summary((crew + passengers).map { it.displayName }),
                    crew = crew,
                    passengers = passengers,
                )
            }
            NewFlightScreen(
                step = newStep,
                detail = current,
                aircraftOptions = aircraft,
                airportInfo = airportInfo,
                importSummary = importSummary,
                hasPreviousFlights = allFlights.any { it.id != current.flight.id },
                suggestion = suggestion,
                hasCrewSources = others.any { it.everyone.isNotEmpty() },
                onImportPrevious = { pickingPrevious = true },
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
            return@composable
        }

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
                val text = runCatching {
                    context.contentResolver.openInputStream(uri)?.use { it.readBytes().decodeToString() }
                }.getOrNull()
                if (text == null) vm.reportCsv("Import Failed", "Could not read that file.") else vm.importCsv(text)
            }
        }
        val exportCsv = androidx.activity.compose.rememberLauncherForActivityResult(
            androidx.activity.result.contract.ActivityResultContracts.CreateDocument("text/csv"),
        ) { uri ->
            uri ?: return@rememberLauncherForActivityResult
            scope.launch {
                runCatching {
                    val csv = vm.exportCsv()
                    context.contentResolver.openOutputStream(uri)?.use { it.write(csv.toByteArray()) }
                        ?: error("Could not write that file.")
                }.onSuccess {
                    android.widget.Toast.makeText(context, "People exported", android.widget.Toast.LENGTH_SHORT).show()
                }.onFailure {
                    vm.reportCsv("Export Failed", it.message ?: "Could not write that file.")
                }
            }
        }

        PeopleListScreen(
            people = people,
            lastFlights = lastFlights,
            onOpen = { nav.navigate("person/$it") },
            add = AddPersonActions(
                onAdd = { nav.navigate("person/new") },
                onScan = { nav.navigate(STANDALONE_SCAN) },
                onFromContact = { nav.navigate(CONTACT_IMPORT) },
                onImportCsv = { importCsv.launch(arrayOf("text/*", "application/csv")) },
            ),
            onExportCsv = { exportCsv.launch("people.csv") },
            onDelete = { deletions.person(it) },
        )
        csvResult?.let { result ->
            androidx.compose.material3.AlertDialog(
                onDismissRequest = { vm.dismissCsvResult() },
                title = { Text(result.title) },
                text = { Text(result.message) },
                confirmButton = { androidx.compose.material3.TextButton(onClick = { vm.dismissCsvResult() }) { Text("OK") } },
            )
        }
    }
    composable("person/new") {
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
        // Unsaved edits are stored before leaving for a document or the
        // scanner; see PersonEditScreen.
        fun persistThen(person: PersonEntity, next: String) = scope.launch {
            vm.save(person).join()
            nav.navigate(next)
        }
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

private fun androidx.navigation.NavGraphBuilder.aircraftRoutes(
    nav: androidx.navigation.NavHostController,
    factory: ViewModelProvider.Factory,
    deletions: Deletions,
) {
    composable(Tab.AIRCRAFT.route) {
        val vm: AircraftViewModel = viewModel(factory = factory)
        val aircraft by vm.aircraft.collectAsState()
        AircraftListScreen(
            aircraft = aircraft,
            onOpen = { nav.navigate("aircraft/$it") },
            onAdd = { nav.navigate("aircraft/new") },
            onDelete = { deletions.aircraft(it) },
        )
    }
    composable("aircraft/new") {
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

private fun airportLookup(context: Context): AirportLookup {
    val db = AirportDatabase.get(context)
    return AirportLookup(db::search, db::airport)
}

@Composable
private fun SignInScreen(notice: String?, onSignIn: () -> Unit, onContinueOffline: () -> Unit) {
    Column(
        Modifier.fillMaxSize().padding(32.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text("FlyFun Forms", style = MaterialTheme.typography.headlineMedium)
        Text(
            "Sign in to generate customs and immigration forms.",
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
        Button(onClick = onSignIn) { Text("Sign in with Google") }
        androidx.compose.material3.TextButton(onClick = onContinueOffline) {
            Text("Enter data without signing in")
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
        android.widget.Toast.makeText(context, "That file has been cleared. Generate it again.", android.widget.Toast.LENGTH_LONG).show()
        return
    }
    val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
    val intent = Intent(Intent.ACTION_SEND).apply {
        type = mimeType(file)
        putExtra(Intent.EXTRA_STREAM, uri)
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }
    context.startActivity(Intent.createChooser(intent, "Share ${file.name}"))
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
                val bytes = context.contentResolver.openInputStream(uri)?.use { it.readBytes() }
                if (bytes != null) vm.previewImport(bytes)
            }
        }

        SettingsScreen(
            state = state,
            signedIn = signedIn,
            onSignIn = { auth.startSignIn() },
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
                        deleteAccountError = it.message ?: "Could not delete the account."
                    }
                    deletingAccount = false
                }
            },
        )
    }
}
