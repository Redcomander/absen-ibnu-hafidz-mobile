# Mobile redesign — first implementation

## Jadwal and Rekapan refresh — 10 November 2026

The new generation request to Stitch returned HTTP 401 because this session has
no available credential for the configured Stitch header. The redesign therefore
adapts the existing [Stitch dashboard concept](./stitch-dashboard.png), rather
than claiming newly generated page concepts. Reconnect Stitch to generate new
references in the same project.

- Shared emerald hero panels, ivory surfaces, gold details and the bundled
  Plus Jakarta Sans font continue the established Stitch direction.
- Jadwal uses one vertical list of lesson cards, local search and day filters,
  collapsible secondary filters, labeled attendance actions and visible saved-data
  timestamps. Cached schedules remain visible during refresh and timeout.
- Rekapan uses a date-range header, wrapping module/type/scope controls, collapsible
  period/search filters, a real-data attendance percentage, responsive metric
  cards and the existing history, teacher summary and PDF workflows.
- Tests cover saved schedules during a hanging network request, recurring
  timetable recovery across dates, old-cache preservation, server failures,
  account isolation, startup/logout races and report rendering at 150% text size.

The earlier implementation notes below describe the first redesign and its
validation at that time. Current offline behavior is documented in
[Offline sync](../OFFLINE_SYNC.md).

[Open the Google Stitch project](https://stitch.withgoogle.com/projects/17552918936715416614).

Generated on 10 November 2026 using the official Stitch MCP endpoint. Only a
generic UI brief was sent; no source code, real names, credentials or student
records were included in the design prompt.

## Reference screens

- [Login concept](./stitch-login.png)
- [Dashboard concept](./stitch-dashboard.png)

These are Stitch concepts, not screenshots of the running Flutter app. Their
sample names, counts, biometric/NFC actions and sample dates are not implemented.

## Implemented

- Forest emerald `#143E35`, warm ivory `#F7F7F0`, gold `#D8B56A`.
- Bundled Plus Jakarta Sans for offline typography, licensed under SIL OFL.
- Scrollable login, password visibility labels, keyboard submission, autofill
  hints and full-width sign-in action.
- Home greeting using the signed-in user's name and the device's current date.
- Live local queue count and network-interface status, with an existing sync
  action. A network interface does not guarantee backend reachability.
- Beranda, Jadwal, optional Rekapan, and Pengaturan navigation.
- Personal sync settings for all signed-in users; Control Center still requires
  super_admin. Existing report role/permission rules are retained.
- Refresh-cookie rotation is saved for remembered sessions. An explicit API
  authentication failure at startup no longer opens a cached offline session.

The home screen deliberately contains no placeholder attendance statistics.
Existing schedule, attendance, Halaqoh and reporting workflows remain reachable.
This update does not modify the backend or its authorization policy.

## Remaining integration work

1. Account-scoped offline cache and queues, with safe handling of existing
   unscoped records rather than deleting pending attendance.
2. Serialized queue updates, current-session credentials, idempotent backend
   replay, conflict handling and explicit retry/error feedback.
3. Secure credential storage and server-side session revocation on logout.
4. Maintenance-mode and production request-ID handling matching the web app.
5. Detailed schedule/attendance screen redesign and an authenticated schedule
   summary on the home screen.

No production database was accessed or migrated. UI tests use mocked preferences
and authentication requests; real-device offline/reconnect testing is still
required before publishing this app.

## Validation

- `flutter analyze`: no issues.
- `flutter test`: 14 tests passed, including small-screen/large-text rendering,
  navigation permissions, refresh-cookie rotation and rejected-session handling.
- Android phone debug packaging succeeded with both ARM64 and ARMv7 Flutter
  runtimes and a verified APK signature, using official dependencies downloaded
  through a temporary local build repository after Java TLS download failures.
- HTML HTTP failures are reported as API errors instead of offline queue success.
  Saved-session and schedule screens provide explicit server-error/retry feedback.
- The phone APK uses `https://ibnuhafidz.ponpes.id/api`. Public checks on 10
  November 2026 returned JSON: maintenance 200 (disabled), and unauthenticated
  `/auth/me` and `/schedules` 401 as expected. The beta host returned HTML 500,
  so it is no longer the default. Authenticated schedule loading still requires
  manual account testing. No hosted configuration was changed.
