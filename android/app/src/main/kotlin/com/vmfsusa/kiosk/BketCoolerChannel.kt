package com.vmfsusa.kiosk

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.bket.bketCamera.BketCamCallback
import com.bket.bketCamera.BketCameraControlAdapter
import com.bket.bketCamera.BketCameraControlIface
import com.bket.bketlock.BketLockAdapter
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference

/**
 * Flutter bridge for the SMG-S400 / BKX16 AI smart cooler hardware.
 *
 * Unlike slot-motor vending (UART / TCN / AFEN), this path:
 *   1. Starts dual-camera recording (host + sub)
 *   2. Opens the electromagnetic door lock
 *   3. Waits for the customer to close the door
 *   4. Stops recording and returns video file paths for cloud AI review
 *
 * Method channel: vmfs.kiosk/bket_cooler
 */
class BketCoolerChannel(
    private val appContext: Context,
    engine: FlutterEngine,
) {
    companion object {
        private const val TAG = "BketCoolerChannel"
        private const val CHANNEL = "vmfs.kiosk/bket_cooler"
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private val channel = MethodChannel(
        engine.dartExecutor.binaryMessenger,
        CHANNEL,
    )

    private var lockAdapter: BketLockAdapter? = null
    private var cameraAdapter: BketCameraControlAdapter? = null

    @Volatile
    private var doorOpen = false

    @Volatile
    private var lockOpen = false

    @Volatile
    private var hostRecording = false

    @Volatile
    private var subRecording = false

    private val hostVideoPath = AtomicReference<String?>(null)
    private val subVideoPath = AtomicReference<String?>(null)

    private val doorStatusCallback =
        BketLockAdapter.LockDoorStatusIface { lock, door, _, _ ->
            lockOpen = lock == 1
            doorOpen = door == 1
            Log.d(TAG, "door callback lock=$lock door=$door")
        }

    private val cameraCallback = object : BketCameraControlIface {
        override fun onInfoHostVideoFile(fileName: String?, isEnd: Boolean) {
            if (!fileName.isNullOrBlank() && isEnd) {
                hostVideoPath.set(fileName)
                Log.i(TAG, "host video ready: $fileName")
            }
        }

        override fun onInfoSubVideoFile(fileName: String?, isEnd: Boolean) {
            if (!fileName.isNullOrBlank() && isEnd) {
                subVideoPath.set(fileName)
                Log.i(TAG, "sub video ready: $fileName")
            }
        }

        override fun onInfoHostTakePicFile(fileName: String?) {
            Log.d(TAG, "host pic: $fileName")
        }

        override fun onInfoSubTakePicFile(fileName: String?) {
            Log.d(TAG, "sub pic: $fileName")
        }

        override fun onInfoHostCameraStatus(status: Int) {
            Log.d(TAG, "host camera status: $status")
        }

        override fun onInfoSubCameraStatus(status: Int) {
            Log.d(TAG, "sub camera status: $status")
        }

        override fun onInfoCameraInitial(result: Int) {
            Log.d(TAG, "camera initial: $result")
        }
    }

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "initialize" -> runAsync(result) { initialize() }
                "getStatus" -> runAsync(result) { getStatusMap() }
                "startShoppingSession" -> {
                    val sessionId = call.argument<String>("sessionId") ?: "session"
                    val timeoutSec = call.argument<Int>("timeoutSec") ?: 300
                    runAsync(result) { startShoppingSession(sessionId, timeoutSec) }
                }
                "testUnlock" -> runAsync(result) { testUnlock() }
                "release" -> runAsync(result) { release(); emptyMap<String, Any?>() }
                else -> result.notImplemented()
            }
        }
    }

    private fun runAsync(result: MethodChannel.Result, block: () -> Map<String, Any?>) {
        Thread {
            try {
                val payload = block()
                mainHandler.post { result.success(payload) }
            } catch (t: Throwable) {
                Log.e(TAG, "method failed", t)
                mainHandler.post {
                    result.error("BKET_ERROR", t.message, t.toString())
                }
            }
        }.start()
    }

    private fun initialize(): Map<String, Any?> {
        if (lockAdapter == null) {
            lockAdapter = BketLockAdapter.getInstance(appContext)
            lockAdapter?.addLock1StatusListenerCallback(doorStatusCallback)
        }
        if (cameraAdapter == null) {
            cameraAdapter = BketCameraControlAdapter.getInstance(cameraCallback, appContext)
        }
        return getStatusMap()
    }

    private fun getStatusMap(): Map<String, Any?> {
        val cam = cameraAdapter
        return mapOf(
            "initialized" to (lockAdapter != null && cam != null),
            "doorOpen" to doorOpen,
            "lockOpen" to lockOpen,
            "hostCameraOnline" to (cam?.bkcam_hostCameraIsOnline() ?: false),
            "subCameraOnline" to (cam?.bkcam_subCameraIsOnline() ?: false),
            "hostRecording" to hostRecording,
            "subRecording" to subRecording,
            "cameraSdkVersion" to cam?.bkcam_bketGetSdkVersion(),
        )
    }

    /** record → unlock → wait for door close → stop record. */
    private fun startShoppingSession(
        sessionId: String,
        timeoutSec: Int,
    ): Map<String, Any?> {
        initialize()

        val lock = lockAdapter ?: throw IllegalStateException("Lock adapter not ready")
        val cam = cameraAdapter ?: throw IllegalStateException("Camera adapter not ready")

        val dir = File(appContext.getExternalFilesDir("bket_sessions"), sessionId)
        if (!dir.exists()) dir.mkdirs()

        val hostFile = File(dir, "${sessionId}_host.mp4").absolutePath
        val subFile = File(dir, "${sessionId}_sub.mp4").absolutePath
        hostVideoPath.set(null)
        subVideoPath.set(null)

        waitForCameraOpen(cam)
        val hostRec = cam.bkcam_startHostRecord(hostFile)
        val subRec = cam.bkcam_startSubRecord(subFile)
        hostRecording = hostRec == 1
        subRecording = subRec == 1
        if (!hostRecording && !subRecording) {
            throw IllegalStateException("Failed to start camera recording")
        }

        lock.openLock1()
        lockOpen = true
        doorOpen = true

        val deadline = System.currentTimeMillis() + timeoutSec * 1000L
        var sawDoorOpen = false
        while (System.currentTimeMillis() < deadline) {
            pollDoorStatus(lock)
            if (doorOpen) {
                sawDoorOpen = true
            } else if (sawDoorOpen) {
                break
            }
            Thread.sleep(400)
        }

        if (doorOpen) {
            cam.bkcam_stopHostRecord()
            cam.bkcam_stopSubRecord()
            hostRecording = false
            subRecording = false
            throw IllegalStateException("Timed out waiting for door to close")
        }

        cam.bkcam_stopHostRecord()
        cam.bkcam_stopSubRecord()
        hostRecording = false
        subRecording = false
        waitForVideoFiles(15_000)

        try {
            lock.closeLock1()
        } catch (_: Throwable) {
        }
        lockOpen = false

        return mapOf(
            "success" to true,
            "sessionId" to sessionId,
            "hostVideoPath" to (hostVideoPath.get() ?: hostFile),
            "subVideoPath" to (subVideoPath.get() ?: subFile),
            "doorClosed" to true,
        )
    }

    private fun testUnlock(): Map<String, Any?> {
        initialize()
        val lock = lockAdapter ?: throw IllegalStateException("Lock adapter not ready")
        lock.openLock1()
        lockOpen = true
        Thread.sleep(500)
        pollDoorStatus(lock)
        return mapOf(
            "success" to true,
            "lockOpen" to lockOpen,
            "doorOpen" to doorOpen,
        )
    }

    private fun release() {
        try {
            cameraAdapter?.bkcam_stopHostRecord()
            cameraAdapter?.bkcam_stopSubRecord()
            cameraAdapter?.bkcam_onDestroy()
        } catch (_: Throwable) {
        }
        try {
            lockAdapter?.closeLock1()
        } catch (_: Throwable) {
        }
        cameraAdapter = null
        lockAdapter = null
        hostRecording = false
        subRecording = false
    }

    private fun waitForCameraOpen(cam: BketCameraControlAdapter) {
        val hostStatus = AtomicInteger(-2)
        val subStatus = AtomicInteger(-2)
        val latch = CountDownLatch(2)

        cam.bkcam_openHostCamera(object : BketCamCallback {
            override fun onSuccess(result: Int) {
                hostStatus.set(result)
                latch.countDown()
            }

            override fun onFailure(result: Int, message: String?) {
                hostStatus.set(-1)
                Log.e(TAG, "host camera open failed: $result $message")
                latch.countDown()
            }
        })
        cam.bkcam_openSubCamera(object : BketCamCallback {
            override fun onSuccess(result: Int) {
                subStatus.set(result)
                latch.countDown()
            }

            override fun onFailure(result: Int, message: String?) {
                subStatus.set(-1)
                Log.e(TAG, "sub camera open failed: $result $message")
                latch.countDown()
            }
        })

        if (!latch.await(20, TimeUnit.SECONDS)) {
            throw IllegalStateException("Camera open timed out")
        }
        if (hostStatus.get() < 0 || subStatus.get() < 0) {
            cam.bkcam_reset()
            throw IllegalStateException(
                "Camera open failed (host=${hostStatus.get()}, sub=${subStatus.get()})",
            )
        }
    }

    private fun pollDoorStatus(lock: BketLockAdapter) {
        try {
            val status = lock.getDoorAndLockStatus(0) ?: return
            if (status.size >= 2) {
                lockOpen = status[0] == 1
                doorOpen = status[1] == 1
            }
        } catch (_: Throwable) {
            // Callbacks may still update doorOpen.
        }
    }

    private fun waitForVideoFiles(timeoutMs: Long) {
        val deadline = System.currentTimeMillis() + timeoutMs
        while (System.currentTimeMillis() < deadline) {
            if (hostVideoPath.get() != null || subVideoPath.get() != null) return
            Thread.sleep(200)
        }
    }
}
