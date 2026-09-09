"""Date/time conversion shared by the form fillers.

Requests always carry UTC.  A form that prints the airport's wall clock
("Heure Locale") declares ``time_reference: "local"`` and a ``time_zone``
in its mapping.
"""

from datetime import datetime
from zoneinfo import ZoneInfo


def utc_to_local(date_str: str, time_str: str, tz_name: str) -> tuple[str, str]:
    """Convert a YYYY-MM-DD / HH:MM pair from UTC to *tz_name*.

    Date and time must convert together: a UTC evening can land on the next
    day locally (23:50Z on 1 June is 01:50 on 2 June in Paris), so printing a
    converted time against the original UTC date would misdate the flight by
    a day on a customs pre-notification.

    The date comes back as YYYY-MM-DD, for the caller to format.
    """
    dt = datetime.strptime(f"{date_str} {time_str}", "%Y-%m-%d %H:%M")
    local = dt.replace(tzinfo=ZoneInfo("UTC")).astimezone(ZoneInfo(tz_name))
    return local.strftime("%Y-%m-%d"), local.strftime("%H:%M")
