import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/access/access.dart';
import '../../core/network/api_client.dart';
import '../auth/auth_controller.dart';
import '../../core/theme/text_prompt.dart';
import '../../core/theme/attendance_widgets.dart';
import 'request_review_card.dart';

class HalaqohReviewScreen extends StatefulWidget {
  const HalaqohReviewScreen({super.key});
  @override
  State<HalaqohReviewScreen> createState() => _HalaqohReviewScreenState();
}

class _HalaqohReviewScreenState extends State<HalaqohReviewScreen> {
  List<Map<String, dynamic>> _requests = [];
  bool _loading = true, _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final auth = context.read<AuthController>();
    if (!canReviewHalaqoh(auth.user)) {
      setState(() {
        _loading = false;
        _error = 'Hanya admin yang dapat meninjau pengajuan.';
      });
      return;
    }
    final owner = auth.user?['id'];
    setState(() => _loading = true);
    try {
      final data = await ApiClient.get(
        '/halaqoh/assignment-change-requests',
        token: auth.token,
        useOfflineCache: false,
      );
      if (mounted && auth.user?['id'] == owner) {
        setState(() {
          _requests = listValue(data['data']);
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _review(Map<String, dynamic> request, bool approve) async {
    if (_busy || !canReviewHalaqoh(context.read<AuthController>().user)) return;
    final owner = context.read<AuthController>().user?['id'];
    final owners = mapValue(request['student_owner_snapshot']);
    final transfers = (request['student_ids'] as List? ?? [])
        .where(
          (id) =>
              owners['$id'] != null &&
              '${owners['$id']}' != '0' &&
              '${owners['$id']}' !=
                  '${request['target_teacher_id'] ?? request['teacher_id']}',
        )
        .toList();
    final text = await showDialog<String>(
      context: context,
      builder: (_) => TextPromptDialog(
        title: approve ? 'Setujui perubahan anggota?' : 'Tolak pengajuan?',
        confirmLabel: approve ? 'Setujui' : 'Tolak',
        label: approve ? null : 'Alasan penolakan (wajib)',
        maxLength: 1000,
        message: approve
            ? 'Perubahan diterapkan setelah server mengonfirmasi.${transfers.isNotEmpty ? " Perhatian: ${transfers.length} santri akan dipindahkan dari Halaqoh guru lain. Periksa daftar anggota sebelum melanjutkan." : ""}'
            : 'Alasan akan terlihat oleh guru pengaju.',
      ),
    );
    if (text == null ||
        !mounted ||
        context.read<AuthController>().user?['id'] != owner ||
        !canReviewHalaqoh(context.read<AuthController>().user)) {
      return;
    }
    setState(() => _busy = true);
    try {
      await ApiClient.post(
        '/halaqoh/assignment-change-requests/${request['id']}/${approve ? 'approve' : 'reject'}',
        token: context.read<AuthController>().token,
        body: approve
            ? {'confirm_transfers': transfers.isNotEmpty}
            : {'reason': text},
        queueOnOffline: false,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              approve ? 'Pengajuan disetujui.' : 'Pengajuan ditolak.',
            ),
          ),
        );
        await _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e is ApiException ? e.message : errorMessage(e)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Persetujuan Halaqoh')),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.all(16),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                AttendanceHeading(
                  title: 'Tinjau perubahan anggota',
                  subtitle:
                      '${_requests.where((r) => r['status'] == 'pending').length} pengajuan menunggu keputusan.\nAnggota berubah hanya setelah Anda menyetujui. Peninjauan memerlukan internet.',
                  icon: Icons.rule_rounded,
                ),
                const SizedBox(height: 16),
                if (_error != null) Text(_error!),
                if (_requests.isEmpty && _error == null)
                  const Text('Belum ada pengajuan.'),
                for (final r in _requests)
                  HalaqohRequestCard(
                    request: r,
                    busy: _busy,
                    onReview: (approve) => _review(r, approve),
                  ),
              ],
            ),
          ),
  );
}
