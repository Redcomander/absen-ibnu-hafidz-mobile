# Build 8: mobile design evaluation

The requested Google Stitch lookup was attempted through its connected MCP tool.
It returned Authentication required. No fresh Stitch design was obtained. The
navigation refinement is based on the supplied reference and the app theme.

## Navigation and spacing

The bottom bar is more compact and uses a circular cutout aligned with the active
button. The traveling icon changes at the midpoint rather than immediately at
the previous tab position. Existing motion, selected semantics, RTL handling,
reduced-motion preferences, and retained tab state are preserved. Settings cards
have 14 px bottom separation; student form journal/student cards have 12 px.
The teacher form scrolls on shorter screens instead of hiding its save button.

## Web report parity

Halaqoh reports consume the same endpoints and JSON as Vue:
chartData/izinStudents/sakitStudents/alpaStudents for students, and stats,
sessionStats, substitutionCount, teachers, history, absence_history for teachers.
Each report loads independently. Teacher picker failures do not prevent report
loading. Filters include dates, teacher, and gender. Both report types use the
existing PDF and Excel routes. Tables render at most ten rows per page and
scroll horizontally. Cached reports remain visible during refresh. Both mobile
entry points lead to this report screen; the group screen no longer fetches
unopened statistics/history at startup.

Formal/Diniyyah reports include Dinas totals, class/teacher/gender filters,
absence history, and the correct original_status from substitute history. Filter
option pages load only when the filter panel opens and fail independently.
Export requests include the same selected filters.

## Dinas and backend deployment

Teacher attendance offers Dinas. Substitute forms display Dinas instead of
Dinas Luar and preserve the existing selection when edited. Halaqoh API totals,
session summaries, teacher summaries, and PDF/Excel exports now count Dinas and
historical Dinas Luar together. PDF teacher summaries use landscape orientation
to fit the extra column. Historical database rows are not rewritten.

Deploy the Go backend changes to apply Halaqoh Dinas aggregation/export updates:
internal/handlers/halaqoh.go, halaqoh_stats.go, and halaqoh_export.go. The existing
teacher_attendance_status.go helper is reused. No schema migration is required.
These changes were not deployed to production during this task. Existing mobile
report endpoint/schema corrections work with the current web-compatible API.

## Notification finish-time recovery

The start-only compact notification cache from older versions previously took
precedence over the complete offline timetable. Binding an account now recovers
missing finish times and class levels from matching IDs in the account/module's
full timetable, persists the repaired compact snapshot, and republishes the native
plan. It never adds members/lessons missing from the compact snapshot or changes
another account. Empty end_time values fall back to jam_selesai, endTime, or
jamSelesai. Labels display class name/section, then level separated by a comma.
Actual missing server times are not guessed; a successful timetable refresh is
still needed when neither cache nor API contains an end time.

## Validation

71 Flutter tests pass, including web report fixtures, picker failure isolation,
small-screen report tables, a real mocked Dinas form submission, legacy alert
cache repair, and all existing offline sync and notification checks. Static
analysis is clean. The complete Go test suite passes, including a database test
that verifies Dinas reporting/export counts while the historical stored status
remains Dinas Luar. Production API writes and database migrations were not run.
