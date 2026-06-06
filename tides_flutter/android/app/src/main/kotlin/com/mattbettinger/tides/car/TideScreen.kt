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
    private var moon: Bitmap? = null
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
                val moonBmp = if (sum?.moonPhase != null || sum?.moonPct != null)
                    MoonRender.render(sum.moonPhase, sum.moonPct) else null
                main.post {
                    hilo = tides
                    conditions = cond
                    summary = sum
                    chart = bmp
                    moon = moonBmp
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

    /**
     * Builds up to four rich rows for the pane:
     *  1) Tides — next high & low.
     *  2) Conditions — water temp, wind, water level.
     *  3) Fishing — rating, best bite windows, tide movement.
     *  4) Sun & Moon — a rendered moon-phase image + sun times.
     */
    private fun buildRows(): List<Row> {
        val rows = ArrayList<Row>()
        val fmt = SimpleDateFormat("EEE h:mm a", Locale.US)
        val now = Date()

        // If the chart couldn't render as the hero image on this host (no
        // level-7 image support), lead with a large chart image in a row.
        if (chart != null && carContext.carAppApiLevel < 7) {
            val icon = CarIcon.Builder(IconCompat.createWithBitmap(chart!!)).build()
            rows.add(
                Row.Builder()
                    .setTitle("Today's tides")
                    .setImage(icon, Row.IMAGE_TYPE_LARGE)
                    .build()
            )
        }

        // 1) Tides — next high & low on one row.
        val nextHigh = hilo.firstOrNull { it.high && it.time.after(now) }
        val nextLow = hilo.firstOrNull { !it.high && it.time.after(now) }
        if (nextHigh != null || nextLow != null) {
            val r = Row.Builder().setTitle("Tides")
            nextHigh?.let { r.addText("▲ High  ${fmt.format(it.time)}  ·  %+.1f ft".format(it.heightFt)) }
            nextLow?.let { r.addText("▼ Low  ${fmt.format(it.time)}  ·  %+.1f ft".format(it.heightFt)) }
            rows.add(r.build())
        }

        // 2) Conditions.
        conditions?.let { c ->
            val parts = ArrayList<String>()
            c.waterTempF?.let { parts.add("Water ${it.toInt()}°F") }
            if (c.windMph != null) {
                val dir = c.windDir?.let { "$it " } ?: ""
                parts.add("Wind $dir${c.windMph.toInt()} mph")
            }
            if (parts.isNotEmpty()) {
                val r = Row.Builder().setTitle("Conditions").addText(parts.joinToString("  ·  "))
                c.waterLevelFt?.let { r.addText("Water level %+.1f ft".format(it)) }
                rows.add(r.build())
            }
        }

        // 3) Fishing — rating + best bite windows + movement (phone-computed).
        summary?.let { s ->
            val title = StringBuilder()
            s.stars?.let { title.append(stars(it)) }
            s.fishingLabel?.let {
                if (title.isNotEmpty()) title.append("  ·  ")
                title.append(it)
            }
            if (title.isNotEmpty()) {
                val r = Row.Builder().setTitle("Fishing  $title")
                s.bestTimes?.let { r.addText("Best: $it") }
                s.movement?.let { r.addText(it) }
                rows.add(r.build())
            }
        }

        // 4) Sun & Moon — rendered moon-phase image + sun times.
        summary?.let { s ->
            if (s.moonPhase != null || s.sunrise != null) {
                val moonText = StringBuilder()
                s.moonPhase?.let { moonText.append(it) }
                s.moonPct?.let {
                    if (moonText.isNotEmpty()) moonText.append("  ·  ")
                    moonText.append("$it% lit")
                }
                val r = Row.Builder()
                    .setTitle(if (moonText.isNotEmpty()) moonText.toString() else "Sun & moon")
                if (s.sunrise != null && s.sunset != null) {
                    r.addText("Sun  ↑${s.sunrise}   ↓${s.sunset}")
                }
                moon?.let {
                    r.setImage(
                        CarIcon.Builder(IconCompat.createWithBitmap(it)).build(),
                        Row.IMAGE_TYPE_LARGE,
                    )
                }
                rows.add(r.build())
            }
        }

        if (rows.isEmpty()) {
            rows.add(Row.Builder().setTitle("No tide data available").build())
        }
        // The Pane content limit is 4 rows; trim defensively.
        return if (rows.size > 4) rows.subList(0, 4) else rows
    }

    private fun stars(n: Int): String {
        val c = n.coerceIn(0, 5)
        return "★".repeat(c) + "☆".repeat(5 - c)
    }
}
