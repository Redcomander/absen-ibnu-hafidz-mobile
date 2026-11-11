package id.ponpes.ibnuhafidz.schedulealerts

import android.Manifest
import android.app.*
import android.content.*
import android.content.pm.PackageManager
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.*
import android.provider.Settings
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.*
import java.util.concurrent.Executors

class ScheduleAlertsPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware,
    PluginRegistry.RequestPermissionsResultListener, PluginRegistry.NewIntentListener {
    private lateinit var context: Context
    private lateinit var channel: MethodChannel
    private var activity: Activity? = null
    private var binding: ActivityPluginBinding? = null
    private var permissionResult: MethodChannel.Result? = null
    private var opened = false

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "ibnu_hafidz/schedule_alerts")
        channel.setMethodCallHandler(this)
    }
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }
    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        this.binding = binding
        activity = binding.activity
        binding.addRequestPermissionsResultListener(this)
        binding.addOnNewIntentListener(this)
        opened = binding.activity.intent?.getBooleanExtra("ibnu_open_schedule", false) == true
    }
    override fun onDetachedFromActivity() {
        binding?.removeRequestPermissionsResultListener(this)
        binding?.removeOnNewIntentListener(this)
        binding = null
        activity = null
        permissionResult?.success(false)
        permissionResult = null
    }
    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)
    override fun onNewIntent(intent: Intent): Boolean {
        if (!intent.getBooleanExtra("ibnu_open_schedule", false)) return false
        activity?.intent = intent
        channel.invokeMethod("openSchedule", null)
        return true
    }
    override fun onRequestPermissionsResult(code: Int, permissions: Array<out String>, results: IntArray): Boolean {
        if (code != 7462) return false
        permissionResult?.success(Alerts.allowed(context))
        permissionResult = null
        return true
    }
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "consumeOpen" -> { result.success(opened); opened = false; activity?.intent?.removeExtra("ibnu_open_schedule") }
            "status" -> result.success(mapOf("allowed" to Alerts.allowed(context), "exact" to Alerts.exact(context), "supported" to true))
            "permission" -> {
                val host = activity
                val prefs = Alerts.prefs(context)
                val automatic = call.argument<Boolean>("automatic") == true
                if (host == null || Alerts.allowed(context) || Build.VERSION.SDK_INT < 33 ||
                    (automatic && prefs.getBoolean("asked", false)) || permissionResult != null) {
                    result.success(Alerts.allowed(context)); return
                }
                prefs.edit().putBoolean("asked", true).apply()
                permissionResult = result
                host.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 7462)
            }
            "notificationSettings", "exactSettings" -> {
                val host = activity
                if (host == null) { result.success(false); return }
                val intent = if (call.method == "exactSettings" && Build.VERSION.SDK_INT >= 31)
                    Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, Uri.parse("package:${context.packageName}"))
                else Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
                host.startActivity(intent)
                result.success(true)
            }
            "bind", "replace", "restore" -> Alerts.executor.execute {
                try {
                    when (call.method) {
                        "bind" -> Alerts.bind(context, call.argument<String>("account") ?: "", call.argument<Boolean>("enabled") != false)
                        "replace" -> {
                            val account = call.argument<String>("account") ?: ""
                            if (account == Alerts.prefs(context).getString("account", "") && account.isNotEmpty()) {
                                val lessons = JSONArray(call.argument<List<Map<String, Any?>>>("lessons") ?: emptyList<Map<String, Any?>>())
                                val encoded = lessons.toString()
                                val prefs = Alerts.prefs(context)
                                if (encoded != prefs.getString("lessons", "[]")) {
                                    Alerts.cancelAlarms(context)
                                    Alerts.clearPosted(context)
                                    prefs.edit().putString("lessons", encoded).commit()
                                    Alerts.restore(context)
                                } else Alerts.summary(context)
                            }
                        }
                        "restore" -> Alerts.restore(context)
                    }
                    Handler(Looper.getMainLooper()).post { result.success(true) }
                } catch (error: Exception) {
                    Handler(Looper.getMainLooper()).post { result.error("schedule_alerts", error.message, null) }
                }
            }
            else -> result.notImplemented()
        }
    }
}

internal object Alerts {
    val executor = Executors.newSingleThreadExecutor()
    private const val TAG = "ibnu_schedule"
    private const val TODAY = 1
    fun prefs(c: Context) = c.getSharedPreferences("ibnu_schedule_alerts", Context.MODE_PRIVATE)
    private fun manager(c: Context) = c.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    private fun alarms(c: Context) = c.getSystemService(Context.ALARM_SERVICE) as AlarmManager
    fun allowed(c: Context) = (Build.VERSION.SDK_INT < 33 || c.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) && manager(c).areNotificationsEnabled()
    fun exact(c: Context) = Build.VERSION.SDK_INT < 31 || alarms(c).canScheduleExactAlarms()
    private fun active(c: Context) = !prefs(c).getString("account", "").isNullOrEmpty() && prefs(c).getBoolean("enabled", true)
    private fun lessons(c: Context) = JSONArray(prefs(c).getString("lessons", "[]"))
    private fun format(pattern: String) = SimpleDateFormat(pattern, Locale.ROOT).apply { timeZone = TimeZone.getTimeZone("Asia/Jakarta"); isLenient = false }
    private fun start(row: JSONObject): Long = format("yyyy-MM-dd HH:mm:ss").parse("${row.getString("date")} ${row.getString("time")}")!!.time
    private fun end(row: JSONObject): Long {
        val raw = row.optString("endTime", "")
        val value = if (raw.isBlank() || raw == "null") "23:59:59" else raw
        val result = format("yyyy-MM-dd HH:mm:ss").parse("${row.getString("date")} $value")!!.time
        return if (result <= start(row)) result + 24 * 60 * 60_000L else result
    }
    private fun alarmIntent(c: Context, key: String): PendingIntent {
        val intent = Intent(c, ScheduleAlarmReceiver::class.java).setData(Uri.parse("ibnu-schedule://alarm/$key"))
            .putExtra("key", key).putExtra("account", prefs(c).getString("account", ""))
        return PendingIntent.getBroadcast(c, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }
    fun cancelAlarms(c: Context) {
        val keys = prefs(c).getStringSet("alarm_keys", emptySet()) ?: emptySet()
        for (key in keys) { val intent = alarmIntent(c, key); alarms(c).cancel(intent); intent.cancel() }
        prefs(c).edit().remove("alarm_keys").commit()
    }
    fun clearPosted(c: Context) {
        for (n in manager(c).activeNotifications) if (n.tag == TAG) manager(c).cancel(TAG, n.id)
    }
    fun bind(c: Context, account: String, enabled: Boolean) {
        val p = prefs(c)
        val changed = p.getString("account", "") != account
        if (changed || !enabled) { cancelAlarms(c); clearPosted(c) }
        val editor = p.edit().putString("account", account).putBoolean("enabled", enabled)
        if (changed) editor.putString("lessons", "[]")
        editor.commit()
        if (active(c)) restore(c)
    }
    private fun schedule(c: Context, key: String, at: Long) {
        if (at <= System.currentTimeMillis()) return
        val intent = alarmIntent(c, key)
        try {
            if (exact(c)) alarms(c).setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, intent)
            else alarms(c).setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, intent)
        } catch (_: SecurityException) {
            alarms(c).setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, intent)
        }
    }
    fun restore(c: Context) {
        cancelAlarms(c)
        if (!active(c) || !allowed(c)) { clearPosted(c); return }
        val today = format("yyyy-MM-dd").format(Date())
        val saved = lessons(c)
        val rows = JSONArray()
        for (i in 0 until saved.length()) {
            val row = saved.getJSONObject(i)
            if (row.getString("date") < today && end(row) <= System.currentTimeMillis()) {
                if (!row.optBoolean("repeatWeekly")) continue
                val date = Calendar.getInstance(TimeZone.getTimeZone("Asia/Jakarta")).apply { timeInMillis = start(row) }
                while (format("yyyy-MM-dd").format(date.time) < today) date.add(Calendar.DAY_OF_YEAR, 7)
                row.put("date", format("yyyy-MM-dd").format(date.time))
            }
            rows.put(row)
        }
        prefs(c).edit().putString("lessons", rows.toString()).commit()
        if (rows.length() == 0) { clearPosted(c); return }
        val now = System.currentTimeMillis()
        val times = sortedSetOf<Long>()
        val finishes = sortedSetOf<Long>()
        for (i in 0 until rows.length()) {
            val at = start(rows.getJSONObject(i)) - 30 * 60_000L
            if (at > now) times.add(at)
            val finish = end(rows.getJSONObject(i))
            if (finish > now) finishes.add(finish)
        }
        val keys = mutableSetOf<String>()
        for (at in times) { val key = "reminder-$at"; schedule(c, key, at); keys.add(key) }
        for (at in finishes) { val key = "finish-$at"; schedule(c, key, at); keys.add(key) }
        // Rolling at midnight also removes yesterday's bar on days without lessons.
        val midnight = Calendar.getInstance(TimeZone.getTimeZone("Asia/Jakarta")).apply {
            set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0); set(Calendar.SECOND, 5); set(Calendar.MILLISECOND, 0); add(Calendar.DAY_OF_YEAR, 1)
        }.timeInMillis
        schedule(c, "rollover", midnight); keys.add("rollover")
        prefs(c).edit().putStringSet("alarm_keys", keys).commit()
        summary(c)
    }
    private fun builder(c: Context, channel: String, title: String, text: String, ongoing: Boolean): Notification.Builder {
        val m = manager(c)
        if (Build.VERSION.SDK_INT >= 26) {
            m.createNotificationChannel(NotificationChannel("ibnu_today", "Jadwal hari ini", NotificationManager.IMPORTANCE_LOW))
            m.createNotificationChannel(NotificationChannel("ibnu_reminders", "Pengingat 30 menit sebelum pelajaran", NotificationManager.IMPORTANCE_HIGH))
        }
        val launch = c.packageManager.getLaunchIntentForPackage(c.packageName)!!.putExtra("ibnu_open_schedule", true)
            .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        val content = PendingIntent.getActivity(c, 7463, launch, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val b = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(c, channel) else Notification.Builder(c)
        b.setSmallIcon(R.drawable.ic_stat_schedule)
            .setLargeIcon(BitmapFactory.decodeResource(c.resources, c.applicationInfo.icon))
            .setContentTitle(title).setContentText(text).setStyle(Notification.BigTextStyle().bigText(text))
            .setContentIntent(content).setOngoing(ongoing).setAutoCancel(!ongoing).setShowWhen(false)
            .setVisibility(Notification.VISIBILITY_PRIVATE).setOnlyAlertOnce(ongoing)
        if (Build.VERSION.SDK_INT < 26) b.setPriority(if (ongoing) Notification.PRIORITY_LOW else Notification.PRIORITY_HIGH)
        return b
    }
    private fun line(row: JSONObject): String {
        val endTime = row.optString("endTime", "").takeIf { it.isNotBlank() && it != "null" }?.take(5) ?: "--:--"
        return "${row.getString("class")} | ${row.getString("time").take(5)} - $endTime WIB | ${row.getString("lesson")}${if (row.optBoolean("substitute")) " (pengganti)" else ""}"
    }
    private fun expires(builder: Notification.Builder, until: Long): Notification.Builder {
        if (Build.VERSION.SDK_INT >= 26) builder.setTimeoutAfter((until - System.currentTimeMillis()).coerceAtLeast(1))
        return builder
    }
    private fun reminder(c: Context, at: Long, rows: List<JSONObject>, updating: Boolean) {
        val key = "reminder-$at"
        if (rows.isEmpty()) { manager(c).cancel(TAG, key.hashCode()); return }
        val now = System.currentTimeMillis()
        val title = if (updating) "Pengingat jadwal mengajar" else
            "Pelajaran dimulai dalam ${((rows.minOf { start(it) } - now + 59_999) / 60_000)} menit"
        val notification = builder(c, "ibnu_reminders", title, rows.joinToString("\n") { line(it) }, false)
            .setOnlyAlertOnce(true).addExtras(Bundle().apply { putLong("ibnu_reminder_at", at) })
        manager(c).notify(TAG, key.hashCode(), expires(notification, rows.maxOf { end(it) }).build())
    }
    fun summary(c: Context) {
        val today = format("yyyy-MM-dd").format(Date())
        val now = System.currentTimeMillis()
        val all = lessons(c)
        val planned = (0 until all.length()).map { all.getJSONObject(it) }
        val rows = planned.filter { it.getString("date") <= today && end(it) > now }.sortedBy { start(it) }
        if (!active(c) || !allowed(c)) { clearPosted(c); return }
        for (posted in manager(c).activeNotifications) {
            if (posted.tag != TAG || posted.id == TODAY) continue
            val at = posted.notification.extras.getLong("ibnu_reminder_at", -1)
            if (at < 0) { manager(c).cancel(TAG, posted.id); continue }
            reminder(c, at, planned.filter { start(it) - 30 * 60_000L == at && end(it) > now }, true)
        }
        if (rows.isEmpty()) { manager(c).cancel(TAG, TODAY); return }
        val notification = builder(c, "ibnu_today", "Jadwal hari ini - ${rows.size} pelajaran", rows.joinToString("\n") { line(it) }, true)
        manager(c).notify(TAG, TODAY, expires(notification, rows.maxOf { end(it) }).build())
    }
    fun receive(c: Context, intent: Intent) {
        if (!active(c) || intent.getStringExtra("account") != prefs(c).getString("account", "")) return
        val key = intent.getStringExtra("key") ?: return
        if (key == "rollover") { restore(c); return }
        if (!allowed(c)) return
        if (key.startsWith("finish-")) { summary(c); return }
        val at = key.removePrefix("reminder-").toLongOrNull() ?: return
        val now = System.currentTimeMillis()
        val all = lessons(c)
        val rows = (0 until all.length()).map { all.getJSONObject(it) }
            .filter { start(it) - 30 * 60_000L == at && start(it) > now && end(it) > now }
        if (rows.isEmpty()) return
        reminder(c, at, rows, false)
    }
}

class ScheduleAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val pending = goAsync()
        Alerts.executor.execute { try { Alerts.receive(context, intent) } catch (_: Exception) { /* A revoked permission must not crash the app. */ } finally { pending.finish() } }
    }
}
class ScheduleRestoreReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action !in setOf(Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED, Intent.ACTION_TIME_CHANGED, Intent.ACTION_TIMEZONE_CHANGED, AlarmManager.ACTION_SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED)) return
        val pending = goAsync()
        Alerts.executor.execute { try { Alerts.restore(context) } catch (_: Exception) { /* Retry on app resume. */ } finally { pending.finish() } }
    }
}
