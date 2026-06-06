package com.mattbettinger.tides.car

import android.graphics.Bitmap
import android.graphics.Color
import kotlin.math.sqrt

/**
 * Renders a simple moon-phase disc (the illuminated fraction) to a bitmap for
 * the Android Auto screen, from the phase name + percent illuminated that the
 * phone computes and shares to the car.
 *
 * The terminator is computed per pixel: with f = illuminated fraction and
 * t = 1 − 2f, a waxing moon is lit where x ≥ t·xw and a waning moon where
 * x ≤ −t·xw (xw = the disc half-width at that row). That gives new → crescent
 * → quarter → gibbous → full correctly for both waxing and waning.
 */
object MoonRender {

    private val LIT = Color.rgb(0xE9, 0xE6, 0xCF)   // pale moon
    private val DARK = Color.rgb(0x2A, 0x2D, 0x3A)  // shadowed side

    fun render(phase: String?, pct: Int?, size: Int = 132): Bitmap {
        val bmp = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val p = (phase ?: "").lowercase()
        var f = (pct ?: 0).coerceIn(0, 100) / 100.0
        if (p.contains("full")) f = 1.0
        if (p.contains("new")) f = 0.0
        // Waning = lit on the left; waxing (incl. "first quarter") = lit on right.
        val waning = p.contains("waning") || p.contains("last") || p.contains("third")
        val t = 1.0 - 2.0 * f

        val r = size / 2.0 - 2.0
        val cx = size / 2.0
        val cy = size / 2.0

        for (py in 0 until size) {
            val ny = py - cy
            if (kotlin.math.abs(ny) > r) continue
            val xw = sqrt(r * r - ny * ny)
            for (px in 0 until size) {
                val nx = px - cx
                val dist = sqrt(nx * nx + ny * ny)
                if (dist > r) continue
                val lit = if (waning) nx <= -t * xw else nx >= t * xw
                var color = if (lit) LIT else DARK
                // Soft 1px edge for a cleaner disc.
                if (dist > r - 1.2) {
                    val a = ((r - dist) / 1.2).coerceIn(0.0, 1.0)
                    color = Color.argb((a * 255).toInt(), Color.red(color),
                        Color.green(color), Color.blue(color))
                }
                bmp.setPixel(px, py, color)
            }
        }
        return bmp
    }
}
