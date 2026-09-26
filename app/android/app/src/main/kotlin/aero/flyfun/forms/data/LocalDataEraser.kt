package aero.flyfun.forms.data

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File

/**
 * "Delete all data": removes everything the app holds about people from this
 * phone, for handing a device on or answering a passenger's erasure request
 * (GDPR Art. 17) in one tap rather than record by record. See legal/GDPR.md §7.
 *
 * Deliberately knows nothing about the account: the sign-in token is not
 * personal data about the people in the app, and signing the pilot out as a
 * side effect would be a surprise. Delete Account is the separate action for
 * the server side.
 */
class LocalDataEraser(
    private val db: FlyFunDatabase,
    private val cacheDir: File,
    /** The web-form WebView's cookies, storage and cache. Main thread; injected so tests need no WebView. */
    private val clearWebStorage: () -> Unit,
) {

    suspend fun eraseAll() {
        // Every table in the @Database entities list, tombstones included, so
        // nothing is left for a later export to carry. Room also checkpoints the
        // WAL and VACUUMs, so the rows do not linger in free pages on disk.
        withContext(Dispatchers.IO) { db.clearAllTables() }
        // Generated forms and move-my-data exports share this folder.
        withContext(Dispatchers.IO) { FormFiles.purge(cacheDir) }
        // Last, and never fatal: the database is what matters, and a missing
        // WebView provider must not make the whole erase look like it failed.
        withContext(Dispatchers.Main) { runCatching { clearWebStorage() } }
    }
}
