package com.zetto.calendar_app_flutter

import android.content.Context
import android.view.View
import android.widget.RemoteViews
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

internal object CalendarWidgetVariants {
    private fun date(pattern: String, now: Date) = SimpleDateFormat(pattern, Locale.KOREAN).format(now)
    fun today(context: Context, height: Int, now: Date, today: String, signedIn: Boolean, events: List<JSONObject>): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.calendar_widget_today)
        val items = events.filter { it.optString("date") == today }
        views.setTextViewText(R.id.widget_day_number, date("d", now))
        views.setTextViewText(R.id.widget_date, date("M월 EEEE", now))
        views.setTextViewText(R.id.widget_summary, if (signedIn) "오늘 일정 ${items.size}개" else "로그인이 필요해요")
        views.setViewVisibility(R.id.widget_empty, if (!signedIn || items.isEmpty()) View.VISIBLE else View.GONE)
        views.setTextViewText(R.id.widget_empty, if (signedIn) "오늘은 여유로운 하루예요" else "앱을 열어 로그인해 주세요")
        views.removeAllViews(R.id.widget_events)
        items.take(((height - 118) / 40).coerceIn(1, 5)).forEach { event ->
            val row = RemoteViews(context.packageName, R.layout.calendar_widget_row)
            row.setTextViewText(R.id.widget_event_time, event.optString("time").takeIf { it != "null" && it.isNotBlank() } ?: "종일")
            row.setTextViewText(R.id.widget_event_title, event.optString("title").take(120))
            views.addView(R.id.widget_events, row)
        }
        return views
    }
    fun next(context: Context, now: Date, today: String, signedIn: Boolean, events: List<JSONObject>): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.calendar_widget_next)
        val event = CalendarWidgetContent.nextEvent(events.map {
            WidgetEvent(it.optString("date"), it.optString("time").takeIf { value -> value != "null" && value.isNotBlank() },
                it.optInt("duration", 60), it.optString("title"))
        }, now)
        views.setTextViewText(R.id.widget_next_time, if (!signedIn) "로그인" else event?.time ?: if (event != null) "종일" else "여유")
        views.setTextViewText(R.id.widget_next_title, if (!signedIn) "앱을 열어 로그인해 주세요" else event?.title?.take(120) ?: "예정된 일정이 없어요")
        views.setTextViewText(R.id.widget_date, event?.let { if (it.date == today) "오늘" else it.date.takeLast(5).replace('-', '/') } ?: date("M월 d일 EEEE", now))
        return views
    }
    fun month(context: Context, now: Date, today: String, signedIn: Boolean, events: List<JSONObject>): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.calendar_widget_month)
        views.setTextViewText(R.id.widget_date, date("yyyy년 M월", now))
        views.setTextViewText(R.id.widget_summary, if (signedIn) "● 일정 있는 날" else "로그인하면 일정이 표시됩니다")
        val eventDates = events.map { it.optString("date") }.toSet()
        val prefix = today.take(7)
        val cells = CalendarWidgetContent.monthDays(now)
        views.removeAllViews(R.id.widget_month_rows)
        cells.chunked(7).forEach { week ->
            val row = RemoteViews(context.packageName, R.layout.calendar_widget_month_week)
            week.forEach { day ->
                val key = day?.let { "$prefix-${it.toString().padStart(2, '0')}" }
                val cell = RemoteViews(context.packageName,
                    if (key == today) R.layout.calendar_widget_month_day_today else R.layout.calendar_widget_month_day)
                cell.setTextViewText(R.id.widget_day_number, day?.toString() ?: "")
                cell.setViewVisibility(R.id.widget_day_dot, if (key in eventDates) View.VISIBLE else View.INVISIBLE)
                if (key != null) cell.setContentDescription(R.id.widget_day_cell,
                    "$key${if (key == today) ", 오늘" else ""}${if (key in eventDates) ", 일정 있음" else ""}")
                row.addView(R.id.widget_month_week, cell)
            }
            views.addView(R.id.widget_month_rows, row)
        }
        return views
    }
}
