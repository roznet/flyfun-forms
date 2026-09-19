package aero.flyfun.forms.ui.flights

import aero.flyfun.forms.logic.ZonedWallClock
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TimePicker
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.material3.rememberTimePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import java.time.Instant
import java.time.ZoneOffset

/**
 * One end of a flight: a date button and a time button over a [ZonedWallClock].
 *
 * Everything is shown and edited in UTC, which is what flight plans and customs
 * forms are filed in. The wall clock carries the zone so a future release can
 * offer local time without the date arithmetic changing - that is the whole
 * reason the type was ported rather than re-derived.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ScheduleField(
    label: String,
    instant: Instant,
    onChange: (Instant) -> Unit,
) {
    val clock = ZonedWallClock(instant, ZonedWallClock.UTC)
    var showDate by remember { mutableStateOf(false) }
    var showTime by remember { mutableStateOf(false) }

    Column(Modifier.fillMaxWidth()) {
        Text(label, style = MaterialTheme.typography.labelMedium)
        Row(Modifier.fillMaxWidth(), Arrangement.spacedBy(8.dp)) {
            OutlinedButton(onClick = { showDate = true }, modifier = Modifier.weight(1.4f)) {
                Text(clock.format("d MMM yyyy"))
            }
            OutlinedButton(onClick = { showTime = true }, modifier = Modifier.weight(1f)) {
                Text("${clock.format("HH:mm")}Z")
            }
        }
    }

    if (showDate) {
        // The picker works in UTC millis, so a date chosen here is the same
        // calendar day the wall clock shows - no device-timezone round trip.
        val state = rememberDatePickerState(
            initialSelectedDateMillis = clock.instant.toEpochMilli(),
        )
        DatePickerDialog(
            onDismissRequest = { showDate = false },
            confirmButton = {
                TextButton(onClick = {
                    state.selectedDateMillis?.let { millis ->
                        val picked = Instant.ofEpochMilli(millis).atOffset(ZoneOffset.UTC).toLocalDate()
                        onChange(clock.settingDate(picked.year, picked.monthValue, picked.dayOfMonth).instant)
                    }
                    showDate = false
                }) { Text("OK") }
            },
            dismissButton = { TextButton(onClick = { showDate = false }) { Text("Cancel") } },
        ) { DatePicker(state = state) }
    }

    if (showTime) {
        val state = rememberTimePickerState(
            initialHour = clock.hour,
            initialMinute = clock.minute,
            is24Hour = true,
        )
        AlertDialog(
            onDismissRequest = { showTime = false },
            title = { Text("$label time (UTC)") },
            text = { TimePicker(state = state) },
            confirmButton = {
                TextButton(onClick = {
                    onChange(clock.settingHour(state.hour).settingMinute(state.minute).instant)
                    showTime = false
                }) { Text("OK") }
            },
            dismissButton = { TextButton(onClick = { showTime = false }) { Text("Cancel") } },
        )
    }
}
