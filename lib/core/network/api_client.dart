import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import 'offline_cache_store.dart';
import 'json_codec.dart';

typedef RefreshTokenCallback = Future<String?> Function();
typedef CanUseNetworkCallback = Future<bool> Function();
typedef QueueOfflineWriteCallback =
    Future<Map<String, dynamic>> Function(
      String path, {
      String? token,
      Object? body,
      required String encoding,
    });

class ApiException implements Exception {
  final int statusCode;
  final String message;
  final bool isServerProtection;

  ApiException(
    this.statusCode,
    this.message, {
    this.isServerProtection = false,
  });

  bool get isAuthenticationRejection =>
      !isServerProtection && (statusCode == 401 || statusCode == 403);

  @override
  String toString() => 'ApiException($statusCode): $message';
}

class DownloadedFile {
  final Uint8List bytes;
  final String? fileName;
  final String contentType;

  const DownloadedFile({
    required this.bytes,
    required this.fileName,
    required this.contentType,
  });
}

class ApiClient {
  static bool isConnectionError(Object error) =>
      error is http.ClientException || error is TimeoutException;
  static RefreshTokenCallback? refreshAuthToken;
  static CanUseNetworkCallback? canUseNetwork;
  static QueueOfflineWriteCallback? queueOfflineWrite;

  static String _url(String path) =>
      '${AppConfig.baseUrl}${AppConfig.apiPrefix}$path';

  static Future<Map<String, dynamic>> get(
    String path, {
    String? token,
    Map<String, String>? query,
    bool retryOnAuthError = true,
    bool useOfflineCache = true,
  }) async {
    final uri = Uri.parse(_url(path)).replace(queryParameters: query);
    final supportsOfflineCache =
        useOfflineCache && _supportsOfflineReadCache(path);
    final scope = OfflineCacheStore.scope;

    try {
      final response = await _requestWithAutoRefresh(
        token: token,
        retryOnAuthError: retryOnAuthError,
        request: (effectiveToken) =>
            http.get(uri, headers: _headers(token: effectiveToken)),
      );

      if (supportsOfflineCache) {
        if (OfflineCacheStore.scope != scope) {
          throw ApiException(409, 'Akun telah berubah. Muat ulang halaman.');
        }
        await OfflineCacheStore.write(
          path,
          response,
          query: query,
          account: scope,
        );
      }

      return response;
    } on ApiException {
      rethrow;
    } catch (error) {
      if (!isConnectionError(error)) rethrow;
      if (supportsOfflineCache) {
        final cached = await OfflineCacheStore.read(
          path,
          query: query,
          account: scope,
        );
        if (cached != null) {
          if (OfflineCacheStore.scope != scope) {
            throw ApiException(409, 'Akun telah berubah. Muat ulang halaman.');
          }
          return cached;
        }
      }
      rethrow;
    }
  }

  static Future<DownloadedFile> download(
    String path, {
    String? token,
    Map<String, String>? query,
    bool retryOnAuthError = true,
  }) async {
    final uri = Uri.parse(_url(path)).replace(queryParameters: query);
    final scope = OfflineCacheStore.scope;
    Future<http.Response> request(String? effectiveToken) => http.get(
      uri,
      headers: {
        'Accept': 'application/pdf,application/octet-stream,*/*',
        if (effectiveToken != null && effectiveToken.isNotEmpty)
          'Authorization': 'Bearer $effectiveToken',
      },
    );

    var response = await request(token);
    _checkServerProtection(response);

    if (response.statusCode == 401 &&
        retryOnAuthError &&
        token != null &&
        token.isNotEmpty &&
        refreshAuthToken != null) {
      if (OfflineCacheStore.scope != scope) {
        throw ApiException(409, 'Akun telah berubah. Muat ulang halaman.');
      }
      final refreshedToken = await refreshAuthToken!.call();
      if (OfflineCacheStore.scope != scope) {
        throw ApiException(409, 'Akun telah berubah. Muat ulang halaman.');
      }
      if (refreshedToken != null && refreshedToken.isNotEmpty) {
        response = await request(refreshedToken);
      }
    }

    _checkServerProtection(response);
    if (response.statusCode >= 400) {
      throw ApiException(response.statusCode, _parseErrorMessage(response));
    }

    return DownloadedFile(
      bytes: response.bodyBytes,
      fileName: extractFilenameFromDisposition(
        response.headers['content-disposition'],
      ),
      contentType:
          response.headers['content-type']?.split(';').first.trim() ??
          'application/octet-stream',
    );
  }

  static Future<Map<String, dynamic>> post(
    String path, {
    String? token,
    Object? body,
    Map<String, String>? headers,
    bool retryOnAuthError = true,
    bool queueOnOffline = true,
  }) async {
    final uri = Uri.parse(_url(path));
    final supportsOfflineQueue = _supportsOfflineQueue(path);

    if (queueOnOffline && supportsOfflineQueue && queueOfflineWrite != null) {
      return queueOfflineWrite!(
        path,
        token: token,
        body: body,
        encoding: 'json',
      );
    }

    final encodedBody = body == null ? null : await BackgroundJson.encode(body);
    try {
      return await _requestWithAutoRefresh(
        token: token,
        retryOnAuthError: retryOnAuthError,
        request: (effectiveToken) => http.post(
          uri,
          headers: _headers(token: effectiveToken, extraHeaders: headers),
          body: encodedBody,
        ),
      );
    } on ApiException {
      rethrow;
    } catch (error) {
      if (!isConnectionError(error)) rethrow;
      if (queueOnOffline && supportsOfflineQueue && queueOfflineWrite != null) {
        return queueOfflineWrite!(
          path,
          token: token,
          body: body,
          encoding: 'json',
        );
      }
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> put(
    String path, {
    required String token,
    required Object body,
  }) async {
    final encodedBody = await BackgroundJson.encode(body);
    return _requestWithAutoRefresh(
      token: token,
      retryOnAuthError: true,
      request: (effectiveToken) => http.put(
        Uri.parse(_url(path)),
        headers: _headers(token: effectiveToken),
        body: encodedBody,
      ),
    );
  }

  static Future<Map<String, dynamic>> delete(
    String path, {
    String? token,
    Object? body,
    Map<String, String>? headers,
    bool retryOnAuthError = true,
  }) async {
    final uri = Uri.parse(_url(path));

    return _requestWithAutoRefresh(
      token: token,
      retryOnAuthError: retryOnAuthError,
      request: (effectiveToken) => http.delete(
        uri,
        headers: _headers(token: effectiveToken, extraHeaders: headers),
        body: body == null ? null : jsonEncode(body),
      ),
    );
  }

  static Future<Map<String, dynamic>> postMultipart(
    String path, {
    String? token,
    Map<String, String>? fields,
    List<http.MultipartFile>? files,
    bool retryOnAuthError = true,
    bool queueOnOffline = true,
  }) async {
    final uri = Uri.parse(_url(path));
    final supportsOfflineQueue = _supportsOfflineQueue(path);

    if (queueOnOffline && supportsOfflineQueue && queueOfflineWrite != null) {
      if (files?.isNotEmpty == true) {
        throw ApiException(
          400,
          'Lampiran belum dapat disimpan offline. Kirim tanpa lampiran atau tunggu koneksi.',
        );
      }
      return queueOfflineWrite!(
        path,
        token: token,
        body: fields,
        encoding: 'multipart',
      );
    }

    Future<http.Response> sendRequest(String? effectiveToken) async {
      final request = http.MultipartRequest('POST', uri);
      request.headers.addAll(_multipartHeaders(token: effectiveToken));
      if (fields != null) {
        request.fields.addAll(fields);
      }
      if (files != null && files.isNotEmpty) {
        request.files.addAll(files);
      }
      final streamed = await request.send();
      return http.Response.fromStream(streamed);
    }

    try {
      return await _requestWithAutoRefresh(
        token: token,
        retryOnAuthError: retryOnAuthError,
        request: sendRequest,
      );
    } on ApiException {
      rethrow;
    } catch (error) {
      if (!isConnectionError(error)) rethrow;
      if (queueOnOffline && supportsOfflineQueue && queueOfflineWrite != null) {
        if (files?.isNotEmpty == true) rethrow;
        return queueOfflineWrite!(
          path,
          token: token,
          body: fields,
          encoding: 'multipart',
        );
      }
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> _requestWithAutoRefresh({
    required Future<http.Response> Function(String? effectiveToken) request,
    required String? token,
    required bool retryOnAuthError,
  }) async {
    final scope = OfflineCacheStore.scope;
    final response = await request(token).timeout(const Duration(seconds: 20));
    _checkServerProtection(response);

    if (response.statusCode == 401 &&
        retryOnAuthError &&
        token != null &&
        token.isNotEmpty &&
        refreshAuthToken != null) {
      if (OfflineCacheStore.scope != scope) {
        throw ApiException(409, 'Akun telah berubah. Muat ulang halaman.');
      }
      final refreshedToken = await refreshAuthToken!.call();
      if (OfflineCacheStore.scope != scope) {
        throw ApiException(409, 'Akun telah berubah. Muat ulang halaman.');
      }
      if (refreshedToken != null && refreshedToken.isNotEmpty) {
        final retryResponse = await request(
          refreshedToken,
        ).timeout(const Duration(seconds: 20));
        return _parse(retryResponse);
      }
    }

    return _parse(response);
  }

  static Map<String, String> _headers({
    String? token,
    Map<String, String>? extraHeaders,
  }) {
    return {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      ...?extraHeaders,
    };
  }

  static Map<String, String> _multipartHeaders({String? token}) {
    return {
      'Accept': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  static bool _supportsOfflineQueue(String path) {
    return path == '/attendance' ||
        path == '/attendance/teacher' ||
        path == '/attendance/substitute' ||
        path.startsWith('/halaqoh/attendance') ||
        path.startsWith('/halaqoh/teacher-attendance');
  }

  static bool _supportsOfflineReadCache(String path) {
    return RegExp(
          r'^/halaqoh/(attendance|teacher-attendance)/\d+$',
        ).hasMatch(path) ||
        path == '/dashboard/stats' ||
        RegExp(r'^/students/\d+/progress$').hasMatch(path) ||
        path == '/schedules' ||
        path == '/attendance' ||
        path == '/attendance/history' ||
        path == '/attendance/statistics' ||
        path == '/attendance/teacher-statistics' ||
        path == '/attendance/assignable-teachers' ||
        path == '/halaqoh/assignments' ||
        path == '/halaqoh/statistics/students' ||
        path == '/halaqoh/statistics/teachers' ||
        path == '/halaqoh/history/students' ||
        path == '/halaqoh/history/teachers';
  }

  static String? extractFilenameFromDisposition(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;

    for (final part in raw.split(';')) {
      final trimmed = part.trim();
      final lower = trimmed.toLowerCase();

      if (lower.startsWith('filename*=')) {
        final value = trimmed.substring(trimmed.indexOf('=') + 1).trim();
        final normalized = value.contains("''")
            ? value.split("''").last
            : value;
        return Uri.decodeComponent(normalized.replaceAll('"', ''));
      }

      if (lower.startsWith('filename=')) {
        return trimmed
            .substring(trimmed.indexOf('=') + 1)
            .trim()
            .replaceAll('"', '');
      }
    }

    return null;
  }

  static String _parseErrorMessage(http.Response response) {
    try {
      if (response.body.isNotEmpty) {
        final raw = _normalizeJson(jsonDecode(response.body));
        if (raw is Map<String, dynamic>) {
          return raw['message']?.toString() ??
              raw['error']?.toString() ??
              'Request failed';
        }
      }
    } catch (_) {
      // Ignore invalid JSON bodies for binary downloads.
    }

    return 'Request failed';
  }

  // Inspect only a bounded prefix. A backend JSON permission denial remains a
  // permission denial; only an explicit hosting protection response is retryable.
  static void _checkServerProtection(http.Response response) {
    final bytes = response.bodyBytes;
    final prefix = utf8
        .decode(bytes.take(32768).toList(), allowMalformed: true)
        .toLowerCase();
    final html =
        prefix.trimLeft().startsWith('<') ||
        (response.headers['content-type'] ?? '').contains('text/html');
    final browserChallenge =
        html &&
        prefix.contains('<title>one moment, please...</title>') &&
        prefix.contains('please wait while your request is being verified') &&
        prefix.contains('window.location.reload');
    if (browserChallenge ||
        ((html || response.statusCode >= 400) &&
            (prefix.contains('imunify360') || prefix.contains('imunify.com')) &&
            (prefix.contains('bot-protection') ||
                prefix.contains('bot protection') ||
                prefix.contains('access denied') ||
                prefix.contains('challenge') ||
                prefix.contains('captcha') ||
                prefix.contains('request is being verified')))) {
      throw ApiException(
        response.statusCode,
        'Akses API diblokir Imunify360 pada hosting. Hubungi admin untuk '
        'mengizinkan API aplikasi tanpa verifikasi browser. '
        'Data tersimpan tetap aman; coba sinkronisasi lagi setelah diperbaiki.',
        isServerProtection: true,
      );
    }
  }

  static Future<Map<String, dynamic>> _parse(http.Response response) async {
    _checkServerProtection(response);
    // Preserve HTTP errors even when a proxy returns HTML instead of JSON.
    if (response.statusCode >= 400) {
      final fallback = response.statusCode >= 500
          ? 'Server API bermasalah (HTTP ${response.statusCode}). Coba lagi nanti.'
          : 'Permintaan gagal (HTTP ${response.statusCode}).';
      final message = _parseErrorMessage(response);
      throw ApiException(
        response.statusCode,
        message == 'Request failed' ? fallback : message,
      );
    }
    Map<String, dynamic> data = {};

    if (response.body.isNotEmpty) {
      dynamic raw;
      try {
        raw = await BackgroundJson.decode(response.body);
      } on FormatException {
        throw ApiException(
          502,
          'Respons API bukan JSON. Periksa koneksi backend pada server.',
        );
      }

      if (raw is Map<String, dynamic>) {
        data = raw;
      } else if (raw is List) {
        data = {'data': raw};
      } else {
        data = {'data': raw};
      }
    }

    final setCookie = response.headers['set-cookie'];
    if (setCookie != null && setCookie.isNotEmpty) {
      data['__set_cookie'] = setCookie;
    }

    return data;
  }

  static dynamic _normalizeJson(dynamic value) {
    if (value is Map) {
      return value.map(
        (key, nestedValue) =>
            MapEntry(key.toString(), _normalizeJson(nestedValue)),
      );
    }

    if (value is List) {
      return value.map(_normalizeJson).toList();
    }

    return value;
  }
}
