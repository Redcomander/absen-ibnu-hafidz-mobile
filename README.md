# Sistem Absensi Ibnu Hafidz

Flutter mobile application for the Ibnu Hafidz attendance system. This app connects to the existing Go backend and mirrors the website workflow for Jadwal, Absensi, Halaqoh, Statistik, Export, and daily operational use.

## Overview

This repository contains the Android-ready mobile client used by teachers, admins, and internal staff.

**Core Goals:**
- Keep the existing Go backend contract unchanged.
- Provide a cleaner and more modern mobile experience.
- Support real attendance operations from mobile devices.
- Remain usable during unstable internet connections through offline cache and automatic sync.

## Features

**Implemented in the current app:**
- Login and saved session persistence.
- Jadwal for Formal, Ramadhan, and Diniyyah modes.
- Student attendance and teacher attendance recording.
- Substitute teacher assignment and cancellation.
- Halaqoh groups, statistics, history, and exports.
- Attendance statistics and history pages.
- PDF and Excel export flows.
- Offline cached data for Jadwal, statistics, and Halaqoh.
- Offline queued writes with reconnect sync capabilities.
- App branding, launcher icon, and Android network permissions configuration.

## Stack

- **Flutter** - UI Toolkit
- **Provider** - State Management
- **HTTP** - Network Requests
- **Shared Preferences** - Local Data Persistence
- **Connectivity Plus** - Network State Detection
- **Path Provider** - Filesystem Access

## Project Structure

- [`lib/`](lib) — Application source code.
- [`assets/`](assets) — Branding files and icons.
- [`android/`](android) — Android project and manifest.
- [`test/`](test) — Regression and widget tests.
- [`PLAY_STORE_SUBMISSION.md`](PLAY_STORE_SUBMISSION.md) — Store listing and publishing notes.

## Backend Target

The release build is configured to use:
- **Host:** `https://ibnuhafidz.ponpes.id` (default for test and release builds)
- **Prefix:** `/api`

Configuration lives in [`lib/core/config/app_config.dart`](lib/core/config/app_config.dart).

## Local Setup

### Requirements

Install the following tools before running the app:
- [Flutter SDK](https://flutter.dev/docs/get-started/install)
- [Android Studio & Android SDK](https://developer.android.com/studio)
- An Android emulator or a physical Android device

### Install Dependencies

```bash
flutter pub get
```

### Run the App

```bash
flutter run
```

### Helpful Commands

```bash
flutter analyze             # Run static analysis
flutter test                # Run unit/widget tests
flutter build apk --debug   # Build a debug APK
flutter build apk --release # Build a release APK
flutter build appbundle     # Build an Android App Bundle (AAB)
```

## Offline and Sync Behavior

The app supports semi-online operations to handle poor connectivity:
- Successful network reads are cached locally.
- Jadwal, statistics, and Halaqoh data remain visible offline.
- Attendance submissions are queued if the connection is unavailable.
- Pending actions sync automatically when the network returns.

## Deployment Checklist

### Already Completed
- [x] App name updated to **Sistem Absensi Ibnu Hafidz**.
- [x] Android internet permissions added.
- [x] Beta API host configured.
- [x] Login and operational feature parity implemented.
- [x] Offline caching and auto-sync implemented.
- [x] Privacy policy page prepared on the web side.
- [x] Play Store submission notes prepared.
- [x] APK builds verified during testing.
- [x] Android application ID finalized to `id.ponpes.ibnuhafidz.absensi`.
- [x] Versioned APK generation script added for release builds.

### Pending for Play Store Release
- [ ] Install missing Android `cmdline-tools` and accept Android SDK licenses.
- [ ] Create a real upload keystore.
- [ ] Configure release signing in the Android build.
- [ ] Generate the final signed Android App Bundle (AAB).
- [ ] Capture final real-device store screenshots.
- [ ] Complete Play Console forms for testing, content rating, and listing.
- [ ] Perform one final end-to-end test on the production-like environment.

## Important Release Notes

The Android project currently uses the default example application ID and debug signing for release builds. While acceptable for internal testing, this **must** be finalized before public Play Store submission.

See [`android/app/build.gradle.kts`](android/app/build.gradle.kts) for the current Android release configuration.

## Recommended Release Flow

1. Finalize the package name and signing key.
2. Run analysis (`flutter analyze`) and tests (`flutter test`).
3. Build the signed app bundle.
4. Upload to **Closed Testing** in the Google Play Console.
5. Verify login, sync, export, and offline recovery on a real device.
6. Promote to **Production** after tester approval.

## Notes

See [Offline sync behavior and deployment](docs/OFFLINE_SYNC.md) for per-account
network settings, Android background timing, queue recovery, and the required
Halaqoh backend update.

- This app is intended for **internal operational use** by the institution.
- The backend API structure remains unchanged to ensure web compatibility.
- In low-network scenarios, the app automatically falls back to the most recently saved local data.
