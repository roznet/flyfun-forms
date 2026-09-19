package aero.flyfun.forms.ui

import aero.flyfun.forms.data.FlyFunDatabase
import aero.flyfun.forms.data.PeopleRepository
import aero.flyfun.forms.data.PersonWithDocuments
import aero.flyfun.forms.data.RoomPeopleRepository
import aero.flyfun.forms.ui.people.PeopleListScreen
import aero.flyfun.forms.ui.people.PeopleViewModel
import aero.flyfun.forms.ui.people.PersonEditScreen
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.compose.runtime.collectAsState
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument

/**
 * Hand-rolled factory rather than a DI framework.
 *
 * The graph is one database and a handful of repositories; Hilt would be more
 * moving parts than the app has objects. Revisit if the graph grows.
 */
private class ViewModelFactory(private val repository: PeopleRepository) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T = when {
        modelClass.isAssignableFrom(PeopleViewModel::class.java) -> PeopleViewModel(repository) as T
        else -> error("Unknown ViewModel ${modelClass.name}")
    }
}

private object Routes {
    const val PEOPLE = "people"
    const val PERSON_NEW = "person/new"
    const val PERSON_EDIT = "person/{personId}"
    fun personEdit(id: String) = "person/$id"
}

@Composable
fun FlyFunApp() {
    val context = LocalContext.current
    val repository = remember {
        val db = FlyFunDatabase.get(context)
        RoomPeopleRepository(db.personDao(), db.travelDocumentDao())
    }
    val factory = remember { ViewModelFactory(repository) }
    val navController = rememberNavController()

    NavHost(navController = navController, startDestination = Routes.PEOPLE) {
        composable(Routes.PEOPLE) {
            val vm: PeopleViewModel = viewModel(factory = factory)
            val people by vm.people.collectAsState()
            PeopleListScreen(
                people = people,
                onOpen = { navController.navigate(Routes.personEdit(it)) },
                onAdd = { navController.navigate(Routes.PERSON_NEW) },
            )
        }

        composable(Routes.PERSON_NEW) {
            val vm: PeopleViewModel = viewModel(factory = factory)
            PersonEditScreen(
                initial = null,
                onSave = { vm.save(it); navController.popBackStack() },
                onAddDocument = { _, _, _, _ -> },
                onDeleteDocument = {},
                onBack = { navController.popBackStack() },
            )
        }

        composable(
            Routes.PERSON_EDIT,
            arguments = listOf(navArgument("personId") { type = NavType.StringType }),
        ) { entry ->
            val personId = entry.arguments?.getString("personId").orEmpty()
            val vm: PeopleViewModel = viewModel(factory = factory)
            val people by vm.people.collectAsState()
            // Read through the observed list so an edit re-renders without a
            // second query; falls back to a direct load if the list has not
            // arrived yet.
            var loaded by remember(personId) { mutableStateOf<PersonWithDocuments?>(null) }
            LaunchedEffect(personId, people) {
                loaded = people.firstOrNull { it.person.id == personId }
            }
            loaded?.let { row ->
                PersonEditScreen(
                    initial = row,
                    onSave = { vm.save(it); navController.popBackStack() },
                    onAddDocument = { type, number, country, expiry ->
                        vm.addDocument(personId, type, number, country, expiry)
                    },
                    onDeleteDocument = { vm.deleteDocument(it) },
                    onBack = { navController.popBackStack() },
                )
            }
        }
    }
}
