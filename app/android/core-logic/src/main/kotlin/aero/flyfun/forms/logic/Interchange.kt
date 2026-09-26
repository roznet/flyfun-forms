package aero.flyfun.forms.logic

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/**
 * The "move my data" interchange format.
 *
 * Spec: designs/future/move-my-data.md. Flat arrays with an explicit join
 * table, deliberately not a nested object graph - nesting forces ownership
 * decisions and makes per-record merge awkward, while flat arrays map 1:1 onto
 * both SwiftData objects and Room entities and merge independently.
 *
 * Every record carries `updatedAt` and a nullable `deletedAt` tombstone, which
 * is what lets a merge decide which side of a conflict is newer and stops a
 * deletion being silently undone by an import.
 *
 * Dates: absolute moments are ISO-8601 with an explicit `Z`; calendar days
 * (a birth date, a passport expiry) are plain `YYYY-MM-DD`. Those are facts
 * printed on a document and carry no timezone.
 */
@Serializable
data class InterchangeDocument(
    val format: String = FORMAT,
    val version: Int = VERSION,
    val exportedAt: String,
    val exportedBy: ExportedBy = ExportedBy(),
    val people: List<PersonRecord> = emptyList(),
    val travelDocuments: List<TravelDocumentRecord> = emptyList(),
    val aircraft: List<AircraftRecord> = emptyList(),
    val trips: List<TripRecord> = emptyList(),
    val flights: List<FlightRecord> = emptyList(),
    val flightPeople: List<FlightPersonRecord> = emptyList(),
) {
    companion object {
        const val FORMAT = "flyfun-forms/data"
        const val VERSION = 1
    }
}

@Serializable
data class ExportedBy(val platform: String = "android", val appVersion: String = "")

/** Common shape every mergeable record shares. */
interface InterchangeRecord {
    val id: String
    val updatedAt: String
    val deletedAt: String?
}

@Serializable
data class PersonRecord(
    override val id: String,
    val firstName: String = "",
    val lastName: String = "",
    val dateOfBirth: String? = null,
    val sex: String? = null,
    val placeOfBirth: String? = null,
    val address: String? = null,
    val phone: String? = null,
    val email: String? = null,
    val isUsualCrew: Boolean = false,
    override val updatedAt: String,
    override val deletedAt: String? = null,
) : InterchangeRecord

@Serializable
data class TravelDocumentRecord(
    override val id: String,
    val personId: String,
    val docType: String = "Passport",
    val docNumber: String = "",
    val issuingCountry: String? = null,
    val expiryDate: String? = null,
    val isActive: Boolean = true,
    override val updatedAt: String,
    override val deletedAt: String? = null,
) : InterchangeRecord

@Serializable
data class AircraftRecord(
    override val id: String,
    val registration: String = "",
    val type: String = "",
    val owner: String? = null,
    val ownerAddress: String? = null,
    val isAirplane: Boolean = true,
    val usualBase: String? = null,
    val ownerPersonId: String? = null,
    val useCompanyOperator: Boolean = false,
    val operatorName: String? = null,
    override val updatedAt: String,
    override val deletedAt: String? = null,
) : InterchangeRecord

@Serializable
data class TripRecord(
    override val id: String,
    val name: String = "",
    val createdAt: String,
    val extraFields: Map<String, String> = emptyMap(),
    override val updatedAt: String,
    override val deletedAt: String? = null,
) : InterchangeRecord

@Serializable
data class FlightRecord(
    override val id: String,
    val originICAO: String = "",
    val destinationICAO: String = "",
    val departureInstant: String,
    val arrivalInstant: String,
    val nature: String = "private",
    val observations: String? = null,
    val contact: String? = null,
    val reasonForVisit: String? = null,
    val aircraftId: String? = null,
    val responsiblePersonId: String? = null,
    val tripId: String? = null,
    val legOrder: Int = 0,
    /** Documents picked by hand for this flight, by number. Absent in files from before it existed. */
    val chosenDocNumbers: List<String>? = null,
    override val updatedAt: String,
    override val deletedAt: String? = null,
) : InterchangeRecord

/** Not versioned per-row: membership travels with its flight. */
@Serializable
data class FlightPersonRecord(
    val flightId: String,
    val personId: String,
    val role: String,
    @SerialName("seatOrder") val seatOrder: Int = 0,
)

/** What an import would do, shown to the user before anything is written. */
data class MergeOutcome<T>(
    val insert: List<T> = emptyList(),
    val update: List<T> = emptyList(),
    val remove: List<T> = emptyList(),
    val unchanged: Int = 0,
)

data class MergeSummary(
    val people: MergeOutcome<PersonRecord> = MergeOutcome(),
    val travelDocuments: MergeOutcome<TravelDocumentRecord> = MergeOutcome(),
    val aircraft: MergeOutcome<AircraftRecord> = MergeOutcome(),
    val trips: MergeOutcome<TripRecord> = MergeOutcome(),
    val flights: MergeOutcome<FlightRecord> = MergeOutcome(),
    val flightPeople: List<FlightPersonRecord> = emptyList(),
) {
    val inserted: Int get() = counts { it.insert.size }
    val updated: Int get() = counts { it.update.size }
    val removed: Int get() = counts { it.remove.size }
    val untouched: Int get() = counts { it.unchanged }

    private fun counts(pick: (MergeOutcome<*>) -> Int): Int =
        pick(people) + pick(travelDocuments) + pick(aircraft) + pick(trips) + pick(flights)

    /** One line for the confirm sheet. */
    fun describe(): String = buildString {
        append("$inserted new")
        append(" · $updated updated")
        append(" · $removed removed")
        append(" · $untouched unchanged")
    }
}

object InterchangeMerge {

    /**
     * Compare two ISO-8601 timestamps as instants, not as strings.
     *
     * `Instant.toString()` emits 0, 3, 6 or 9 fractional digits depending on
     * precision, so a plain string compare puts "…:12Z" after "…:12.500Z" even
     * though it is half a second earlier. Falls back to string order only if a
     * value is unparseable, which should not happen in a file we wrote.
     */
    internal fun isNewer(incoming: String, existing: String): Boolean =
        runCatching {
            java.time.Instant.parse(incoming) > java.time.Instant.parse(existing)
        }.getOrElse { incoming > existing }

    val json = Json {
        prettyPrint = true
        ignoreUnknownKeys = true
        explicitNulls = false
        encodeDefaults = true
    }

    /**
     * Decide what an import changes, per record.
     *
     * Rules, from move-my-data.md section 6:
     *  - in the file but not local -> insert
     *  - in both -> the newer `updatedAt` wins, whole record
     *  - local only -> keep; an import never deletes what the file does not mention
     *  - a tombstone newer than the local row -> remove
     *
     * Never destructive by surprise: the caller shows this before applying it.
     */
    fun <T : InterchangeRecord> merge(local: List<T>, incoming: List<T>): MergeOutcome<T> {
        val byId = local.associateBy { it.id }
        val insert = mutableListOf<T>()
        val update = mutableListOf<T>()
        val remove = mutableListOf<T>()
        var unchanged = 0

        for (record in incoming) {
            val existing = byId[record.id]
            when {
                existing == null ->
                    if (record.deletedAt == null) insert += record else unchanged++
                !isNewer(record.updatedAt, existing.updatedAt) -> unchanged++
                record.deletedAt != null -> remove += record
                else -> update += record
            }
        }
        return MergeOutcome(insert, update, remove, unchanged)
    }

    fun summarise(local: LocalSnapshot, document: InterchangeDocument): MergeSummary {
        val flights = merge(local.flights, document.flights)
        // Membership is not independently versioned - it rides with its flight,
        // and only for flights this merge is actually going to write.
        val writtenFlightIds = (flights.insert + flights.update).mapTo(mutableSetOf()) { it.id }
        return MergeSummary(
            people = merge(local.people, document.people),
            travelDocuments = merge(local.travelDocuments, document.travelDocuments),
            aircraft = merge(local.aircraft, document.aircraft),
            trips = merge(local.trips, document.trips),
            flights = flights,
            flightPeople = document.flightPeople.filter { it.flightId in writtenFlightIds },
        )
    }

    /** Everything currently held, in interchange shape. */
    data class LocalSnapshot(
        val people: List<PersonRecord> = emptyList(),
        val travelDocuments: List<TravelDocumentRecord> = emptyList(),
        val aircraft: List<AircraftRecord> = emptyList(),
        val trips: List<TripRecord> = emptyList(),
        val flights: List<FlightRecord> = emptyList(),
    )

    fun encode(document: InterchangeDocument): String =
        json.encodeToString(InterchangeDocument.serializer(), document)

    /**
     * @throws IllegalArgumentException when the file is not one of ours, or is a
     *   version this build cannot read. Better to say so than to half-import.
     */
    fun decode(text: String): InterchangeDocument {
        val document = runCatching {
            json.decodeFromString(InterchangeDocument.serializer(), text)
        }.getOrElse { throw IllegalArgumentException("This is not a FlyFun Forms data file.") }

        require(document.format == InterchangeDocument.FORMAT) {
            "This is not a FlyFun Forms data file."
        }
        require(document.version <= InterchangeDocument.VERSION) {
            "This file was written by a newer version of the app."
        }
        return document
    }
}
