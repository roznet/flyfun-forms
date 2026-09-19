package aero.flyfun.forms.ui

import aero.flyfun.forms.auth.AuthService
import aero.flyfun.forms.auth.TokenStore
import aero.flyfun.forms.data.AircraftEntity
import aero.flyfun.forms.data.FlightEntity
import aero.flyfun.forms.data.FlightRepository
import aero.flyfun.forms.data.FlyFunDatabase
import aero.flyfun.forms.data.PeopleRepository
import aero.flyfun.forms.data.PersonWithDocuments
import aero.flyfun.forms.data.RoomFlightRepository
import aero.flyfun.forms.data.DataTransfer
import aero.flyfun.forms.data.RoomPeopleRepository
import aero.flyfun.forms.net.ApiClient
import aero.flyfun.forms.ui.aircraft.AircraftEditScreen
import aero.flyfun.forms.ui.aircraft.AircraftListScreen
import aero.flyfun.forms.ui.aircraft.AircraftViewModel
import aero.flyfun.forms.ui.flights.FlightEditScreen
import aero.flyfun.forms.ui.flights.FlightListScreen
import aero.flyfun.forms.ui.flights.FlightsViewModel
import aero.flyfun.forms.ui.people.PeopleListScreen
import aero.flyfun.forms.ui.people.PeopleViewModel
import aero.flyfun.forms.scan.ScanScreen
import aero.flyfun.forms.ui.webform.WebFormScreen
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
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
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
import kotlinx.coroutines.launch
import java.io.File
import java.time.Instant
import java.time.temporal.ChronoUnit

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
) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T = when {
        modelClass.isAssignableFrom(PeopleViewModel::class.java) -> PeopleViewModel(people) as T
        modelClass.isAssignableFrom(AircraftViewModel::class.java) -> AircraftViewModel(flights) as T
        modelClass.isAssignableFrom(FlightsViewModel::class.java) ->
            FlightsViewModel(flights, people, api, cacheDir) as T
        modelClass.isAssignableFrom(DataTransferViewModel::class.java) ->
            DataTransferViewModel(transfer, cacheDir, appVersion) as T
        else -> error("Unknown ViewModel ${modelClass.name}")
    }
}

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
        )
    }
    var signedIn by remember { mutableStateOf(tokens.isSignedIn) }

    if (!signedIn) {
        SignInScreen(
            onSignIn = { auth.startSignIn() },
            // Form generation is the only thing that needs the server. Everything
            // else - people, aircraft, flights - is local, so let a pilot get on
            // with data entry rather than blocking the whole app behind a login.
            onContinueOffline = { signedIn = true },
        )
        return
    }

    val navController = rememberNavController()
    val backStack by navController.currentBackStackEntryAsState()
    val currentRoute = backStack?.destination?.route

    Scaffold(
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
            flightRoutes(navController, factory, context)
            peopleRoutes(navController, factory)
            aircraftRoutes(navController, factory)
            settingsRoute(factory, context, tokens, auth) { signedIn = false }
        }
    }
}

private fun androidx.navigation.NavGraphBuilder.flightRoutes(
    nav: androidx.navigation.NavHostController,
    factory: ViewModelProvider.Factory,
    context: Context,
) {
    composable(Tab.FLIGHTS.route) {
        val vm: FlightsViewModel = viewModel(factory = factory)
        val flights by vm.allFlights.collectAsState()
        val scope = rememberCoroutineScope()
        FlightListScreen(
            flights = flights,
            onOpen = { nav.navigate("flight/$it") },
            onAdd = {
                scope.launch {
                    val suggested = vm.newFlightDefaults()
                    val now = Instant.now().truncatedTo(ChronoUnit.HOURS).plus(1, ChronoUnit.DAYS)
                    val flight = FlightEntity(
                        departureInstant = now,
                        arrivalInstant = now.plus(2, ChronoUnit.HOURS),
                        aircraftId = suggested?.id,
                        // Seed the route from where the aircraft usually lives.
                        originICAO = suggested?.usualBase.orEmpty(),
                    )
                    vm.save(flight)
                    nav.navigate("flight/${flight.id}")
                }
            },
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
        val aircraft by vm.aircraft.collectAsState()
        val people by peopleVm.people.collectAsState()
        val forms by vm.airportForms.collectAsState()
        val generate by vm.generate.collectAsState()

        androidx.compose.runtime.LaunchedEffect(flightId) { vm.load(flightId) }

        // A fetched fill plan takes over the screen until it is dismissed.
        (generate as? aero.flyfun.forms.ui.flights.GenerateState.WebPlan)?.let { web ->
            WebFormScreen(plan = web.plan, onBack = { vm.clearGenerateState() })
            return@composable
        }

        FlightEditScreen(
            detail = detail,
            aircraftOptions = aircraft,
            people = people.map { it.person },
            airportForms = forms,
            generateState = generate,
            onSave = { vm.save(it) },
            onSetCrew = { vm.setCrew(flightId, it) },
            onSetPassengers = { vm.setPassengers(flightId, it) },
            onGenerate = { airport, form -> vm.generateForm(airport, form) },
            onOpenWebForm = { airport, form -> vm.prefillWebForm(airport, form) },
            onShare = { shareFile(context, it) },
            onDismissGenerate = { vm.clearGenerateState() },
            onBack = { nav.popBackStack() },
        )
    }
}

private fun androidx.navigation.NavGraphBuilder.peopleRoutes(
    nav: androidx.navigation.NavHostController,
    factory: ViewModelProvider.Factory,
) {
    composable(Tab.PEOPLE.route) {
        val vm: PeopleViewModel = viewModel(factory = factory)
        val people by vm.people.collectAsState()
        PeopleListScreen(
            people = people,
            onOpen = { nav.navigate("person/$it") },
            onAdd = { nav.navigate("person/new") },
        )
    }
    composable("person/new") {
        val vm: PeopleViewModel = viewModel(factory = factory)
        PersonEditScreen(
            initial = null,
            onSave = { vm.save(it); nav.popBackStack() },
            onAddDocument = { _, _, _, _ -> },
            onDeleteDocument = {},
            onBack = { nav.popBackStack() },
        )
    }
    composable(
        "person/{personId}/scan",
        arguments = listOf(navArgument("personId") { type = NavType.StringType }),
    ) { entry ->
        val personId = entry.arguments?.getString("personId").orEmpty()
        val vm: PeopleViewModel = viewModel(factory = factory)
        ScanScreen(
            onScanned = { result ->
                // The scan fills the document; the person's own name is left
                // alone, because the pilot may have spelled it deliberately and
                // an MRZ is transliterated and upper-cased.
                vm.addDocument(
                    personId = personId,
                    docType = if (result.format == aero.flyfun.forms.logic.MRZFormat.TD1) "Identity card" else "Passport",
                    docNumber = result.passportNumber,
                    issuingCountry = result.issuingCountry,
                    expiry = result.expiryDate,
                )
                nav.popBackStack()
            },
            onBack = { nav.popBackStack() },
        )
    }

    composable(
        "person/{personId}",
        arguments = listOf(navArgument("personId") { type = NavType.StringType }),
    ) { entry ->
        val personId = entry.arguments?.getString("personId").orEmpty()
        val vm: PeopleViewModel = viewModel(factory = factory)
        val people by vm.people.collectAsState()
        val row: PersonWithDocuments? = people.firstOrNull { it.person.id == personId }
        row?.let {
            PersonEditScreen(
                initial = it,
                onSave = { updated -> vm.save(updated); nav.popBackStack() },
                onAddDocument = { type, number, country, expiry ->
                    vm.addDocument(personId, type, number, country, expiry)
                },
                onDeleteDocument = { id -> vm.deleteDocument(id) },
                onBack = { nav.popBackStack() },
                onScan = { nav.navigate("person/$personId/scan") },
            )
        }
    }
}

private fun androidx.navigation.NavGraphBuilder.aircraftRoutes(
    nav: androidx.navigation.NavHostController,
    factory: ViewModelProvider.Factory,
) {
    composable(Tab.AIRCRAFT.route) {
        val vm: AircraftViewModel = viewModel(factory = factory)
        val aircraft by vm.aircraft.collectAsState()
        AircraftListScreen(
            aircraft = aircraft,
            onOpen = { nav.navigate("aircraft/$it") },
            onAdd = { nav.navigate("aircraft/new") },
        )
    }
    composable("aircraft/new") {
        val vm: AircraftViewModel = viewModel(factory = factory)
        AircraftEditScreen(null, onSave = { vm.save(it); nav.popBackStack() }, onBack = { nav.popBackStack() })
    }
    composable(
        "aircraft/{aircraftId}",
        arguments = listOf(navArgument("aircraftId") { type = NavType.StringType }),
    ) { entry ->
        val id = entry.arguments?.getString("aircraftId").orEmpty()
        val vm: AircraftViewModel = viewModel(factory = factory)
        val aircraft by vm.aircraft.collectAsState()
        val existing: AircraftEntity? = aircraft.firstOrNull { it.id == id }
        existing?.let {
            AircraftEditScreen(it, onSave = { u -> vm.save(u); nav.popBackStack() }, onBack = { nav.popBackStack() })
        }
    }
}

@Composable
private fun SignInScreen(onSignIn: () -> Unit, onContinueOffline: () -> Unit) {
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
    val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
    val intent = Intent(Intent.ACTION_SEND).apply {
        type = when (file.extension.lowercase()) {
            "pdf" -> "application/pdf"
            "docx" -> "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
            "xlsx" -> "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
            else -> "application/octet-stream"
        }
        putExtra(Intent.EXTRA_STREAM, uri)
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }
    context.startActivity(Intent.createChooser(intent, "Share ${file.name}"))
}


private fun androidx.navigation.NavGraphBuilder.settingsRoute(
    factory: ViewModelProvider.Factory,
    context: Context,
    tokens: TokenStore,
    auth: AuthService,
    onSignedOut: () -> Unit,
) {
    composable(Tab.SETTINGS.route) {
        val vm: DataTransferViewModel = viewModel(factory = factory)
        val state by vm.state.collectAsState()
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
            signedIn = tokens.isSignedIn,
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
            onSignOut = { scope.launch { auth.signOut(); onSignedOut() } },
            onDismiss = { vm.reset() },
        )
    }
}
