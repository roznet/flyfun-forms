package aero.flyfun.forms.data

import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey
import java.time.Instant
import java.time.LocalDate
import java.util.UUID

/**
 * Every entity carries three fields the iOS SwiftData models do not have:
 *
 *  - `id`, a UUID string rather than an opaque PersistentIdentifier. Stable
 *    across devices, which is what makes export/import and any future sync
 *    possible at all. SwiftData + CloudKit cannot express a unique constraint;
 *    Room can, and we want one.
 *  - `updatedAt`, so a merge can decide which side of a conflict is newer.
 *  - `deletedAt`, a tombstone. Without it, importing a file from a device where
 *    a row was deleted silently resurrects it.
 *
 * See designs/future/move-my-data.md section 6 and android-app.md section 3.
 */
private fun newId(): String = UUID.randomUUID().toString()

@Entity(
    tableName = "person",
    indices = [Index("lastName"), Index("deletedAt")],
)
data class PersonEntity(
    @PrimaryKey val id: String = newId(),
    val firstName: String = "",
    val lastName: String = "",
    val dateOfBirth: LocalDate? = null,
    val sex: String? = null,
    val placeOfBirth: String? = null,
    val address: String? = null,
    val phone: String? = null,
    val email: String? = null,
    val isUsualCrew: Boolean = false,
    val updatedAt: Instant = Instant.now(),
    val deletedAt: Instant? = null,
) {
    val displayName: String
        get() = "$firstName $lastName".trim()
}

@Entity(
    tableName = "travel_document",
    foreignKeys = [
        ForeignKey(
            entity = PersonEntity::class,
            parentColumns = ["id"],
            childColumns = ["personId"],
            onDelete = ForeignKey.CASCADE,
        ),
    ],
    indices = [Index("personId"), Index("deletedAt")],
)
data class TravelDocumentEntity(
    @PrimaryKey val id: String = newId(),
    val personId: String,
    val docType: String = "Passport",
    val docNumber: String = "",
    /** ISO alpha-3, e.g. FRA, GBR. Nationality derives from this, never from the person. */
    val issuingCountry: String? = null,
    val expiryDate: LocalDate? = null,
    val isActive: Boolean = true,
    val updatedAt: Instant = Instant.now(),
    val deletedAt: Instant? = null,
)

@Entity(
    tableName = "aircraft",
    foreignKeys = [
        ForeignKey(
            entity = PersonEntity::class,
            parentColumns = ["id"],
            childColumns = ["ownerPersonId"],
            onDelete = ForeignKey.SET_NULL,
        ),
    ],
    indices = [Index("registration"), Index("ownerPersonId"), Index("deletedAt")],
)
data class AircraftEntity(
    @PrimaryKey val id: String = newId(),
    val registration: String = "",
    val type: String = "",
    val owner: String? = null,
    val ownerAddress: String? = null,
    val isAirplane: Boolean = true,
    val usualBase: String? = null,
    val ownerPersonId: String? = null,
    val useCompanyOperator: Boolean = false,
    val operatorName: String? = null,
    val updatedAt: Instant = Instant.now(),
    val deletedAt: Instant? = null,
)

@Entity(
    tableName = "trip",
    indices = [Index("deletedAt")],
)
data class TripEntity(
    @PrimaryKey val id: String = newId(),
    val name: String = "",
    val createdAt: Instant = Instant.now(),
    /** Form-specific extras, JSON-encoded map, as on iOS. */
    val extraFieldsJson: String? = null,
    val updatedAt: Instant = Instant.now(),
    val deletedAt: Instant? = null,
)

/**
 * The schedule is stored as two absolute instants.
 *
 * iOS still dual-writes a `departureDate` + `departureTimeUTC` pair alongside
 * the instants, because CloudKit syncs its store between devices running
 * different app versions and an older build writes only the pair. Android is a
 * new store with no legacy rows and no such constraint, so it inherits only the
 * representation iOS is migrating towards. See Models/Flight.swift lines 7-27.
 */
@Entity(
    tableName = "flight",
    foreignKeys = [
        ForeignKey(
            entity = AircraftEntity::class,
            parentColumns = ["id"],
            childColumns = ["aircraftId"],
            onDelete = ForeignKey.SET_NULL,
        ),
        ForeignKey(
            entity = PersonEntity::class,
            parentColumns = ["id"],
            childColumns = ["responsiblePersonId"],
            onDelete = ForeignKey.SET_NULL,
        ),
        ForeignKey(
            entity = TripEntity::class,
            parentColumns = ["id"],
            childColumns = ["tripId"],
            onDelete = ForeignKey.SET_NULL,
        ),
    ],
    indices = [
        Index("aircraftId"), Index("responsiblePersonId"), Index("tripId"),
        Index("departureInstant"), Index("deletedAt"),
    ],
)
data class FlightEntity(
    @PrimaryKey val id: String = newId(),
    val departureInstant: Instant,
    val arrivalInstant: Instant,
    val originICAO: String = "",
    val destinationICAO: String = "",
    val nature: String = "private",
    val observations: String? = null,
    val contact: String? = null,
    val reasonForVisit: String? = null,
    val aircraftId: String? = null,
    val responsiblePersonId: String? = null,
    val tripId: String? = null,
    val legOrder: Int = 0,
    val updatedAt: Instant = Instant.now(),
    val deletedAt: Instant? = null,
)

/** Roles a person can hold on a flight. */
object FlightRole {
    const val CREW = "crew"
    const val PASSENGER = "passenger"
}

/**
 * One junction with a `role` column, rather than iOS's two separate
 * relationships. "Everyone on this flight" is then a single query.
 *
 * Room's @Relation/@Junction cannot filter on a junction's own columns, so
 * role-specific reads are explicit @Query in [aero.flyfun.forms.data.FlightDao].
 */
@Entity(
    tableName = "flight_person",
    primaryKeys = ["flightId", "personId", "role"],
    foreignKeys = [
        ForeignKey(
            entity = FlightEntity::class,
            parentColumns = ["id"],
            childColumns = ["flightId"],
            onDelete = ForeignKey.CASCADE,
        ),
        ForeignKey(
            entity = PersonEntity::class,
            parentColumns = ["id"],
            childColumns = ["personId"],
            onDelete = ForeignKey.CASCADE,
        ),
    ],
    indices = [Index("personId"), Index("flightId")],
)
data class FlightPersonCrossRef(
    val flightId: String,
    val personId: String,
    val role: String,
    val seatOrder: Int = 0,
)
