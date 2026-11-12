# Pembaruan APK dari dalam aplikasi

## Rilis 1.0.2 (build 14)

Kode setelah build 14: kartu halaqoh milik pengguna menyediakan tombol terpisah
Tambah Santri / Hapus Santri. Keduanya mengirim pengajuan untuk persetujuan admin,
bukan mengubah anggota secara langsung. Perubahan ini memerlukan APK berikutnya;
APK build 14 yang sudah dibuat belum memuat tombol terpisah tersebut.

- Rekapan sakit, izin, dan alpha menampilkan jumlah santri, frekuensi per nama,
  serta pencarian terpisah untuk setiap status.
- Profil perkembangan menampilkan grafik komposisi, tren bulanan interaktif,
  filter modul, dan filter catatan terbaru.
- Peringkat alpha, izin, dan sakit mengikuti modul serta periode yang dipilih.
- Beranda diperbarui dengan tema hijau–emas dan animasi pembuka ringan.
- Analisis Flutter bersih dan 99 tes otomatis lulus sebelum build.

Deploy backend minimal commit `c88c472` agar peringkat per status dan frekuensi
halaqoh tersedia. Tidak memerlukan migrasi database. Gunakan sertifikat yang
sama dengan build 13, unggah sebagai draft dan uji pembaruan opsional pada
ponsel tanpa uninstall untuk memeriksa akun, jadwal offline, serta antrean lokal.

## Rilis 1.0.1 (build 13)

- Persetujuan halaqoh menampilkan perubahan jumlah anggota, santri yang masuk
  dan keluar, serta peringatan perpindahan dari guru lain. Rincian lengkap dapat
  dibuka sebelum mengambil keputusan. Perhitungan mengikuti jenis pengajuan:
  tambah, ganti daftar, hapus satu, atau hapus semua.
- Form absensi santri dan guru memakai header hijau, pilihan status berikon,
  serta ringkasan jumlah hadir/izin/sakit/alpa. Berlaku pada pelajaran dan halaqoh.
- Kartu jadwal hari ini di dashboard membuka modul dan kartu jadwal yang dipilih
  di bagian atas, termasuk saat memakai salinan jadwal offline.
- Filter periode dashboard memakai nama bulan Indonesia, misalnya November/2026.
- Analisis Flutter bersih dan 94 tes otomatis lulus. Pengujian instalasi langsung
  dari build 12 ke 13 pada ponsel tetap diperlukan setelah publikasi opsional.

Catatan rilis untuk dashboard web:

> Tampilan persetujuan halaqoh dan form absensi diperbarui. Perubahan anggota
> lebih mudah ditinjau, status absensi lebih jelas, dan kartu jadwal hari ini
> langsung membuka jadwal terkait. Filter dashboard menggunakan bulan/tahun.

Unggah APK build 13 sebagai draft, periksa versi 1.0.1, lalu publikasikan dengan
minimum versi 0 untuk uji pembaruan opsional pada satu ponsel sebelum distribusi
lebih luas. Pastikan akun, jadwal offline dan antrean absensi tetap tersedia
setelah pemasangan tanpa uninstall.

## Instalasi awal

Updater ada mulai build 12. Build 11 dan sebelumnya perlu diperbarui secara
manual satu kali tanpa menghapus aplikasi/data. Rilis berikutnya dapat dikelola
oleh Super Admin dari web.

## Modul

- `lib/core/updates/app_update_model.dart`: metadata dan kebijakan versionCode.
- `lib/core/updates/app_update_service.dart`: HTTPS allowlist, streaming unduhan,
  pembatalan, batas ukuran, SHA-256, penyimpanan cache dan komunikasi Android.
- `lib/core/updates/app_update_controller.dart`: deduplikasi, throttle lima menit,
  kebijakan mandatory yang disimpan, lifecycle dan status unduh/installer.
- `lib/core/updates/update_gate.dart`: UI Indonesia, opsional/wajib dan tombol
  Periksa Pembaruan pada Pengaturan. Tidak mengganti autentikasi/offline queue.
- `AppUpdateInstaller.kt`: PackageManager, signer/build/hash yang cocok,
  FileProvider terbatas dan installer OS. Membuka installer bukan bukti berhasil.

`package_info_plus` 8.3.1 dipilih untuk AGP 8.11.1 yang sudah ada. Versi 9/10
memerlukan AGP >=8.12.1. `crypto` menangani SHA-256; tidak memakai penyimpanan
umum, root atau instalasi diam-diam.

## Build

Pilih key yang sama dengan instalasi lama melalui `IBNU_KEYSTORE_PATH`,
`IBNU_KEYSTORE_PASSWORD`, `IBNU_KEY_ALIAS`, `IBNU_KEY_PASSWORD`. Jangan commit
file key atau nilainya. Build release tanpa pilihan key eksplisit ditolak.

```sh
flutter pub get
flutter build apk --release --build-name=1.1.0 --build-number=13 \
  --dart-define=APP_BASE_URL=https://ibnuhafidz.ponpes.id \
  --dart-define=APP_UPDATE_TRUSTED_HOSTS=ibnuhafidz.ponpes.id
```

Gunakan `build/app/outputs/apk/release/app-release.apk` untuk diunggah.
APK debug/profile debuggable ditolak backend. APK bootstrap kompatibilitas
mempertahankan key historis workspace, bukan key produksi baru. Jangan mengganti
sertifikat tanpa rencana migrasi/rotasi Android yang terpisah.

## Pengujian

Suite Flutter: 90 tes lulus, termasuk 11 tes pembaruan. Uji perangkat nyata tetap
mencakup izin pemasangan, tombol back pada mandatory, pembatalan installer dan
pemeriksaan data/antrean setelah upgrade. Gunakan 12 → 13 untuk perangkat pengguna
saat ini. Contoh 1.0.0+1 → 1.1.0+2 hanya untuk perangkat uji bersih dengan kode
updater di kedua APK dan key yang sama.

Panduan backend, migrasi 002, cPanel, kebijakan minimum dan checklist lengkap
tersedia pada repository backend: `MOBILE_APP_RELEASES.md`.
