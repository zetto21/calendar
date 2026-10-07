package com.zetto.calendar_app_flutter

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.os.Build
import android.os.Bundle
import android.util.SizeF
import android.view.View
import android.widget.RemoteViews
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

open class CalendarWidgetProvider : AppWidgetProvider() {
    internal open val defaultSize = CalendarWidgetSize.MEDIUM
    internal open val kind = CalendarWidgetKind.AGENDA

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        ids.forEach { render(context, manager, it, defaultSize, kind) }
    }
    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, id: Int, options: Bundle) {
        render(context, manager, id, defaultSize, kind)
    }
    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action in listOf(Intent.ACTION_DATE_CHANGED, Intent.ACTION_TIME_CHANGED, Intent.ACTION_TIMEZONE_CHANGED)) refresh(context)
    }
    companion object {
        fun save(context: Context, snapshot: String) {
            require(snapshot.length <= 2_000_000)
            val data = JSONObject(snapshot)
            require(data.has("signedIn") && data.getJSONArray("events").length() <= 500)
            check(context.getSharedPreferences("calendar_widget", Context.MODE_PRIVATE).edit()
                .putString("snapshot", snapshot).commit())
            refresh(context)
        }
        fun refresh(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            listOf(
                Triple(CalendarWidgetProvider::class.java, CalendarWidgetSize.MEDIUM, CalendarWidgetKind.AGENDA),
                Triple(CalendarSmallWidgetProvider::class.java, CalendarWidgetSize.SMALL, CalendarWidgetKind.AGENDA),
                Triple(CalendarLargeWidgetProvider::class.java, CalendarWidgetSize.LARGE, CalendarWidgetKind.AGENDA),
                Triple(CalendarTodayWidgetProvider::class.java, CalendarWidgetSize.LARGE, CalendarWidgetKind.TODAY),
                Triple(CalendarNextWidgetProvider::class.java, CalendarWidgetSize.MEDIUM, CalendarWidgetKind.NEXT),
                Triple(CalendarMonthWidgetProvider::class.java, CalendarWidgetSize.LARGE, CalendarWidgetKind.MONTH),
            ).forEach { (provider, size, kind) ->
                manager.getAppWidgetIds(ComponentName(context, provider))
                    .forEach { render(context, manager, it, size, kind) }
            }
        }
        private fun render(context: Context, manager: AppWidgetManager, id: Int, fallback: CalendarWidgetSize, kind: CalendarWidgetKind) {
            val options = manager.getAppWidgetOptions(id)
            val now = Date()
            val today = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(now)
            val data = runCatching { JSONObject(context.getSharedPreferences("calendar_widget", Context.MODE_PRIVATE)
                .getString("snapshot", "{}") ?: "{}") }.getOrDefault(JSONObject())
            val array = data.optJSONArray("events")
            val signedIn = data.optBoolean("signedIn", false)
            val events = if (!signedIn || array == null) emptyList() else (0 until array.length())
                .mapNotNull { array.optJSONObject(it) }
                .sortedWith(compareBy<JSONObject> { it.optString("date") }.thenBy { it.optString("time") })
            fun views(width: Int, height: Int): RemoteViews {
                val result = when (kind) {
                    CalendarWidgetKind.MONTH -> CalendarWidgetVariants.month(context, now, today, signedIn, events)
                    CalendarWidgetKind.NEXT -> CalendarWidgetVariants.next(context, now, today, signedIn, events)
                    CalendarWidgetKind.TODAY -> CalendarWidgetVariants.today(context, height, now, today, signedIn, events)
                    CalendarWidgetKind.AGENDA -> createViews(context, CalendarWidgetSize.forBounds(width, height), height,
                        now, today, signedIn, events.filter { it.optString("date") >= today })
                }
                val intent = Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                result.setOnClickPendingIntent(R.id.widget_root, PendingIntent.getActivity(context, 0, intent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
                return result
            }
            // Supply each host-reported size so rotation and resizing select the correct layout.
            if (Build.VERSION.SDK_INT >= 31) {
                @Suppress("DEPRECATION")
                val sizes = options.getParcelableArrayList<SizeF>(AppWidgetManager.OPTION_APPWIDGET_SIZES)
                    ?.filter { it.width.isFinite() && it.height.isFinite() && it.width > 0 && it.height > 0 }
                    ?.distinct()?.take(16)
                if (!sizes.isNullOrEmpty()) {
                    manager.updateAppWidget(id, RemoteViews(sizes.associateWith { views(it.width.toInt(), it.height.toInt()) }))
                    return
                }
            }
            val landscape = context.resources.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE
            val widthKey = if (landscape) AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH else AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH
            val heightKey = if (landscape) AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT else AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT
            val width = options.getInt(widthKey, fallback.width).takeIf { it > 0 } ?: fallback.width
            val height = options.getInt(heightKey, fallback.height).takeIf { it > 0 } ?: fallback.height
            manager.updateAppWidget(id, views(width, height))
        }
        private fun createViews(context: Context, size: CalendarWidgetSize, height: Int, now: Date,
                                today: String, signedIn: Boolean, events: List<JSONObject>): RemoteViews {
            val layout = when (size) {
                CalendarWidgetSize.SMALL -> R.layout.calendar_widget_small
                CalendarWidgetSize.MEDIUM -> R.layout.calendar_widget
                CalendarWidgetSize.LARGE -> R.layout.calendar_widget_large
            }
            val views = RemoteViews(context.packageName, layout)
            val format = if (size == CalendarWidgetSize.SMALL) "M월 d일 (E)" else "M월 d일 EEEE"
            views.setTextViewText(R.id.widget_date, SimpleDateFormat(format, Locale.KOREAN).format(now))
            views.removeAllViews(R.id.widget_events)
            views.setViewVisibility(R.id.widget_empty, if (!signedIn || events.isEmpty()) View.VISIBLE else View.GONE)
            views.setTextViewText(R.id.widget_empty, if (!signedIn) "앱을 열어 로그인해 주세요" else "예정된 일정이 없어요")
            val rowLayout = if (size == CalendarWidgetSize.MEDIUM) R.layout.calendar_widget_row_compact else R.layout.calendar_widget_row
            events.take(size.eventCount(height)).forEach { event ->
                val row = RemoteViews(context.packageName, rowLayout)
                val date = event.optString("date")
                val label = if (date == today) "오늘" else date.takeLast(5).replace('-', '/')
                val time = event.optString("time").takeIf { it.isNotBlank() && it != "null" } ?: "종일"
                row.setTextViewText(R.id.widget_event_time, "$label · $time")
                row.setTextViewText(R.id.widget_event_title, event.optString("title").take(120))
                views.addView(R.id.widget_events, row)
            }
            return views
        }
    }
}

class CalendarSmallWidgetProvider : CalendarWidgetProvider() {
    internal override val defaultSize = CalendarWidgetSize.SMALL
}
class CalendarLargeWidgetProvider : CalendarWidgetProvider() {
    internal override val defaultSize = CalendarWidgetSize.LARGE
}

class CalendarTodayWidgetProvider : CalendarWidgetProvider() {
    internal override val defaultSize = CalendarWidgetSize.LARGE
    internal override val kind = CalendarWidgetKind.TODAY
}
class CalendarNextWidgetProvider : CalendarWidgetProvider() {
    internal override val kind = CalendarWidgetKind.NEXT
}
class CalendarMonthWidgetProvider : CalendarWidgetProvider() {
    internal override val defaultSize = CalendarWidgetSize.LARGE
    internal override val kind = CalendarWidgetKind.MONTH
}
