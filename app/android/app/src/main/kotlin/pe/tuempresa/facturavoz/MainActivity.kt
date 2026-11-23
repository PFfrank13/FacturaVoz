package pe.tuempresa.facturavoz

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // In-app updates: the APK is downloaded and verified (SHA-256) in Dart;
        // Android still asks the user to confirm every installation.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "facturavoz/updater")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "versionCode" -> {
                        val info = packageManager.getPackageInfo(packageName, 0)
                        val code = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode
                        else @Suppress("DEPRECATION") info.versionCode.toLong()
                        result.success(code)
                    }
                    "canInstall" -> result.success(
                        Build.VERSION.SDK_INT < 26 || packageManager.canRequestPackageInstalls()
                    )
                    "openInstallSettings" -> {
                        if (Build.VERSION.SDK_INT >= 26) {
                            startActivity(
                                Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                    Uri.parse("package:$packageName"))
                            )
                        }
                        result.success(null)
                    }
                    "install" -> {
                        val path = call.argument<String>("path")
                        val file = path?.let { File(it) }
                        val updates = File(cacheDir, "updates").canonicalPath
                        if (file == null || !file.isFile || !file.canonicalPath.startsWith(updates)) {
                            result.error("bad_path", "Archivo de actualización no válido", null)
                        } else {
                            val uri = FileProvider.getUriForFile(this, "$packageName.updates", file)
                            startActivity(Intent(Intent.ACTION_VIEW).apply {
                                setDataAndType(uri, "application/vnd.android.package-archive")
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
                            })
                            result.success(null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
