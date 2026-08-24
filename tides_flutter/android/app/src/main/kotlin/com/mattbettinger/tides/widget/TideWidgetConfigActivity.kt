package com.mattbettinger.tides.widget

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.Intent
import android.os.Bundle
import android.view.View
import android.widget.ArrayAdapter
import android.widget.Button
import android.widget.ListView
import android.widget.TextView
import android.widget.Toast
import com.mattbettinger.tides.R
import com.mattbettinger.tides.car.CarStation
import com.mattbettinger.tides.car.NoaaRepo

/**
 * Shown when the user drags a Tide widget onto their home screen. Picks up to
 * [TideWidgetProvider.MAX_STATIONS] favorites for that widget instance to
 * track — one station gets the full previous+next-3 tide chart view, several
 * get one compact line each (see [TideWidgetProvider]).
 */
class TideWidgetConfigActivity : Activity() {
    private var appWidgetId = AppWidgetManager.INVALID_APPWIDGET_ID
    private lateinit var favorites: List<CarStation>

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Cancelled unless "Add Widget" is actually tapped below.
        setResult(RESULT_CANCELED)
        setContentView(R.layout.activity_widget_config)

        appWidgetId = intent?.extras?.getInt(
            AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID,
        ) ?: AppWidgetManager.INVALID_APPWIDGET_ID
        if (appWidgetId == AppWidgetManager.INVALID_APPWIDGET_ID) {
            finish()
            return
        }

        favorites = NoaaRepo.readFavorites(this)
        val listView = findViewById<ListView>(R.id.config_list)
        val emptyView = findViewById<TextView>(R.id.config_empty)
        val addButton = findViewById<Button>(R.id.config_add)

        if (favorites.isEmpty()) {
            listView.visibility = View.GONE
            addButton.visibility = View.GONE
            emptyView.visibility = View.VISIBLE
            return
        }

        listView.choiceMode = ListView.CHOICE_MODE_MULTIPLE
        listView.adapter = ArrayAdapter(
            this, android.R.layout.simple_list_item_multiple_choice, favorites.map { it.name },
        )
        listView.setOnItemClickListener { _, _, position, _ ->
            if (listView.checkedItemCount > TideWidgetProvider.MAX_STATIONS) {
                listView.setItemChecked(position, false)
                Toast.makeText(
                    this, "Up to ${TideWidgetProvider.MAX_STATIONS} stations per widget",
                    Toast.LENGTH_SHORT,
                ).show()
            }
            addButton.isEnabled = listView.checkedItemCount > 0
        }

        addButton.setOnClickListener {
            val selected = favorites.filterIndexed { i, _ -> listView.isItemChecked(i) }
            if (selected.isEmpty()) return@setOnClickListener
            TideWidgetProvider.saveStations(this, appWidgetId, selected)
            TideWidgetProvider.updateWidget(this, AppWidgetManager.getInstance(this), appWidgetId)
            val result = Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
            setResult(RESULT_OK, result)
            finish()
        }
    }
}
