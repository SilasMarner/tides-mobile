package com.mattbettinger.tides

import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.ArrayList

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
            intent.type = if (uris.isEmpty()) "text/plain" else "image/*"

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
                // ClipData carries the URI grants across to the resolved composer.
                val clip = ClipData.newUri(contentResolver, "attachment", uris[0])
                for (i in 1 until uris.size) clip.addItem(ClipData.Item(uris[i]))
                intent.clipData = clip
            }

            val chooser = Intent.createChooser(intent, "Send catches")
            chooser.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            if (uris.isNotEmpty()) {
                chooser.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                // The chooser's automatic grant propagation only reliably covers
                // the first URI on some Android versions, so a multi-attachment
                // target (e.g. Gmail) could read the first photo but silently drop
                // the rest. Explicitly grant read access for every attachment to
                // every app that can handle the send.
                val resolvers = packageManager.queryIntentActivities(
                    intent, PackageManager.MATCH_DEFAULT_ONLY
                )
                for (ri in resolvers) {
                    val pkg = ri.activityInfo.packageName
                    for (uri in uris) {
                        grantUriPermission(
                            pkg, uri, Intent.FLAG_GRANT_READ_URI_PERMISSION
                        )
                    }
                }
            }
            startActivity(chooser)
            result.success(true)
        } catch (e: ActivityNotFoundException) {
            result.error("no_email_app", "No email app is set up on this device.", null)
        } catch (e: Exception) {
            result.error("send_failed", e.message, null)
        }
    }
}
