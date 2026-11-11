package id.ponpes.ibnuhafidz.absensi

import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.Executors

class AppUpdateInstaller(private val activity: FlutterActivity) {
    private val worker = Executors.newSingleThreadExecutor()
    fun close() { worker.shutdownNow() }
    @Suppress("DEPRECATION") private fun code(info: PackageInfo): Long = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()
    @Suppress("DEPRECATION") private fun signatures(info: PackageInfo): Set<String> {
        val certs = if (Build.VERSION.SDK_INT >= 28) info.signingInfo?.apkContentsSigners else info.signatures
        return certs?.map { certificate -> MessageDigest.getInstance("SHA-256").digest(certificate.toByteArray()).joinToString("") { "%02x".format(it.toInt() and 255) } }?.toSet() ?: emptySet()
    }
    @Suppress("DEPRECATION") fun register(engine: FlutterEngine, required: (Boolean) -> Unit) {
        MethodChannel(engine.dartExecutor.binaryMessenger, "ibnu_hafidz/app_updates").setMethodCallHandler { call, result ->
            when (call.method) {
                "required" -> { required(call.arguments == true); result.success(null) }
                "installed" -> { val info = activity.packageManager.getPackageInfo(activity.packageName, 0); result.success(mapOf("version" to info.versionName, "code" to code(info), "package" to info.packageName)) }
                "install" -> {
                    val path = call.argument<String>("path")
                    val expected = call.argument<Number>("version_code")?.toLong() ?: 0
                    val digest = call.argument<String>("sha256") ?: ""
                    if (path == null) { result.error("invalid", "APK tidak tersedia", null); return@setMethodCallHandler }
                    worker.execute {
                        try {
                            val root = File(activity.cacheDir, "updates").canonicalFile
                            val file = File(path).canonicalFile
                            if (file.parentFile != root || !file.isFile || !file.name.endsWith(".apk")) throw IllegalArgumentException()
                            val actual = file.inputStream().use { stream -> val hash = MessageDigest.getInstance("SHA-256"); val buffer = ByteArray(65536); var count = stream.read(buffer); while (count >= 0) { if (count > 0) hash.update(buffer, 0, count); count = stream.read(buffer) }; hash.digest().joinToString("") { "%02x".format(it.toInt() and 255) } }
                            if (actual != digest) throw IllegalArgumentException()
                            val flags = if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES else PackageManager.GET_SIGNATURES
                            val current = activity.packageManager.getPackageInfo(activity.packageName, flags)
                            val archive = activity.packageManager.getPackageArchiveInfo(file.path, flags) ?: throw IllegalArgumentException()
                            if (archive.packageName != current.packageName || code(archive) != expected || code(archive) <= code(current) || signatures(archive).isEmpty() || signatures(archive) != signatures(current)) throw IllegalArgumentException()
                            activity.runOnUiThread {
                                try {
                                    if (Build.VERSION.SDK_INT >= 26 && !activity.packageManager.canRequestPackageInstalls()) {
                                        activity.startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:" + activity.packageName)))
                                        result.success("permission_required")
                                    } else {
                                        val uri = FileProvider.getUriForFile(activity, activity.packageName + ".app_updates", file)
                                        val intent = Intent(Intent.ACTION_VIEW).setDataAndType(uri, "application/vnd.android.package-archive").addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                        activity.startActivity(intent)
                                        result.success("opened")
                                    }
                                } catch (_: Exception) { result.error("installer", "Installer Android tidak dapat dibuka", null) }
                            }
                        } catch (_: Exception) { activity.runOnUiThread { result.error("invalid_apk", "Versi, integritas atau tanda tangan APK tidak cocok", null) } }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
