package aero.flyfun.forms.data

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.TypeConverters
import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase

@Database(
    entities = [
        PersonEntity::class,
        TravelDocumentEntity::class,
        AircraftEntity::class,
        TripEntity::class,
        FlightEntity::class,
        FlightPersonCrossRef::class,
    ],
    version = 2,
    exportSchema = true,
)
@TypeConverters(Converters::class)
abstract class FlyFunDatabase : RoomDatabase() {

    abstract fun personDao(): PersonDao
    abstract fun travelDocumentDao(): TravelDocumentDao
    abstract fun aircraftDao(): AircraftDao
    abstract fun tripDao(): TripDao
    abstract fun flightDao(): FlightDao

    companion object {
        private const val NAME = "flyfun-forms.db"

        @Volatile
        private var instance: FlyFunDatabase? = null

        fun get(context: Context): FlyFunDatabase =
            instance ?: synchronized(this) {
                instance ?: build(context.applicationContext).also { instance = it }
            }

        private fun build(context: Context): FlyFunDatabase =
            Room.databaseBuilder(context, FlyFunDatabase::class.java, NAME)
                // No fallbackToDestructiveMigration: this database holds passport
                // details a pilot typed in by hand, and on Android it is the only
                // copy - there is no CloudKit behind it. Losing it to a schema
                // bump is not an acceptable failure mode, so a missing migration
                // must fail loudly in development instead.
                .addMigrations(MIGRATION_1_2)
                .build()

        /** Per-flight document choice (`FlightEntity.chosenDocNumbers`): one nullable column. */
        val MIGRATION_1_2 = object : Migration(1, 2) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE `flight` ADD COLUMN `chosenDocNumbers` TEXT")
            }
        }
    }
}
