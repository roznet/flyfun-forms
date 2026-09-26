package aero.flyfun.forms.ui.people

import aero.flyfun.forms.data.PersonEntity
import aero.flyfun.forms.data.PersonWithDocuments
import aero.flyfun.forms.data.TravelDocumentEntity
import aero.flyfun.forms.logic.PeopleRanking
import aero.flyfun.forms.logic.RankedPerson
import aero.flyfun.forms.ui.common.DeleteOverflowMenu
import aero.flyfun.forms.ui.common.SwipeToDelete
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.ContactPage
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.DocumentScanner
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.PersonAdd
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.SortByAlpha
import androidx.compose.material.icons.filled.Upload
import androidx.compose.material3.Card
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.UUID

/**
 * What the People tab's + menu offers. Port of iOS `AddPersonMenuItems` plus
 * the CSV import; each entry is shown only when the caller handles it.
 */
class AddPersonActions(
    val onAdd: () -> Unit,
    val onScan: (() -> Unit)? = null,
    val onFromContact: (() -> Unit)? = null,
    val onImportCsv: (() -> Unit)? = null,
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PeopleListScreen(
    people: List<PersonWithDocuments>,
    /** When each person last flew, by id; see "Sort by Recent". */
    lastFlights: Map<String, Instant>,
    onOpen: (String) -> Unit,
    add: AddPersonActions,
    onExportCsv: () -> Unit,
    onDelete: (PersonEntity) -> Unit,
    /** The person open beside the list, on a screen wide enough for both. */
    selectedId: String? = null,
) {
    var query by rememberSaveable { mutableStateOf("") }
    var sortByRecent by rememberSaveable { mutableStateOf(false) }
    var addMenu by remember { mutableStateOf(false) }
    var overflow by remember { mutableStateOf(false) }

    val shown = remember(people, lastFlights, query, sortByRecent) {
        val matching = people.filter { PeopleRanking.matches(query, it.person.firstName, it.person.lastName) }
        if (!sortByRecent) {
            matching
        } else {
            val byId = matching.associateBy { it.person.id }
            PeopleRanking.byRecent(matching.map { it.person.ranked(lastFlights) }).map { byId.getValue(it.id) }
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("People") },
                actions = {
                    IconButton(onClick = { sortByRecent = !sortByRecent }) {
                        Icon(
                            if (sortByRecent) Icons.Default.SortByAlpha else Icons.Default.Schedule,
                            contentDescription = if (sortByRecent) "Sort A-Z" else "Sort by Recent",
                        )
                    }
                    Box {
                        IconButton(onClick = { overflow = true }) {
                            Icon(Icons.Default.MoreVert, contentDescription = "More")
                        }
                        DropdownMenu(expanded = overflow, onDismissRequest = { overflow = false }) {
                            DropdownMenuItem(
                                text = { Text("Export to CSV") },
                                leadingIcon = { Icon(Icons.Default.Upload, contentDescription = null) },
                                enabled = people.isNotEmpty(),
                                onClick = { overflow = false; onExportCsv() },
                            )
                        }
                    }
                },
            )
        },
        floatingActionButton = {
            Box {
                FloatingActionButton(onClick = { addMenu = true }) {
                    Icon(Icons.Default.Add, contentDescription = "Add person")
                }
                DropdownMenu(expanded = addMenu, onDismissRequest = { addMenu = false }) {
                    AddPersonMenuItems(add) { addMenu = false }
                }
            }
        },
    ) { padding ->
        Column(Modifier.fillMaxSize().padding(padding)) {
            if (people.isNotEmpty()) {
                SearchField(query, { query = it }, "Search by name")
            }
            when {
                people.isEmpty() -> Column(
                    modifier = Modifier.fillMaxSize().padding(32.dp),
                    verticalArrangement = Arrangement.Center,
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Text("No crew or passengers yet", style = MaterialTheme.typography.titleMedium)
                    Spacer(Modifier.height(8.dp))
                    Text(
                        "Add the people you fly with, and their passports, so forms fill themselves.",
                        style = MaterialTheme.typography.bodyMedium,
                    )
                }
                shown.isEmpty() -> Text(
                    "No one matches “${query.trim()}”.",
                    style = MaterialTheme.typography.bodyMedium,
                    modifier = Modifier.padding(16.dp),
                )
                else -> LazyColumn(modifier = Modifier.fillMaxSize()) {
                    items(shown, key = { "${it.person.id}:${it.person.updatedAt}" }) { row ->
                        SwipeToDelete(onDelete = { onDelete(row.person) }) {
                            PersonRow(row, lastFlight = lastFlights[row.person.id].takeIf { sortByRecent }, selected = row.person.id == selectedId) {
                                onOpen(row.person.id)
                            }
                        }
                        HorizontalDivider()
                    }
                }
            }
        }
    }
}

/** The menu entries behind a + button, shared by the People tab and the picker. */
@Composable
fun AddPersonMenuItems(add: AddPersonActions, close: () -> Unit) {
    DropdownMenuItem(
        text = { Text("Add Person") },
        leadingIcon = { Icon(Icons.Default.PersonAdd, contentDescription = null) },
        onClick = { close(); add.onAdd() },
    )
    add.onScan?.let { scan ->
        DropdownMenuItem(
            text = { Text("Scan Document") },
            leadingIcon = { Icon(Icons.Default.DocumentScanner, contentDescription = null) },
            onClick = { close(); scan() },
        )
    }
    add.onFromContact?.let { contact ->
        DropdownMenuItem(
            text = { Text("Import from Contact") },
            leadingIcon = { Icon(Icons.Default.ContactPage, contentDescription = null) },
            onClick = { close(); contact() },
        )
    }
    add.onImportCsv?.let { csv ->
        DropdownMenuItem(
            text = { Text("Import from CSV") },
            leadingIcon = { Icon(Icons.Default.Download, contentDescription = null) },
            onClick = { close(); csv() },
        )
    }
}

@Composable
private fun PersonRow(row: PersonWithDocuments, lastFlight: Instant?, selected: Boolean, onClick: () -> Unit) {
    val active = row.documents.filter { it.isActive && it.deletedAt == null }
    ListItem(
        headlineContent = { Text(row.person.displayName.ifBlank { "New Person" }) },
        supportingContent = {
            Text(
                listOfNotNull(
                    // Nationality derives from the documents, never the person.
                    active.mapNotNull { it.issuingCountry }.distinct().joinToString("/").ifBlank { null },
                    if (active.isEmpty()) "No documents" else "${active.size} document${if (active.size == 1) "" else "s"}",
                    lastFlight?.let { "Flew ${lastFlightFormat.format(it)}" },
                ).joinToString(" · "),
            )
        },
        trailingContent = if (row.person.isUsualCrew) { { CrewPill() } } else null,
        colors = if (selected) ListItemDefaults.colors(containerColor = MaterialTheme.colorScheme.secondaryContainer) else ListItemDefaults.colors(),
        modifier = Modifier.clickable(onClick = onClick),
    )
}

/** The small "Crew" tag iOS puts on usual crew. */
@Composable
fun CrewPill(text: String = "Crew") {
    Surface(color = MaterialTheme.colorScheme.secondaryContainer, shape = CircleShape) {
        Text(
            text,
            style = MaterialTheme.typography.labelSmall,
            modifier = Modifier.padding(horizontal = 8.dp, vertical = 2.dp),
        )
    }
}

/**
 * A search box above a list. A plain text field rather than M3 `SearchBar`,
 * whose expanding, full-screen behaviour is for app-wide search, not for
 * filtering the list below it.
 */
@Composable
fun SearchField(query: String, onChange: (String) -> Unit, placeholder: String, modifier: Modifier = Modifier) {
    OutlinedTextField(
        value = query,
        onValueChange = onChange,
        placeholder = { Text(placeholder) },
        leadingIcon = { Icon(Icons.Default.Search, contentDescription = null) },
        trailingIcon = if (query.isNotEmpty()) {
            { IconButton(onClick = { onChange("") }) { Icon(Icons.Default.Close, contentDescription = "Clear search") } }
        } else {
            null
        },
        singleLine = true,
        keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Words),
        modifier = modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
    )
}

fun PersonEntity.ranked(lastFlights: Map<String, Instant>) = RankedPerson(
    id = id,
    firstName = firstName,
    lastName = lastName,
    isUsualCrew = isUsualCrew,
    lastFlight = lastFlights[id],
)

private val lastFlightFormat: DateTimeFormatter =
    DateTimeFormatter.ofPattern("d MMM yyyy").withZone(ZoneId.systemDefault())

private val dateFormat: DateTimeFormatter = DateTimeFormatter.ofPattern("d MMM yyyy")

/** Same vocabulary as iOS, so a record moved between the two reads the same. */
private val sexOptions = listOf("Male", "Female")
private val documentTypes = listOf("Passport", "Identity card", "Other")

/**
 * The person's own fields, plus the list of their documents.
 *
 * Opening a document or the scanner first hands the edited person to the
 * caller to save: a new person has to exist before a document can point at
 * them, and an existing one would otherwise lose unsaved edits - or, after a
 * scan fills the date of birth, have them overwritten by this screen's stale
 * copy. Because the stored row is always current on return, the field state is
 * keyed on it rather than saved separately.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PersonEditScreen(
    initial: PersonWithDocuments?,
    onSave: (PersonEntity) -> Unit,
    onOpenDocument: (PersonEntity, String?) -> Unit,
    onDeleteDocument: (String) -> Unit,
    onBack: () -> Unit,
    onScan: ((PersonEntity) -> Unit)? = null,
    /** Null for a person not stored yet. */
    onDelete: (() -> Unit)? = null,
) {
    val existing = initial?.person
    val id = remember { existing?.id ?: UUID.randomUUID().toString() }
    var firstName by remember(existing) { mutableStateOf(existing?.firstName.orEmpty()) }
    var lastName by remember(existing) { mutableStateOf(existing?.lastName.orEmpty()) }
    var dateOfBirth by remember(existing) { mutableStateOf(existing?.dateOfBirth) }
    var placeOfBirth by remember(existing) { mutableStateOf(existing?.placeOfBirth.orEmpty()) }
    var sex by remember(existing) { mutableStateOf(existing?.sex) }
    var email by remember(existing) { mutableStateOf(existing?.email.orEmpty()) }
    var phone by remember(existing) { mutableStateOf(existing?.phone.orEmpty()) }
    var address by remember(existing) { mutableStateOf(existing?.address.orEmpty()) }
    var usualCrew by remember(existing) { mutableStateOf(existing?.isUsualCrew ?: false) }

    fun edited() = (existing ?: PersonEntity(id = id)).copy(
        firstName = firstName.trim(),
        lastName = lastName.trim(),
        dateOfBirth = dateOfBirth,
        placeOfBirth = placeOfBirth.trim().ifBlank { null },
        sex = sex,
        email = email.trim().ifBlank { null },
        phone = phone.trim().ifBlank { null },
        address = address.trim().ifBlank { null },
        isUsualCrew = usualCrew,
    )

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(if (existing == null) "New Person" else "Edit Person") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.Default.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    TextButton(onClick = { onSave(edited()) }) { Text("Save") }
                    onDelete?.let { DeleteOverflowMenu(onDelete = it) }
                },
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            OutlinedTextField(
                value = firstName,
                onValueChange = { firstName = it },
                label = { Text("First name") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Words),
                modifier = Modifier.fillMaxWidth(),
            )
            OutlinedTextField(
                value = lastName,
                onValueChange = { lastName = it },
                label = { Text("Last name") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Words),
                modifier = Modifier.fillMaxWidth(),
            )

            Spacer(Modifier.height(4.dp))
            Text("Details", style = MaterialTheme.typography.titleMedium)
            OptionalDateField(
                label = "Date of birth",
                value = dateOfBirth,
                onChange = { dateOfBirth = it },
                yearRange = 1900..LocalDate.now().year,
                latest = LocalDate.now(),
            )
            OutlinedTextField(
                value = placeOfBirth,
                onValueChange = { placeOfBirth = it },
                label = { Text("Place of birth") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Words),
                modifier = Modifier.fillMaxWidth(),
            )
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text("Sex", style = MaterialTheme.typography.bodyLarge)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    sexOptions.forEach { option ->
                        FilterChip(
                            selected = sex == option,
                            // Tapping the selected chip again clears it.
                            onClick = { sex = if (sex == option) null else option },
                            label = { Text(option) },
                        )
                    }
                }
            }
            OutlinedTextField(
                value = email,
                onValueChange = { email = it },
                label = { Text("Email") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email),
                modifier = Modifier.fillMaxWidth(),
            )
            OutlinedTextField(
                value = phone,
                onValueChange = { phone = it },
                label = { Text("Phone") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Phone),
                modifier = Modifier.fillMaxWidth(),
            )
            OutlinedTextField(
                value = address,
                onValueChange = { address = it },
                label = { Text("Address") },
                minLines = 2,
                maxLines = 3,
                modifier = Modifier.fillMaxWidth(),
            )
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text("Usual crew", style = MaterialTheme.typography.bodyLarge)
                Switch(checked = usualCrew, onCheckedChange = { usualCrew = it })
            }

            Spacer(Modifier.height(8.dp))
            Text("Travel documents", style = MaterialTheme.typography.titleMedium)
            DocumentSection(
                documents = initial?.documents.orEmpty().filter { it.deletedAt == null },
                onOpen = { docId -> onOpenDocument(edited(), docId) },
                onDelete = onDeleteDocument,
                onScan = onScan?.let { scan -> { scan(edited()) } },
            )
        }
    }
}

@Composable
private fun DocumentSection(
    documents: List<TravelDocumentEntity>,
    onOpen: (String?) -> Unit,
    onDelete: (String) -> Unit,
    onScan: (() -> Unit)? = null,
) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        documents.forEach { doc ->
            Card(modifier = Modifier.fillMaxWidth().clickable { onOpen(doc.id) }) {
                ListItem(
                    headlineContent = {
                        Text("${doc.docType} (${doc.issuingCountry ?: "?"})")
                    },
                    supportingContent = {
                        Text(
                            buildString {
                                append(doc.docNumber.ifBlank { "No number" })
                                doc.expiryDate?.let { append(" · expires ${it.format(dateFormat)}") }
                                if (!doc.isActive) append(" · inactive")
                            },
                        )
                    },
                    trailingContent = {
                        IconButton(onClick = { onDelete(doc.id) }) {
                            Icon(Icons.Default.Delete, contentDescription = "Remove document")
                        }
                    },
                )
            }
        }

        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            TextButton(onClick = { onOpen(null) }) { Text("Add document") }
            if (onScan != null) {
                TextButton(onClick = onScan) { Text("Scan passport") }
            }
        }
    }
}

/**
 * One passport or ID card, every field editable - the counterpart of iOS's
 * `DocumentEditView`. Used both for a new document and for correcting a
 * scanned one.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DocumentEditScreen(
    initial: TravelDocumentEntity,
    isNew: Boolean,
    onSave: (TravelDocumentEntity) -> Unit,
    onDelete: () -> Unit,
    onBack: () -> Unit,
) {
    var docType by remember(initial) { mutableStateOf(initial.docType) }
    var number by remember(initial) { mutableStateOf(initial.docNumber) }
    var country by remember(initial) { mutableStateOf(initial.issuingCountry.orEmpty()) }
    var expiry by remember(initial) { mutableStateOf(initial.expiryDate) }
    var active by remember(initial) { mutableStateOf(initial.isActive) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(if (isNew) "New Document" else "Edit Document") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.Default.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    TextButton(
                        enabled = number.isNotBlank(),
                        onClick = {
                            onSave(
                                initial.copy(
                                    docType = docType,
                                    docNumber = number.trim().uppercase(),
                                    issuingCountry = country.trim().uppercase().ifBlank { null },
                                    expiryDate = expiry,
                                    isActive = active,
                                ),
                            )
                        },
                    ) { Text("Save") }
                },
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text("Document type", style = MaterialTheme.typography.bodyLarge)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                documentTypes.forEach { type ->
                    FilterChip(
                        selected = docType == type,
                        onClick = { docType = type },
                        label = { Text(type) },
                    )
                }
            }
            OutlinedTextField(
                value = number,
                // Upper-cased on save, not per keystroke: rewriting the text under
                // the keyboard breaks its composing span and drops characters.
                onValueChange = { number = it },
                label = { Text("Document number") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Characters),
                modifier = Modifier.fillMaxWidth(),
            )
            OutlinedTextField(
                value = country,
                onValueChange = { if (it.length <= 3) country = it.uppercase() },
                label = { Text("Issuing country (e.g. FRA)") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Characters),
                modifier = Modifier.fillMaxWidth(),
            )
            OptionalDateField(
                label = "Expiry date",
                value = expiry,
                onChange = { expiry = it },
                yearRange = LocalDate.now().year - 20..LocalDate.now().year + 20,
            )
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text("Active", style = MaterialTheme.typography.bodyLarge)
                Switch(checked = active, onCheckedChange = { active = it })
            }
            if (!isNew) {
                Spacer(Modifier.height(8.dp))
                TextButton(onClick = onDelete) {
                    Text("Remove document", color = MaterialTheme.colorScheme.error)
                }
            }
        }
    }
}
