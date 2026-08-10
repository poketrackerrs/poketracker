package com.baygroupusa.poketracker

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val installerChannel = "poketracker/installer"
    private val emulatorChannel = "poketracker/emulators"
    private val storageChannel = "poketracker/storage"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, installerChannel)
            .setMethodCallHandler { call, result ->
                if (call.method == "installApk") {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.error("NO_PATH", "No APK path provided", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val file = File(path)
                        val uri = FileProvider.getUriForFile(
                            this, "$packageName.fileprovider", file
                        )
                        val intent = Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(uri, "application/vnd.android.package-archive")
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("INSTALL_FAILED", e.message, null)
                    }
                } else {
                    result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, emulatorChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "installedPackages" -> {
                        val candidates = call.argument<List<String>>("packages") ?: emptyList()
                        val installed = candidates.filter { isInstalled(it) }
                        result.success(installed)
                    }
                    "launchRom" -> {
                        val pkg = call.argument<String>("package")
                        val path = call.argument<String>("path")
                        result.success(launchRom(pkg, path))
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, storageChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "hasAllFilesAccess" -> result.success(hasAllFilesAccess())
                    "requestAllFilesAccess" -> result.success(requestAllFilesAccess())
                    "externalStorageDir" ->
                        result.success(Environment.getExternalStorageDirectory().absolutePath)
                    else -> result.notImplemented()
                }
            }
    }

    /// True if the app may read/write shared storage with plain file paths.
    private fun hasAllFilesAccess(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Environment.isExternalStorageManager()
        } else {
            // Pre-Android 11: covered by the legacy WRITE permission at install.
            true
        }
    }

    /// Opens the system "All files access" screen for this app. Returns whether
    /// access is already granted (so Dart can skip the trip to Settings).
    private fun requestAllFilesAccess(): Boolean {
        if (hasAllFilesAccess()) return true
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            try {
                val intent = Intent(
                    Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                    Uri.parse("package:$packageName")
                ).apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) }
                startActivity(intent)
            } catch (_: Exception) {
                // Fall back to the general list if the per-app screen is missing.
                try {
                    val intent = Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION)
                        .apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) }
                    startActivity(intent)
                } catch (_: Exception) {}
            }
        }
        return false
    }

    private fun isInstalled(pkg: String): Boolean {
        return try {
            packageManager.getPackageInfo(pkg, 0)
            true
        } catch (e: Exception) {
            false
        }
    }

    /// Opens a ROM in the given emulator app. Returns true only if the emulator
    /// accepted the ROM; if it can't, opens the emulator so the user can load
    /// the ROM manually and returns false.
    private fun launchRom(pkg: String?, path: String?): Boolean {
        if (pkg == null) return false
        // 1) Try to hand the ROM straight to the emulator.
        if (path != null) {
            try {
                val file = File(path)
                if (file.exists()) {
                    val uri = FileProvider.getUriForFile(
                        this, "$packageName.fileprovider", file
                    )
                    for (mime in listOf("application/octet-stream", "*/*")) {
                        val view = Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(uri, mime)
                            setPackage(pkg)
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        if (view.resolveActivity(packageManager) != null) {
                            try {
                                startActivity(view)
                                return true
                            } catch (_: Exception) {}
                        }
                    }
                }
            } catch (_: Exception) {}
        }
        // 2) Couldn't hand it off — open the emulator so the ROM can be loaded.
        try {
            val launch = packageManager.getLaunchIntentForPackage(pkg)
            if (launch != null) {
                launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(launch)
            }
        } catch (_: Exception) {}
        return false
    }
}
