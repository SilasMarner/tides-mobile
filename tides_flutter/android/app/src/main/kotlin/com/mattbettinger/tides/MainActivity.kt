package com.mattbettinger.tides

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.ArrayList

class MainActivity : FlutterActivity() {
    private var widgetChannel: MethodChannel? = null

    // A widget tap's station payload, held until Dart asks for it. Only needed
    // for a cold start (configureFlutterEngine runs before HomeScreen's Dart
    // code has registered a handler, so pushing immediately would be dropped);
    // a tap while already running is pushed straight through instead — see
    // captureWidgetIntent.
    private var pendingWidgetStation: Map<String, Any?>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        widgetChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.mattbettinger.tides/widget"
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                if (call.method == "consumePendingStation") {
                    result.success(pendingWidgetStation)
                    pendingWidgetStation = null
                } else {
                    result.notImplemented()
                }
            }
        }
        captureWidgetIntent(intent, push = false)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.mattbettinger.tides/setup"
        ).setMethodCallHandler { call, result ->
            if (call.method == "clearFLNCache") {
                // FLN stores scheduled notification metadata in a named SharedPreferences
                // file. If this file contains entries saved by an older FLN version that
                // lacked the required "type" field, every FLN operation (zonedSchedule,
                // cancelAll, etc.) throws "Missing type parameter". Wiping it lets FLN
                // start fresh; AlarmManager entries are re-created by rescheduleAllStations.
                applicationContext
                    .getSharedPreferences("scheduled_notifications", Context.MODE_PRIVATE)
                    .edit().clear().apply()
                result.success(null)
            } else {
                result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.mattbettinger.tides/email"
        ).setMethodCallHandler { call, result ->
            if (call.method == "sendEmail") {
                sendEmail(
                    call.argument<String>("subject"),
                    call.argument<String>("body"),
                    call.argument<List<String>>("recipients"),
                    call.argument<List<String>>("attachments"),
                    result,
                )
            } else {
                result.notImplemented()
            }
        }
    }

    // launchMode="singleTop" reuses this activity for a widget tap while the
    // app's already running, instead of a fresh onCreate — that's the only
    // case this fires (a cold start is handled in configureFlutterEngine).
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        captureWidgetIntent(intent, push = true)
    }

    /**
     * Reads the widget-tap extras MainActivity is launched with, if any. On a
     * cold start ([push] false) the payload is stashed for Dart to pull once
     * it's ready; while already running ([push] true) it's pushed straight to
     * Dart's already-registered listener.
     */
    private fun captureWidgetIntent(intent: Intent?, push: Boolean) {
        val stationId = intent?.getStringExtra("station_id") ?: return
        val payload = mapOf(
            "id" to stationId,
            "name" to (intent.getStringExtra("station_name") ?: ""),
            "lat" to intent.getDoubleExtra("station_lat", 0.0),
            "lon" to intent.getDoubleExtra("station_lon", 0.0),
        )
        // Avoid re-delivering the same tap if this intent is read again.
        intent.removeExtra("station_id")
        if (push) {
            widgetChannel?.invokeMethod("openStation", payload)
        } else {
            pendingWidgetStation = payload
        }
    }

    /**
     * Composes an email via a clean ACTION_SEND intent wrapped in a system
     * chooser. flutter_email_sender's attachment path put `mailto:` data on the
     * ACTION_SEND intent, which made Gmail parse it as a mailto and silently drop
     * the body + attachment (blank email). We never set data on the SEND intent.
     *
     * An earlier attempt used a SENDTO `mailto:` *selector* to limit the chooser
     * to email apps, but that two-step resolution (resolve the selector, then
     * deliver SEND to it) failed to launch on some devices (START result -91).
     * A plain ACTION_SEND with an image MIME type is the standard share path
     * Gmail handles reliably; EXTRA_EMAIL still prefills the recipient.
     *
     * For multiple photos we deliberately do NOT hand-build clipData or grant
     * URI permissions manually. Setting clipData ourselves suppresses the
     * framework's migrateExtraStreamToClipData(), which is what moves every
     * EXTRA_STREAM URI into clipData and grants read access to ALL of them when
     * the chooser launches the target. Doing it by hand granted only some URIs,
     * which is exactly why Gmail dropped photos on a multi-catch send. We just
     * set EXTRA_STREAM + FLAG_GRANT_READ_URI_PERMISSION and let the OS migrate.
     */
    private fun sendEmail(
        subject: String?,
        body: String?,
        recipients: List<String>?,
        attachments: List<String>?,
        result: MethodChannel.Result,
    ) {
        try {
            val authority = "$packageName.fileprovider"
            val uris = ArrayList<Uri>()
            attachments?.forEach { path ->
                val f = File(path)
                if (f.exists()) uris.add(FileProvider.getUriForFile(this, authority, f))
            }

            val intent = Intent(
                if (uris.size > 1) Intent.ACTION_SEND_MULTIPLE else Intent.ACTION_SEND
            )
            // Attachments are a mix now (a PDF report + the original photos), so
            // a generic type is correct; "image/*" would mis-describe the PDF.
            intent.type = if (uris.isEmpty()) "text/plain" else "*/*"

            if (!recipients.isNullOrEmpty()) {
                intent.putExtra(Intent.EXTRA_EMAIL, recipients.toTypedArray())
            }
            subject?.let { intent.putExtra(Intent.EXTRA_SUBJECT, it) }
            body?.let { intent.putExtra(Intent.EXTRA_TEXT, it) }

            if (uris.isNotEmpty()) {
                intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                if (uris.size == 1) {
                    intent.putExtra(Intent.EXTRA_STREAM, uris[0])
                } else {
                    intent.putParcelableArrayListExtra(Intent.EXTRA_STREAM, uris)
                }
            }

            val chooser = Intent.createChooser(intent, "Send catches")
            chooser.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(chooser)
            result.success(true)
        } catch (e: ActivityNotFoundException) {
            result.error("no_email_app", "No email app is set up on this device.", null)
        } catch (e: Exception) {
            result.error("send_failed", e.message, null)
        }
    }
}
