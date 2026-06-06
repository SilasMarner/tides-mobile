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

/** Live conditions for the rich pane (any field may be null if the station
 *  lacks that sensor). */
data class CarConditions(
    val waterTempF: Double?,
    val windMph: Double?,
    val windDir: String?,
    val waterLevelFt: Double?,
)

/** Phone-computed extras (fishing, sun, moon) read from the shared cache the
 *  Flutter app writes. Absent if the station hasn't been opened/prefetched. */
data class CarSummary(
    val stars: Int?,
    val fishingLabel: String?,
    val bestTimes: String?,
    val movement: String?,
    val sunrise: String?,
    val sunset: String?,
    val moonPhase: String?,
    val moonPct: Int?,
)

/**
 * Bridges the car module to the same data the phone app uses:
 *  - favorites + phone-computed extras are read from the shared_preferences
 *    store the Flutter app writes (no duplication, no extra storage),
 *  - tides and live conditions come from NOAA CO-OPS, the same source as the
 *    phone app.
 */
object NoaaRepo {

    private const val BASE = "https://api.tidesandcurrents.noaa.gov/api/prod/datagetter"

    private fun httpGet(url: String): String {
        val conn = (URL(url).openConnection() as HttpURLConnection).apply {
            connectTimeout = 12000
            readTimeout = 15000
        }
        try {
            return conn.inputStream.bufferedReader().use { it.readText() }
        } finally {
            conn.disconnect()
        }
    }

    private fun flutterPrefs(context: Context) =
        context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

    /**
     * Reads the user's favorite stations from the Flutter app's SharedPreferences.
     * The favorites value is a JSON array of `{id, name, lat, lon}`.
     */
    fun readFavorites(context: Context): List<CarStation> {
        val raw = flutterPrefs(context).getString("flutter.favorites", null) ?: return emptyList()
        return try {
            val arr = JSONArray(raw)
            (0 until arr.length()).map { i ->
                val o = arr.getJSONObject(i)
                CarStation(
                    o.getString("id"), o.getString("name"),
                    o.getDouble("lat"), o.getDouble("lon"),
                )
            }
        } catch (e: Exception) {
            emptyList()
        }
    }

    /** Reads the phone-computed fishing/sun/moon summary for a station, if cached. */
    fun readCarSummary(context: Context, stationId: String): CarSummary? {
        val raw = flutterPrefs(context).getString("flutter.car_$stationId", null) ?: return null
        return try {
            val o = JSONObject(raw)
            CarSummary(
                stars = if (o.has("stars")) o.getInt("stars") else null,
                fishingLabel = o.optString("label").ifEmpty { null },
                bestTimes = o.optString("best").ifEmpty { null },
                movement = o.optString("movement").ifEmpty { null },
                sunrise = o.optString("sunrise").ifEmpty { null },
                sunset = o.optString("sunset").ifEmpty { null },
                moonPhase = o.optString("moonPhase").ifEmpty { null },
                moonPct = if (o.has("moonPct")) o.getInt("moonPct") else null,
            )
        } catch (e: Exception) {
            null
        }
    }

    /**
     * High/low tide predictions over today + the next two days (so "next tides"
     * spans past midnight), in station-local time. Background-thread only.
     */
    fun fetchTides(station: CarStation): List<TidePoint> {
        val ymd = SimpleDateFormat("yyyyMMdd", Locale.US)
        val now = Date()
        val begin = ymd.format(now)
        val end = ymd.format(Date(now.time + 2L * 24 * 3600 * 1000))
        val url = "$BASE?begin_date=$begin&end_date=$end&station=${station.id}" +
            "&product=predictions&datum=MLLW&time_zone=lst_ldt&interval=hilo" +
            "&units=english&format=json&application=opentides_auto"
        val preds = JSONObject(httpGet(url)).optJSONArray("predictions") ?: return emptyList()
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

    /**
     * Hourly predicted heights for today (for the chart curve), as
     * (hourOfDay 0..23, heightFt). Station-local time.
     */
    fun fetchHourly(station: CarStation): List<Pair<Int, Double>> {
        val ymd = SimpleDateFormat("yyyyMMdd", Locale.US)
        val today = ymd.format(Date())
        val url = "$BASE?begin_date=$today&end_date=$today&station=${station.id}" +
            "&product=predictions&datum=MLLW&time_zone=lst_ldt&interval=h" +
            "&units=english&format=json&application=opentides_auto"
        val preds = JSONObject(httpGet(url)).optJSONArray("predictions") ?: return emptyList()
        val parse = SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.US)
        val out = ArrayList<Pair<Int, Double>>()
        for (i in 0 until preds.length()) {
            val p = preds.getJSONObject(i)
            val t = parse.parse(p.getString("t")) ?: continue
            val v = p.getString("v").toDoubleOrNull() ?: continue
            val cal = java.util.Calendar.getInstance().apply { time = t }
            out.add(cal.get(java.util.Calendar.HOUR_OF_DAY) to v)
        }
        return out
    }

    /** Latest live observations (water temp, wind, water level). Best-effort:
     *  each product is fetched independently so a missing sensor doesn't fail
     *  the others. */
    fun fetchConditions(station: CarStation): CarConditions {
        fun latest(product: String, extra: String = ""): JSONObject? = try {
            val url = "$BASE?date=latest&station=${station.id}&product=$product" +
                "&time_zone=lst_ldt&units=english&format=json&application=opentides_auto$extra"
            JSONObject(httpGet(url)).optJSONArray("data")?.optJSONObject(0)
        } catch (e: Exception) { null }

        val wt = latest("water_temperature")?.optString("v")?.toDoubleOrNull()
        val wl = latest("water_level", "&datum=MLLW")?.optString("v")?.toDoubleOrNull()
        val windObj = latest("wind")
        val windSpeed = windObj?.optString("s")?.toDoubleOrNull() // knots
        val windDir = windObj?.optString("dr")?.ifEmpty { null }
        return CarConditions(
            waterTempF = wt,
            windMph = windSpeed?.let { it * 1.15078 }, // knots → mph
            windDir = windDir,
            waterLevelFt = wl,
        )
    }
}
