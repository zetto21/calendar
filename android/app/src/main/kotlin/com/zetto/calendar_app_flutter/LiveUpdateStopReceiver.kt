package com.zetto.calendar_app_flutter

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class LiveUpdateStopReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == LiveUpdateService.STOP) LiveUpdateService.end(context)
    }
}
