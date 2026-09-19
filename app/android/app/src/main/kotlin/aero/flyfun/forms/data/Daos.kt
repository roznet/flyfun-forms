package aero.flyfun.forms.data

import androidx.room.Dao
import androidx.room.Delete
import androidx.room.Embedded
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Relation
import androidx.room.Transaction
import androidx.room.Upsert
import kotlinx.coroutines.flow.Flow
import java.time.Instant

/** A person with their travel documents. */
data class PersonWithDocuments(
    @Embedded val person: PersonEntity,
    @Relation(parentColumn = "id", entityColumn = "personId")
    val documents: List<TravelDocumentEntity>,
)

@Dao
interface PersonDao {

    @Transaction
    @Query("SELECT * FROM person WHERE deletedAt IS NULL ORDER BY lastName COLLATE NOCASE, firstName COLLATE NOCASE")
    fun observeAll(): Flow<List<PersonWithDocuments>>

    @Transaction
    @Query("SELECT * FROM person WHERE id = :id")
    suspend fun byId(id: String): PersonWithDocuments?

    @Query("SELECT * FROM person WHERE deletedAt IS NULL AND isUsualCrew = 1 ORDER BY lastName COLLATE NOCASE")
    suspend fun usualCrew(): List<PersonEntity>

    /** Live rows only, read once rather than observed. */
    @Query("SELECT * FROM person WHERE deletedAt IS NULL")
    suspend fun observeAllOnce(): List<PersonEntity>

    /**
     * Everything, tombstones included. Export needs the tombstones: without
     * them a deletion made on this device never reaches the other one, and the
     * record quietly comes back.
     */
    @Query("SELECT * FROM person")
    suspend fun allIncludingDeleted(): List<PersonEntity>

    @Upsert
    suspend fun upsert(person: PersonEntity)

    @Upsert
    suspend fun upsertAll(people: List<PersonEntity>)

    /** Tombstone rather than a hard delete, so the deletion can propagate on export. */
    @Query("UPDATE person SET deletedAt = :at, updatedAt = :at WHERE id = :id")
    suspend fun softDelete(id: String, at: Instant = Instant.now())

    @Delete
    suspend fun hardDelete(person: PersonEntity)
}

@Dao
interface TravelDocumentDao {

    @Query("SELECT * FROM travel_document WHERE personId = :personId AND deletedAt IS NULL")
    suspend fun forPerson(personId: String): List<TravelDocumentEntity>

    @Upsert
    suspend fun upsert(document: TravelDocumentEntity)

    @Upsert
    suspend fun upsertAll(documents: List<TravelDocumentEntity>)

    @Query("UPDATE travel_document SET deletedAt = :at, updatedAt = :at WHERE id = :id")
    suspend fun softDelete(id: String, at: Instant = Instant.now())

    @Query("SELECT * FROM travel_document")
    suspend fun allIncludingDeleted(): List<TravelDocumentEntity>
}

@Dao
interface AircraftDao {

    @Query("SELECT * FROM aircraft WHERE deletedAt IS NULL ORDER BY registration COLLATE NOCASE")
    fun observeAll(): Flow<List<AircraftEntity>>

    @Query("SELECT * FROM aircraft WHERE deletedAt IS NULL ORDER BY registration COLLATE NOCASE")
    suspend fun all(): List<AircraftEntity>

    @Query("SELECT * FROM aircraft WHERE id = :id")
    suspend fun byId(id: String): AircraftEntity?

    /** Registration normalised the way the FPL import does it: dashes stripped, uppercased. */
    @Query("SELECT * FROM aircraft WHERE deletedAt IS NULL AND UPPER(REPLACE(registration, '-', '')) = :normalised LIMIT 1")
    suspend fun byNormalisedRegistration(normalised: String): AircraftEntity?

    @Upsert
    suspend fun upsert(aircraft: AircraftEntity)

    @Query("UPDATE aircraft SET deletedAt = :at, updatedAt = :at WHERE id = :id")
    suspend fun softDelete(id: String, at: Instant = Instant.now())

    @Query("SELECT * FROM aircraft")
    suspend fun allIncludingDeleted(): List<AircraftEntity>
}

@Dao
interface TripDao {

    @Query("SELECT * FROM trip WHERE deletedAt IS NULL ORDER BY createdAt DESC")
    fun observeAll(): Flow<List<TripEntity>>

    @Query("SELECT * FROM trip WHERE id = :id")
    suspend fun byId(id: String): TripEntity?

    @Upsert
    suspend fun upsert(trip: TripEntity)

    @Query("UPDATE trip SET deletedAt = :at, updatedAt = :at WHERE id = :id")
    suspend fun softDelete(id: String, at: Instant = Instant.now())

    @Query("SELECT * FROM trip")
    suspend fun allIncludingDeleted(): List<TripEntity>
}

@Dao
interface FlightDao {

    @Query("SELECT * FROM flight WHERE deletedAt IS NULL ORDER BY departureInstant DESC")
    fun observeAll(): Flow<List<FlightEntity>>

    @Query("SELECT * FROM flight WHERE deletedAt IS NULL AND departureInstant >= :from ORDER BY departureInstant ASC")
    fun observeUpcoming(from: Instant): Flow<List<FlightEntity>>

    @Query("SELECT * FROM flight WHERE deletedAt IS NULL AND departureInstant < :before ORDER BY departureInstant DESC")
    fun observePast(before: Instant): Flow<List<FlightEntity>>

    @Query("SELECT * FROM flight WHERE id = :id")
    suspend fun byId(id: String): FlightEntity?

    @Query("SELECT * FROM flight WHERE deletedAt IS NULL AND tripId = :tripId ORDER BY legOrder ASC")
    suspend fun legsOfTrip(tripId: String): List<FlightEntity>

    /**
     * People on a flight in a given role.
     *
     * Explicit SQL because Room's @Relation with @Junction cannot filter on the
     * junction's own `role` column.
     */
    @Query(
        """
        SELECT p.* FROM person p
        JOIN flight_person fp ON fp.personId = p.id
        WHERE fp.flightId = :flightId AND fp.role = :role AND p.deletedAt IS NULL
        ORDER BY fp.seatOrder ASC, p.lastName COLLATE NOCASE
        """,
    )
    suspend fun peopleOn(flightId: String, role: String): List<PersonEntity>

    suspend fun crewOn(flightId: String) = peopleOn(flightId, FlightRole.CREW)

    suspend fun passengersOn(flightId: String) = peopleOn(flightId, FlightRole.PASSENGER)

    /** The last flight that had an aircraft, for [aero.flyfun.forms.data.defaultAircraftForNewFlight]. */
    @Query("SELECT * FROM flight WHERE deletedAt IS NULL AND aircraftId IS NOT NULL ORDER BY departureInstant DESC LIMIT 1")
    suspend fun lastFlightWithAircraft(): FlightEntity?

    @Upsert
    suspend fun upsert(flight: FlightEntity)

    @Query("UPDATE flight SET deletedAt = :at, updatedAt = :at WHERE id = :id")
    suspend fun softDelete(id: String, at: Instant = Instant.now())

    @Query("SELECT * FROM flight")
    suspend fun allIncludingDeleted(): List<FlightEntity>

    @Query("SELECT * FROM flight_person")
    suspend fun allMemberships(): List<FlightPersonCrossRef>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun addPerson(ref: FlightPersonCrossRef)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun addPeople(refs: List<FlightPersonCrossRef>)

    @Query("DELETE FROM flight_person WHERE flightId = :flightId AND personId = :personId AND role = :role")
    suspend fun removePerson(flightId: String, personId: String, role: String)

    @Query("DELETE FROM flight_person WHERE flightId = :flightId AND role = :role")
    suspend fun clearRole(flightId: String, role: String)

    /** Replace everyone in a role in one transaction, which is what an edit screen wants. */
    @Transaction
    suspend fun setPeople(flightId: String, role: String, personIds: List<String>) {
        clearRole(flightId, role)
        addPeople(
            personIds.mapIndexed { index, personId ->
                FlightPersonCrossRef(flightId = flightId, personId = personId, role = role, seatOrder = index)
            },
        )
    }
}

/**
 * The aircraft a new flight should start on, or null when there is nothing to
 * go on.
 *
 * Ported from `Aircraft.defaultForNewFlight`. Most pilots fly one aircraft, or
 * the same one for a stretch, so defaulting to "None" asked every new flight for
 * an answer that was already known. The last one flown wins over the only one on
 * file, so a second aircraft added mid-season does not keep offering the one it
 * replaced.
 */
fun defaultAircraftForNewFlight(
    lastFlownAircraftId: String?,
    available: List<AircraftEntity>,
): AircraftEntity? {
    lastFlownAircraftId?.let { id -> available.firstOrNull { it.id == id } }?.let { return it }
    return available.singleOrNull()
}
