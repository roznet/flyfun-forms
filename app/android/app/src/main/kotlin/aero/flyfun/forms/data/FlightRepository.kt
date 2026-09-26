package aero.flyfun.forms.data

import aero.flyfun.forms.logic.FlightPeople
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.map
import java.time.Instant

/** Aircraft, flights and the people on them. */
interface FlightRepository {
    fun observeFlights(): Flow<List<FlightEntity>>
    fun observeAircraft(): Flow<List<AircraftEntity>>

    suspend fun flight(id: String): FlightEntity?
    suspend fun aircraft(id: String): AircraftEntity?
    suspend fun allAircraft(): List<AircraftEntity>

    suspend fun saveFlight(flight: FlightEntity)
    suspend fun saveAircraft(aircraft: AircraftEntity)
    suspend fun deleteFlight(id: String)
    suspend fun deleteAircraft(id: String)
    suspend fun restoreFlight(id: String)
    suspend fun restoreAircraft(id: String)

    suspend fun crew(flightId: String): List<PersonEntity>
    suspend fun passengers(flightId: String): List<PersonEntity>
    suspend fun setCrew(flightId: String, personIds: List<String>)
    suspend fun setPassengers(flightId: String, personIds: List<String>)

    /** The aircraft a new flight should start on. */
    suspend fun suggestedAircraft(): AircraftEntity?

    /** Matched the way FPL import normalises: dashes stripped, uppercased. */
    suspend fun aircraftByRegistration(registration: String): AircraftEntity?

    /** Each person's most recent live flight, by person id. */
    fun observeLastFlights(): Flow<Map<String, Instant>>

    /** Who was on each live flight, crew in seat order: suggestions and co-traveller groups. */
    fun observeFlightPeople(): Flow<List<FlightPeople>>
}

class RoomFlightRepository(
    private val flights: FlightDao,
    private val aircraftDao: AircraftDao,
) : FlightRepository {

    override fun observeFlights(): Flow<List<FlightEntity>> = flights.observeAll()
    override fun observeAircraft(): Flow<List<AircraftEntity>> = aircraftDao.observeAll()

    override suspend fun flight(id: String) = flights.byId(id)
    override suspend fun aircraft(id: String) = aircraftDao.byId(id)
    override suspend fun allAircraft() = aircraftDao.all()

    override suspend fun saveFlight(flight: FlightEntity) =
        flights.upsert(flight.copy(updatedAt = Instant.now()))

    override suspend fun saveAircraft(aircraft: AircraftEntity) =
        aircraftDao.upsert(aircraft.copy(updatedAt = Instant.now()))

    override suspend fun deleteFlight(id: String) = flights.softDelete(id, Instant.now())
    override suspend fun deleteAircraft(id: String) = aircraftDao.softDelete(id, Instant.now())

    override suspend fun restoreFlight(id: String) = flights.restore(id, Instant.now())
    override suspend fun restoreAircraft(id: String) = aircraftDao.restore(id, Instant.now())

    override suspend fun crew(flightId: String) = flights.crewOn(flightId)
    override suspend fun passengers(flightId: String) = flights.passengersOn(flightId)

    override suspend fun setCrew(flightId: String, personIds: List<String>) =
        flights.setPeople(flightId, FlightRole.CREW, personIds)

    override suspend fun setPassengers(flightId: String, personIds: List<String>) =
        flights.setPeople(flightId, FlightRole.PASSENGER, personIds)

    override suspend fun suggestedAircraft(): AircraftEntity? =
        defaultAircraftForNewFlight(
            lastFlownAircraftId = flights.lastFlightWithAircraft()?.aircraftId,
            available = aircraftDao.all(),
        )

    override suspend fun aircraftByRegistration(registration: String): AircraftEntity? =
        aircraftDao.byNormalisedRegistration(registration.replace("-", "").uppercase())

    override fun observeLastFlights(): Flow<Map<String, Instant>> =
        flights.observeLastFlights().map { rows -> rows.associate { it.personId to it.lastFlight } }

    override fun observeFlightPeople(): Flow<List<FlightPeople>> =
        combine(flights.observeAll(), flights.observeMemberships()) { all, memberships ->
            val byFlight = memberships.groupBy { it.flightId }
            all.map { flight ->
                val onBoard = byFlight[flight.id].orEmpty().sortedBy { it.seatOrder }
                FlightPeople(
                    flightId = flight.id,
                    departure = flight.departureInstant,
                    aircraftId = flight.aircraftId,
                    crew = onBoard.filter { it.role == FlightRole.CREW }.map { it.personId },
                    passengers = onBoard.filter { it.role == FlightRole.PASSENGER }.map { it.personId },
                )
            }
        }
}
