package com.mattbettinger.tides.car

import android.os.Handler
import android.os.Looper
import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.model.Action
import androidx.car.app.model.ActionStrip
import androidx.car.app.model.ItemList
import androidx.car.app.model.ListTemplate
import androidx.car.app.model.Row
import androidx.car.app.model.Template
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/** Shows the next high/low tides for one station, fetched live from NOAA. */
class TideScreen(carContext: CarContext, private val station: CarStation) :
    Screen(carContext) {

    private var loading = true
    private var error: String? = null
    private var tides: List<TidePoint> = emptyList()
    private val main = Handler(Looper.getMainLooper())

    init {
        load()
    }

    private fun load() {
        loading = true
        error = null
        Thread {
            try {
                val all = NoaaRepo.fetchTides(station)
                val now = Date()
                val next = all.filter { it.time.after(now) }.take(5)
                main.post {
                    // Fall back to the most recent few if everything is in the past.
                    tides = if (next.isNotEmpty()) next else all.takeLast(5)
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

    override fun onGetTemplate(): Template {
        if (loading) {
            return ListTemplate.Builder()
                .setLoading(true)
                .setTitle(station.name)
                .setHeaderAction(Action.BACK)
                .build()
        }

        val fmt = SimpleDateFormat("EEE h:mm a", Locale.US)
        val list = ItemList.Builder()

        if (error != null) {
            list.addItem(Row.Builder().setTitle(error!!).build())
        } else if (tides.isEmpty()) {
            list.addItem(Row.Builder().setTitle("No tide predictions available").build())
        } else {
            tides.forEach { t ->
                val sign = if (t.heightFt >= 0) "+" else ""
                val arrow = if (t.high) "▲ High" else "▼ Low"
                list.addItem(
                    Row.Builder()
                        .setTitle("$arrow   ${fmt.format(t.time)}")
                        .addText("$sign${"%.1f".format(t.heightFt)} ft")
                        .build()
                )
            }
        }

        return ListTemplate.Builder()
            .setSingleList(list.build())
            .setTitle(station.name)
            .setHeaderAction(Action.BACK)
            .setActionStrip(
                ActionStrip.Builder()
                    .addAction(
                        Action.Builder()
                            .setTitle("Refresh")
                            .setOnClickListener {
                                load()
                                invalidate()
                            }
                            .build()
                    )
                    .build()
            )
            .build()
    }
}
