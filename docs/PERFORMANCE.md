# Performance and offline preparation — first pass

## Findings and changes

The home shell previously replaced its active page on every tab change. Returning
to Jadwal recreated its state and requested the timetable again; returning to
Rekapan recreated its report requests. Tabs now mount on first use and remain in
an IndexedStack. Unopened tabs make no requests, and returning to an opened tab
preserves its data, search, and scroll position. Account changes replace the page
keys, and report permissions still determine which tabs exist.

The timetable warmer and visible page could request the same account/type/date
concurrently. Schedule and attendance repositories now share the in-flight
request for each resource. The entry is removed after completion or failure, so
later refreshes can still fetch new data. This is request coalescing, not a
permanent memory cache.

Offline preparation previously saved only timetables. After pending submissions
finish, the foreground app now prepares today's Formal, Diniyyah, and enabled
Ramadhan attendance forms. It downloads at most eight forms per pass, one request
at a time, prioritizing the signed-in teacher's assignments. Each request remains
subject to server permissions. Preparation checks the account, connection policy,
and pending queue before subsequent requests. Successful passes are spaced ten
minutes apart; failures can retry after about one minute. Other forms are cached
when opened online. Halaqoh still requires opening its forms online beforehand.

Attendance forms now read saved rosters before refreshing. A late response cannot
overwrite edits typed while the request was running. Reopening a form overlays
pending queue entries for that exact account, type, schedule, and date; it neither
discards those entries nor treats them as confirmed server records. Invalid or
denied roster responses leave the previous valid cache intact. Readiness counts
appear in sync settings for the current account/day.

## Evidence

Regression tests verify these concrete request counts:

| Scenario | Expected requests |
| --- | --- |
| Home before opening Jadwal or Rekapan | 0 page requests |
| First opening Jadwal | 1 timetable request |
| Jadwal → Pengaturan → Jadwal | Still 1 timetable request |
| Two concurrent timetable readers | 1 request |
| Two concurrent attendance readers | 1 request |
| Offline search/filtering | 0 additional requests |

Tests also cover bounded preparation, account isolation, connection-policy
interruption, saved-roster recovery, queued-edit overlays, and editing a cached
form while a server response is pending. These are behavioral checks, not a
measurement of physical-phone frame time or startup latency.

## Real-phone profiling

Validation completed with 39 passing Flutter tests and a clean analyzer. Both
debug and profile phone builds succeeded and passed APK signature verification.
The profile package contains AOT application libraries and Flutter runtimes for
ARM64 and ARMv7, uses the same application ID and signing certificate as the test
app, and is 53.9 MiB (the debug package is 131.2 MiB). This size comparison is
packaging evidence, not a runtime speed measurement. Both are internal test builds.

- [Profile APK for phone performance testing](../build/phone/ibnu-hafidz-performance-test.apk)
- [Updated debug APK](../build/phone/ibnu-hafidz-android-test.apk)

Only an Android emulator was attached during this pass. No physical-device FPS,
memory, battery, or startup improvements are claimed yet. Use Flutter profile
mode on the actual phone to collect those numbers; debug builds include tooling
overhead and are unsuitable for representative performance measurements.

With a USB-connected phone and Flutter installed:

```powershell
flutter devices
flutter run --profile -d DEVICE_ID --dart-define=APP_BASE_URL=https://ibnuhafidz.ponpes.id
```

Use the DevTools link printed by Flutter. Record cold startup, first Jadwal open,
returning to Jadwal, long-list scrolling, opening a saved attendance form,
reconnection with pending submissions, and retained memory after visiting all
tabs. Repeat with airplane mode and with slow connectivity. Keep test attendance
on a test account and do not submit invented records to production.

The CPU timeline includes `attendance.refresh` and `offline.prepare` tasks.
Preparation events record only counts, never credentials, names, or form contents.
Measure performance with preparation both active and idle. Frame and memory
measurements should determine the next optimization, such as flattening unusually
large day groups, report pagination, or backend query improvements.

Backend idempotency receipts, cross-device conflict detection, and production SQL
profiling are separate follow-up work; this pass makes no database schema changes.


## Flutter upgrade and sync frame work (2026-11-10)

Verified toolchain: Flutter stable 3.47.9, Dart 3.13.7, DevTools 2.60.0.
The app requires Flutter 3.47.9 or later.
The Android package ID and signing configuration remain the same, and the build
number is incremented to 2 so this APK can update the previous test installation.
No database schema migration, queue deletion, or cache-key replacement is involved.

Large JSON response decoding, queued submission decoding/encoding, and cache
serialization use Flutter `compute` isolates. Payloads below a 32 KiB estimated
budget stay inline to avoid isolate overhead on small requests. The JSON encoder
uses a bounded structural estimate rather than encoding the entire payload first.
The existing SharedPreferences cache and SQLite queue formats stay compatible.

Foreground replay reads at most 12 complete queue rows from SQLite per pass.
Existence checks select only an ID with LIMIT 1, and status reads omit submission
bodies. Full details are read for the exact account/ID when the user opens them.
An idle check no longer toggles the syncing indicator; unchanged status does not
notify listeners. Replay yields to the event loop between acknowledgements.
Jadwal, Rekapan, and Halaqoh subscribe only to the settings fields they display,
so unrelated queue progress does not rebuild those pages.

Submission ordering, blocked-row handling, per-user connection policy, sync leases,
and deletion only after successful server acknowledgement remain enforced.
These changes reduce known work on the UI isolate. Actual frame-time improvement
must still be measured on a physical phone using the profile APK and DevTools;
unit/widget tests cannot establish a real-device FPS number.


Validation on the upgraded SDK: `flutter analyze --no-pub` reports no issues;
all 43 tests pass. Added checks cover a 1,500-student JSON/cache round trip,
metadata-only queue status with on-demand details, idle sync notifications,
FIFO/account-safe limited reads, and no timetable rebuild from sync status.
Existing offline cache, permission, submission acknowledgement, restart recovery,
and form-edit preservation tests still pass. The initial network-status update
also avoids fetching a successful online timetable a second time.


Updated phone artifacts (Flutter 3.47.9, version 1.0.0+2):
- [Profile / performance APK](../build/phone/ibnu-hafidz-performance-test.apk): 54.1 MiB, ARM64 and ARMv7 AOT.
- [Debug APK](../build/phone/ibnu-hafidz-android-test.apk): 116.7 MiB, ARM64 and ARMv7.
Both retain package `id.ponpes.ibnuhafidz.absensi` and the earlier test signing
certificate, with production API `https://ibnuhafidz.ponpes.id`. Install as an
update to retain local submissions and saved settings; do not uninstall first.
The emulator-only smoke harness is a separate application ID and local mock API.

Native Android smoke verification also passed on the API 37 emulator using the
upgraded SDK/plugins: two records (JSON and multipart) persisted while offline;
after the app was backgrounded and connectivity restored, WorkManager delivered
both to the local mock API and the SQLite queue became empty with a recorded
acknowledgement timestamp. The test used only the separate `.syncsmoke` package
and fake account 901; no production attendance was submitted.


## Schedule alerts and large timetable rendering

Jadwal now uses a lazy SliverList for individual day headings and lesson cards;
previously a day group created every lesson card in one Column. Grouping/search
results are memoized by the source list and filters, so unrelated UI changes do
not re-sort and re-filter the timetable. A 1,000-row cached timetable regression
verifies fewer than 20 lesson subtrees are built initially, with no overflow.
Pending attendance overlay queries filter the request path in SQLite before
transferring JSON bodies to Dart, excluding unrelated queued Halaqoh actions.

Notification snapshots retain only this user's reminder fields. Notifications
reuse downloaded schedules, debounce changes, and skip identical native plans.
Native disk writes/alarm reconciliation run off the Android main thread. Scheduled
alerts do not launch Dart or poll the network. See [schedule alerts](./SCHEDULE_ALERTS.md).
The updated suite has 55 passing tests; native offline reminder/logout checks also
passed. These checks do not establish physical-phone FPS measurements.
