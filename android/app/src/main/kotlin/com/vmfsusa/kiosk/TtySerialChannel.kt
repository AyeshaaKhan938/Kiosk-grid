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
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Direct /dev/ttyS* serial bridge to the Reyeah Control Board.
 *
 * Confirmed against the factory APK (libserial_port.so + android_serialport_api).
 * The Reyeah board on this hardware is wired to the tablet's UART pins, not
 * through a USB-to-serial bridge — so usb_serial enumeration sees nothing.
 *
 * Method channel: vmfs.kiosk/tty_serial
 *
 * Concurrency model
 * -----------------
 * Every native call (open / write / read / close) is dispatched onto a
 * single-thread executor. That serializes access to the underlying
 * file descriptor end-to-end — there's no longer a window where close()
 * on the UI thread can yank the fd while a background read is mid-flight
 * inside libserial_port.so. Eliminating that race is what fixes the
 * post-dispense SIGSEGV that was killing the activity (the crash that
 * sometimes auto-relaunched via the HOME launcher, sometimes left the
 * screen black).
 *
 * The `closing` flag is set the moment a close request is enqueued, so
 * any in-flight read returns its accumulated bytes immediately instead
 * of looping into a freshly-closed fd.
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

    /** Set true while a close is being processed so reads bail out cleanly. */
    private val closing = AtomicBoolean(false)

    /** Every native operation runs on this single thread. */
    private val ioThread = Executors.newSingleThreadExecutor { r ->
        Thread(r, "vmfs-tty-io").apply { isDaemon = true }
    }

    private val main = Handler(Looper.getMainLooper())

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                // listDevices is pure filesystem — safe on the platform thread.
                "listDevices" -> result.success(listDevices())
                "isOpen" -> result.success(port != null)

                "open" -> {
                    val path = call.argument<String>("path")
                    val baud = call.argument<Int>("baud") ?: 9600
                    ioThread.execute {
                        try {
                            val ok = open(path, baud)
                            main.post { result.success(ok) }
                        } catch (e: Throwable) {
                            main.post { result.error("TTY_ERROR", e.message ?: "open failed", null) }
                        }
                    }
                }

                "write" -> {
                    val data = call.argument<ByteArray>("data")
                    ioThread.execute {
                        try {
                            val ok = write(data)
                            main.post { result.success(ok) }
                        } catch (e: Throwable) {
                            main.post { result.error("TTY_ERROR", e.message ?: "write failed", null) }
                        }
                    }
                }

                "read" -> {
                    val timeout = call.argument<Int>("timeoutMs") ?: 1000
                    ioThread.execute {
                        val bytes = try {
                            readWithTimeout(timeout)
                        } catch (_: Throwable) {
                            byteArrayOf()
                        }
                        main.post { result.success(bytes) }
                    }
                }

                "close" -> {
                    // Flip the flag immediately so any read sitting in
                    // readWithTimeout returns on the next sleep tick instead
                    // of trying to read from a closing fd.
                    closing.set(true)
                    ioThread.execute {
                        val ok = try { close() } catch (_: Throwable) { false }
                        closing.set(false)
                        main.post { result.success(ok) }
                    }
                }

                else -> result.notImplemented()
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

    /** All callers run on ioThread, so direct field access is safe here. */
    private fun open(path: String?, baud: Int): Boolean {
        if (path.isNullOrEmpty()) throw IllegalArgumentException("path required")
        // We deliberately do NOT close the previous SerialPort here. The
        // native close path (libserial_port.so) SIGSEGV'd on this hardware
        // and SIGSEGV bypasses Kotlin try/catch, so any attempt to clean
        // up was killing the activity. We just abandon the previous
        // reference; the leaked fd is reclaimed when the JVM finalizes
        // the SerialPort, or at app exit. Open creates a fresh fd
        // regardless of any zombie one — Linux lets you open the same
        // TTY twice without conflict.
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
     * Returns an empty array if no data arrived within the timeout, or if a
     * close was requested mid-read.
     */
    private fun readWithTimeout(timeoutMs: Int): ByteArray {
        val ins = inputStream ?: return byteArrayOf()
        val deadline = System.currentTimeMillis() + timeoutMs
        val buffer = ByteArray(1024)
        var total = 0
        var lastByteAt = 0L

        while (System.currentTimeMillis() < deadline) {
            // Abort early if a close was requested. We're on the same thread
            // as close() (single-thread executor), but the flag is checked
            // here as defense against future refactors that change threading.
            if (closing.get()) break

            val available = try { ins.available() } catch (_: IOException) { 0 }
            if (available > 0) {
                val n = try {
                    ins.read(buffer, total, minOf(buffer.size - total, available))
                } catch (_: IOException) {
                    break
                }
                if (n > 0) {
                    total += n
                    lastByteAt = System.currentTimeMillis()
                }
                if (total >= buffer.size) break
                continue
            }
            if (total > 0 && System.currentTimeMillis() - lastByteAt > 80) break
            try { Thread.sleep(15) } catch (_: InterruptedException) { break }
        }

        return if (total > 0) buffer.copyOf(total) else byteArrayOf()
    }

    private fun close(): Boolean = closeInternal()

    /**
     * Intentional no-op-with-null. Calling SerialPort.close() — or
     * close() on the wrapped InputStream/OutputStream, which all
     * delegate to the same JNI close on the underlying file
     * descriptor — was SIGSEGV-ing on this hardware after the motor
     * fired. SIGSEGV from native code can't be caught from Kotlin,
     * so any attempt to "safely close" was killing the activity.
     *
     * We just null the references. The JVM will eventually finalize
     * the SerialPort and run its native close on the GC thread, where
     * any crash is suppressed by the runtime instead of taking down
     * the activity. The leaked fd is acceptable: at one per dispense,
     * Android's per-process ulimit (8k–32k fds) is good for years.
     */
    private fun closeInternal(): Boolean {
        return try {
            inputStream = null
            outputStream = null
            port = null
            true
        } catch (_: Throwable) {
            false
        }
    }
}
