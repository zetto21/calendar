package com.zetto.calendar_app_flutter

import java.util.GregorianCalendar
import org.junit.Assert.*
import org.junit.Test

class CalendarWidgetContentTest {
    private fun now(year: Int, month: Int, day: Int, hour: Int = 10, minute: Int = 0) =
        GregorianCalendar(year, month - 1, day, hour, minute).time

    @Test fun leapMonthStartsInCorrectWeekdayAndIncludesLeapDay() {
        val cells = CalendarWidgetContent.monthDays(now(2024, 2, 10))
        assertEquals(42, cells.size)
        assertEquals(listOf(null, null, null, null, 1, 2, 3), cells.take(7))
        assertEquals((1..29).toList(), cells.filterNotNull())
    }
    @Test fun monthStartingSundayDoesNotAddAnEmptyWeek() {
        val cells = CalendarWidgetContent.monthDays(now(2026, 2, 1))
        assertEquals(1, cells.first())
        assertEquals(28, cells.filterNotNull().last())
        assertEquals(14, cells.count { it == null })
    }
    @Test fun nextEventSkipsEndedEventsAndPrefersOngoingOrUpcomingToday() {
        val ended = WidgetEvent("2026-10-07", "08:00", 60, "종료")
        val allDay = WidgetEvent("2026-10-07", null, 0, "종일")
        val ongoing = WidgetEvent("2026-10-07", "09:30", 60, "진행 중")
        val upcoming = WidgetEvent("2026-10-07", "14:00", 60, "예정")
        val tomorrow = WidgetEvent("2026-10-08", "08:00", 60, "내일")
        val events = listOf(tomorrow, allDay, upcoming, ended, ongoing)
        assertEquals(ongoing, CalendarWidgetContent.nextEvent(events, now(2026, 10, 7)))
        assertEquals(upcoming, CalendarWidgetContent.nextEvent(events, now(2026, 10, 7, 10, 30)))
        assertEquals(allDay, CalendarWidgetContent.nextEvent(events, now(2026, 10, 7, 16)))
        assertEquals(tomorrow, CalendarWidgetContent.nextEvent(listOf(ended, tomorrow), now(2026, 10, 7)))
        assertNull(CalendarWidgetContent.nextEvent(listOf(ended), now(2026, 10, 7)))
    }
}
