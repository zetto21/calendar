package com.zetto.calendar_app_flutter

import org.junit.Assert.*
import org.junit.Test

class CalendarWidgetSizeTest {
    @Test fun resizingSwitchesBetweenCompactWideAndTallLayouts() {
        assertEquals(CalendarWidgetSize.SMALL, CalendarWidgetSize.forBounds(150, 180))
        assertEquals(CalendarWidgetSize.MEDIUM, CalendarWidgetSize.forBounds(300, 190))
        assertEquals(CalendarWidgetSize.LARGE, CalendarWidgetSize.forBounds(300, 360))
        assertEquals(CalendarWidgetSize.SMALL, CalendarWidgetSize.forBounds(150, 360))
    }
    @Test fun rowsFitAvailableHeightAndNeverExceedEachLayoutsLimit() {
        for (size in CalendarWidgetSize.entries) {
            assertEquals(size.maxEvents, size.eventCount(size.height))
            assertEquals(1, size.eventCount(0))
            assertEquals(size.maxEvents, size.eventCount(1000))
            for (height in 140..600) {
                val count = size.eventCount(height)
                assertTrue(count in 1..size.maxEvents)
                assertTrue(size.headerHeight + count * size.rowHeight <= height)
            }
        }
        assertEquals(1, CalendarWidgetSize.MEDIUM.eventCount(140))
    }
}
