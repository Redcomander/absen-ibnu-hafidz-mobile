# Offline attendance and automatic sync

## User behavior

- Sign in online once with **Ingat perangkat ini** enabled to allow Android to
  authenticate background work after the app closes. Without it, sync runs while
  the signed-in app is open; queued data remains on disk for the next login.
- Each account has its own **Pengaturan Sinkronisasi** on this device: **Wi-Fi**
  or **Wi-Fi/Data**. The default is Wi-Fi/Data. Preferences are local to the device,
  not shared between different phones. Wi-Fi mode also permits Ethernet; a VPN
  alone does not qualify as Wi-Fi.
- Load the required schedules and attendance forms while online before working
  offline. Forms and lists that have never been loaded cannot be invented offline.
  Cached API data is separated by API host and account ID.
- Jadwal now opens its saved timetable before attempting a network refresh.
  The app warms unfiltered Formal, Diniyyah, and enabled Ramadhan schedules when
  signed in and connected to an allowed network, at most every ten minutes.
  Search, gender, and day filters run locally and cannot replace the stored full
  timetable with a filtered or empty search result. Refreshes time out after
  eight seconds while the saved lessons remain visible.
- After pending submissions finish, preparation also caches up to eight of
  today's lesson attendance forms, prioritizing the signed-in teacher's classes.
  It follows the account's Wi-Fi/data setting and pauses further downloads when
  a new submission is pending. Saved forms open before refresh, retain typed edits
  during late responses, and show the account's pending changes when reopened.
  Sync settings show the last preparation's form count. See
  [Performance and preparation](./PERFORMANCE.md) for limits and verification.
- When no exact-date snapshot exists, the last saved recurring timetable remains
  readable. Attendance flags, counts, and teaching material from the previous date
  are cleared and shown as needing an online update. Expired substitute-only
  assignments are excluded. Older unfiltered account-scoped caches are also used
  after an app upgrade. A first successful download is still required; an offline
  phone cannot discover new assignments or timetable changes.
- A remembered account can reach its offline pages while startup session
  validation is pending. An explicit authentication rejection still signs it out;
  a delayed validation response cannot undo a subsequent logout.
- Attendance is saved to a transactional SQLite queue before attempting the
  network, including when online. A queued response means **saved on this device**;
  only a successful server response confirms submission. Settings show pending
  entries, server errors, rejected entries, retries, and the last confirmation.
- Open-app sync runs on network changes, app resume, and every 30 seconds.
  Android WorkManager also schedules network-constrained one-off work and a
  15-minute periodic safety check. Android controls actual timing. Battery
  restrictions, Doze, and force-stop can delay work; reopening the app retries.
  This implementation does not configure closed-app background execution on iOS.
- Submissions are processed in order. A validation, permission, missing-resource,
  or conflict response blocks that entry and later entries until reviewed and
  retried. Network errors, timeouts, rate limits, and server failures remain
  pending for automatic retry. No failed entry is silently deleted.
- Signing out pauses that account's work without deleting its queue. Signing in
  as another user never transfers or submits those entries. Return to the original
  account to resume. Uninstalling or clearing app data removes local storage.
- Old shared-preference queues are retained. Recovery is explicit and only imports
  rows whose original token payload identifies the signed-in account. Unknown or
  malformed rows remain in their original storage for manual investigation.

## Halaqoh session windows — deploy the backend update

The matching Go backend changes must be deployed before relying on delayed
Halaqoh submission outside a session window. No database migration is required.
Deploy both server write-error fixes and signed offline permits; restarting the
Go server is required. Existing web API fields and normal permissions are retained.

Opening today's Halaqoh attendance form online obtains a signed permit bound to
the authenticated user, form kind, assignment IDs, date, and session. The mobile
app stores the original capture timestamp in the queued submission. After the
session closes, replay is allowed only with that permit and a capture timestamp
inside the scheduled Jakarta session window. The permit expires at Jakarta
midnight three days after the attendance date. Normal current permissions are
still checked on replay. A client timestamp is a user-declared capture time,
not independent evidence of physical presence.

Forms cached before this backend update have no permit. Load them online again.
An expired/missing permit or changed permission leaves the data blocked for admin
review; the app cannot override the server's policy. Queued photos are not
supported: attempting to queue file attachments returns an explicit error rather
than dropping files. The current mobile attendance forms submit text fields.

## Delivery and storage

- Queue rows contain payloads and encoding, never a saved access token. Replay
  obtains the current account's credentials and coordinates refresh-cookie
  rotation between the foreground and background isolates.
- A database lease prevents overlapping foreground/background replays. Acknowledge
  removes only the successfully submitted row in a transaction, so a concurrent
  new submission is preserved. Stale leases expire after a process crash.
- Replay is **at least once**: if the server saves a request but its response is
  lost, the request is retried. Existing attendance upserts use schedule/student/
  date/session identity. This does not provide server-side exactly-once receipts
  or automatic conflict merging across phones and web edits. Avoid editing the
  same attendance concurrently on multiple devices; later accepted writes can
  replace earlier values under the existing API rules.
- Backend attendance handlers now return failures when the main write or student
  attendance transaction commit fails, instead of reporting success and allowing
  the mobile queue to discard unsaved data. Business records are not migrated,
  cleared, or rewritten by this upgrade.

## Validation

Run `flutter analyze`, `flutter test`, and backend `go test ./...`.
Sync regression tests cover restart recovery, concurrent enqueue/acknowledge,
account isolation, network preferences, JSON/multipart replay, server rejection,
network retries, and worker leases. Permit tests cover signature, user, resource,
date, form kind, session, capture-window, and expiration checks.

The Android emulator smoke test passed with the app off-screen: network constraints
held the queue while offline, reconnect triggered native workers, both JSON and
multipart requests received mock-server confirmations, and the on-device SQLite
queue was empty afterward (`integrity_check: ok`). Production attendance was not
used for this test.

The isolated Android smoke harness is [background_sync_smoke.dart](../tool/background_sync_smoke.dart)
with [sync_mock_server.py](../tool/sync_mock_server.py). Build it with a separate
debug application ID ending in `.syncsmoke`, target the harness, and set
`APP_BASE_URL=http://10.0.2.2:18089`. It refuses other API hosts. Start the mock API,
disable emulator networking, launch the harness, background the app, kill its
background process with `am kill` (not force-stop), then reconnect. Verify both
JSON and multipart POSTs on the mock server and an empty SQLite queue. This test
must never use production credentials or the regular app's application ID.
