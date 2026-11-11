# Android schedule alerts

The notification shade shows today's Formal, Diniyyah, and enabled Ramadhan
lessons assigned to the signed-in teacher, including valid substitute assignments.
Administrators do not receive alerts for other teachers' timetables. Each lesson
reminds 30 minutes before its start; simultaneous lessons share one reminder.
Notifications include the installed app logo and a monochrome book status icon.
Tapping a notification opens Jadwal after authentication.

Build 6 displays class name (including sub-class), then level, followed by start
and end times in WIB and the lesson name. The current API stores sections such
as A/B in the class name; explicit sub_kelas/subkelas values are supported too.
Finished lessons are filtered from the daily bar at end-time alarms, without
waiting for another sync. The bar disappears once its last lesson finishes.
Posted reminders are likewise updated or removed when their lessons finish.
Android 8+ also receives an OS notification timeout as a fallback, independent
of the Flutter process. Older supported versions use the end-time alarm.
Exact-alarm access enables timely boundary updates; Android may delay alarms
without this access. Existing start-only notification cache is preserved with
an unknown end shown as --:--; sync once after updating to download end times.
No attendance or account data is cleared by this update.


## Permissions and user controls

Notifications are enabled per account on this device, under **Pengingat jadwal
saya** in Settings. Android's notification permission is requested once when an
assigned timetable becomes available. The Settings card links to notification
settings and **Alarms & reminders** access. When exact-alarm access is granted,
AlarmManager uses exact delivery while idle. Without access, Android may delay
an inexact reminder. Neither full-screen alarms nor a permanent background
service are used. The Android package uses SCHEDULE_EXACT_ALARM, not the
restricted USE_EXACT_ALARM permission.

## Offline behavior and changes

Schedules use Asia/Jakarta (WIB), independent of the phone's timezone. Alarms and
a compact personal plan are persisted natively and survive process exit, reboot,
app update, and clock/timezone changes. Original weekly assignments roll forward
offline. Substitutions are restricted to their actual date and never recur.
An undated legacy substitution is valid only for its downloaded date. Fresh empty
responses remove obsolete assignments; failed requests preserve saved reminders.
Logging out or switching accounts cancels the previous account's alerts.
Disabling alerts cancels them without deleting attendance or schedule data.

Foreground downloads reuse the existing timetable preparation requests. Android
WorkManager refreshes schedules after pending submissions finish, subject to the
account's Wi-Fi/data policy. During 23:00-23:59 WIB it also checks tomorrow's
substitutions so a midnight lesson can remind on the previous date. This does not
overwrite the main offline timetable cache. Historical browsing does not replace
personal reminder snapshots. New or revoked assignments require a successful
online refresh; cached alarms cannot discover server changes while offline.
Android force-stop and manufacturer battery restrictions can prevent delivery
until the app is reopened. Precise timing requires the OS permissions above.

## Implementation and verification

The local [Android plugin](../packages/ibnu_schedule_alerts/) uses native
AlarmManager and notification receivers; it does not start a Flutter engine when
an alarm fires. JSON persistence and alarm reconciliation run on a serialized
background executor. Identical plans avoid rescheduling. Notification permission
failures never interrupt attendance saves. Private lock-screen visibility is used.
The feature currently targets Android; no iOS notification implementation is added.

Regression tests cover assignment ownership, substitute dates, WIB midnight,
invalid/deleted rows, deduplication, per-user preferences, removal, persistence,
and next-day substitution merging. The isolated
[notification harness](../tool/notification_smoke.dart) refuses production API
configuration and uses only a separate `.syncsmoke` application and fake user.
Native emulator checks verified a logo-bearing today bar, an offline background
30-minute reminder for its synthetic lesson, and cancellation on logout.
No production attendance was created.

On Windows without Developer Mode, Android-only plugin generation can use
command-scoped environment overrides (no system settings change):

```powershell
$env:FLUTTER_WINDOWS = 'false'
$env:FLUTTER_LINUX = 'false'
flutter pub get
```

These flags apply only to the current terminal process and its child commands.


## Phone build

Version 1.0.0+3 is available as the
[profile APK](../build/phone/ibnu-hafidz-performance-test.apk) (54.3 MiB) and
[debug APK](../build/phone/ibnu-hafidz-android-test.apk) (116.8 MiB).
Both use the production API and retain the previous package/signing certificate.
Install as an update; attendance, cached schedules, and sync preferences are kept.
Validation: all 55 Flutter tests pass, static analysis is clean, and native offline
notification display/timing/logout checks passed on the isolated Android emulator.


## Build 6 expiry validation

65 Flutter tests passed and static analysis was clean. The isolated
notification_expiry_smoke harness was installed only as the disposable
id.ponpes.ibnuhafidz.absensi.syncsmoke package on the emulator. It seeded one
already-ended lesson and two lessons ending 20 and 40 seconds later. The daily
notification excluded the expired lesson, showed the complete class and time,
changed from two lessons to one, then cleared after the final end while the app
was in the background. The test package was uninstalled afterward; no production
API requests or attendance writes were used. Production APK build 6 retains the
previous signing certificate for installation over the existing app.
