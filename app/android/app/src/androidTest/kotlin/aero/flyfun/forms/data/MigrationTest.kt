package aero.flyfun.forms.data

import androidx.room.Room
import androidx.room.testing.MigrationTestHelper
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Every migration runs against the exported schema of the version it starts
 * from. The database has no copy behind it, so a migration that loses a row or
 * fails Room's schema check on launch is unrecoverable for the pilot.
 */
@RunWith(AndroidJUnit4::class)
class MigrationTest {

    private val dbName = "migration-test.db"

    @get:Rule
    val helper = MigrationTestHelper(
        InstrumentationRegistry.getInstrumentation(),
        FlyFunDatabase::class.java,
    )

    @After
    fun tearDown() {
        InstrumentationRegistry.getInstrumentation().targetContext.deleteDatabase(dbName)
    }

    @Test
    fun migrate1To2KeepsFlightsWithNoChosenDocuments() = runTest {
        helper.createDatabase(dbName, 1).use { db ->
            db.execSQL(
                "INSERT INTO flight (id, departureInstant, arrivalInstant, originICAO, destinationICAO, " +
                    "nature, legOrder, updatedAt) VALUES ('f1', 1790000000000, 1790006000000, 'LFMD', 'EGTF', " +
                    "'private', 0, 1790000000000)",
            )
        }

        helper.runMigrationsAndValidate(dbName, 2, true, FlyFunDatabase.MIGRATION_1_2).close()

        // Opened through Room, so the entity mapping is checked as well as the SQL.
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val db = Room.databaseBuilder(context, FlyFunDatabase::class.java, dbName)
            .addMigrations(FlyFunDatabase.MIGRATION_1_2)
            .build()
        try {
            val flight = db.flightDao().byId("f1")
            assertNotNull(flight)
            assertEquals("EGTF", flight!!.destinationICAO)
            assertNull(flight.chosenDocNumbers)

            db.flightDao().upsert(flight.copy(chosenDocNumbers = listOf("ZZ1234567")))
            assertEquals(listOf("ZZ1234567"), db.flightDao().byId("f1")?.chosenDocNumbers)
        } finally {
            db.close()
        }
    }
}
