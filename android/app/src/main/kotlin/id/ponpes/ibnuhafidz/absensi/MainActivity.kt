package id.ponpes.ibnuhafidz.absensi

import android.app.Activity
import android.app.KeyguardManager
import android.content.Intent
import android.hardware.biometrics.BiometricManager
import android.hardware.biometrics.BiometricPrompt
import android.os.Build
import android.os.CancellationSignal
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var mandatoryUpdate = false
    private var updateInstaller: AppUpdateInstaller? = null
    override fun popSystemNavigator(): Boolean = if (mandatoryUpdate) true else super.popSystemNavigator()
    private var pending: MethodChannel.Result? = null
    private var cancellation: CancellationSignal? = null
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        updateInstaller = AppUpdateInstaller(this)
        updateInstaller!!.register(flutterEngine) { mandatoryUpdate = it }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ibnu_hafidz/device_security").setMethodCallHandler { call, result ->
            if (call.method != "authenticate") { result.notImplemented(); return@setMethodCallHandler }
            if (pending != null) { result.success(false); return@setMethodCallHandler }
            val keyguard = getSystemService(KEYGUARD_SERVICE) as KeyguardManager
            if (!keyguard.isDeviceSecure) { result.error("not_secure", "Aktifkan PIN atau biometrik perangkat terlebih dahulu", null); return@setMethodCallHandler }
            pending = result
            try {
                if (Build.VERSION.SDK_INT >= 29) {
                    val builder = BiometricPrompt.Builder(this).setTitle("Buka Ibnu Hafidz").setSubtitle("Verifikasi pemilik perangkat")
                    if (Build.VERSION.SDK_INT >= 30) builder.setAllowedAuthenticators(BiometricManager.Authenticators.BIOMETRIC_STRONG or BiometricManager.Authenticators.DEVICE_CREDENTIAL)
                    else { @Suppress("DEPRECATION") builder.setDeviceCredentialAllowed(true) }
                    cancellation = CancellationSignal()
                    builder.build().authenticate(cancellation!!, mainExecutor, object : BiometricPrompt.AuthenticationCallback() {
                        override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) { finishAuth(true) }
                        override fun onAuthenticationError(code: Int, message: CharSequence) { finishAuth(false) }
                    })
                } else {
                    @Suppress("DEPRECATION") val intent = keyguard.createConfirmDeviceCredentialIntent("Buka Ibnu Hafidz", "Masukkan PIN/pola perangkat")
                    if (intent == null) finishAuth(false) else { @Suppress("DEPRECATION") startActivityForResult(intent, 7291) }
                }
            } catch (_: Exception) { finishAuth(false) }
        }
    }
    private fun finishAuth(success: Boolean) { pending?.success(success); pending = null; cancellation = null }
    @Deprecated("Deprecated in Android")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == 7291) finishAuth(resultCode == Activity.RESULT_OK)
    }
    override fun onDestroy() { updateInstaller?.close(); cancellation?.cancel(); finishAuth(false); super.onDestroy() }
}
