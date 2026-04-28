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

    // ── State ───────────────────────────────────────────────────────────────────
    private var downloadId: Long = -1L
    private var progressSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private var progressRunnable: Runnable? = null
    private var downloadReceiver: BroadcastReceiver? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ── EventChannel: streams progress to Flutter ────────────────────────
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    progressSink = events
                }
                override fun onCancel(arguments: Any?) {
                    progressSink = null
                }
            })

        // ── MethodChannel: start / cancel download ───────────────────────────
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

    // ── Download via DownloadManager (survives screen-off) ───────────────────
    private fun startDownload(url: String) {
        val dm = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager

        // Cancel any previous in-progress download
        if (downloadId != -1L) {
            dm.remove(downloadId)
            stopProgressPolling()
        }

        val destFile = File(
            getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS),
            "cardvault-update.apk"
        )
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

        // Register completion receiver
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                val id = intent?.getLongExtra(DownloadManager.EXTRA_DOWNLOAD_ID, -1L)
                if (id == downloadId) {
                    stopProgressPolling()
                    checkAndInstall(dm, destFile)
                    unregisterReceiver(this)
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
            registerReceiver(
                receiver,
                IntentFilter(DownloadManager.ACTION_DOWNLOAD_COMPLETE)
            )
        }
        downloadReceiver = receiver

        // Poll progress every 500 ms
        startProgressPolling(dm)
    }

    private fun startProgressPolling(dm: DownloadManager) {
        val runnable = object : Runnable {
            override fun run() {
                val progress = queryProgress(dm)
                mainHandler.post { progressSink?.success(progress) }
                if (progress["status"] == "downloading") {
                    mainHandler.postDelayed(this, 500)
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
                DownloadManager.STATUS_RUNNING  -> "downloading"
                DownloadManager.STATUS_PAUSED   -> "paused"
                DownloadManager.STATUS_PENDING  -> "pending"
                DownloadManager.STATUS_SUCCESSFUL -> "done"
                DownloadManager.STATUS_FAILED   -> "error"
                else -> "unknown"
            }
            mapOf("status" to status, "percent" to percent, "downloaded" to bytesDownloaded, "total" to bytesTotal)
        } else {
            cursor.close()
            mapOf("status" to "error", "percent" to 0.0)
        }
    }

    private fun checkAndInstall(dm: DownloadManager, destFile: File) {
        val query = DownloadManager.Query().setFilterById(downloadId)
        val cursor = dm.query(query)
        var success = false
        if (cursor.moveToFirst()) {
            val status = cursor.getInt(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS))
            success = (status == DownloadManager.STATUS_SUCCESSFUL)
        }
        cursor.close()

        mainHandler.post {
            if (success && destFile.exists()) {
                progressSink?.success(mapOf("status" to "installing", "percent" to 100.0))
                installApk(destFile)
            } else {
                progressSink?.success(mapOf("status" to "error", "percent" to 0.0))
            }
        }
    }

    private fun installApk(file: File) {
        val intent = Intent(Intent.ACTION_VIEW).apply {
            val uri = FileProvider.getUriForFile(
                this@MainActivity,
                "${packageName}.ota_update_provider",
                file
            )
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
    }

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
    }

    override fun onDestroy() {
        super.onDestroy()
        stopProgressPolling()
        downloadReceiver?.let {
            try { unregisterReceiver(it) } catch (_: Exception) {}
        }
    }
}