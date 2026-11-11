import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../settings/app_settings_controller.dart';

class HelpScreen extends StatefulWidget {
  const HelpScreen({super.key});
  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> {
  String _search = '';
  static const articles = {
    'Menyiapkan jadwal offline':
        'Buka Jadwal saat terhubung internet. Jadwal mingguan disimpan pada perangkat akun ini. Tunggu persiapan formulir selesai, lalu buka kelas yang akan diabsen agar daftar santrinya tersedia. Jadwal baru di server belum muncul sebelum berhasil diunduh.',
    'Mengisi absensi tanpa internet':
        'Isi dan simpan absensi seperti biasa. Keterangan antrean berarti data masih di perangkat dan belum dikonfirmasi server. Jangan hapus aplikasi atau data perangkat sebelum antrean kosong.',
    'Data belum terkirim':
        'Buka Pengaturan untuk melihat antrean, alasan kegagalan, dan konfirmasi terakhir. Periksa preferensi Wi-Fi/data dan tekan Sinkronkan sekarang. Data gagal tetap disimpan; penolakan izin atau batas waktu perlu ditinjau admin.',
    'Mengubah anggota Halaqoh':
        'Guru pengampu dapat mengajukan tambah/hapus anggota dari halaman Halaqoh. Anggota baru berlaku setelah admin menyetujui. Pengajuan dan peninjauan memerlukan internet.',
    'Memahami indikator kehadiran':
        'Indikator tindak lanjut menandai minimal tiga catatan Alpha selama 30 hari terakhir pada modul yang dipilih. Periksa tanggal, catatan guru, dan keadaan santri. Sesi yang belum diabsen tidak otomatis dianggap Alpha.',
    'Menyimpan filter rekapan':
        'Pilih periode, modul, guru/kelas dan pencarian. Tekan Simpan filter saat ini, lalu beri nama. Tekan nama filter untuk menerapkan ulang. Preferensi hanya untuk akun ini pada perangkat ini.',
    'Notifikasi tidak muncul':
        'Aktifkan pengingat jadwal, izinkan notifikasi dan alarm tepat waktu di Pengaturan. Periksa juga pengaturan baterai Android. Buka jadwal online setelah ada perubahan penugasan.',
    'Kunci biometrik atau PIN':
        'Aktifkan PIN/pola atau biometrik di pengaturan perangkat dahulu. Aplikasi meminta verifikasi saat mengaktifkan atau menonaktifkan kunci. Setelah aplikasi masuk latar belakang, buka kembali dengan autentikasi perangkat.',
    'Teks lebih besar dan kontras':
        'Buka Pengaturan, pilih ukuran teks dan Kontras tinggi. Skala aplikasi ditambahkan ke ukuran teks sistem; data dan preferensi akun lain tidak berubah.',
    'Membersihkan cache dengan aman':
        'Menu penyimpanan hanya membersihkan cache laporan lama. Jadwal, formulir absensi, antrean pengiriman, sesi login, dan filter tersimpan tetap dipertahankan.',
  };
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Pusat bantuan')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        TextField(
          decoration: const InputDecoration(
            labelText: 'Cari panduan',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (v) => setState(() => _search = v.toLowerCase()),
        ),
        const SizedBox(height: 16),
        for (final item in articles.entries.where(
          (e) => '${e.key} ${e.value}'.toLowerCase().contains(_search),
        ))
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ExpansionTile(
              title: Text(item.key),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              children: [Text(item.value)],
            ),
          ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () async {
            final settings = context.read<AppSettingsController>();
            await Clipboard.setData(
              ClipboardData(
                text:
                    'Laporan masalah Ibnu Hafidz\nVersi: 1.0.0+11\nKoneksi: ${settings.connectionLabel}\nAntrean belum dikonfirmasi: ${settings.pendingSyncCount}\nWaktu: ${DateTime.now().toIso8601String()}\nLangkah kejadian:\nHasil yang diharapkan:\nHasil yang terjadi:',
              ),
            );
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Format laporan disalin. Lengkapi lalu kirim ke admin.',
                  ),
                ),
              );
            }
          },
          icon: const Icon(Icons.copy_outlined),
          label: const Text('Salin format laporan masalah'),
        ),
      ],
    ),
  );
}
