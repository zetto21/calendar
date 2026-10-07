package com.zetto.calendar_app_flutter

import org.junit.Assert.*
import org.junit.Test

class LiveUpdateTimingTest {
    @Test fun displayOnlyWithinTenMinutesOrWhileOngoing() {
        val start = 1_800_000L
        val end = 5_400_000L
        assertEquals(1_200_000L, LiveUpdateTiming.displayStart(start))
        assertFalse(LiveUpdateTiming.isDue(start, end, 1_199_999L))
        assertTrue(LiveUpdateTiming.isDue(start, end, 1_200_000L))
        assertTrue(LiveUpdateTiming.isDue(start, end, start))
        assertTrue(LiveUpdateTiming.isDue(start, end, end - 1))
        assertFalse(LiveUpdateTiming.isDue(start, end, end))
    }
}
