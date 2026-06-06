package com.mattbettinger.tides.car

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/** A favorite tide station, mirrored from the Flutter app's saved favorites. */
data class CarStation(val id: String, val name: String, val lat: Double, val lon: Double)

/** One high or low tide prediction. */
data class TidePoint(val time: Date, val label: String, val heightFt: Double, val high: Boolean)

/**
 * Bridges the car module to the same data the phone app uses:
 *  - favorites are read straight from the shared_preferences store the Flutter
 *    app writes to (no duplication, no extra storage),
 *  - tide predictions come from NOAA CO-OPS, the same source as the phone app.
 */
object NoaaRepo {

    /**
     * Reads the user's favorite stations from the Flutter app's SharedPreferences.
     * The `shared_preferences` plugin stores values in `FlutterSharedPreferences`
     * with keys prefixed `flutter.`; the favorites value is a JSON array of
     * `{id, name, lat, lon}` (see Station.toJson in the Dart code).
     */
    fun readFavorites(context: Context): List<CarStation> {
        val prefs = context.getSharedPreferences(
            "FlutterSharedPreferences", Context.MODE_PRIVATE
        )
        val raw = prefs.getString("flutter.favorites", null) ?: return emptyList()
        return try {
            val arr = JSONArray(raw)
            (0 until arr.length()).map { i ->
                val o = arr.getJSONObject(i)
                CarStation(
                    o.getString("id"),
                    o.getString("name"),
                    o.getDouble("lat"),
                    o.getDouble("lon"),
                )
            }
        } catch (e: Exception) {
            emptyList()
        }
    }

    /**
     * Fetches high/low tide predictions for a station over today + the next two
     * days (so "next tides" always spans past midnight), in the station's local
     * time. Blocking — call from a background thread.
     */
    fun fetchTides(station: CarStation): List<TidePoint> {
        val ymd = SimpleDateFormat("yyyyMMdd", Locale.US)
        val now = Date()
        val begin = ymd.format(now)
        val end = ymd.format(Date(now.time + 2L * 24 * 3600 * 1000))
        val url = URL(
            "https://api.tidesandcurrents.noaa.gov/api/prod/datagetter" +
                "?begin_date=$begin&end_date=$end&station=${station.id}" +
                "&product=predictions&datum=MLLW&time_zone=lst_ldt&interval=hilo" +
                "&units=english&format=json&application=opentides_auto"
        )
        val conn = (url.openConnection() as HttpURLConnection).apply {
            connectTimeout = 12000
            readTimeout = 15000
        }
        try {
            conn.inputStream.bufferedReader().use { reader ->
                val body = reader.readText()
                val preds = JSONObject(body).optJSONArray("predictions")
                    ?: return emptyList()
                val parse = SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.US)
                val out = ArrayList<TidePoint>()
                for (i in 0 until preds.length()) {
                    val p = preds.getJSONObject(i)
                    val t = parse.parse(p.getString("t")) ?: continue
                    val v = p.getString("v").toDoubleOrNull() ?: continue
                    val high = p.getString("type") == "H"
                    out.add(TidePoint(t, if (high) "High" else "Low", v, high))
                }
                return out
            }
        } finally {
            conn.disconnect()
        }
    }
}
