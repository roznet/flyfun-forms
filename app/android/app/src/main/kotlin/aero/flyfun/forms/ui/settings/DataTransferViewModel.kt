package aero.flyfun.forms.ui.settings

import android.content.res.Resources
import aero.flyfun.forms.R
import aero.flyfun.forms.data.DataTransfer
import aero.flyfun.forms.data.FormFiles
import aero.flyfun.forms.logic.DataFileCrypto
import aero.flyfun.forms.logic.InterchangeMerge
import aero.flyfun.forms.logic.MergeSummary
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.io.File

sealed interface TransferState {
    data object Idle : TransferState
    data object Working : TransferState

    /** Export finished; the passphrase is shown once and never stored. */
    data class Exported(val file: File, val passphrase: String?) : TransferState

    /** Decoded but nothing written yet - the user confirms from here. */
    data class Previewed(val summary: MergeSummary) : TransferState
    data class Imported(val summary: MergeSummary) : TransferState
    data class NeedsPassword(val bytes: ByteArray) : TransferState {
        override fun equals(other: Any?) = this === other
        override fun hashCode() = System.identityHashCode(this)
    }
    data class Failed(val message: String) : TransferState
}

class DataTransferViewModel(
    private val transfer: DataTransfer,
    private val cacheDir: File,
    private val appVersion: String,
    /** The app's (not an activity's) resources, for messages this shows; see strings.xml. */
    private val resources: Resources,
) : ViewModel() {

    private val _state = MutableStateFlow<TransferState>(TransferState.Idle)
    val state = _state.asStateFlow()

    private var pending: MergeSummary? = null

    fun exportEncrypted() = viewModelScope.launch {
        _state.value = TransferState.Working
        _state.value = runCatching {
            val passphrase = DataFileCrypto.generatePassphrase()
            val bytes = transfer.exportEncrypted(appVersion, passphrase.toCharArray())
            val file = outDir().resolve("flyfun-forms-data.ffdata")
            file.writeBytes(bytes)
            TransferState.Exported(file, passphrase)
        }.getOrElse { TransferState.Failed(it.message ?: resources.getString(R.string.settings_export_failed)) }
    }

    /** GDPR Art. 20: machine-readable, and deliberately not encrypted. */
    fun exportPlain() = viewModelScope.launch {
        _state.value = TransferState.Working
        _state.value = runCatching {
            val file = outDir().resolve("flyfun-forms-export.json")
            file.writeText(transfer.exportPlain(appVersion))
            TransferState.Exported(file, null)
        }.getOrElse { TransferState.Failed(it.message ?: resources.getString(R.string.settings_export_failed)) }
    }

    fun previewImport(bytes: ByteArray, password: String? = null) = viewModelScope.launch {
        _state.value = TransferState.Working
        if (DataFileCrypto.looksEncrypted(bytes) && password == null) {
            _state.value = TransferState.NeedsPassword(bytes)
            return@launch
        }
        _state.value = runCatching {
            val (_, summary) = transfer.preview(bytes, password?.toCharArray())
            pending = summary
            TransferState.Previewed(summary)
        }.getOrElse {
            when (it) {
                is DataFileCrypto.WrongPasswordException ->
                    TransferState.Failed(resources.getString(R.string.settings_wrong_password))
                else -> TransferState.Failed(it.message ?: resources.getString(R.string.settings_could_not_read_file))
            }
        }
    }

    fun confirmImport() = viewModelScope.launch {
        val summary = pending ?: return@launch
        _state.value = TransferState.Working
        _state.value = runCatching {
            transfer.apply(summary)
            pending = null
            TransferState.Imported(summary)
        }.getOrElse { TransferState.Failed(it.message ?: resources.getString(R.string.settings_import_failed)) }
    }

    fun reset() {
        pending = null
        _state.value = TransferState.Idle
    }

    // Same directory as generated forms, so the same purge clears exports.
    private fun outDir() = FormFiles.dir(cacheDir)

    /** Kept so the import sheet can describe what it is about to do. */
    val mergeDescription: String? get() = pending?.describe()

    @Suppress("unused")
    private val encoder = InterchangeMerge
}
