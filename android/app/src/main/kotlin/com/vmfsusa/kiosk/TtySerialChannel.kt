package com.vmfsusa.kiosk

import android.os.Handler
import android.os.Looper
import android_serialport_api.SerialPort
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream

/**
 * Direct /dev/ttyS* serial bridge to the Reyeah Control Board.
 *
 * Confirmed against the factory APK (libserial_port.so + android_serialport_api).
 * The Reyeah board on this hardware is wired to the tablet's UART pins, not
 * through a USB-to-serial bridge — so usb_serial enumeration sees nothing.
 *
 * Method channel: vmfs.kiosk/tty_serial
 *
 * Methods:
 *   listDevices()            -> List<String>     all /dev/ttyS* and /dev/ttyUSB* paths
 *   open(path, baud)         -> bool              opens the port at the given baud rate
 *   write(data: ByteArray)   -> bool              writes raw bytes
 *   read(timeoutMs)          -> ByteArray         reads up to N bytes within timeout
 *   close()                  -> bool              closes the port
 *   isOpen()                 -> bool              current port state
 */
class TtySerialChannel(engine: FlutterEngine) {

    private val channel = MethodChannel(
        engine.dartExecutor.binaryMessenger,
        "vmfs.kiosk/tty_serial",
    )

    private var port: SerialPort? = null
    private var inputStream: InputStream? = null
    private var outputStream: OutputStream? = null

    private val main = Handler(Looper.getMainLooper())

    init {
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "listDevices" -> result.success(listDevices())
                    "open" -> {
                        val path = call.argument<String>("path")
                        val baud = call.argument<Int>("baud") ?: 9600
                        result.success(open(path, baud))
                    }
                    "write" -> {
                        val data = call.argument<ByteArray>("data")
                        result.success(write(data))
                    }
                    "read" -> {
                        val timeout = call.argument<Int>("timeoutMs") ?: 1000
                        // Blocking-with-timeout reads run on a background thread.
                        Thread {
                            val bytes = readWithTimeout(timeout)
                            main.post { result.success(bytes) }
                        }.start()
                    }
                    "close" -> result.success(close())
                    "isOpen" -> result.success(port != null)
                    else -> result.notImplemented()
                }
            } catch (e: Throwable) {
                result.error("TTY_ERROR", e.javaClass.simpleName + ": " + (e.message ?: ""), null)
            }
        }
    }

    private fun listDevices(): List<String> {
        val dev = File("/dev")
        val files = dev.listFiles() ?: return emptyList()
        return files
            .filter { it.name.startsWith("ttyS") || it.name.startsWith("ttyUSB") }
            .map { it.absolutePath }
            .sorted()
    }

    private fun open(path: String?, baud: Int): Boolean {
        if (path.isNullOrEmpty()) throw IllegalArgumentException("path required")
        close()
        val file = File(path)
        if (!file.exists()) throw IOException("Device not found: $path")
        val sp = SerialPort(file, baud, 0)
        port = sp
        inputStream = sp.inputStream
        outputStream = sp.outputStream
        return true
    }

    private fun write(data: ByteArray?): Boolean {
        val out = outputStream ?: throw IllegalStateException("port not open")
        if (data == null) throw IllegalArgumentException("data required")
        out.write(data)
        out.flush()
        return true
    }

    /**
     * Read up to 1024 bytes, returning whatever has arrived after [timeoutMs]
     * OR as soon as a quiet period (>=80 ms with no new bytes) is detected.
     * Returns an empty array if no data arrived within the timeout.
     */
    private fun readWithTimeout(timeoutMs: Int): ByteArray {
        val ins = inputStream ?: return byteArrayOf()
        val deadline = System.currentTimeMillis() + timeoutMs
        val buffer = ByteArray(1024)
        var total = 0
        var lastByteAt = 0L

        while (System.currentTimeMillis() < deadline) {
            val available = try { ins.available() } catch (_: IOException) { 0 }
            if (available > 0) {
                val n = ins.read(buffer, total, minOf(buffer.size - total, available))
                if (n > 0) {
                    total += n
                    lastByteAt = System.currentTimeMillis()
                }
                if (total >= buffer.size) break
                continue
            }
            // If we already have bytes and 80 ms of silence has passed → frame complete.
            if (total > 0 && System.currentTimeMillis() - lastByteAt > 80) break
            try { Thread.sleep(15) } catch (_: InterruptedException) { break }
        }

        return if (total > 0) buffer.copyOf(total) else byteArrayOf()
    }

    private fun close(): Boolean {
        return try {
            try { inputStream?.close() } catch (_: Throwable) {}
            try { outputStream?.close() } catch (_: Throwable) {}
            try { port?.close() } catch (_: Throwable) {}
            inputStream = null
            outputStream = null
            port = null
            true
        } catch (_: Throwable) {
            false
        }
    }
}
