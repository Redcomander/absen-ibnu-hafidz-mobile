import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_update_model.dart';
import 'app_update_service.dart';

class AppUpdateController extends ChangeNotifier {
  AppUpdateController({AppUpdateService? service})
    : service = service ?? AppUpdateService();
  final AppUpdateService service;
  InstalledApp? installed;
  AppUpdate? update;
  File? apk;
  bool checking = false,
      downloading = false,
      installing = false,
      dismissed = false,
      _disposed = false;
  double progress = 0;
  String? error, message;
  DateTime? _lastCheck;
  Future<void>? _inFlight;
  bool get mandatory =>
      update != null &&
      installed != null &&
      update!.mandatoryFor(installed!.code);
  bool get available =>
      update != null && installed != null && update!.newerThan(installed!.code);
  bool get visible => available && (mandatory || !dismissed);
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> check({bool manual = false}) {
    if (!service.supported) return Future.value();
    if (_inFlight != null) return _inFlight!;
    if (!manual &&
        _lastCheck != null &&
        DateTime.now().difference(_lastCheck!) < const Duration(minutes: 5)) {
      return Future.value();
    }
    return _inFlight = _check(manual).whenComplete(() => _inFlight = null);
  }

  Future<void> _check(bool manual) async {
    checking = true;
    error = null;
    message = null;
    _notify();
    try {
      installed = await service.installed();
      final prefs = await SharedPreferences.getInstance();
      if (update == null) {
        try {
          final raw = prefs.getString('verified_update_policy');
          if (raw != null) {
            final cached = AppUpdate.parse(
              Map<String, dynamic>.from(jsonDecode(raw) as Map),
            );
            if (cached.package == installed!.package) {
              if (cached.code > 0) service.validate(cached.url, download: true);
              update = cached;
            }
          }
        } catch (_) {
          /* Ignore malformed cached metadata. */
        }
      }
      if (update != null && !available) {
        update = null;
        apk = null;
        await prefs.remove('verified_update_policy');
        await service.cleanup();
      }
      await service.requireUpdate(mandatory);
      _notify();
      final result = await service.check(installed!);
      if (downloading && update?.code != result.code) {
        service.cancel();
      }
      if (update?.code != result.code) {
        apk = null;
        dismissed = false;
      }
      update = result;
      await prefs.setString(
        'verified_update_policy',
        jsonEncode(result.toJson()),
      );
      if (manual) dismissed = false;
      if (!available) {
        message = 'Aplikasi sudah menggunakan versi terbaru.';
        apk = null;
        await service.cleanup();
      }
      _lastCheck = DateTime.now();
    } catch (e) {
      error = 'Pemeriksaan pembaruan gagal. Periksa koneksi dan coba lagi.';
      _lastCheck = DateTime.now();
    } finally {
      checking = false;
      await service.requireUpdate(mandatory);
      _notify();
    }
  }

  Future<void> resume() async {
    // Always reread the installed build after returning from settings/installer.
    if (!service.supported) return;
    try {
      installed = await service.installed();
      if (!available) {
        update = null;
        apk = null;
        await service.requireUpdate(false);
        _notify();
      }
    } catch (_) {
      /* Keep a verified mandatory policy active. */
    }
    await check();
  }

  void dismiss() {
    if (!mandatory) {
      dismissed = true;
      service.cancel();
      _notify();
    }
  }

  void cancel() {
    service.cancel();
  }

  Future<void> download() async {
    if (downloading || checking || update == null) return;
    final release = update!;
    downloading = true;
    progress = 0;
    error = null;
    message = null;
    _notify();
    try {
      final downloaded = await service.download(release, (value) {
        progress = value;
        _notify();
      });
      if (update?.code == release.code && update?.sha256 == release.sha256) {
        apk = downloaded;
      } else {
        await downloaded.delete();
      }
    } on UpdateCancelled {
      message = 'Unduhan dibatalkan. Anda dapat mencoba lagi.';
    } on FileSystemException {
      error = 'APK gagal disimpan. Periksa ruang penyimpanan dan coba lagi.';
    } catch (e) {
      error = e is FormatException
          ? e.message.toString()
          : 'Unduhan gagal. Periksa koneksi dan coba lagi.';
    } finally {
      downloading = false;
      _notify();
    }
  }

  Future<void> install() async {
    if (installing || apk == null || update == null) return;
    installing = true;
    error = null;
    _notify();
    try {
      final status = await service.install(apk!, update!);
      message = status == 'permission_required'
          ? 'Izinkan pemasangan dari aplikasi ini, lalu tekan Pasang pembaruan lagi.'
          : 'Installer Android telah dibuka. Konfirmasi pemasangan; versi akan diperiksa kembali saat aplikasi dibuka.';
      if (status != 'permission_required' && status != 'opened') {
        throw StateError('Installer belum tersedia');
      }
    } catch (_) {
      error =
          'Installer belum dapat dibuka. Periksa izin, versi dan tanda tangan APK, lalu coba lagi.';
    } finally {
      installing = false;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    service.cancel();
    super.dispose();
  }
}
