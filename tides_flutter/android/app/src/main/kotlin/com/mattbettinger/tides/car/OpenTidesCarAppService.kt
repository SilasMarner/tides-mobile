package com.mattbettinger.tides.car

import android.content.pm.ApplicationInfo
import androidx.car.app.CarAppService
import androidx.car.app.Session
import androidx.car.app.validation.HostValidator

/**
 * Entry point for OpenTides on Android Auto. The car host binds to this service
 * and the Car App Library renders our templated screens on the car display.
 *
 * Performance note: Android only instantiates this service when the phone is
 * actually connected to a car head unit — it is completely dormant otherwise,
 * so it has no effect on the normal phone app.
 */
class OpenTidesCarAppService : CarAppService() {

    override fun createHostValidator(): HostValidator {
        // Debug builds: allow any host so the Desktop Head Unit (DHU) can connect.
        // Release builds: only allow Google-signed template hosts (the standard
        // allowlist shipped with the Car App Library).
        return if (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0) {
            HostValidator.ALLOW_ALL_HOSTS_VALIDATOR
        } else {
            HostValidator.Builder(applicationContext)
                .addAllowedHosts(androidx.car.app.R.array.hosts_allowlist_sample)
                .build()
        }
    }

    override fun onCreateSession(): Session = OpenTidesSession()
}
