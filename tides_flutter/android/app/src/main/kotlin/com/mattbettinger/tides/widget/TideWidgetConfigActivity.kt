package com.mattbettinger.tides.widget

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.Intent
import android.os.Bundle
import android.view.View
import android.widget.ArrayAdapter
import android.widget.ListView
import android.widget.TextView
import com.mattbettinger.tides.R
import com.mattbettinger.tides.car.NoaaRepo

/**
 * Shown when the user drags a Tide widget onto their home screen. Picks
 * which favorite station that specific widget instance tracks. Each widget
 * is bound to exactly one station — add it again to track another.
 */
class TideWidgetConfigActivity : Activity() {
    private var appWidgetId = AppWidgetManager.INVALID_APPWIDGET_ID

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Cancelled unless a station is actually picked below.
        setResult(RESULT_CANCELED)
        setContentView(R.layout.activity_widget_config)

        appWidgetId = intent?.extras?.getInt(
            AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID,
        ) ?: AppWidgetManager.INVALID_APPWIDGET_ID
        if (appWidgetId == AppWidgetManager.INVALID_APPWIDGET_ID) {
            finish()
            return
        }

        val favorites = NoaaRepo.readFavorites(this)
        val listView = findViewById<ListView>(R.id.config_list)
        val emptyView = findViewById<TextView>(R.id.config_empty)

        if (favorites.isEmpty()) {
            listView.visibility = View.GONE
            emptyView.visibility = View.VISIBLE
            return
        }

        listView.adapter = ArrayAdapter(
            this, android.R.layout.simple_list_item_1, favorites.map { it.name },
        )
        listView.setOnItemClickListener { _, _, position, _ ->
            val station = favorites[position]
            TideWidgetProvider.saveStation(this, appWidgetId, station)
            TideWidgetProvider.updateWidget(this, AppWidgetManager.getInstance(this), appWidgetId)
            val result = Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
            setResult(RESULT_OK, result)
            finish()
        }
    }
}
