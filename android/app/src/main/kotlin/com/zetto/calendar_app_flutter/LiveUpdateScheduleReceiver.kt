package com.zetto.calendar_app_flutter

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class LiveUpdateScheduleReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == LiveUpdateService.ALARM || intent.action in setOf(
                Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED,
                Intent.ACTION_TIME_CHANGED, Intent.ACTION_TIMEZONE_CHANGED,
                android.app.AlarmManager.ACTION_SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED)) {
            LiveUpdateService.resumeAutomatic(context)
        }
    }
}
