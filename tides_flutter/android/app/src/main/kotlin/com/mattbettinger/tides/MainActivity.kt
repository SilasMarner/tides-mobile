package com.mattbettinger.tides

import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.mattbettinger.tides/setup"
        ).setMethodCallHandler { call, result ->
            if (call.method == "clearFLNCache") {
                // FLN stores scheduled notification metadata in a named SharedPreferences
                // file. If this file contains entries saved by an older FLN version that
                // lacked the required "type" field, every FLN operation (zonedSchedule,
                // cancelAll, etc.) throws "Missing type parameter". Wiping it lets FLN
                // start fresh; AlarmManager entries are re-created by rescheduleAllStations.
                applicationContext
                    .getSharedPreferences("scheduled_notifications", Context.MODE_PRIVATE)
                    .edit().clear().apply()
                result.success(null)
            } else {
                result.notImplemented()
            }
        }
    }
}
