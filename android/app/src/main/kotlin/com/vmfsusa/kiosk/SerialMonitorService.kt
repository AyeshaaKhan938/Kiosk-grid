package com.vmfsusa.kiosk

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat

/**
 * Foreground service that keeps the kiosk's process priority high
 * so Android's low-memory killer is unlikely to ever reap us.
 *
 * Mirrors factory.apk's foreground service slot (FOREGROUND_SERVICE
 * permission + persistent notification). The actual board polling /
 * dispense logic stays in the activity — this service is the priority
 * anchor only.
 *
 * Started from MainActivity.onCreate. Not bound to anything; runs
 * until the activity stops it or the process is killed (then the
 * BootReceiver brings everything back on next boot).
 *
 * The persistent notification is hidden behind immersive mode in the
 * kiosk anyway — customers never see it.
 */
class SerialMonitorService : Service() {

    companion object {
        private const val TAG = "SerialMonitorService"
        private const val CHANNEL_ID = "vmfs_serial_monitor"
        private const val CHANNEL_NAME = "VMFS Kiosk background"
        private const val NOTIFICATION_ID = 0x4D46 // "MF"

        fun start(context: Context) {
            val intent = Intent(context, SerialMonitorService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, SerialMonitorService::class.java))
        }
    }

    override fun onCreate() {
        super.onCreate()
        Log.i(TAG, "SerialMonitorService onCreate")
        ensureNotificationChannel()
        startForeground(NOTIFICATION_ID, buildNotification())
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Restart if killed (kiosk-friendly behavior).
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        Log.i(TAG, "SerialMonitorService onDestroy")
        super.onDestroy()
    }

    private fun ensureNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val mgr = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val existing = mgr.getNotificationChannel(CHANNEL_ID)
        if (existing != null) return
        val channel = NotificationChannel(
            CHANNEL_ID, CHANNEL_NAME, NotificationManager.IMPORTANCE_MIN,
        ).apply {
            description = "Keeps the kiosk app running in the background"
            setShowBadge(false)
            setSound(null, null)
            enableVibration(false)
            enableLights(false)
        }
        mgr.createNotificationChannel(channel)
    }

    private fun buildNotification(): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_notify_sync)
            .setContentTitle("VMFS USA Kiosk")
            .setContentText("Running")
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setOngoing(true)
            .setShowWhen(false)
            .setOnlyAlertOnce(true)
            .build()
    }
}
