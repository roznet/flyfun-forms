package aero.flyfun.forms.data

import aero.flyfun.forms.logic.AircraftRecord
import aero.flyfun.forms.logic.DataFileCrypto
import aero.flyfun.forms.logic.FlightPersonRecord
import aero.flyfun.forms.logic.FlightRecord
import aero.flyfun.forms.logic.InterchangeDocument
import aero.flyfun.forms.logic.InterchangeMerge
import aero.flyfun.forms.logic.MergeSummary
import aero.flyfun.forms.logic.PersonRecord
import aero.flyfun.forms.logic.TravelDocumentRecord
import aero.flyfun.forms.logic.TripExtras
import aero.flyfun.forms.logic.TripRecord
import androidx.room.withTransaction
import java.time.Instant
import java.time.LocalDate

/**
 * Moves the whole dataset in and out of the app.
 *
 * Two features, one serializer: an encrypted file for carrying data to another
 * device, and a plaintext one for GDPR Art. 20 portability. They differ only in
 * the wrapper. See designs/future/move-my-data.md.
 */
class DataTransfer(private val db: FlyFunDatabase) {

    // --- Export ---

    suspend fun snapshot(appVersion: String): InterchangeDocument {
        // allIncludingDeleted, never the live-rows query: a tombstone left out
        // of the export means the deletion never reaches the other device, and
        // the record quietly comes back on the next import.
        val people = db.personDao().allIncludingDeleted()
        val flights = db.flightDao().allIncludingDeleted()
        return InterchangeDocument(
            exportedAt = Instant.now().toString(),
            exportedBy = aero.flyfun.forms.logic.ExportedBy("android", appVersion),
            people = people.map { it.toRecord() },
            travelDocuments = db.travelDocumentDao().allIncludingDeleted().map { it.toRecord() },
            aircraft = db.aircraftDao().allIncludingDeleted().map { it.toRecord() },
            trips = db.tripDao().allIncludingDeleted().map { it.toRecord() },
            flights = flights.map { it.toRecord() },
            flightPeople = db.flightDao().allMemberships().map {
                FlightPersonRecord(it.flightId, it.personId, it.role, it.seatOrder)
            },
        )
    }

    /** Encrypted, for moving to another device. */
    suspend fun exportEncrypted(appVersion: String, password: CharArray): ByteArray =
        DataFileCrypto.encrypt(InterchangeMerge.encode(snapshot(appVersion)), password)

    /** Plaintext, for the GDPR portability export. Machine-readable by design. */
    suspend fun exportPlain(appVersion: String): String =
        InterchangeMerge.encode(snapshot(appVersion))

    // --- Import ---

    /** Decode without writing anything, so the user can be shown what will change. */
    suspend fun preview(bytes: ByteArray, password: CharArray?): Pair<InterchangeDocument, MergeSummary> {
        val text = if (DataFileCrypto.looksEncrypted(bytes)) {
            val pw = password ?: throw IllegalArgumentException("This file needs its password.")
            DataFileCrypto.decrypt(bytes, pw)
        } else {
            String(bytes, Charsets.UTF_8)
        }
        val document = InterchangeMerge.decode(text)
        return document to InterchangeMerge.summarise(localSnapshot(), document)
    }

    /**
     * Apply a previously previewed merge.
     *
     * One transaction: a half-applied import of passport records is worse than
     * a failed one.
     */
    suspend fun apply(summary: MergeSummary) = db.withTransaction {
        val people = db.personDao()
        val documents = db.travelDocumentDao()
        val aircraft = db.aircraftDao()
        val trips = db.tripDao()
        val flights = db.flightDao()

        // Order matters: parents before children, because of the foreign keys.
        (summary.people.insert + summary.people.update).forEach { people.upsert(it.toEntity()) }
        summary.people.remove.forEach { people.softDelete(it.id, Instant.parse(it.deletedAt)) }

        (summary.aircraft.insert + summary.aircraft.update).forEach { aircraft.upsert(it.toEntity()) }
        summary.aircraft.remove.forEach { aircraft.softDelete(it.id, Instant.parse(it.deletedAt)) }

        (summary.trips.insert + summary.trips.update).forEach { trips.upsert(it.toEntity()) }
        summary.trips.remove.forEach { trips.softDelete(it.id, Instant.parse(it.deletedAt)) }

        (summary.travelDocuments.insert + summary.travelDocuments.update)
            .forEach { documents.upsert(it.toEntity()) }
        summary.travelDocuments.remove.forEach { documents.softDelete(it.id, Instant.parse(it.deletedAt)) }

        (summary.flights.insert + summary.flights.update).forEach { flights.upsert(it.toEntity()) }
        summary.flights.remove.forEach { flights.softDelete(it.id, Instant.parse(it.deletedAt)) }

        summary.flightPeople
            .groupBy { it.flightId to it.role }
            .forEach { (key, refs) ->
                flights.setPeople(key.first, key.second, refs.sortedBy { it.seatOrder }.map { it.personId })
            }
    }

    private suspend fun localSnapshot() = InterchangeMerge.LocalSnapshot(
        people = db.personDao().allIncludingDeleted().map { it.toRecord() },
        travelDocuments = db.travelDocumentDao().allIncludingDeleted().map { it.toRecord() },
        aircraft = db.aircraftDao().allIncludingDeleted().map { it.toRecord() },
        trips = db.tripDao().allIncludingDeleted().map { it.toRecord() },
        flights = db.flightDao().allIncludingDeleted().map { it.toRecord() },
    )
}

// --- Entity <-> record. Instants are ISO with Z; calendar days stay plain dates. ---

private fun PersonEntity.toRecord() = PersonRecord(
    id = id, firstName = firstName, lastName = lastName,
    dateOfBirth = dateOfBirth?.toString(), sex = sex, placeOfBirth = placeOfBirth,
    address = address, phone = phone, email = email, isUsualCrew = isUsualCrew,
    updatedAt = updatedAt.toString(), deletedAt = deletedAt?.toString(),
)

private fun PersonRecord.toEntity() = PersonEntity(
    id = id, firstName = firstName, lastName = lastName,
    dateOfBirth = dateOfBirth?.let(LocalDate::parse), sex = sex, placeOfBirth = placeOfBirth,
    address = address, phone = phone, email = email, isUsualCrew = isUsualCrew,
    updatedAt = Instant.parse(updatedAt), deletedAt = deletedAt?.let(Instant::parse),
)

private fun TravelDocumentEntity.toRecord() = TravelDocumentRecord(
    id = id, personId = personId, docType = docType, docNumber = docNumber,
    issuingCountry = issuingCountry, expiryDate = expiryDate?.toString(), isActive = isActive,
    updatedAt = updatedAt.toString(), deletedAt = deletedAt?.toString(),
)

private fun TravelDocumentRecord.toEntity() = TravelDocumentEntity(
    id = id, personId = personId, docType = docType, docNumber = docNumber,
    issuingCountry = issuingCountry, expiryDate = expiryDate?.let(LocalDate::parse), isActive = isActive,
    updatedAt = Instant.parse(updatedAt), deletedAt = deletedAt?.let(Instant::parse),
)

private fun AircraftEntity.toRecord() = AircraftRecord(
    id = id, registration = registration, type = type, owner = owner,
    ownerAddress = ownerAddress, isAirplane = isAirplane, usualBase = usualBase,
    ownerPersonId = ownerPersonId, useCompanyOperator = useCompanyOperator,
    operatorName = operatorName,
    updatedAt = updatedAt.toString(), deletedAt = deletedAt?.toString(),
)

private fun AircraftRecord.toEntity() = AircraftEntity(
    id = id, registration = registration, type = type, owner = owner,
    ownerAddress = ownerAddress, isAirplane = isAirplane, usualBase = usualBase,
    ownerPersonId = ownerPersonId, useCompanyOperator = useCompanyOperator,
    operatorName = operatorName,
    updatedAt = Instant.parse(updatedAt), deletedAt = deletedAt?.let(Instant::parse),
)

private fun TripEntity.toRecord() = TripRecord(
    id = id, name = name, createdAt = createdAt.toString(),
    extraFields = TripExtras.decode(extraFieldsJson),
    updatedAt = updatedAt.toString(), deletedAt = deletedAt?.toString(),
)

private fun TripRecord.toEntity() = TripEntity(
    id = id, name = name, createdAt = Instant.parse(createdAt),
    extraFieldsJson = TripExtras.encode(extraFields),
    updatedAt = Instant.parse(updatedAt), deletedAt = deletedAt?.let(Instant::parse),
)

private fun FlightEntity.toRecord() = FlightRecord(
    id = id, originICAO = originICAO, destinationICAO = destinationICAO,
    departureInstant = departureInstant.toString(), arrivalInstant = arrivalInstant.toString(),
    nature = nature, observations = observations, contact = contact, reasonForVisit = reasonForVisit,
    aircraftId = aircraftId, responsiblePersonId = responsiblePersonId, tripId = tripId,
    legOrder = legOrder,
    updatedAt = updatedAt.toString(), deletedAt = deletedAt?.toString(),
)

private fun FlightRecord.toEntity() = FlightEntity(
    id = id, originICAO = originICAO, destinationICAO = destinationICAO,
    departureInstant = Instant.parse(departureInstant), arrivalInstant = Instant.parse(arrivalInstant),
    nature = nature, observations = observations, contact = contact, reasonForVisit = reasonForVisit,
    aircraftId = aircraftId, responsiblePersonId = responsiblePersonId, tripId = tripId,
    legOrder = legOrder,
    updatedAt = Instant.parse(updatedAt), deletedAt = deletedAt?.let(Instant::parse),
)
