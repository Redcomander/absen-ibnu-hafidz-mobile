import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/network/offline_cache_store.dart';
import '../../core/network/sync_store.dart';

class CacheManagement {
  static bool isReport(String path) =>
      [
        '/attendance/history',
        '/attendance/statistics',
        '/attendance/teacher-statistics',
        '/halaqoh/statistics/students',
        '/halaqoh/statistics/teachers',
        '/halaqoh/history/students',
        '/halaqoh/history/teachers',
      ].contains(path.split('?').first) ||
      RegExp(r'^/students/\d+/progress(?:\?|$)').hasMatch(path);
  static Future<Map<String, int>> inspect(String account) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final prefix = 'offline_api_cache_v2::$account::';
    int bytes = 0, reports = 0, protected = 0;
    for (final key in prefs.getKeys().where((k) => k.startsWith(prefix))) {
      final raw = prefs.getString(key) ?? '';
      bytes += utf8.encode(raw).length;
      if (isReport(key.substring(prefix.length))) {
        reports++;
      } else {
        protected++;
      }
    }
    return {
      'bytes': bytes,
      'reports': reports,
      'protected': protected,
      'queue': (await SyncStore.instance.entries(
        account,
        includeBody: false,
      )).length,
    };
  }

  static Future<int> clearReports(
    String account, {
    required DateTime before,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final prefix = 'offline_api_cache_v2::$account::';
    int removed = 0;
    for (final key
        in prefs.getKeys().where((k) => k.startsWith(prefix)).toList()) {
      if (OfflineCacheStore.scope != account) break;
      if (!isReport(key.substring(prefix.length))) continue;
      try {
        final record = jsonDecode(prefs.getString(key) ?? '{}');
        final date = DateTime.tryParse('${record['saved_at']}');
        if (date != null && date.isBefore(before)) {
          await prefs.remove(key);
          removed++;
        }
      } catch (_) {
        /* Keep unknown or unreadable records. */
      }
    }
    return removed;
  }
}

class StorageScreen extends StatefulWidget {
  const StorageScreen({super.key});
  @override
  State<StorageScreen> createState() => _StorageScreenState();
}

class _StorageScreenState extends State<StorageScreen> {
  Map<String, int> _data = {};
  bool _busy = false;
  int _days = 30;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final owner = OfflineCacheStore.scope;
    try {
      final data = await CacheManagement.inspect(owner);
      if (mounted && owner == OfflineCacheStore.scope) {
        setState(() => _data = data);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Ukuran penyimpanan belum dapat dibaca.');
      }
    }
  }

  Future<void> _clear() async {
    final owner = OfflineCacheStore.scope;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bersihkan laporan lama?'),
        content: Text(
          'Hapus salinan laporan yang disimpan lebih dari $_days hari lalu. Jadwal, formulir, antrean, login dan preferensi tetap disimpan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Bersihkan'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted || owner != OfflineCacheStore.scope) return;
    setState(() => _busy = true);
    try {
      final count = await CacheManagement.clearReports(
        owner,
        before: DateTime.now().subtract(Duration(days: _days)),
      );
      if (mounted && owner == OfflineCacheStore.scope) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$count salinan laporan dibersihkan.')),
        );
        await _load();
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Pembersihan belum selesai. Data antrean tetap disimpan.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Penyimpanan offline')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (_error != null) Text(_error!),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cache API akun ini: ${((_data['bytes'] ?? 0) / 1024).toStringAsFixed(1)} KB',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  '${_data['reports'] ?? 0} salinan laporan • ${_data['protected'] ?? 0} salinan dilindungi',
                ),
                Text(
                  '${_data['queue'] ?? 0} pengiriman belum dikonfirmasi server (selalu dilindungi).',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Angka cache API tidak mencakup ukuran aplikasi dan seluruh database SQLite. Jadwal mingguan, data formulir dan antrean tidak dibersihkan lewat menu ini.',
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<int>(
          initialValue: _days,
          decoration: const InputDecoration(labelText: 'Umur cache laporan'),
          items: [
            for (final d in [7, 30, 90])
              DropdownMenuItem(value: d, child: Text('Lebih dari $d hari')),
          ],
          onChanged: _busy ? null : (v) => setState(() => _days = v ?? 30),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _busy ? null : _clear,
          icon: const Icon(Icons.cleaning_services_outlined),
          label: Text(_busy ? 'Membersihkan...' : 'Bersihkan laporan lama'),
        ),
      ],
    ),
  );
}
