package com.mattbettinger.tides.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.view.View
import android.widget.RemoteViews
import com.mattbettinger.tides.MainActivity
import com.mattbettinger.tides.R
import com.mattbettinger.tides.car.CarStation
import com.mattbettinger.tides.car.NoaaRepo
import com.mattbettinger.tides.car.TidePoint
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Home-screen widget: the previous tide plus the next 3, for one favorite
 * station, tap to open that station in the app. Each widget instance is
 * bound to its own station via [TideWidgetConfigActivity] (add the widget
 * again to track a second one). Data comes from the same NoaaRepo the
 * Android Auto module already uses, independent of the Flutter engine.
 */
class TideWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        val pending = goAsync()
        Thread {
            try {
                for (id in appWidgetIds) updateWidget(context, appWidgetManager, id)
            } finally {
                pending.finish()
            }
        }.start()
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        val editor = widgetPrefs(context).edit()
        for (id in appWidgetIds) {
            editor.remove(stationIdKey(id))
            editor.remove(stationNameKey(id))
            editor.remove(latKey(id))
            editor.remove(lonKey(id))
        }
        editor.apply()
    }

    companion object {
        private const val PREFS = "tide_widget_prefs"
        private val ROW_IDS = intArrayOf(
            R.id.widget_row0, R.id.widget_row1, R.id.widget_row2, R.id.widget_row3,
        )

        private fun widgetPrefs(context: Context): SharedPreferences =
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

        private fun stationIdKey(id: Int) = "widget_${id}_station_id"
        private fun stationNameKey(id: Int) = "widget_${id}_station_name"
        private fun latKey(id: Int) = "widget_${id}_lat"
        private fun lonKey(id: Int) = "widget_${id}_lon"

        fun saveStation(context: Context, appWidgetId: Int, station: CarStation) {
            widgetPrefs(context).edit()
                .putString(stationIdKey(appWidgetId), station.id)
                .putString(stationNameKey(appWidgetId), station.name)
                .putFloat(latKey(appWidgetId), station.lat.toFloat())
                .putFloat(lonKey(appWidgetId), station.lon.toFloat())
                .apply()
        }

        /**
         * Renders immediately (a "set up" prompt, or the station name with a
         * loading row), then fetches tides on a background thread and pushes a
         * second update when they arrive. Safe to call from any thread.
         */
        fun updateWidget(context: Context, appWidgetManager: AppWidgetManager, appWidgetId: Int) {
            val prefs = widgetPrefs(context)
            val stationId = prefs.getString(stationIdKey(appWidgetId), null)
            val stationName = prefs.getString(stationNameKey(appWidgetId), null)

            if (stationId == null || stationName == null) {
                showUnconfigured(context, appWidgetManager, appWidgetId)
                return
            }

            val lat = prefs.getFloat(latKey(appWidgetId), 0f).toDouble()
            val lon = prefs.getFloat(lonKey(appWidgetId), 0f).toDouble()
            val station = CarStation(stationId, stationName, lat, lon)
            val openPendingIntent = openStationPendingIntent(context, appWidgetId, station)

            val placeholder = RemoteViews(context.packageName, R.layout.widget_tides)
            placeholder.setTextViewText(R.id.widget_title, stationName)
            placeholder.setViewVisibility(R.id.widget_rows, View.VISIBLE)
            placeholder.setTextViewText(R.id.widget_row0, "Loading…")
            for (rid in ROW_IDS.drop(1)) placeholder.setTextViewText(rid, "")
            placeholder.setOnClickPendingIntent(R.id.widget_root, openPendingIntent)
            appWidgetManager.updateAppWidget(appWidgetId, placeholder)

            Thread {
                val points = try {
                    NoaaRepo.fetchTides(station)
                } catch (e: Exception) {
                    emptyList()
                }
                val views = RemoteViews(context.packageName, R.layout.widget_tides)
                views.setTextViewText(R.id.widget_title, stationName)
                views.setViewVisibility(R.id.widget_rows, View.VISIBLE)
                views.setOnClickPendingIntent(R.id.widget_root, openPendingIntent)
                val rows = buildRows(points)
                for (i in ROW_IDS.indices) {
                    views.setTextViewText(ROW_IDS[i], rows.getOrElse(i) { "" })
                }
                appWidgetManager.updateAppWidget(appWidgetId, views)
            }.start()
        }

        private fun showUnconfigured(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int,
        ) {
            val views = RemoteViews(context.packageName, R.layout.widget_tides)
            views.setTextViewText(R.id.widget_title, "Tap to set up")
            views.setViewVisibility(R.id.widget_rows, View.GONE)
            val configIntent = Intent(context, TideWidgetConfigActivity::class.java).apply {
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            views.setOnClickPendingIntent(
                R.id.widget_root,
                PendingIntent.getActivity(
                    context, appWidgetId, configIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                ),
            )
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }

        private fun openStationPendingIntent(
            context: Context,
            appWidgetId: Int,
            station: CarStation,
        ): PendingIntent {
            val openIntent = Intent(context, MainActivity::class.java).apply {
                putExtra("station_id", station.id)
                putExtra("station_name", station.name)
                putExtra("station_lat", station.lat)
                putExtra("station_lon", station.lon)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            return PendingIntent.getActivity(
                context, appWidgetId, openIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        /**
         * The most recent past tide plus the next 3 upcoming, one line each
         * ("up arrow 6:14 AM  1.6 ft"). [points] arrive time-sorted from NoaaRepo.
         */
        private fun buildRows(points: List<TidePoint>): List<String> {
            if (points.isEmpty()) return listOf("No tide data")
            val now = Date()
            val fmt = SimpleDateFormat("h:mm a", Locale.US)
            val past = points.lastOrNull { it.time.before(now) }
            val upcoming = points.filter { it.time.after(now) }.take(3)
            return (listOfNotNull(past) + upcoming).map { p ->
                val arrow = if (p.high) "↑" else "↓"
                "$arrow ${fmt.format(p.time)}  ${"%.1f".format(p.heightFt)} ft"
            }
        }
    }
}
