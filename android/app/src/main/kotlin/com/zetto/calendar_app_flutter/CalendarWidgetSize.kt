package com.zetto.calendar_app_flutter

internal enum class CalendarWidgetSize(val width: Int, val height: Int, val maxEvents: Int, val rowHeight: Int, val headerHeight: Int) {
    SMALL(140, 180, 2, 40, 80), MEDIUM(280, 190, 3, 32, 88), LARGE(280, 360, 6, 44, 92);

    companion object {
        fun forBounds(width: Int, height: Int): CalendarWidgetSize = when {
            width < 220 -> SMALL
            height >= 270 -> LARGE
            else -> MEDIUM
        }
    }
    fun eventCount(height: Int): Int = ((height - headerHeight) / rowHeight).coerceIn(1, maxEvents)
}
