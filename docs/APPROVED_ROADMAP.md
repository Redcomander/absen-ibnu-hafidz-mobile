# Progres fitur yang disetujui — build 11

Pilihan: 1 (mengikuti dashboard pengguna web), 2, 5, 10, 11, 12, 13, 14, 15.

| Tahap | Pekerjaan | Status |
| --- | --- | --- |
| 1 | Dashboard pengguna dan persetujuan Halaqoh | Selesai, diuji |
| 2 | Profil santri, indikator Alpha, filter tersimpan | Selesai, diuji; API baru perlu deploy |
| 3 | Bantuan, kunci perangkat, aksesibilitas, pengelolaan cache | Selesai, diuji |
| 4 | Pengujian dan APK build 11 | Selesai |

## Fitur dan lokasi

1. **Beranda / Ringkasan saya:** memakai `/dashboard/stats`, sama dengan Vue.
   Ada periode bulanan, ringkasan kehadiran pribadi Formal/Diniyyah/Halaqoh,
   jadwal hari ini dan riwayat tugas pengganti. Jadwal Ramadhan mengikuti flag
   server. Memerlukan izin `dashboard.view`, sesuai frontend web.
2. **Beranda / Persetujuan Halaqoh:** admin/super_admin dapat meninjau anggota
   sebelumnya dan yang diajukan. Persetujuan perpindahan santri meminta konfirmasi;
   penolakan wajib menyertakan alasan. Hanya online, memakai aturan server yang ada.
5. **Beranda / Profil & perkembangan santri:** pencarian dengan pagination,
   profil minimal, periode 30/90/365 hari, tren kehadiran bulanan dan 30 catatan
   terakhir. Memerlukan `students.view`; setiap modul mengikuti izin rekapan
   masing-masing. Setelah berhasil dibuka online, respons dapat dibaca offline.
10. **Santri / Perlu tindak lanjut:** minimal tiga catatan Alpha dalam 30 hari
    terakhir pada modul yang dipilih. Tidak menyimpulkan pelanggaran, dan tidak
    menganggap sesi yang belum diabsen sebagai Alpha.
11. **Rekapan / Simpan filter saat ini:** maksimal sepuluh filter bernama per
    laporan dan akun/perangkat. Menyimpan periode, guru, kelas, gender dan
    pencarian yang berlaku. Absensi dan Halaqoh memiliki kumpulan filter terpisah.
12. **Pengaturan / Pusat bantuan:** panduan dapat dicari. Pengguna bisa menyalin
    format laporan masalah untuk dilengkapi dan dikirim sendiri kepada admin.
13. **Pengaturan / Kunci biometrik / PIN perangkat:** verifikasi diperlukan
    untuk mengaktifkan dan menonaktifkan. Aplikasi terkunci saat masuk latar
    belakang, termasuk halaman detail yang terbuka. Android 10+ memakai prompt
    biometrik/credential; Android lebih lama memakai PIN/pola perangkat.
    Membatalkan autentikasi tetap mempertahankan kunci dan data halaman.
14. **Pengaturan:** tambahan ukuran teks 100–150% di atas skala sistem dan tema
    kontras tinggi. Preferensi disimpan per akun pada perangkat ini.
15. **Pengaturan / Penyimpanan offline:** ukuran cache API, jumlah salinan dan
    antrean. Pembersihan memerlukan konfirmasi dan hanya menghapus cache laporan
    lebih tua dari 7/30/90 hari. Jadwal, formulir, antrean SQLite, login dan
    preferensi tetap disimpan. Ukuran cache bukan ukuran total aplikasi/SQLite.

## Pengujian

- Suíte lengkap Flutter: 78 tes lulus. Satu tes tambahan alur persetujuan juga
  lulus; total 79 tes tersedia. Ketujuh tes baru lulus.
- Analisis Flutter bersih.
- `go test ./...` lulus, termasuk pembatasan periode, izin modul, hitungan Alpha,
  dan pembuktian endpoint baca tidak mengubah catatan.
- Tes cache melindungi antrean, jadwal, formulir, laporan baru dan akun lain.
- Tes kunci mencakup halaman detail, pembatalan autentikasi dan pemulihan halaman.
- APK Android berhasil dibangun. Identitas aplikasi dan sertifikat sama dengan
  versi sebelumnya, sehingga dapat dipasang sebagai pembaruan tanpa uninstall.
- Biometrik sungguhan tetap perlu dicoba di ponsel yang sudah memiliki PIN/pola.

## Backend yang perlu dipublikasikan

Dua endpoint tambahan hanya membaca data:

- `GET /api/students/:id/progress?start_date=YYYY-MM-DD&end_date=YYYY-MM-DD`
- `GET /api/students/attendance-signals?module=Formal&page=1`

Deploy backend workspace ini untuk mengaktifkan profil perkembangan dan indikator
Alpha di hosting. Tanpa backend terbaru, aplikasi menjelaskan bahwa pembaruan
server diperlukan. Dashboard dan persetujuan memakai endpoint yang sudah ada.
Tidak ada migrasi database, penghapusan atau penulisan ulang catatan lama.
Pertahankan konfigurasi dan data server saat mengganti binari dan me-restart
proses dengan mekanisme deployment yang biasa. Commit dan push dilakukan setelah implementasi. Deployment hosting belum dilakukan.

## Berkas utama

- [Dashboard](../lib/features/home/user_dashboard.dart)
- [Persetujuan](../lib/features/halaqoh/review_screen.dart)
- [Profil](../lib/features/students/students_screen.dart)
- [Preferensi](../lib/features/settings/user_preferences.dart)
- [Penyimpanan](../lib/features/settings/storage_screen.dart)
- [Tes fitur baru](../test/features/improvements/approved_features_test.dart)


## Progres selanjutnya

1. Deploy backend terbaru dari `main` dengan konfigurasi dan database yang sama.
   Tidak ada migrasi database untuk pembaruan ini.
2. Uji endpoint profil/perkembangan dan indikator Alpha dengan akun berizin;
   pastikan akun tanpa izin tetap ditolak dan catatan yang tampil sesuai web.
3. Pasang APK build 11 sebagai pembaruan tanpa menghapus aplikasi lama.
4. Uji dashboard dengan akun guru dan admin serta periode yang berbeda.
5. Uji persetujuan/penolakan Halaqoh, termasuk perpindahan santri dan alasan
   penolakan. Cocokkan hasil akhirnya dengan web.
6. Di ponsel, uji biometrik/PIN: aktifkan, batalkan, buka kembali, dan pindahkan
   aplikasi ke latar belakang dari halaman detail. Pastikan keadaan tetap terkunci
   ketika autentikasi gagal.
7. Uji aksesibilitas dengan ukuran teks sistem besar, tambahan skala aplikasi,
   dan kontras tinggi pada formulir serta laporan.
8. Siapkan jadwal online, buat absensi offline, bersihkan cache laporan lama,
   lalu sambungkan jaringan dan pastikan server mengonfirmasi pengiriman.
9. Catat temuan melalui format laporan di Pusat bantuan; perbaiki hasil uji
   lapangan sebelum distribusi lebih luas.
