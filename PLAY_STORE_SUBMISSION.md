# Play Store Submission Kit — Ibnu Hafidz Mobile

## 1. Privacy Policy URL
Recommended public URL after frontend deploy:

https://beta.ibnuhafidz.ponpes.id/privacy-policy.html

Source page:
- ibnu-hafidz-vue-frontend/public/privacy-policy.html

## 2. App Name
Sistem Absensi Ibnu Hafidz

## 3. Short Description
Absensi, jadwal, halaqoh, dan rekap internal Pondok Ibnu Hafidz.

## 4. Full Description
Ibnu Hafidz Mobile adalah aplikasi internal untuk mendukung pengelolaan jadwal, absensi, halaqoh, dan statistik di lingkungan Pondok Pesantren Tahfidz Ibnu Hafidz.

Fitur utama:
- Jadwal mengajar dan aktivitas harian dalam satu aplikasi.
- Absensi santri dan guru yang terintegrasi.
- Manajemen halaqoh, termasuk pengganti guru dan riwayat.
- Statistik kehadiran dan export laporan PDF atau Excel.
- Sinkronisasi data yang dirancang untuk penggunaan operasional harian.

Aplikasi ini ditujukan untuk penggunaan internal oleh guru, admin, dan pihak yang berwenang di lingkungan Ibnu Hafidz.

## 5. Category
- App category: Education

## 6. Target Audience and Content Rating
Recommended setup:
- Target audience: 18+ (guru, admin, dan staf internal)
- Content rating: Everyone
- Not directed to general children as a public consumer app
- No gambling, violence, sexual content, or user-generated public content

## 7. App Icon
Current launcher icon source:
- ibnu-hafidz-flutter/assets/branding/favicon.png

Play Console listing icon recommendation:
- export a 512 x 512 PNG based on the same brand icon
- keep transparent or solid clean background

## 8. Screenshot Checklist
Prepare at least these screenshots from a real phone before publishing:
- Login screen
- Jadwal screen
- Absensi santri action in Jadwal
- Statistik guru
- Halaqoh groups
- Halaqoh stats
- Export report dialog

Recommended device screenshots:
- Phone portrait, minimum 2 screenshots
- Better to upload 5 to 8 screenshots

## 9. Closed Testing Notes
Suggested tester instructions:
- Login with provided guru account
- Check Jadwal and attendance submission
- Check Halaqoh attendance and substitute flow
- Check Statistics and export PDF or Excel
- Report any login, sync, or export issues

## 10. Release Notes
Version 1.0.0
- Jadwal dan absensi terintegrasi
- Statistik santri dan guru
- Fitur halaqoh lengkap
- Export laporan PDF dan Excel
- Dukungan offline cache dan auto sync
- Tampilan mobile yang lebih rapi dan modern

## 11. Production API Configuration
The Flutter app is now configured so that release builds default to:

https://beta.ibnuhafidz.ponpes.id/api

For local or custom builds you can override the host with compile-time variables if needed.

## 12. Deployment Readiness Status
Already prepared:
- privacy policy page
- app branding and launcher icon
- beta API base URL
- offline cache and auto sync
- export flows
- installable APK builds
- finalized Android package name: id.ponpes.ibnuhafidz.absensi
- versioned APK generation for release builds

Still required before final Play Store release:
- install Android cmdline-tools and accept SDK licenses on the build machine
- real upload keystore and release signing config
- final Android App Bundle upload
- final store screenshots and listing completion
- closed testing verification on the production-like environment
