package com.mattbettinger.tides.car

import android.content.Intent
import androidx.car.app.Screen
import androidx.car.app.Session

/** Holds the navigation stack for one car connection; opens the favorites list. */
class OpenTidesSession : Session() {
    override fun onCreateScreen(intent: Intent): Screen = StationListScreen(carContext)
}
