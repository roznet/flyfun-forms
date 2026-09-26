package aero.flyfun.forms.ui.people

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.DisplayMode
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.SelectableDates
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import java.time.LocalDate
import java.time.format.DateTimeFormatter

private val displayFormat: DateTimeFormatter = DateTimeFormatter.ofPattern("d MMM yyyy")
private const val MILLIS_PER_DAY = 86_400_000L

/**
 * A calendar date that may be unset - the counterpart of iOS's
 * `OptionalDatePicker`.
 *
 * The dialog opens in text-input mode: a date of birth or an expiry is copied
 * off a document, and typing it beats paging a calendar back fifty years. The
 * mode toggle is still there for anyone who prefers the calendar.
 *
 * The picker works in UTC millis, and a [LocalDate] is mapped through its epoch
 * day, so no device timezone can shift the chosen day.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun OptionalDateField(
    label: String,
    value: LocalDate?,
    onChange: (LocalDate?) -> Unit,
    modifier: Modifier = Modifier,
    yearRange: IntRange = 1900..LocalDate.now().year + 20,
    latest: LocalDate? = null,
) {
    var showPicker by remember { mutableStateOf(false) }

    Row(
        modifier = modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(label, style = MaterialTheme.typography.bodyLarge)
        Row(verticalAlignment = Alignment.CenterVertically) {
            OutlinedButton(onClick = { showPicker = true }) {
                Text(value?.format(displayFormat) ?: "Set")
            }
            if (value != null) {
                IconButton(onClick = { onChange(null) }) {
                    Icon(Icons.Default.Clear, contentDescription = "Clear $label")
                }
            }
        }
    }

    if (showPicker) {
        val latestMillis = latest?.toEpochDay()?.times(MILLIS_PER_DAY)
        val state = rememberDatePickerState(
            initialSelectedDateMillis = value?.toEpochDay()?.times(MILLIS_PER_DAY),
            yearRange = yearRange,
            initialDisplayMode = DisplayMode.Input,
            selectableDates = object : SelectableDates {
                override fun isSelectableDate(utcTimeMillis: Long) =
                    latestMillis == null || utcTimeMillis <= latestMillis
            },
        )
        DatePickerDialog(
            onDismissRequest = { showPicker = false },
            confirmButton = {
                TextButton(onClick = {
                    state.selectedDateMillis?.let { onChange(LocalDate.ofEpochDay(Math.floorDiv(it, MILLIS_PER_DAY))) }
                    showPicker = false
                }) { Text("OK") }
            },
            dismissButton = { TextButton(onClick = { showPicker = false }) { Text("Cancel") } },
        ) { DatePicker(state = state, title = { Text(label, modifier = Modifier.padding(start = 24.dp, end = 12.dp, top = 16.dp)) }) }
    }
}
