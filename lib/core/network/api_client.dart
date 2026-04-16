import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import 'offline_cache_store.dart';

typedef RefreshTokenCallback = Future<String?> Function();
typedef CanUseNetworkCallback = Future<bool> Function();
typedef QueueOfflineWriteCallback = Future<Map<String, dynamic>> Function(
  String path, {
  String? token,
  Object? body,
});

class ApiException implements Exception {
  final int statusCode;
  final String message;

  ApiException(this.statusCode, this.message);

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
  }) async {
    final uri = Uri.parse(_url(path)).replace(queryParameters: query);
    final supportsOfflineCache = _supportsOfflineReadCache(path);

    try {
      final response = await _requestWithAutoRefresh(
        token: token,
        retryOnAuthError: retryOnAuthError,
        request: (effectiveToken) => http.get(
          uri,
          headers: _headers(token: effectiveToken),
        ),
      );

      if (supportsOfflineCache) {
        await OfflineCacheStore.write(path, response, query: query);
      }

      return response;
    } on ApiException {
      rethrow;
    } catch (_) {
      if (supportsOfflineCache) {
        final cached = await OfflineCacheStore.read(path, query: query);
        if (cached != null) {
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

    Future<http.Response> request(String? effectiveToken) => http.get(
          uri,
          headers: {
            'Accept': 'application/pdf,application/octet-stream,*/*',
            if (effectiveToken != null && effectiveToken.isNotEmpty)
              'Authorization': 'Bearer $effectiveToken',
          },
        );

    var response = await request(token);

    if (response.statusCode == 401 &&
        retryOnAuthError &&
        token != null &&
        token.isNotEmpty &&
        refreshAuthToken != null) {
      final refreshedToken = await refreshAuthToken!.call();
      if (refreshedToken != null && refreshedToken.isNotEmpty) {
        response = await request(refreshedToken);
      }
    }

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

    if (queueOnOffline && supportsOfflineQueue && canUseNetwork != null) {
      final allowed = await canUseNetwork!.call();
      if (!allowed && queueOfflineWrite != null) {
        return queueOfflineWrite!(path, token: token, body: body);
      }
    }

    try {
      return await _requestWithAutoRefresh(
        token: token,
        retryOnAuthError: retryOnAuthError,
        request: (effectiveToken) => http.post(
          uri,
          headers: _headers(token: effectiveToken, extraHeaders: headers),
          body: body == null ? null : jsonEncode(body),
        ),
      );
    } on ApiException {
      rethrow;
    } catch (_) {
      if (queueOnOffline && supportsOfflineQueue && queueOfflineWrite != null) {
        return queueOfflineWrite!(path, token: token, body: body);
      }
      rethrow;
    }
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

    if (queueOnOffline && supportsOfflineQueue && canUseNetwork != null) {
      final allowed = await canUseNetwork!.call();
      if (!allowed && queueOfflineWrite != null) {
        return queueOfflineWrite!(path, token: token, body: fields);
      }
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
    } catch (_) {
      if (queueOnOffline && supportsOfflineQueue && queueOfflineWrite != null) {
        return queueOfflineWrite!(path, token: token, body: fields);
      }
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> _requestWithAutoRefresh({
    required Future<http.Response> Function(String? effectiveToken) request,
    required String? token,
    required bool retryOnAuthError,
  }) async {
    final response = await request(token);

    if (response.statusCode == 401 &&
        retryOnAuthError &&
        token != null &&
        token.isNotEmpty &&
        refreshAuthToken != null) {
      final refreshedToken = await refreshAuthToken!.call();
      if (refreshedToken != null && refreshedToken.isNotEmpty) {
        final retryResponse = await request(refreshedToken);
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
    return path == '/schedules' ||
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

  static Map<String, dynamic> _parse(http.Response response) {
    Map<String, dynamic> data = {};

    if (response.body.isNotEmpty) {
      final raw = _normalizeJson(jsonDecode(response.body));

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

    if (response.statusCode >= 400) {
      throw ApiException(
        response.statusCode,
        data['message']?.toString() ??
            data['error']?.toString() ??
            'Request failed',
      );
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
