package com.zetto.calendar_app_flutter

internal object LiveUpdateTiming {
    fun displayStart(start: Long): Long = start - 600_000L
    fun isDue(start: Long, end: Long, now: Long): Boolean =
        now >= displayStart(start) && now < end
}
