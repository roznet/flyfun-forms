package aero.flyfun.forms.data

import aero.flyfun.forms.logic.DocumentResolver
import aero.flyfun.forms.logic.PeopleCsv
import aero.flyfun.forms.logic.ResolvableDocument
import kotlinx.coroutines.flow.Flow
import java.time.Instant

/**
 * Everything the UI is allowed to know about storage.
 *
 * The interface exists so the storage behind it can change without the screens
 * noticing - which is the precondition for adding Drive appDataFolder sync
 * later (designs/future/android-app.md section 3). Nothing above this line
 * touches a DAO.
 */
interface PeopleRepository {
    fun observePeople(): Flow<List<PersonWithDocuments>>
    suspend fun person(id: String): PersonWithDocuments?
    suspend fun save(person: PersonEntity)
    suspend fun saveDocument(document: TravelDocumentEntity)
    suspend fun deletePerson(id: String)
    suspend fun restorePerson(id: String)
    suspend fun deleteDocument(id: String)

    /**
     * The document to use for this person at this airport: the one picked for
     * the flight among [chosenDocNumbers], else the automatic choice.
     */
    suspend fun resolveDocument(
        personId: String,
        airport: String,
        chosenDocNumbers: List<String> = emptyList(),
    ): TravelDocumentEntity?

    /** Import a people CSV; throws [aero.flyfun.forms.logic.CsvImportException] on a bad file. */
    suspend fun importCsv(content: String): PeopleCsv.ImportPlan

    /** Everyone, one row per active document, in the columns [importCsv] reads. */
    suspend fun exportCsv(): String
}

class RoomPeopleRepository(
    private val people: PersonDao,
    private val documents: TravelDocumentDao,
) : PeopleRepository {

    override fun observePeople(): Flow<List<PersonWithDocuments>> = people.observeAll()

    override suspend fun person(id: String): PersonWithDocuments? = people.byId(id)

    override suspend fun save(person: PersonEntity) =
        people.upsert(person.copy(updatedAt = Instant.now()))

    override suspend fun saveDocument(document: TravelDocumentEntity) =
        documents.upsert(document.copy(updatedAt = Instant.now()))

    override suspend fun deletePerson(id: String) = people.softDelete(id, Instant.now())

    override suspend fun restorePerson(id: String) = people.restore(id, Instant.now())

    override suspend fun deleteDocument(id: String) = documents.softDelete(id, Instant.now())

    override suspend fun resolveDocument(
        personId: String,
        airport: String,
        chosenDocNumbers: List<String>,
    ): TravelDocumentEntity? {
        val held = documents.forPerson(personId)
        val chosen = DocumentResolver.resolve(held.map { it.toResolvable() }, airport, chosenDocNumbers) ?: return null
        return held.firstOrNull { it.id == chosen.id }
    }

    override suspend fun importCsv(content: String): PeopleCsv.ImportPlan {
        val parsed = PeopleCsv.parse(content)
        val stored = people.observeAllOnce()
        val known = stored.map { person ->
            PeopleCsv.KnownPerson(
                id = person.id,
                firstName = person.firstName,
                lastName = person.lastName,
                dateOfBirth = person.dateOfBirth,
                docNumbers = documents.forPerson(person.id).map { it.docNumber }.toSet(),
            )
        }
        val plan = PeopleCsv.plan(parsed, known)
        val now = Instant.now()
        val newPeople = plan.newPeople.map { planned ->
            val row = planned.person
            val person = PersonEntity(
                firstName = row.firstName,
                lastName = row.lastName,
                sex = PeopleCsv.normaliseSex(row.sex),
                dateOfBirth = row.dateOfBirth,
                isUsualCrew = row.isCrew,
                updatedAt = now,
            )
            person to planned.documents.map { it.toDocument(person.id, now) }
        }
        people.importPeople(
            people = newPeople.map { it.first },
            documents = newPeople.flatMap { it.second } +
                plan.documentsForExisting.map { it.row.toDocument(it.personId, now) },
        )
        return plan
    }

    override suspend fun exportCsv(): String {
        val everyone = people.observeAllOnce().sortedWith(
            compareBy(String.CASE_INSENSITIVE_ORDER, PersonEntity::lastName)
                .thenBy(String.CASE_INSENSITIVE_ORDER, PersonEntity::firstName),
        )
        return PeopleCsv.export(
            everyone.map { person ->
                PeopleCsv.ExportPerson(
                    firstName = person.firstName,
                    lastName = person.lastName,
                    sex = person.sex,
                    dateOfBirth = person.dateOfBirth,
                    isCrew = person.isUsualCrew,
                    documents = documents.forPerson(person.id).filter { it.isActive }.map {
                        PeopleCsv.ExportDocument(it.docType, it.docNumber, it.expiryDate, it.issuingCountry)
                    },
                )
            },
        )
    }
}

/** The pure-logic shape; :core-logic knows nothing about Room. */
fun TravelDocumentEntity.toResolvable() = ResolvableDocument(
    id = id,
    docType = docType,
    docNumber = docNumber,
    issuingCountry = issuingCountry,
    expiryDate = expiryDate,
    isActive = isActive,
)

private fun aero.flyfun.forms.logic.CsvPerson.toDocument(personId: String, now: Instant) = TravelDocumentEntity(
    personId = personId,
    docType = docType ?: "Passport",
    docNumber = docNumber.orEmpty(),
    issuingCountry = (docIssuingCountry ?: nationality)?.uppercase(),
    expiryDate = docExpiry,
    updatedAt = now,
)
