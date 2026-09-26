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
import aero.flyfun.forms.ui.common.ChoiceField
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import java.time.Instant
import java.time.ZoneOffset

/**
 * One end of a flight: date, time and the zone they are shown in, over a
 * [ZonedWallClock]. Port of iOS `FlightDateTimeField`.
 *
 * The instant is the only thing stored; the zone is how it is read. Switching
 * zone re-displays the same moment, an edit that crosses midnight in the
 * shown zone moves the day, and DST is taken on the flight's own date.
 *
 * [zones] are the route's airport zones in route order. The field starts in
 * UTC and moves to [preferredZone] (the origin for a departure, the
 * destination for an arrival) once it is known, unless the pilot has picked
 * a zone themselves.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ScheduleField(
    label: String,
    instant: Instant,
    onChange: (Instant) -> Unit,
    zones: List<String> = emptyList(),
    preferredZone: String? = null,
) {
    var zoneId by rememberSaveable { mutableStateOf(ZonedWallClock.UTC) }
    var zoneChosen by rememberSaveable { mutableStateOf(false) }
    LaunchedEffect(zones, preferredZone) {
        zoneId = ZonedWallClock.resolvedTimeZoneId(zoneId, zones, preferredZone, zoneChosen)
    }
    val clock = ZonedWallClock(instant, zoneId)
    val isUtc = zoneId == ZonedWallClock.UTC
    var showDate by remember { mutableStateOf(false) }
    var showTime by remember { mutableStateOf(false) }

    Column(Modifier.fillMaxWidth()) {
        Text(label, style = MaterialTheme.typography.labelMedium)
        Row(Modifier.fillMaxWidth(), Arrangement.spacedBy(8.dp)) {
            OutlinedButton(onClick = { showDate = true }, modifier = Modifier.weight(1.4f)) {
                Text(clock.format("d MMM yyyy"))
            }
            OutlinedButton(onClick = { showTime = true }, modifier = Modifier.weight(1f)) {
                Text(if (isUtc) "${clock.format("HH:mm")}Z" else clock.format("HH:mm"))
            }
        }
        val options = ZonedWallClock.timeZoneOptions(zones, instant)
        if (options.size > 1) {
            ChoiceField(
                label = "$label zone",
                selected = options.firstOrNull { it.identifier == zoneId } ?: options.first(),
                options = options,
                display = { it.label },
                onSelect = { zoneId = it.identifier; zoneChosen = true },
            )
        } else if (!isUtc) {
            Text(clock.zoneId, style = MaterialTheme.typography.bodySmall)
        }
    }

    if (showDate) {
        // The picker works in UTC millis: hand it midnight UTC of the day the
        // wall clock shows in its zone, and read the chosen day back the same way.
        val state = rememberDatePickerState(
            initialSelectedDateMillis = java.time.LocalDate.of(clock.year, clock.month, clock.day)
                .atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli(),
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
            title = { Text("$label time (${if (isUtc) "UTC" else clock.zoneId})") },
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
