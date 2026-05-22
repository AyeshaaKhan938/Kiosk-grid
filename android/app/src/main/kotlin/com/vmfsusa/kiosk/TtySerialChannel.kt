package com.vmfsusa.kiosk

import android.os.Handler
import android.os.Looper
import android.util.Log
import android_serialport_api.SerialPort
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.util.concurrent.Executors
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Direct /dev/ttyS* serial bridge to the Reyeah Control Board.
 *
 * Architecture mirrors factory.apk's `com.yy.tools.util.SerialPortUtils`
 * (confirmed via jadx decompile) — the production-tested pattern on
 * this exact hardware:
 *
 *   - SINGLE persistent SerialPort instance reused across many
 *     dispenses (factory only re-opens when port/baud changes).
 *   - All native calls serialized on one I/O thread.
 *   - On open: drain any residual bytes the prior session left in
 *     the kernel RX buffer ("丢弃残留数据" in factory source).
 *   - A persistent background ReadThread pumps incoming bytes into
 *     an in-process queue. Subsequent `read` calls drain the queue
 *     (no native read race with close — which is what was SIGSEGV-ing
 *     before).
 *   - On close: signal ReadThread to exit, interrupt it, THEN tear
 *     down streams in order (input, output, port). Identical
 *     teardown order to factory's `closeSerialPort()`.
 *
 * Method channel: vmfs.kiosk/tty_serial
 *
 * Methods (same surface Dart already uses — no caller changes
 * required):
 *   listDevices()          -> List<String>  /dev/ttyS* + /dev/ttyUSB*
 *   open(path, baud)       -> bool          reused if already open
 *   write(data: ByteArray) -> bool          queues + flushes
 *   read(timeoutMs)        -> ByteArray     drains rx queue
 *   close()                -> bool          teardown + cleanup
 *   isOpen()               -> bool
 */
class TtySerialChannel(engine: FlutterEngine) {

    companion object {
        private const val TAG = "TtySerialChannel"
    }

    private val channel = MethodChannel(
        engine.dartExecutor.binaryMessenger,
        "vmfs.kiosk/tty_serial",
    )

    // ── Persistent singleton state ────────────────────────────────────
    // Reused across dispenses when port/baud match the current session.
    // Only re-created when an open() arrives with different params or
    // close() has explicitly been called.
    private var port: SerialPort? = null
    private var inputStream: InputStream? = null
    private var outputStream: OutputStream? = null
    private var currentPath: String? = null
    private var currentBaud: Int = 0

    // ── Background reader ─────────────────────────────────────────────
    // Pumps every byte that arrives on the TTY into rxQueue. Test
    // dispense + customer dispense pull from this queue rather than
    // touching the native fd, which removes the read-vs-close race
    // that was the SIGSEGV source.
    private var readThread: ReadThread? = null
    private val rxQueue = LinkedBlockingQueue<ByteArray>()

    // Serialize all native ops on a single thread so close() can never
    // run concurrent with an open() / write() / explicit read() on the
    // platform thread.
    private val ioThread = Executors.newSingleThreadExecutor { r ->
        Thread(r, "vmfs-tty-io").apply { isDaemon = true }
    }

    private val main = Handler(Looper.getMainLooper())

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "listDevices" -> result.success(listDevices())
                "isOpen" -> result.success(port != null)

                "open" -> {
                    val path = call.argument<String>("path")
                    val baud = call.argument<Int>("baud") ?: 9600
                    ioThread.execute {
                        try {
                            val ok = openSerialPort(path, baud)
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
                            val ok = sendSerialPort(data)
                            main.post { result.success(ok) }
                        } catch (e: Throwable) {
                            main.post { result.error("TTY_ERROR", e.message ?: "write failed", null) }
                        }
                    }
                }

                "read" -> {
                    val timeout = call.argument<Int>("timeoutMs") ?: 1000
                    ioThread.execute {
                        val bytes = drainQueue(timeout.toLong())
                        main.post { result.success(bytes) }
                    }
                }

                "close" -> {
                    ioThread.execute {
                        val ok = try { closeSerialPort() } catch (_: Throwable) { false }
                        main.post { result.success(ok) }
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    // ── /dev/ttyS* + /dev/ttyUSB* enumeration ─────────────────────────

    private fun listDevices(): List<String> {
        val dev = File("/dev")
        val files = dev.listFiles() ?: return emptyList()
        return files
            .filter { it.name.startsWith("ttyS") || it.name.startsWith("ttyUSB") }
            .map { it.absolutePath }
            .sorted()
    }

    // ── openSerialPort: reuse if possible, drain residual bytes ──────

    /**
     * Mirrors factory's `SerialPortUtils.openSerialPort()`. If the
     * requested path + baud match the current session AND the read
     * thread is still alive AND the port isn't null, return without
     * touching native code. Otherwise tear down the old port and
     * open a fresh one.
     */
    private fun openSerialPort(path: String?, baud: Int): Boolean {
        if (path.isNullOrEmpty()) throw IllegalArgumentException("path required")

        val sameSession = path == currentPath &&
            baud == currentBaud &&
            port != null &&
            readThread?.isStillReading() == true
        if (sameSession) {
            Log.d(TAG, "openSerialPort: reusing existing session $path@$baud")
            return true
        }

        // Tear down the previous session before opening a new one. We
        // do this through the same orderly close path the factory uses,
        // so it's safe even if the previous session was alive.
        closeSerialPortInternal()

        val file = File(path)
        if (!file.exists()) throw IOException("Device not found: $path")

        // Reyeah-supplied tablets ship rooted with /system/bin/su available
        // but with /dev/ttyS* nodes that aren't world-readable by default.
        // Mirror factory.apk's SerialPort constructor: if the app process
        // can't open the device, escalate to chmod 666 via su. If su isn't
        // available (non-rooted dev tablets), this best-effort fails
        // silently and the next SerialPort() throws a clean SecurityException.
        if (!file.canRead() || !file.canWrite()) {
            Log.d(TAG, "openSerialPort: $path is not r/w by app uid, attempting chmod 666 via su")
            try {
                val process = Runtime.getRuntime().exec("/system/bin/su")
                val cmd = "chmod 666 ${file.absolutePath}\nexit\n"
                process.outputStream.write(cmd.toByteArray())
                process.outputStream.flush()
                process.outputStream.close()
                process.waitFor()
                Log.d(TAG, "openSerialPort: chmod exited ${process.exitValue()}, " +
                    "canRead=${file.canRead()} canWrite=${file.canWrite()}")
            } catch (e: Throwable) {
                Log.w(TAG, "openSerialPort: chmod fallback failed (${e.message}); " +
                    "device probably isn't rooted")
            }
        }

        Log.d(TAG, "openSerialPort: opening $path@$baud")
        val sp = SerialPort(file, baud, 0)
        port = sp
        inputStream = sp.inputStream
        outputStream = sp.outputStream
        currentPath = path
        currentBaud = baud

        // Drain residual bytes (mirrors factory: "丢弃残留数据").
        drainResidualBytes()

        // Start the persistent reader.
        val ins = inputStream
        if (ins != null) {
            val t = ReadThread(ins, rxQueue)
            readThread = t
            t.start()
            Log.d(TAG, "openSerialPort: ReadThread started")
        }

        return true
    }

    private fun drainResidualBytes() {
        val ins = inputStream ?: return
        try {
            val available = ins.available()
            if (available > 0) {
                val drained = ByteArray(available)
                ins.read(drained)
                Log.d(TAG, "drained $available residual bytes on open")
            }
        } catch (_: IOException) {
            // Best-effort; nothing to do if the drain fails.
        }
    }

    // ── sendSerialPort: write + flush ────────────────────────────────

    private fun sendSerialPort(data: ByteArray?): Boolean {
        val out = outputStream ?: throw IllegalStateException("port not open")
        if (data == null) throw IllegalArgumentException("data required")
        out.write(data)
        out.flush()
        return true
    }

    // ── Reading: drain the queue the background thread populates ─────

    /**
     * Drain all bytes that the ReadThread has buffered, waiting up to
     * [timeoutMs] for the first chunk to arrive. After the first chunk,
     * give a short quiet-window for additional bytes to land (the
     * board can split a frame across multiple OS reads), then return.
     *
     * Crucially this NEVER touches the native fd directly — we just
     * consume from a thread-safe queue. That removes the close-vs-read
     * race that was the SIGSEGV source.
     */
    private fun drainQueue(timeoutMs: Long): ByteArray {
        val firstChunk = rxQueue.poll(timeoutMs, java.util.concurrent.TimeUnit.MILLISECONDS)
            ?: return byteArrayOf()

        // Got something — give the rest of the frame a short window to
        // arrive (factory observed up to ~80 ms of intra-frame silence
        // before a frame is considered complete).
        val acc = ArrayList<ByteArray>()
        acc.add(firstChunk)
        var more = rxQueue.poll(80, java.util.concurrent.TimeUnit.MILLISECONDS)
        while (more != null) {
            acc.add(more)
            more = rxQueue.poll(80, java.util.concurrent.TimeUnit.MILLISECONDS)
        }

        val totalLen = acc.sumOf { it.size }
        val out = ByteArray(totalLen)
        var off = 0
        for (chunk in acc) {
            System.arraycopy(chunk, 0, out, off, chunk.size)
            off += chunk.size
        }
        return out
    }

    // ── closeSerialPort: factory's exact teardown order ──────────────

    /**
     * Mirrors factory's `closeSerialPort()`:
     *   1. signal ReadThread to stop via volatile flag
     *   2. interrupt it (wakes any blocking read / sleep)
     *   3. close input stream
     *   4. close output stream
     *   5. close the SerialPort itself (which closes the JNI fd)
     *
     * Tearing the reader down FIRST is the key — the previous SIGSEGV
     * happened because close() yanked the fd while a background reader
     * was mid-syscall. With the reader stopped, close is safe.
     */
    private fun closeSerialPort(): Boolean = closeSerialPortInternal()

    private fun closeSerialPortInternal(): Boolean {
        Log.d(TAG, "closeSerialPort: tearing down")
        try {
            readThread?.let {
                it.requestStop()
                it.interrupt()
                // Brief join — give the reader a chance to exit cleanly
                // before we yank the fd. The factory doesn't join but
                // their read thread checks the flag every chunk; ours
                // does the same. 200 ms is plenty.
                try { it.join(200) } catch (_: InterruptedException) {}
            }
            readThread = null

            try { inputStream?.close() } catch (_: Throwable) {}
            try { outputStream?.close() } catch (_: Throwable) {}
            try { port?.close() } catch (_: Throwable) {}

            inputStream = null
            outputStream = null
            port = null
            currentPath = null
            currentBaud = 0

            // Clear any queued bytes so the next session starts clean.
            rxQueue.clear()
            return true
        } catch (_: Throwable) {
            return false
        }
    }
}

/**
 * Persistent reader, mirrors factory's `SerialPortUtils$ReadThread`.
 * Blocks on `InputStream.read()`-style polling, copies anything it
 * receives into the shared rxQueue, and exits cleanly when its stop
 * flag is set OR the thread is interrupted.
 */
private class ReadThread(
    private val stream: InputStream,
    private val queue: LinkedBlockingQueue<ByteArray>,
) : Thread("vmfs-tty-read") {

    private val stopRequested = AtomicBoolean(false)

    init {
        isDaemon = true
    }

    fun requestStop() {
        stopRequested.set(true)
    }

    fun isStillReading(): Boolean =
        isAlive && !stopRequested.get() && !isInterrupted

    override fun run() {
        val buf = ByteArray(1024)
        while (!stopRequested.get() && !isInterrupted) {
            try {
                val available = try { stream.available() } catch (_: IOException) { -1 }
                if (available < 0) break
                if (available == 0) {
                    try { sleep(15) } catch (_: InterruptedException) { break }
                    continue
                }
                val n = try {
                    stream.read(buf, 0, minOf(buf.size, available))
                } catch (_: IOException) {
                    if (stopRequested.get()) break else continue
                }
                if (n > 0) {
                    queue.offer(buf.copyOf(n))
                }
            } catch (_: InterruptedException) {
                break
            } catch (e: Throwable) {
                Log.e("TtySerialChannel", "ReadThread error: ${e.message}")
                if (stopRequested.get()) break
            }
        }
    }
}
