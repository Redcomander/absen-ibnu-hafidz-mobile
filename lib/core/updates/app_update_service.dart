import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../config/app_config.dart';
import 'app_update_model.dart';

class UpdateCancelled implements Exception {}

class AppUpdateService {
  static const native = MethodChannel('ibnu_hafidz/app_updates');
  static const trusted = String.fromEnvironment(
    'APP_UPDATE_TRUSTED_HOSTS',
    defaultValue: 'ibnuhafidz.ponpes.id',
  );
  HttpClient? _downloadClient;
  bool _cancelled = false;
  final Set<String> hosts;
  final HttpClient Function() clientFactory;
  AppUpdateService({
    Set<String>? trustedHosts,
    HttpClient Function()? clientFactory,
  }) : clientFactory = clientFactory ?? HttpClient.new,
       hosts =
           trustedHosts ??
           trusted
               .split(',')
               .map((s) => s.trim().toLowerCase())
               .where((s) => s.isNotEmpty)
               .toSet();
  bool get supported => Platform.isAndroid;
  Uri validate(String value, {bool download = false}) {
    final u = Uri.parse(value);
    if (u.scheme != 'https' ||
        !hosts.contains(u.host.toLowerCase()) ||
        u.port != 443 ||
        u.userInfo.isNotEmpty ||
        u.fragment.isNotEmpty ||
        (download &&
            (!RegExp(r'^/api/app/download/[1-9][0-9]*$').hasMatch(u.path) ||
                u.hasQuery))) {
      throw const FormatException('Alamat pembaruan tidak dipercaya');
    }
    return u;
  }

  Future<InstalledApp> installed() async {
    final info = await PackageInfo.fromPlatform();
    final current = await native.invokeMapMethod<String, dynamic>('installed');
    return InstalledApp(
      current?['version']?.toString() ?? info.version,
      int.tryParse('${current?['code'] ?? info.buildNumber}') ?? 0,
      current?['package']?.toString() ?? info.packageName,
    );
  }

  Future<AppUpdate> check(InstalledApp app) async {
    final uri = validate(
      '${AppConfig.baseUrl}/api/app/version',
    ).replace(queryParameters: {'version_code': '${app.code}'});
    final client = clientFactory()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 12));
      request.followRedirects = false;
      request.headers.set('Cache-Control', 'no-cache');
      final response = await request.close().timeout(
        const Duration(seconds: 12),
      );
      if (response.statusCode != 200) {
        throw const HttpException('Server pembaruan belum tersedia');
      }
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 12))) {
        bytes.addAll(chunk);
        if (bytes.length > 65536) {
          throw const FormatException('Metadata terlalu besar');
        }
      }
      final update = AppUpdate.parse(
        Map<String, dynamic>.from(jsonDecode(utf8.decode(bytes)) as Map),
      );
      if (update.package != app.package) {
        throw const FormatException('Paket rilis tidak sesuai');
      }
      if (update.code > 0) validate(update.url, download: true);
      return update;
    } finally {
      client.close(force: true);
    }
  }

  Future<Directory> updateDirectory() async {
    final dir = Directory('${(await getTemporaryDirectory()).path}/updates');
    await dir.create(recursive: true);
    return dir;
  }

  Future<File> download(
    AppUpdate update,
    void Function(double) progress,
  ) async {
    if (_downloadClient != null) {
      throw StateError('Unduhan lain sedang berjalan');
    }
    _cancelled = false;
    final client = clientFactory()
      ..connectionTimeout = const Duration(seconds: 15);
    _downloadClient = client;
    File? partial;
    IOSink? sink;
    try {
      final dir = await updateDirectory();
      partial = File('${dir.path}/release-${update.code}.part');
      final request = await client
          .getUrl(validate(update.url, download: true))
          .timeout(const Duration(seconds: 20));
      request.followRedirects = false;
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      if (response.statusCode != 200 ||
          (response.headers.value(HttpHeaders.contentEncodingHeader) != null &&
              response.headers.value(HttpHeaders.contentEncodingHeader) !=
                  'identity')) {
        throw const HttpException('Server menolak unduhan APK');
      }
      if (response.contentLength != -1 &&
          response.contentLength != update.size) {
        throw const FormatException('Ukuran APK tidak sesuai');
      }
      sink = partial.openWrite();
      var received = 0;
      var last = DateTime.fromMillisecondsSinceEpoch(0);
      await for (final chunk in response.timeout(const Duration(seconds: 30))) {
        if (_cancelled) throw UpdateCancelled();
        received += chunk.length;
        if (received > update.size) {
          throw const FormatException('APK melebihi ukuran rilis');
        }
        sink.add(chunk);
        await sink.flush();
        final now = DateTime.now();
        if (now.difference(last).inMilliseconds >= 100) {
          last = now;
          progress(received / update.size);
        }
      }
      await sink.close();
      sink = null;
      if (_cancelled) throw UpdateCancelled();
      if (received != update.size) {
        throw const FormatException('Unduhan APK belum lengkap');
      }
      final hash = await sha256.bind(partial.openRead()).first;
      if (hash.toString() != update.sha256) {
        throw const FormatException('SHA-256 APK tidak cocok. Unduh ulang.');
      }
      final file = File('${dir.path}/release-${update.code}.apk');
      if (await file.exists()) await file.delete();
      await partial.rename(file.path);
      partial = null;
      progress(1);
      return file;
    } catch (e) {
      if (_cancelled) throw UpdateCancelled();
      rethrow;
    } finally {
      try {
        await sink?.close();
      } catch (_) {
        /* Retain the original download error. */
      }
      try {
        if (partial != null && await partial.exists()) await partial.delete();
      } catch (_) {
        /* Only a private incomplete temporary file remains. */
      }
      client.close(force: true);
      _downloadClient = null;
    }
  }

  void cancel() {
    _cancelled = true;
    _downloadClient?.close(force: true);
  }

  Future<String> install(File file, AppUpdate update) async =>
      await native.invokeMethod<String>('install', {
        'path': file.path,
        'version_code': update.code,
        'sha256': update.sha256,
      }) ??
      'failed';
  Future<void> requireUpdate(bool required) async {
    if (!supported) return;
    try {
      await native.invokeMethod<void>('required', required);
    } on PlatformException {
      /* Overlay remains enforced in Flutter. */
    } on MissingPluginException {
      /* Unsupported test host. */
    }
  }

  Future<void> cleanup() async {
    final dir = await updateDirectory();
    await for (final item in dir.list(followLinks: false)) {
      if (item is File &&
          RegExp(
            r'^release-[0-9]+\.(apk|part)$',
          ).hasMatch(item.uri.pathSegments.last)) {
        await item.delete();
      }
    }
  }
}
