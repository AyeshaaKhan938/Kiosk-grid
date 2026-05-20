package com.vmfsusa.kiosk

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
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
}
