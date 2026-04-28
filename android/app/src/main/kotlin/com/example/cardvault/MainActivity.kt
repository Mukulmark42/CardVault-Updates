package com.example.cardvault

import android.app.DownloadManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.database.Cursor
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterFragmentActivity() {

    companion object {
        private const val METHOD_CHANNEL = "com.cardvault/ota"
        private const val EVENT_CHANNEL  = "com.cardvault/ota_progress"
    }

    // ── State ────────────────────────────────────────────────────────────────────
    private var downloadId: Long = -1L
    private var progressSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private var progressRunnable: Runnable? = null
    private var downloadReceiver: BroadcastReceiver? = null
    private var installTriggered = false  // guard: only install once

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ── EventChannel: streams progress to Flutter ────────────────────────────
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    progressSink = events
                }
                override fun onCancel(arguments: Any?) {
                    progressSink = null
                }
            })

        // ── MethodChannel: start / cancel download ───────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startDownload" -> {
                        val url = call.argument<String>("url") ?: run {
                            result.error("BAD_ARGS", "url is required", null)
                            return@setMethodCallHandler
                        }
                        startDownload(url)
                        result.success(null)
                    }
                    "cancelDownload" -> {
                        cancelDownload()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // ── Download via DownloadManager (survives screen-off) ───────────────────────
    private fun startDownload(url: String) {
        val dm = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager

        // Cancel any in-progress download
        if (downloadId != -1L) {
            dm.remove(downloadId)
            stopProgressPolling()
        }
        installTriggered = false

        val destFile = getDestFile()
        if (destFile.exists()) destFile.delete()

        val request = DownloadManager.Request(Uri.parse(url)).apply {
            setTitle("CardVault Update")
            setDescription("Downloading update…")
            setDestinationUri(Uri.fromFile(destFile))
            setNotificationVisibility(
                DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED
            )
            setAllowedOverMetered(true)
            setAllowedOverRoaming(true)
        }

        downloadId = dm.enqueue(request)

        // ── Broadcast receiver: fires when DownloadManager finishes ──────────────
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                val id = intent?.getLongExtra(DownloadManager.EXTRA_DOWNLOAD_ID, -1L)
                if (id == downloadId) {
                    stopProgressPolling()
                    triggerInstallIfReady(dm, destFile)
                    try { unregisterReceiver(this) } catch (_: Exception) {}
                    downloadReceiver = null
                }
            }
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(
                receiver,
                IntentFilter(DownloadManager.ACTION_DOWNLOAD_COMPLETE),
                Context.RECEIVER_NOT_EXPORTED
            )
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            registerReceiver(receiver, IntentFilter(DownloadManager.ACTION_DOWNLOAD_COMPLETE))
        }
        downloadReceiver = receiver

        // ── Polling: updates Flutter progress bar every 500 ms ───────────────────
        startProgressPolling(dm, destFile)
    }

    // ── Progress polling ─────────────────────────────────────────────────────────
    private fun startProgressPolling(dm: DownloadManager, destFile: File) {
        val runnable = object : Runnable {
            override fun run() {
                val info = queryProgress(dm)
                val status = info["status"] as String

                mainHandler.post { progressSink?.success(info) }

                when (status) {
                    "downloading", "pending", "paused" -> {
                        // Keep polling
                        mainHandler.postDelayed(this, 500)
                    }
                    "done" -> {
                        // Download finished — trigger install
                        triggerInstallIfReady(dm, destFile)
                    }
                    "error" -> {
                        mainHandler.post {
                            progressSink?.success(mapOf("status" to "error", "percent" to 0.0))
                        }
                    }
                    // else: unknown / already handled
                }
            }
        }
        progressRunnable = runnable
        mainHandler.postDelayed(runnable, 500)
    }

    private fun stopProgressPolling() {
        progressRunnable?.let { mainHandler.removeCallbacks(it) }
        progressRunnable = null
    }

    private fun queryProgress(dm: DownloadManager): Map<String, Any> {
        val query = DownloadManager.Query().setFilterById(downloadId)
        val cursor: Cursor = dm.query(query)
        return if (cursor.moveToFirst()) {
            val bytesDownloaded = cursor.getLong(
                cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR)
            )
            val bytesTotal = cursor.getLong(
                cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_TOTAL_SIZE_BYTES)
            )
            val statusCode = cursor.getInt(
                cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS)
            )
            cursor.close()

            val percent = if (bytesTotal > 0) (bytesDownloaded * 100.0 / bytesTotal) else 0.0
            val status = when (statusCode) {
                DownloadManager.STATUS_RUNNING    -> "downloading"
                DownloadManager.STATUS_PAUSED     -> "paused"
                DownloadManager.STATUS_PENDING    -> "pending"
                DownloadManager.STATUS_SUCCESSFUL -> "done"
                DownloadManager.STATUS_FAILED     -> "error"
                else                              -> "unknown"
            }
            mapOf(
                "status"     to status,
                "percent"    to percent,
                "downloaded" to bytesDownloaded,
                "total"      to bytesTotal
            )
        } else {
            cursor.close()
            mapOf("status" to "error", "percent" to 0.0)
        }
    }

    // ── Auto-install: called from both the receiver AND the polling loop ─────────
    @Synchronized
    private fun triggerInstallIfReady(dm: DownloadManager, destFile: File) {
        if (installTriggered) return   // Only install once

        // Verify DownloadManager reports success
        val query = DownloadManager.Query().setFilterById(downloadId)
        val cursor = dm.query(query)
        var success = false
        if (cursor.moveToFirst()) {
            val status = cursor.getInt(
                cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS)
            )
            success = (status == DownloadManager.STATUS_SUCCESSFUL)
        }
        cursor.close()

        if (success && destFile.exists() && destFile.length() > 0) {
            installTriggered = true
            mainHandler.post {
                // Notify Flutter: 100% + installing status
                progressSink?.success(mapOf("status" to "installing", "percent" to 100.0))
                // Small delay so Flutter UI can update before the installer takes over
                mainHandler.postDelayed({ installApk(destFile) }, 500)
            }
        } else if (!success) {
            mainHandler.post {
                progressSink?.success(mapOf("status" to "error", "percent" to 0.0))
            }
        }
    }

    // ── Launch system APK installer ──────────────────────────────────────────────
    private fun installApk(file: File) {
        try {
            val uri = FileProvider.getUriForFile(
                this,
                "${packageName}.ota_update_provider",
                file
            )
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
            }
            startActivity(intent)
        } catch (e: Exception) {
            // Fallback: tell Flutter something went wrong
            progressSink?.success(mapOf("status" to "error", "percent" to 0.0))
        }
    }

    private fun getDestFile(): File =
        File(
            getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS),
            "cardvault-update.apk"
        )

    // ── Cancel download ──────────────────────────────────────────────────────────
    private fun cancelDownload() {
        stopProgressPolling()
        if (downloadId != -1L) {
            val dm = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
            dm.remove(downloadId)
            downloadId = -1L
        }
        downloadReceiver?.let {
            try { unregisterReceiver(it) } catch (_: Exception) {}
            downloadReceiver = null
        }
        installTriggered = false
    }

    override fun onDestroy() {
        super.onDestroy()
        stopProgressPolling()
        downloadReceiver?.let {
            try { unregisterReceiver(it) } catch (_: Exception) {}
        }
    }
}