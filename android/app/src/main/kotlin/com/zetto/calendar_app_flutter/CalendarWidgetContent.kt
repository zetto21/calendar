package com.zetto.calendar_app_flutter

import java.util.Calendar
import java.util.Date
import java.util.GregorianCalendar
import java.util.Locale
import java.text.SimpleDateFormat

internal enum class CalendarWidgetKind { AGENDA, TODAY, NEXT, MONTH }
internal data class WidgetEvent(val date: String, val time: String?, val duration: Int, val title: String)
internal object CalendarWidgetContent {
    fun monthDays(now: Date): List<Int?> {
        val month = GregorianCalendar().apply { time = now; set(Calendar.DAY_OF_MONTH, 1) }
        val offset = month.get(Calendar.DAY_OF_WEEK) - Calendar.SUNDAY
        val days = month.getActualMaximum(Calendar.DAY_OF_MONTH)
        return (0 until 42).map { if (it in offset until offset + days) it - offset + 1 else null }
    }
    fun nextEvent(events: List<WidgetEvent>, now: Date): WidgetEvent? {
        val today = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(now)
        val clock = Calendar.getInstance().apply { time = now }
        val minute = clock.get(Calendar.HOUR_OF_DAY) * 60 + clock.get(Calendar.MINUTE)
        val candidates = events.filter { event ->
            event.date > today || (event.date == today && (event.time == null ||
                startMinute(event.time) + event.duration.coerceAtLeast(1) > minute))
        }
        return candidates.minWithOrNull(compareBy<WidgetEvent> { it.date }
            .thenBy { if (it.date == today && it.time != null) 0 else 1 }
            .thenBy { it.time ?: "" })
    }
    private fun startMinute(time: String): Int {
        val parts = time.split(':')
        return (parts.getOrNull(0)?.toIntOrNull() ?: 0) * 60 + (parts.getOrNull(1)?.toIntOrNull() ?: 0)
    }
}
