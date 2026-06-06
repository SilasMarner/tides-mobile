package com.mattbettinger.tides.car

import android.graphics.Bitmap
import android.os.Handler
import android.os.Looper
import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.model.Action
import androidx.car.app.model.ActionStrip
import androidx.car.app.model.CarIcon
import androidx.car.app.model.Pane
import androidx.car.app.model.PaneTemplate
import androidx.car.app.model.Row
import androidx.car.app.model.Template
import androidx.core.graphics.drawable.IconCompat
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

/**
 * Rich station screen for Android Auto: a rendered tide-chart image plus
 * glanceable rows (next high/low, live conditions, fishing + sun/moon).
 *
 * Android Auto only allows template UI, so this is as close to the phone's
 * detail screen as the platform permits — the chart is drawn to a bitmap
 * (see [TideChart]) since custom widgets can't be projected.
 */
class TideScreen(carContext: CarContext, private val station: CarStation) :
    Screen(carContext) {

    private var loading = true
    private var error: String? = null
    private var hilo: List<TidePoint> = emptyList()
    private var conditions: CarConditions? = null
    private var summary: CarSummary? = null
    private var chart: Bitmap? = null
    private val main = Handler(Looper.getMainLooper())

    init { load() }

    private fun load() {
        loading = true
        error = null
        Thread {
            try {
                val hourly = NoaaRepo.fetchHourly(station)
                val tides = NoaaRepo.fetchTides(station)
                val cond = try { NoaaRepo.fetchConditions(station) } catch (e: Exception) { null }
                val sum = NoaaRepo.readCarSummary(carContext, station.id)
                val todayHilo = tides.filter { isToday(it.time) }
                val bmp = if (hourly.isNotEmpty())
                    TideChart.render(hourly, todayHilo) else null
                main.post {
                    hilo = tides
                    conditions = cond
                    summary = sum
                    chart = bmp
                    loading = false
                    invalidate()
                }
            } catch (e: Exception) {
                main.post {
                    error = "Couldn't load tides — check your connection"
                    loading = false
                    invalidate()
                }
            }
        }.start()
    }

    private fun isToday(d: Date): Boolean {
        val a = Calendar.getInstance()
        val b = Calendar.getInstance().apply { time = d }
        return a.get(Calendar.YEAR) == b.get(Calendar.YEAR) &&
            a.get(Calendar.DAY_OF_YEAR) == b.get(Calendar.DAY_OF_YEAR)
    }

    override fun onGetTemplate(): Template {
        if (loading) {
            return PaneTemplate.Builder(Pane.Builder().setLoading(true).build())
                .setTitle(station.name)
                .setHeaderAction(Action.BACK)
                .build()
        }

        val pane = Pane.Builder()
        if (error != null) {
            pane.addRow(Row.Builder().setTitle(error!!).build())
        } else {
            buildRows().forEach { pane.addRow(it) }
            // Attach the chart image. Pane.setImage needs car API level 7;
            // older hosts fall back to a large image on the first row.
            chart?.let { bmp ->
                val icon = CarIcon.Builder(IconCompat.createWithBitmap(bmp)).build()
                if (carContext.carAppApiLevel >= 7) {
                    pane.setImage(icon)
                }
            }
        }

        return PaneTemplate.Builder(pane.build())
            .setTitle(station.name)
            .setHeaderAction(Action.BACK)
            .setActionStrip(
                ActionStrip.Builder()
                    .addAction(
                        Action.Builder()
                            .setTitle("Refresh")
                            .setOnClickListener { load(); invalidate() }
                            .build()
                    )
                    .build()
            )
            .build()
    }

    /** Builds up to four glanceable rows for the pane. */
    private fun buildRows(): List<Row> {
        val rows = ArrayList<Row>()
        val fmt = SimpleDateFormat("EEE h:mm a", Locale.US)
        val now = Date()

        // If the chart couldn't render on this host (no level-7 image support),
        // lead with a large chart image inside a row instead.
        if (chart != null && carContext.carAppApiLevel < 7) {
            val icon = CarIcon.Builder(IconCompat.createWithBitmap(chart!!)).build()
            rows.add(
                Row.Builder()
                    .setTitle("Today's tides")
                    .setImage(icon, Row.IMAGE_TYPE_LARGE)
                    .build()
            )
        }

        val nextHigh = hilo.firstOrNull { it.high && it.time.after(now) }
        val nextLow = hilo.firstOrNull { !it.high && it.time.after(now) }
        nextHigh?.let {
            rows.add(
                Row.Builder()
                    .setTitle("▲ High   ${fmt.format(it.time)}")
                    .addText("%+.1f ft".format(it.heightFt))
                    .build()
            )
        }
        nextLow?.let {
            rows.add(
                Row.Builder()
                    .setTitle("▼ Low   ${fmt.format(it.time)}")
                    .addText("%+.1f ft".format(it.heightFt))
                    .build()
            )
        }

        // Conditions row (only the parts we actually have).
        conditions?.let { c ->
            val parts = ArrayList<String>()
            c.waterTempF?.let { parts.add("Water ${it.toInt()}°F") }
            if (c.windMph != null) {
                val dir = c.windDir?.let { "$it " } ?: ""
                parts.add("Wind $dir${c.windMph.toInt()} mph")
            }
            if (parts.isNotEmpty()) {
                val wl = c.waterLevelFt?.let { "Water level %+.1f ft".format(it) } ?: "Live conditions"
                rows.add(Row.Builder().setTitle(parts.joinToString("  ·  ")).addText(wl).build())
            }
        }

        // Fishing + sun/moon (phone-computed, shown when cached).
        summary?.let { s ->
            val title = StringBuilder()
            s.stars?.let { title.append("Fishing ").append(stars(it)) }
            s.fishingLabel?.let {
                if (title.isNotEmpty()) title.append("  ·  ")
                title.append(it)
            }
            val sub = StringBuilder()
            if (s.sunrise != null && s.sunset != null) sub.append("Sun ${s.sunrise}–${s.sunset}")
            if (s.moonPhase != null) {
                if (sub.isNotEmpty()) sub.append("  ·  ")
                sub.append("Moon ${s.moonPhase}")
                s.moonPct?.let { sub.append(" ${it}%") }
            }
            if (title.isNotEmpty() || sub.isNotEmpty()) {
                val row = Row.Builder()
                    .setTitle(if (title.isNotEmpty()) title.toString() else "Sun & moon")
                if (sub.isNotEmpty()) row.addText(sub.toString())
                rows.add(row.build())
            }
        }

        if (rows.isEmpty()) {
            rows.add(Row.Builder().setTitle("No tide data available").build())
        }
        return rows
    }

    private fun stars(n: Int): String {
        val c = n.coerceIn(0, 5)
        return "★".repeat(c) + "☆".repeat(5 - c)
    }
}
