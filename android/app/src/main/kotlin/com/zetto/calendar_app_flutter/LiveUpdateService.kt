package com.zetto.calendar_app_flutter

import android.app.*
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.drawable.Icon
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.SystemClock
import android.widget.RemoteViews
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * A user-selected event timer, drawn as a custom card that mirrors the iOS
 * Live Activity: a colored status row, title + live countdown, time range
 * and a progress bar. The system chronometer ticks without Dart.
 */
class LiveUpdateService : Service() {
    companion object {
        const val CHANNEL = "calendar_live_updates"
        const val ID = 4200
        const val STOP = "calendar.live_update.STOP"
        private const val PREFS = "calendar_live_update"

        /** How long the finished state lingers, matching the iOS Activity's staleDate. */
        private const val LINGER_MS = 180_000L
        private val ORANGE = Color.parseColor("#FF9500")
        private val GREEN = Color.parseColor("#34C759")

        fun createChannel(context: Context) {
            if (Build.VERSION.SDK_INT >= 26) {
                context.getSystemService(NotificationManager::class.java).createNotificationChannel(
                    NotificationChannel(CHANNEL, "일정 실시간 업데이트", NotificationManager.IMPORTANCE_LOW).apply {
                        description = "선택한 일정의 남은 시간과 진행 상태를 표시합니다."
                        setShowBadge(false)
                    }
                )
            }
        }

        fun activeIDs(context: Context): List<String> {
            val prefs = context.getSharedPreferences(PREFS, MODE_PRIVATE)
            val id = prefs.getString("eventID", null)
            return if (id != null && prefs.getLong("end", 0) > System.currentTimeMillis()) listOf(id) else emptyList()
        }

        fun end(context: Context) {
            context.getSharedPreferences(PREFS, MODE_PRIVATE).edit().clear().apply()
            context.stopService(Intent(context, LiveUpdateService::class.java))
            context.getSystemService(NotificationManager::class.java).cancel(ID)
        }
    }

    private val handler = Handler(Looper.getMainLooper())
    private val tick = object : Runnable {
        override fun run() {
            val prefs = getSharedPreferences(PREFS, MODE_PRIVATE)
            val now = System.currentTimeMillis()
            val end = prefs.getLong("end", 0)
            val start = prefs.getLong("start", 0)
            if (end <= 0 || !notificationsEnabled()) {
                finish()
                return
            }
            val lingerUntil = end + LINGER_MS
            if (now >= lingerUntil) {
                finish()
                return
            }
            getSystemService(NotificationManager::class.java).notify(ID, notification())
            val nextBoundary = when {
                now < start -> start
                now < end -> end
                else -> lingerUntil
            }
            handler.postDelayed(this, minOf(15_000L, (nextBoundary - now).coerceAtLeast(1L)))
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == STOP) {
            finish()
            return START_NOT_STICKY
        }
        createChannel(this)
        val prefs = getSharedPreferences(PREFS, MODE_PRIVATE)
        if (intent?.hasExtra("eventID") == true) {
            val start = intent.getLongExtra("start", 0)
            val end = intent.getLongExtra("end", 0)
            if (end <= start || end <= System.currentTimeMillis()) {
                finish()
                return START_NOT_STICKY
            }
            prefs.edit()
                .putString("eventID", intent.getStringExtra("eventID"))
                .putString("title", intent.getStringExtra("title"))
                .putString("color", intent.getStringExtra("color"))
                .putLong("start", start).putLong("end", end).apply()
        }
        if (activeIDs(this).isEmpty() || !notificationsEnabled()) {
            finish()
            return START_NOT_STICKY
        }
        val notification = notification()
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(ID, notification)
        }
        handler.removeCallbacks(tick)
        handler.post(tick)
        return START_STICKY
    }

    private fun notificationsEnabled(): Boolean {
        val manager = getSystemService(NotificationManager::class.java)
        return manager.areNotificationsEnabled() &&
            (Build.VERSION.SDK_INT < 26 || manager.getNotificationChannel(CHANNEL)?.importance != NotificationManager.IMPORTANCE_NONE)
    }

    private fun notification(): Notification {
        val prefs = getSharedPreferences(PREFS, MODE_PRIVATE)
        val now = System.currentTimeMillis()
        val start = prefs.getLong("start", now)
        val end = prefs.getLong("end", now + 1)
        val title = prefs.getString("title", "일정") ?: "일정"
        val started = now >= start
        val finished = now >= end
        val statusText = if (finished) "일정 종료" else if (started) "진행 중" else "시작 예정"
        val statusIcon = when {
            finished -> R.drawable.ic_status_done
            started -> R.drawable.ic_status_ongoing
            else -> R.drawable.ic_status_upcoming
        }
        val statusColor = if (finished) GREEN else ORANGE
        val eventColor = try { Color.parseColor(prefs.getString("color", "#3B82F6")) } catch (_: Exception) { Color.rgb(59, 130, 246) }
        val accentColor = if (finished) GREEN else eventColor
        val format = SimpleDateFormat("a h:mm", Locale.KOREAN)
        val range = "${format.format(Date(start))} – ${format.format(Date(end))}"
        val timeText = if (finished) "일정이 종료되었습니다" else range
        val progress = (((now - start).toDouble() / (end - start).coerceAtLeast(1)) * 1000).toInt().coerceIn(0, 1000)
        val progressValue = if (finished) 1000 else progress

        fun buildViews(layout: Int, expanded: Boolean): RemoteViews {
            val views = RemoteViews(packageName, layout)
            views.setImageViewResource(R.id.status_icon, statusIcon)
            views.setInt(R.id.status_icon, "setColorFilter", statusColor)
            views.setInt(R.id.status_chip, "setBackgroundResource", if (finished) R.drawable.chip_done else R.drawable.chip_upcoming)
            views.setTextViewText(R.id.status_text, statusText)
            views.setTextColor(R.id.status_text, statusColor)
            views.setTextViewText(android.R.id.title, title)
            views.setTextColor(R.id.countdown, accentColor)
            if (finished) {
                views.setChronometer(R.id.countdown, SystemClock.elapsedRealtime(), null, false)
                views.setTextViewText(R.id.countdown, "종료")
            } else {
                val target = if (started) end else start
                views.setChronometer(R.id.countdown, SystemClock.elapsedRealtime() + (target - now), null, true)
                views.setChronometerCountDown(R.id.countdown, true)
            }
            if (expanded) views.setTextViewText(R.id.time_text, timeText)
            views.setProgressBar(android.R.id.progress, 1000, progressValue, false)
            if (Build.VERSION.SDK_INT >= 31) {
                views.setColorStateList(android.R.id.progress, "setProgressTintList", ColorStateList.valueOf(accentColor))
            }
            return views
        }

        val open = PendingIntent.getActivity(this, ID,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val stop = PendingIntent.getBroadcast(this, ID,
            Intent(this, LiveUpdateStopReceiver::class.java).setAction(STOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CHANNEL) else Notification.Builder(this)
        builder.setSmallIcon(R.drawable.ic_stat_calendar)
            .setContentTitle(title)
            .setColor(accentColor)
            .setOngoing(true).setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_EVENT)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .setContentIntent(open).setDeleteIntent(stop)
            .addAction(Notification.Action.Builder(null, "실시간 업데이트 종료", stop).build())
        if (Build.VERSION.SDK_INT >= 26) builder.setTimeoutAfter((end + LINGER_MS - now).coerceAtLeast(1))
        if (Build.VERSION.SDK_INT >= 36) {
            val remainingColor = Color.argb(70, 128, 128, 128)
            val segments = mutableListOf<Notification.ProgressStyle.Segment>()
            if (progressValue > 0) segments += Notification.ProgressStyle.Segment(progressValue).setColor(accentColor)
            if (progressValue < 1000) segments += Notification.ProgressStyle.Segment(1000 - progressValue).setColor(remainingColor)
            // Status-bar chips require a standard (non-RemoteViews) notification.
            builder.setSubText(statusText)
                .setContentText(timeText)
                .addExtras(android.os.Bundle().apply { putBoolean("android.requestPromotedOngoing", true) })
                .setStyle(Notification.ProgressStyle()
                    .setStyledByProgress(false)
                    .setProgress(progressValue)
                    .setProgressSegments(segments)
                    .setProgressStartIcon(Icon.createWithResource(this, R.drawable.ic_status_upcoming).setTint(accentColor))
                    .setProgressEndIcon(Icon.createWithResource(this, R.drawable.ic_status_done).setTint(if (finished) GREEN else Color.GRAY))
                    .setProgressTrackerIcon(Icon.createWithResource(this, if (finished) R.drawable.ic_status_done else R.drawable.ic_tracker_dot).setTint(accentColor)))
            if (finished) {
                builder.setShortCriticalText("종료")
            } else {
                builder.setWhen(if (started) end else start).setShowWhen(true)
                    .setUsesChronometer(true).setChronometerCountDown(true)
            }
        } else {
            builder.setStyle(Notification.DecoratedCustomViewStyle())
                .setCustomContentView(buildViews(R.layout.notification_live_activity_collapsed, expanded = false))
                .setCustomBigContentView(buildViews(R.layout.notification_live_activity_expanded, expanded = true))
        }
        return builder.build()
    }

    private fun finish() {
        getSharedPreferences(PREFS, MODE_PRIVATE).edit().clear().apply()
        handler.removeCallbacks(tick)
        stopForeground(STOP_FOREGROUND_REMOVE)
        getSystemService(NotificationManager::class.java).cancel(ID)
        stopSelf()
    }

    override fun onDestroy() {
        handler.removeCallbacks(tick)
        super.onDestroy()
    }
}
