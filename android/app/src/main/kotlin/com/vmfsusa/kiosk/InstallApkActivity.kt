package com.vmfsusa.kiosk

import android.app.Activity
import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.util.Log
import androidx.core.content.FileProvider
import java.io.File

/**
 * Handles APK install intents outside [MainActivity].
 *
 * OEM vending launchers (e.g. com.yy.chuanyisoft) crash in onActivityResult when
 * the system package installer returns — setVisibility on a null View. VMFS routes
 * installs here so [MainActivity] / Flutter never receive that result.
 */
class InstallApkActivity : Activity() {

    private var handedOffToInstaller = false
    private var resumeAfterInstaller = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        if (savedInstanceState != null) {
            handedOffToInstaller = savedInstanceState.getBoolean(KEY_HANDED_OFF, false)
            return
        }

        val path = intent.getStringExtra(EXTRA_APK_PATH)
        if (path.isNullOrBlank()) {
            Log.w(TAG, "No APK path — finishing")
            finish()
            return
        }

        releaseLockTaskIfPinned()
        handedOffToInstaller = launchPackageInstaller(path)
        if (!handedOffToInstaller) {
            finish()
        }
    }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        outState.putBoolean(KEY_HANDED_OFF, handedOffToInstaller)
    }

    override fun onResume() {
        super.onResume()
        if (handedOffToInstaller && resumeAfterInstaller) {
            finish()
            return
        }
        if (handedOffToInstaller) {
            resumeAfterInstaller = true
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        // Do not call super — some OEM bases touch null views here.
        finish()
    }

    private fun releaseLockTaskIfPinned() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return
        }
        try {
            val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            if (am.lockTaskModeState != ActivityManager.LOCK_TASK_MODE_NONE) {
                stopLockTask()
            }
        } catch (t: Throwable) {
            Log.w(TAG, "stopLockTask: ${t.message}")
        }
    }

    private fun launchPackageInstaller(path: String): Boolean {
        val file = File(path)
        if (!file.exists()) {
            Log.w(TAG, "APK missing: $path")
            return false
        }

        return try {
            val uri: Uri =
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    FileProvider.getUriForFile(
                        this,
                        packageName + ".fileprovider",
                        file,
                    )
                } else {
                    Uri.fromFile(file)
                }

            val installIntent =
                Intent(Intent.ACTION_VIEW)
                    .setDataAndType(uri, "application/vnd.android.package-archive")
                    .addFlags(
                        Intent.FLAG_GRANT_READ_URI_PERMISSION or
                            Intent.FLAG_ACTIVITY_NEW_TASK,
                    )

            startActivity(installIntent)
            true
        } catch (t: Throwable) {
            Log.e(TAG, "launchPackageInstaller failed", t)
            false
        }
    }

    companion object {
        private const val TAG = "InstallApkActivity"
        const val EXTRA_APK_PATH = "apk_path"
        private const val KEY_HANDED_OFF = "handed_off_to_installer"
    }
}
