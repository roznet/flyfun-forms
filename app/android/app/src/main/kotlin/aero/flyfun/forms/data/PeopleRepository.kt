package aero.flyfun.forms.data

import aero.flyfun.forms.logic.DocumentResolver
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

    /** The document to use for this person at this airport. */
    suspend fun resolveDocument(personId: String, airport: String): TravelDocumentEntity?
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

    override suspend fun resolveDocument(personId: String, airport: String): TravelDocumentEntity? {
        val held = documents.forPerson(personId)
        // Map onto the pure-logic shape; :core-logic knows nothing about Room.
        val resolvable = held.map {
            ResolvableDocument(
                id = it.id,
                docType = it.docType,
                docNumber = it.docNumber,
                issuingCountry = it.issuingCountry,
                expiryDate = it.expiryDate,
                isActive = it.isActive,
            )
        }
        // TODO(S8+): pass the remembered per-airport override once preferences exist.
        val chosen = DocumentResolver.resolve(resolvable, airport) ?: return null
        return held.firstOrNull { it.id == chosen.id }
    }
}
