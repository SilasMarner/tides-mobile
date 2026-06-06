package com.mattbettinger.tides.car

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.DashPathEffect
import android.graphics.Paint
import android.graphics.Path
import java.util.Calendar

/**
 * Renders today's tide curve to a Bitmap for display on the Android Auto
 * screen. Android Auto can't run our Flutter chart widget, but it can show an
 * image — so we draw the same idea (curve + high/low dots + current-time line)
 * onto a bitmap. Colours mirror the phone app (navy card, cyan curve).
 */
object TideChart {

    private const val BG = 0xFF0F1F35.toInt()      // kCardBg
    private const val CURVE = 0xFF2BE7FF.toInt()    // bright cyan
    private const val HIGH = 0xFF4DD0E1.toInt()     // kHighTide
    private const val LOW = 0xFF1565C0.toInt()      // kLowTide
    private const val NOW = 0xFFFFB300.toInt()      // amber
    private const val GRID = 0x22FFFFFF

    /**
     * @param hourly  (hourOfDay 0..23, heightFt) predicted heights for today.
     * @param hiloToday today's high/low points (for the dots).
     */
    fun render(
        hourly: List<Pair<Int, Double>>,
        hiloToday: List<TidePoint>,
        width: Int = 720,
        height: Int = 340,
    ): Bitmap {
        val bmp = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val c = Canvas(bmp)
        c.drawColor(BG)

        if (hourly.size < 2) return bmp

        val padL = 16f
        val padR = 16f
        val padT = 22f
        val padB = 22f
        val plotW = width - padL - padR
        val plotH = height - padT - padB

        val heights = hourly.map { it.second }
        var minV = heights.min()
        var maxV = heights.max()
        // Pad the range so the curve doesn't touch the edges.
        val span = (maxV - minV).coerceAtLeast(0.5)
        minV -= span * 0.18
        maxV += span * 0.18

        fun x(hourFloat: Double) = padL + (hourFloat / 24.0).toFloat() * plotW
        fun y(v: Double) =
            padT + (1f - ((v - minV) / (maxV - minV)).toFloat()) * plotH

        // Zero (MLLW datum) baseline if it falls within range.
        if (minV < 0 && maxV > 0) {
            val gp = Paint().apply {
                color = GRID; strokeWidth = 1.5f; isAntiAlias = true
            }
            c.drawLine(padL, y(0.0), width - padR, y(0.0), gp)
        }

        // Tide curve.
        val curvePaint = Paint().apply {
            color = CURVE
            style = Paint.Style.STROKE
            strokeWidth = 5f
            isAntiAlias = true
            strokeCap = Paint.Cap.ROUND
            strokeJoin = Paint.Join.ROUND
        }
        val path = Path()
        hourly.forEachIndexed { i, (h, v) ->
            val px = x(h.toDouble())
            val py = y(v)
            if (i == 0) path.moveTo(px, py) else path.lineTo(px, py)
        }
        c.drawPath(path, curvePaint)

        // High / low dots.
        val dotFill = Paint().apply { isAntiAlias = true; style = Paint.Style.FILL }
        val dotRing = Paint().apply {
            isAntiAlias = true; style = Paint.Style.STROKE
            strokeWidth = 2f; color = Color.WHITE
        }
        for (p in hiloToday) {
            val cal = Calendar.getInstance().apply { time = p.time }
            val hf = cal.get(Calendar.HOUR_OF_DAY) + cal.get(Calendar.MINUTE) / 60.0
            val px = x(hf)
            val py = y(p.heightFt)
            dotFill.color = if (p.high) HIGH else LOW
            c.drawCircle(px, py, 7f, dotFill)
            c.drawCircle(px, py, 7f, dotRing)
        }

        // Current-time vertical amber line.
        val cal = Calendar.getInstance()
        val nowH = cal.get(Calendar.HOUR_OF_DAY) + cal.get(Calendar.MINUTE) / 60.0
        val nowPaint = Paint().apply {
            color = NOW
            strokeWidth = 3f
            isAntiAlias = true
            pathEffect = DashPathEffect(floatArrayOf(10f, 8f), 0f)
        }
        val nx = x(nowH)
        c.drawLine(nx, padT, nx, height - padB, nowPaint)

        return bmp
    }
}
