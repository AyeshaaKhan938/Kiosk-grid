package com.vmfsusa.kiosk

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Log
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Triggers the system PackageInstaller for a downloaded APK.
 *
 * Method channel: vmfs.kiosk/apk_installer
 *
 * Methods:
 *   canRequestInstalls() → bool
 *     Whether the current package is allowed to launch installs without
 *     prompting the user every time. False on first run.
 *   openInstallSettings() → bool
 *     Opens the "Install unknown apps" settings page so the admin can
 *     grant permission. Returns true if the intent was launched.
 *   installApk(path) → bool
 *     Hands the APK at [path] to PackageInstaller. On the very first call
 *     Android asks the user "Replace this app?" — subsequent updates of
 *     the same package install silently after the initial Allow.
 */
class ApkInstallerChannel(private val context: Context, engine: FlutterEngine) {

    companion object {
        private const val TAG = "ApkInstallerChannel"
    }

    private val channel = MethodChannel(
        engine.dartExecutor.binaryMessenger,
        "vmfs.kiosk/apk_installer",
    )

    init {
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "canRequestInstalls" -> result.success(canRequestInstalls())
                    "openInstallSettings" -> result.success(openInstallSettings())
                    "installApk" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrBlank()) {
                            result.error("INVALID_ARGS", "path required", null)
                        } else {
                            result.success(installApk(path))
                        }
                    }
                    "installApkSilent" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrBlank()) {
                            result.error("INVALID_ARGS", "path required", null)
                        } else {
                            result.success(installApkSilent(path))
                        }
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Throwable) {
                result.error(
                    "INSTALL_ERROR",
                    e.javaClass.simpleName + ": " + (e.message ?: ""),
                    null,
                )
            }
        }
    }

    private fun canRequestInstalls(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.packageManager.canRequestPackageInstalls()
        } else {
            true
        }
    }

    private fun openInstallSettings(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val intent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES)
                .setData(Uri.parse("package:" + context.packageName))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(intent)
            true
        } else {
            false
        }
    }

    private fun installApk(path: String): Boolean {
        val file = File(path)
        if (!file.exists()) return false

        val uri: Uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            FileProvider.getUriForFile(
                context,
                context.packageName + ".fileprovider",
                file,
            )
        } else {
            Uri.fromFile(file)
        }

        val intent = Intent(Intent.ACTION_VIEW)
            .setDataAndType(uri, "application/vnd.android.package-archive")
            .addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_GRANT_READ_URI_PERMISSION,
            )
        context.startActivity(intent)
        return true
    }

    /**
     * Silent self-update via `pm install -r` running under root.
     *
     * Reyeah ships the kiosk tablets rooted with `/system/bin/su` available,
     * which is exactly the trust level pm needs to install an APK without
     * showing the system "Replace this app?" confirmation. The factory APK
     * uses the same trick — it's why their kiosks accept OTA updates with
     * zero operator interaction.
     *
     * Flow:
     *   1. exec `/system/bin/su -c "pm install -r <path>"`
     *   2. pm installs the new APK over the old one in place. Because we
     *      sign every release with the same Codemagic keystore the OS
     *      treats it as the same package — settings, prefs, the kiosk
     *      PIN, and SharedPreferences all survive.
     *   3. pm signals the package manager to kill our process; the OS
     *      then re-resolves the HOME-launcher intent (which is us) and
     *      relaunches MainActivity from the new APK. No `am start`
     *      needed — being the system's HOME launcher handles re-entry
     *      for free.
     *
     * Returns true if `pm install -r` exits 0 before our process is killed.
     * If su isn't granted to our UID (Magisk policy missing) or pm fails
     * for any reason, returns false and the Dart caller falls back to the
     * dialog-driven [installApk] path.
     */
    private fun installApkSilent(path: String): Boolean {
        val file = File(path)
        if (!file.exists()) {
            Log.w(TAG, "installApkSilent: file does not exist: $path")
            return false
        }

        return try {
            Log.i(TAG, "installApkSilent: exec'ing su pm install -r $path")
            val process = Runtime.getRuntime().exec(
                arrayOf("/system/bin/su", "-c", "pm install -r \"$path\""),
            )
            val exit = process.waitFor()
            Log.i(TAG, "installApkSilent: pm install -r returned exit=$exit")
            exit == 0
        } catch (e: Throwable) {
            Log.e(TAG, "installApkSilent: ${e.javaClass.simpleName}: ${e.message}")
            false
        }
    }
}
