package aero.flyfun.forms.data

import kotlinx.coroutines.flow.Flow
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

    suspend fun crew(flightId: String): List<PersonEntity>
    suspend fun passengers(flightId: String): List<PersonEntity>
    suspend fun setCrew(flightId: String, personIds: List<String>)
    suspend fun setPassengers(flightId: String, personIds: List<String>)

    /** The aircraft a new flight should start on. */
    suspend fun suggestedAircraft(): AircraftEntity?

    /** Matched the way FPL import normalises: dashes stripped, uppercased. */
    suspend fun aircraftByRegistration(registration: String): AircraftEntity?
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
}
