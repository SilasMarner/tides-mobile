package com.mattbettinger.tides.widget

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.SystemClock
import android.view.View
import android.widget.RemoteViews
import com.mattbettinger.tides.MainActivity
import com.mattbettinger.tides.R
import com.mattbettinger.tides.car.CarStation
import com.mattbettinger.tides.car.CarSummary
import com.mattbettinger.tides.car.NoaaRepo
import com.mattbettinger.tides.car.TidePoint
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Home-screen widget: for one to [MAX_STATIONS] favorite stations, tap to open
 * that station in the app. Which stations a given widget instance tracks is
 * picked in [TideWidgetConfigActivity]. A single-station widget shows the
 * previous tide plus the next 3, exactly as before; a multi-station widget
 * trades that per-station detail for one compact line per station (just its
 * next tide) so several fit in the same widget instead of needing one
 * placement per station. Data comes from the same NoaaRepo the Android Auto
 * module already uses, independent of the Flutter engine.
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
                for (id in appWidgetIds) updateWidget(context, appWidgetManager, id, blocking = true)
            } finally {
                pending.finish()
            }
        }.start()
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        val editor = widgetPrefs(context).edit()
        for (id in appWidgetIds) editor.remove(stationsKey(id))
        editor.apply()
    }

    companion object {
        const val MAX_STATIONS = 4

        private const val PREFS = "tide_widget_prefs"
        private val ROW_IDS = intArrayOf(
            R.id.widget_row0, R.id.widget_row1, R.id.widget_row2, R.id.widget_row3,
        )

        private fun widgetPrefs(context: Context): SharedPreferences =
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

        private fun stationsKey(id: Int) = "widget_${id}_stations"

        fun saveStations(context: Context, appWidgetId: Int, stations: List<CarStation>) {
            val arr = JSONArray()
            for (s in stations.take(MAX_STATIONS)) {
                arr.put(JSONObject().apply {
                    put("id", s.id); put("name", s.name); put("lat", s.lat); put("lon", s.lon)
                })
            }
            widgetPrefs(context).edit().putString(stationsKey(appWidgetId), arr.toString()).apply()
        }

        private fun readStations(context: Context, appWidgetId: Int): List<CarStation> {
            val raw = widgetPrefs(context).getString(stationsKey(appWidgetId), null) ?: return emptyList()
            return try {
                val arr = JSONArray(raw)
                (0 until arr.length()).map { i ->
                    val o = arr.getJSONObject(i)
                    CarStation(o.getString("id"), o.getString("name"), o.getDouble("lat"), o.getDouble("lon"))
                }
            } catch (e: Exception) {
                emptyList()
            }
        }

        /**
         * Renders immediately (a "set up" prompt, or a loading placeholder), then
         * fetches tides on a background thread and pushes a second update when
         * they arrive. Safe to call from any thread.
         */
        fun updateWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int,
            blocking: Boolean = false,
        ) {
            val stations = readStations(context, appWidgetId)
            if (stations.isEmpty()) {
                showUnconfigured(context, appWidgetManager, appWidgetId)
                return
            }
            if (stations.size == 1) {
                updateSingleStation(context, appWidgetManager, appWidgetId, stations[0], blocking)
            } else {
                updateMultiStation(context, appWidgetManager, appWidgetId, stations, blocking)
            }
        }

        // ── Single station: previous tide + next 3, as before ──────────────────

        private fun updateSingleStation(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int,
            station: CarStation,
            blocking: Boolean,
        ) {
            val openPendingIntent = openStationPendingIntent(context, appWidgetId, 0, station)

            // Cheap SharedPreferences read (no network) — safe to show right away
            // rather than waiting on the tide fetch below.
            val summaryLine = formatSummary(NoaaRepo.readCarSummary(context, station.id))

            val placeholder = RemoteViews(context.packageName, R.layout.widget_tides)
            placeholder.setTextViewText(R.id.widget_title, station.name)
            placeholder.setViewVisibility(R.id.widget_rows, View.VISIBLE)
            placeholder.setTextViewText(R.id.widget_row0, "Loading…")
            for (rid in ROW_IDS.drop(1)) {
                placeholder.setTextViewText(rid, "")
                placeholder.setViewVisibility(rid, View.VISIBLE)
            }
            setSummaryRow(placeholder, summaryLine)
            placeholder.setOnClickPendingIntent(R.id.widget_root, openPendingIntent)
            appWidgetManager.updateAppWidget(appWidgetId, placeholder)

            runFetch(blocking) {
                val points = loadTides(context, appWidgetId, station)
                val views = RemoteViews(context.packageName, R.layout.widget_tides)
                views.setTextViewText(R.id.widget_title, station.name)
                views.setViewVisibility(R.id.widget_rows, View.VISIBLE)
                views.setOnClickPendingIntent(R.id.widget_root, openPendingIntent)
                val rows = buildTideRows(points)
                for (i in ROW_IDS.indices) {
                    views.setTextViewText(ROW_IDS[i], rows.getOrElse(i) { "" })
                    views.setViewVisibility(ROW_IDS[i], View.VISIBLE)
                }
                setSummaryRow(views, summaryLine)
                appWidgetManager.updateAppWidget(appWidgetId, views)
            }
        }

        private fun setSummaryRow(views: RemoteViews, summaryLine: String?) {
            if (summaryLine == null) {
                views.setViewVisibility(R.id.widget_summary, View.GONE)
            } else {
                views.setTextViewText(R.id.widget_summary, summaryLine)
                views.setViewVisibility(R.id.widget_summary, View.VISIBLE)
            }
        }

        // "★★★★☆ Very Good · ↑6:16 AM ↓6:50 PM" — whichever pieces are cached.
        // Null when nothing's cached (station never opened in the app yet).
        private fun formatSummary(summary: CarSummary?): String? {
            if (summary == null) return null
            val rating = summary.stars?.let { stars ->
                val filled = "★".repeat(stars.coerceIn(0, 5))
                val empty = "☆".repeat((5 - stars).coerceIn(0, 5))
                val label = summary.fishingLabel?.let { " $it" } ?: ""
                "$filled$empty$label"
            }
            val sun = if (summary.sunrise != null || summary.sunset != null) {
                listOfNotNull(
                    summary.sunrise?.let { "↑$it" },
                    summary.sunset?.let { "↓$it" },
                ).joinToString(" ")
            } else null
            val parts = listOfNotNull(rating, sun)
            return if (parts.isEmpty()) null else parts.joinToString(" · ")
        }

        // ── Multiple stations: one compact, independently-tappable line each ───

        private fun updateMultiStation(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int,
            stations: List<CarStation>,
            blocking: Boolean,
        ) {
            val genericOpenIntent = openAppPendingIntent(context, appWidgetId)

            val placeholder = RemoteViews(context.packageName, R.layout.widget_tides)
            placeholder.setTextViewText(R.id.widget_title, "My Tides")
            placeholder.setViewVisibility(R.id.widget_rows, View.VISIBLE)
            placeholder.setViewVisibility(R.id.widget_summary, View.GONE)
            placeholder.setOnClickPendingIntent(R.id.widget_root, genericOpenIntent)
            for (i in ROW_IDS.indices) {
                if (i < stations.size) {
                    placeholder.setTextViewText(ROW_IDS[i], "${shortName(stations[i])} — Loading…")
                    placeholder.setViewVisibility(ROW_IDS[i], View.VISIBLE)
                } else {
                    placeholder.setViewVisibility(ROW_IDS[i], View.GONE)
                }
            }
            appWidgetManager.updateAppWidget(appWidgetId, placeholder)

            runFetch(blocking) {
                val views = RemoteViews(context.packageName, R.layout.widget_tides)
                views.setTextViewText(R.id.widget_title, "My Tides")
                views.setViewVisibility(R.id.widget_rows, View.VISIBLE)
                views.setOnClickPendingIntent(R.id.widget_root, genericOpenIntent)
                for (i in ROW_IDS.indices) {
                    if (i >= stations.size) {
                        views.setViewVisibility(ROW_IDS[i], View.GONE)
                        continue
                    }
                    val station = stations[i]
                    val points = loadTides(context, appWidgetId, station)
                    views.setTextViewText(ROW_IDS[i], "${shortName(station)} — ${nextTideLine(points)}")
                    views.setViewVisibility(ROW_IDS[i], View.VISIBLE)
                    views.setOnClickPendingIntent(
                        ROW_IDS[i], openStationPendingIntent(context, appWidgetId, i, station),
                    )
                }
                appWidgetManager.updateAppWidget(appWidgetId, views)
            }
        }

        // From onUpdate the fetch must finish inside the goAsync window — a
        // detached thread there outlives the receiver and Android can freeze or
        // kill the process mid-request, leaving the widget on "Loading…".
        // Everywhere else (the config activity, on the main thread) it has to
        // go to a background thread.
        private fun runFetch(blocking: Boolean, block: () -> Unit) {
            if (blocking) block() else Thread { block() }.start()
        }

        private fun tidesKey(station: CarStation) = "tides_${station.id}"

        /**
         * Fresh NOAA predictions, remembered per station. A failed fetch (no
         * signal when the system woke the widget, a NOAA hiccup) falls back to
         * the last good copy — the predictions span today + 2 days, so it stays
         * useful for hours — instead of blanking the widget to "No tide data"
         * until the next hourly refresh, and schedules a prompt retry.
         */
        private fun loadTides(
            context: Context,
            appWidgetId: Int,
            station: CarStation,
        ): List<TidePoint> {
            val prefs = widgetPrefs(context)
            val fresh = try {
                NoaaRepo.fetchTides(station)
            } catch (e: Exception) {
                emptyList()
            }
            if (fresh.isNotEmpty()) {
                val arr = JSONArray()
                for (p in fresh) {
                    arr.put(JSONArray().put(p.time.time).put(p.heightFt).put(p.high))
                }
                prefs.edit().putString(tidesKey(station), arr.toString()).apply()
                return fresh
            }
            scheduleRetry(context, appWidgetId)
            val raw = prefs.getString(tidesKey(station), null) ?: return emptyList()
            return try {
                val arr = JSONArray(raw)
                (0 until arr.length()).map { i ->
                    val a = arr.getJSONArray(i)
                    val high = a.getBoolean(2)
                    TidePoint(Date(a.getLong(0)), if (high) "High" else "Low", a.getDouble(1), high)
                }
            } catch (e: Exception) {
                emptyList()
            }
        }

        // Inexact one-shot (no exact-alarm permission needed): re-run this
        // widget's update in ~15 minutes rather than waiting out the hourly period.
        private fun scheduleRetry(context: Context, appWidgetId: Int) {
            val intent = Intent(context, TideWidgetProvider::class.java).apply {
                action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, intArrayOf(appWidgetId))
            }
            val pi = PendingIntent.getBroadcast(
                context, appWidgetId, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            am.set(AlarmManager.ELAPSED_REALTIME, SystemClock.elapsedRealtime() + 15 * 60 * 1000L, pi)
        }

        // Station names are long ("GALVESTON, Galveston Channel, TX") — just the
        // first segment keeps a compact row from being all name, no tide.
        private fun shortName(station: CarStation) = station.name.substringBefore(",")

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

        // [row] distinguishes request codes for a multi-station widget's several
        // per-row PendingIntents (each opens a different station) from each other
        // and from other widgets' — PendingIntent.getActivity reuses any existing
        // intent with the same request code, which would otherwise make every
        // row open whichever station registered its intent first.
        private fun openStationPendingIntent(
            context: Context,
            appWidgetId: Int,
            row: Int,
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
                context, appWidgetId * 10 + row, openIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        // A multi-station widget's background (title, padding, any row beyond
        // its tap target) has no single station to open — falls through to just
        // launching the app.
        private fun openAppPendingIntent(context: Context, appWidgetId: Int): PendingIntent {
            val openIntent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            return PendingIntent.getActivity(
                context, appWidgetId * 10 + MAX_STATIONS, openIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        /**
         * The most recent past tide plus the next 3 upcoming, one line each
         * ("up arrow 6:14 AM  1.6 ft"). [points] arrive time-sorted from NoaaRepo.
         */
        private fun buildTideRows(points: List<TidePoint>): List<String> {
            if (points.isEmpty()) return listOf("No tide data")
            val now = Date()
            val fmt = SimpleDateFormat("h:mm a", Locale.US)
            val past = points.lastOrNull { it.time.before(now) }
            val upcoming = points.filter { it.time.after(now) }.take(3)
            return (listOfNotNull(past) + upcoming).map { tideLine(it, fmt) }
        }

        // Just the next upcoming tide, for a multi-station widget's one-line-
        // per-station rows.
        private fun nextTideLine(points: List<TidePoint>): String {
            val now = Date()
            val next = points.firstOrNull { it.time.after(now) } ?: return "No tide data"
            return tideLine(next, SimpleDateFormat("h:mm a", Locale.US))
        }

        private fun tideLine(p: TidePoint, fmt: SimpleDateFormat): String {
            val arrow = if (p.high) "↑" else "↓"
            return "$arrow ${fmt.format(p.time)}  ${"%.1f".format(p.heightFt)} ft"
        }
    }
}
