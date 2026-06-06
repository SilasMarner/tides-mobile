package com.mattbettinger.tides.car

import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.model.Action
import androidx.car.app.model.ItemList
import androidx.car.app.model.ListTemplate
import androidx.car.app.model.MessageTemplate
import androidx.car.app.model.Row
import androidx.car.app.model.Template

/** Top-level car screen: the user's favorite stations (from the phone app). */
class StationListScreen(carContext: CarContext) : Screen(carContext) {

    override fun onGetTemplate(): Template {
        val favorites = NoaaRepo.readFavorites(carContext)

        if (favorites.isEmpty()) {
            return MessageTemplate.Builder(
                "Add favorite stations in the OpenTides phone app, " +
                    "then they'll appear here for quick tide checks."
            )
                .setTitle("OpenTides")
                .setHeaderAction(Action.APP_ICON)
                .build()
        }

        val list = ItemList.Builder()
        // The car host limits how many rows are shown while driving; cap at 6.
        favorites.take(6).forEach { st ->
            list.addItem(
                Row.Builder()
                    .setTitle(st.name)
                    .addText("Next tides")
                    .setBrowsable(true)
                    .setOnClickListener { screenManager.push(TideScreen(carContext, st)) }
                    .build()
            )
        }

        return ListTemplate.Builder()
            .setSingleList(list.build())
            .setTitle("OpenTides — Favorites")
            .setHeaderAction(Action.APP_ICON)
            .build()
    }
}
