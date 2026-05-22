package com.vmfsusa.kiosk

import android.content.Context
import android.os.Environment
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.BufferedWriter
import java.io.File
import java.io.FileWriter
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.Executors

/**
 * Persistent log file writer — Kotlin port of factory.apk's
 * `com.yy.tools.util.LogFileUtil`.
 *
 * Writes a date-rotated text file at
 *   <external-files-dir>/vmfs-kiosk-logs/{yyyy-MM-dd}.log
 *
 * Date rotation happens on the next append after midnight.
 *
 * Method channel: vmfs.kiosk/log_file
 *   append(line)   -> bool  write a line with timestamp prefix
 *   path()         -> String?  current log file path (for support / debugging)
 *   listFiles()    -> List<String>  all log files, newest first
 *
 * Writes are dispatched to a single-thread executor so callers never
 * block on disk I/O.
 */
class LogFileChannel(private val context: Context, engine: FlutterEngine) {

    companion object {
        private const val TAG = "LogFileChannel"
        private const val DIR_NAME = "vmfs-kiosk-logs"
    }

    private val channel = MethodChannel(
        engine.dartExecutor.binaryMessenger,
        "vmfs.kiosk/log_file",
    )

    private val ioThread = Executors.newSingleThreadExecutor { r ->
        Thread(r, "vmfs-logfile-io").apply { isDaemon = true }
    }

    private val fileDateFormat = SimpleDateFormat("yyyy-MM-dd", Locale.US)
    private val lineDateFormat = SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS", Locale.US)

    private var writer: BufferedWriter? = null
    private var currentDateKey: String = ""

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "append" -> {
                    val line = call.argument<String>("line") ?: ""
                    ioThread.execute {
                        val ok = appendLine(line)
                        result.success(ok)
                    }
                }
                "path" -> result.success(currentLogFile()?.absolutePath)
                "listFiles" -> result.success(listLogFiles())
                else -> result.notImplemented()
            }
        }
    }

    private fun logsDir(): File {
        // getExternalFilesDir doesn't require runtime permissions and
        // survives uninstall in the app's scoped storage area. Path on
        // a typical Reyeah tablet:
        //   /storage/emulated/0/Android/data/com.vmfsusa.kiosk/files/vmfs-kiosk-logs/
        val base = context.getExternalFilesDir(null)
            ?: File(context.filesDir, "logs")
        val dir = File(base, DIR_NAME)
        if (!dir.exists()) dir.mkdirs()
        return dir
    }

    private fun currentDateKey(): String = fileDateFormat.format(Date())

    private fun currentLogFile(): File? {
        val dir = logsDir()
        return File(dir, "${currentDateKey()}.log")
    }

    private fun openWriter(): BufferedWriter? {
        val file = currentLogFile() ?: return null
        return try {
            BufferedWriter(FileWriter(file, true))
        } catch (e: Throwable) {
            Log.e(TAG, "openWriter failed: ${e.message}")
            null
        }
    }

    private fun appendLine(line: String): Boolean {
        return try {
            val today = currentDateKey()
            if (today != currentDateKey || writer == null) {
                // Rolled over (or first call) — close old, open today's.
                try { writer?.close() } catch (_: Throwable) {}
                writer = openWriter()
                currentDateKey = today
            }
            val w = writer ?: return false
            w.write("${lineDateFormat.format(Date())}  $line\n")
            w.flush()
            true
        } catch (e: Throwable) {
            Log.e(TAG, "appendLine failed: ${e.message}")
            false
        }
    }

    private fun listLogFiles(): List<String> {
        val dir = logsDir()
        val files = dir.listFiles()?.filter { it.name.endsWith(".log") } ?: return emptyList()
        return files.sortedByDescending { it.lastModified() }
            .map { it.absolutePath }
    }
}
