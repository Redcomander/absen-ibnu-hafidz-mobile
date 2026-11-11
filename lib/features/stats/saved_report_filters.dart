import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/network/offline_cache_store.dart';
import '../../core/theme/text_prompt.dart';

class SavedReportFilters extends StatefulWidget {
  const SavedReportFilters({
    super.key,
    required this.report,
    required this.capture,
    required this.apply,
  });
  final String report;
  final Map<String, dynamic> Function() capture;
  final void Function(Map<String, dynamic>) apply;
  @override
  State<SavedReportFilters> createState() => _SavedReportFiltersState();
}

class _SavedReportFiltersState extends State<SavedReportFilters> {
  List<Map<String, dynamic>> _views = [];
  bool _busy = false;
  String get _key =>
      'saved_reports::${OfflineCacheStore.scope}::${widget.report}';
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final key = _key;
    final prefs = await SharedPreferences.getInstance();
    try {
      final rows = jsonDecode(prefs.getString(key) ?? '[]');
      if (mounted && key == _key) {
        setState(
          () => _views = (rows as List)
              .whereType<Map>()
              .map((x) => Map<String, dynamic>.from(x))
              .toList(),
        );
      }
    } catch (_) {
      /* Preserve unreadable preferences until user explicitly saves. */
    }
  }

  Future<void> _save() async {
    if (_busy) return;
    final key = _key;
    final label = await showDialog<String>(
      context: context,
      builder: (_) => const TextPromptDialog(
        title: 'Simpan filter laporan',
        confirmLabel: 'Simpan',
        label: 'Nama filter',
      ),
    );
    if (label == null || label.isEmpty || !mounted || key != _key) return;
    if (_views.length >= 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Maksimal 10 filter. Hapus salah satu untuk menambahkan.',
          ),
        ),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final next = [
        ..._views,
        {'name': label, 'filters': widget.capture()},
      ];
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, jsonEncode(next));
      if (mounted && key == _key) setState(() => _views = next);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(int index) async {
    final key = _key;
    final next = [..._views]..removeAt(index);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(next));
    if (mounted && key == _key) setState(() => _views = next);
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      TextButton.icon(
        onPressed: _busy ? null : _save,
        icon: const Icon(Icons.bookmark_add_outlined),
        label: const Text('Simpan filter saat ini'),
      ),
      if (_views.isNotEmpty)
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < _views.length; i++)
              InputChip(
                label: Text('${_views[i]['name']}'),
                onPressed: () => widget.apply(
                  Map<String, dynamic>.from(_views[i]['filters'] as Map),
                ),
                onDeleted: () => _delete(i),
                deleteButtonTooltipMessage: 'Hapus filter tersimpan',
              ),
          ],
        ),
    ],
  );
}
