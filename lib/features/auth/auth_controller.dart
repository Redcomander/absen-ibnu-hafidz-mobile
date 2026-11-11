import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/network/api_client.dart';
import '../../core/network/offline_cache_store.dart';
import '../../core/network/sync_store.dart';

class AuthController extends ChangeNotifier {
  static const _tokenKey = 'auth_token';
  static const _refreshCookieKey = 'refresh_cookie';
  static const _rememberMeKey = 'remember_me';
  static const _cachedUserKey = 'cached_user';
  static const _lastUsernameKey = 'last_username';

  bool isLoading = true;
  bool isAuthenticated = false;
  bool rememberMe = true;
  bool isOfflineSession = false;
  String? sessionWarning;
  bool isReconnecting = false;
  String? token;
  String? lastUsername;
  Map<String, dynamic>? user;
  Future<String?>? _refreshFuture;
  String? _sessionRefreshCookie;
  int _sessionGeneration = 0;

  final String? backgroundAccount;
  AuthController({this.backgroundAccount}) {
    ApiClient.refreshAuthToken = _refreshAccessToken;
  }

  Future<void> init() async {
    final generation = _sessionGeneration;
    final prefs = await SharedPreferences.getInstance();
    rememberMe = prefs.getBool(_rememberMeKey) ?? true;
    lastUsername = prefs.getString(_lastUsernameKey);
    token = prefs.getString(_tokenKey);

    // A remembered account can open its local schedules while session validation
    // runs. An explicit 401/403 below still clears the session immediately.
    if (backgroundAccount == null && rememberMe && token != null) {
      if (await restoreCachedSession()) {
        isLoading = false;
        notifyListeners();
      }
    }

    if (token != null && token!.isNotEmpty) {
      try {
        final me = await ApiClient.get('/auth/me', token: token);
        if (generation != _sessionGeneration) return;
        if (backgroundAccount != null &&
            await SyncStore.instance.getMeta('active_account') !=
                backgroundAccount) {
          isLoading = false;
          return;
        }
        user = me['user'] is Map<String, dynamic> ? me['user'] : me;
        isAuthenticated = true;
        isOfflineSession = false;
        OfflineCacheStore.scope = SyncStore.account(user!['id']);
        await _persistCachedUser();
      } catch (error) {
        if (generation != _sessionGeneration) return;
        if (backgroundAccount != null &&
            await SyncStore.instance.getMeta('active_account') !=
                backgroundAccount) {
          isLoading = false;
          return;
        }
        if (error is ApiException && error.isAuthenticationRejection) {
          await logout();
        } else {
          await restoreCachedSession();
          sessionWarning = error is ApiException
              ? error.message
              : 'Server belum terhubung. Menggunakan sesi tersimpan.';
        }
      }
    } else if (rememberMe) {
      await restoreCachedSession();
    }

    isLoading = false;
    notifyListeners();
  }

  Future<void> setRememberMe(bool value) async {
    rememberMe = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_rememberMeKey, value);

    if (!value) {
      await prefs.remove(_cachedUserKey);
      await prefs.remove(_lastUsernameKey);
    }

    notifyListeners();
  }

  Future<void> login(String username, String password, {bool? rememberMe}) =>
      _withSessionLock(
        () => _login(username, password, rememberMe: rememberMe),
      );

  Future<void> _login(
    String username,
    String password, {
    bool? rememberMe,
  }) async {
    _sessionGeneration++;
    if (rememberMe != null) {
      await setRememberMe(rememberMe);
    }

    final res = await ApiClient.post(
      '/auth/login',
      body: {'username': username, 'password': password},
      retryOnAuthError: false,
      queueOnOffline: false,
    );

    final accessToken = (res['access_token'] ?? res['data']?['access_token'])
        ?.toString();
    if (accessToken == null || accessToken.isEmpty) {
      throw ApiException(500, 'Access token missing');
    }

    final refreshCookie = _extractCookiePair(res['__set_cookie']);
    _sessionRefreshCookie = refreshCookie;

    token = accessToken;
    user = (res['user'] ?? res['data']?['user']) as Map<String, dynamic>?;
    lastUsername = username;
    isOfflineSession = false;
    sessionWarning = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_rememberMeKey, this.rememberMe);

    if (this.rememberMe) {
      await prefs.setString(_tokenKey, accessToken);
      await prefs.setString(_lastUsernameKey, username);
      if (refreshCookie != null && refreshCookie.isNotEmpty) {
        await prefs.setString(_refreshCookieKey, refreshCookie);
      }
    } else {
      await prefs.remove(_tokenKey);
      await prefs.remove(_refreshCookieKey);
      await prefs.remove(_lastUsernameKey);
    }

    if (user == null) {
      final me = await ApiClient.get('/auth/me', token: accessToken);
      user = me['user'] is Map<String, dynamic> ? me['user'] : me;
    }

    await SyncStore.instance.setMeta(
      'active_account',
      SyncStore.account(user!['id']),
    );
    await _persistCachedUser();
    OfflineCacheStore.scope = SyncStore.account(user!['id']);
    isAuthenticated = true;
    notifyListeners();
  }

  Future<bool> restoreCachedSession({String? username}) async {
    if (!rememberMe) return false;

    final prefs = await SharedPreferences.getInstance();
    final cachedUserRaw = prefs.getString(_cachedUserKey);
    final savedUsername = prefs.getString(_lastUsernameKey);

    if (cachedUserRaw == null || cachedUserRaw.isEmpty) return false;
    if (username != null &&
        savedUsername != null &&
        savedUsername.isNotEmpty &&
        savedUsername != username) {
      return false;
    }

    final decoded = jsonDecode(cachedUserRaw);
    if (decoded is! Map) return false;

    user = Map<String, dynamic>.from(decoded);
    lastUsername = savedUsername;
    isAuthenticated = true;
    isOfflineSession = true;
    OfflineCacheStore.scope = SyncStore.account(user!['id']);
    notifyListeners();
    return true;
  }

  bool shouldUseOfflineFallback(Object error) {
    return ApiClient.isConnectionError(error);
  }

  Future<bool> reconnect() async {
    if (isReconnecting || token == null) return false;
    final scope = OfflineCacheStore.scope;
    isReconnecting = true;
    notifyListeners();
    try {
      final me = await ApiClient.get('/auth/me', token: token);
      if (!isAuthenticated || OfflineCacheStore.scope != scope) return false;
      user = me['user'] is Map<String, dynamic> ? me['user'] : me;
      isOfflineSession = false;
      sessionWarning = null;
      await _persistCachedUser();
      return true;
    } catch (error) {
      if (error is ApiException && error.isAuthenticationRejection) {
        await logout();
      } else {
        sessionWarning = error is ApiException
            ? error.message
            : 'Server belum terhubung. Periksa koneksi lalu coba lagi.';
      }
      return false;
    } finally {
      isReconnecting = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    _sessionGeneration++;
    OfflineCacheStore.scope = 'anonymous';
    await SyncStore.instance.setMeta('active_account', '');
    token = null;
    _sessionRefreshCookie = null;
    user = null;
    isAuthenticated = false;
    isOfflineSession = false;
    sessionWarning = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_refreshCookieKey);
    await prefs.remove(_cachedUserKey);
    await prefs.remove(_lastUsernameKey);
    notifyListeners();
  }

  Future<String?> _refreshAccessToken() {
    _refreshFuture ??= _lockedRefresh().whenComplete(() {
      _refreshFuture = null;
    });
    return _refreshFuture!;
  }

  Future<String?> _lockedRefresh() async {
    return _withSessionLock(_doRefreshAccessToken);
  }

  Future<T> _withSessionLock<T>(Future<T> Function() action) async {
    for (var attempt = 0; attempt < 30; attempt++) {
      final lease = await SyncStore.instance.acquire('refresh');
      if (lease == null) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        continue;
      }
      try {
        return await action();
      } finally {
        await SyncStore.instance.release('refresh', lease);
      }
    }
    throw ApiException(503, 'Pembaruan sesi sedang berjalan. Coba lagi.');
  }

  Future<String?> _doRefreshAccessToken() async {
    final activeAtStart = await SyncStore.instance.getMeta('active_account');
    if (backgroundAccount != null && activeAtStart != backgroundAccount) {
      return null;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final refreshCookie = rememberMe
        ? prefs.getString(_refreshCookieKey)
        : _sessionRefreshCookie;
    final savedToken = prefs.getString(_tokenKey);
    if (savedToken != null && savedToken != token && user != null) {
      final savedUser = prefs.getString(_cachedUserKey);
      if (savedUser != null &&
          (jsonDecode(savedUser) as Map)['id'] == user!['id']) {
        token = savedToken;
        return savedToken;
      }
    }

    if (refreshCookie == null || refreshCookie.isEmpty) {
      return null;
    }

    try {
      final res = await ApiClient.post(
        '/auth/refresh',
        headers: {'Cookie': refreshCookie},
        retryOnAuthError: false,
        queueOnOffline: false,
      );

      final newToken = (res['access_token'] ?? res['data']?['access_token'])
          ?.toString();
      if (newToken == null || newToken.isEmpty) {
        return null;
      }
      if (await SyncStore.instance.getMeta('active_account') != activeAtStart) {
        return null;
      }

      token = newToken;
      user =
          (res['user'] ?? res['data']?['user']) as Map<String, dynamic>? ??
          user;
      isAuthenticated = true;
      isOfflineSession = false;
      _sessionRefreshCookie =
          _extractCookiePair(res['__set_cookie']) ?? refreshCookie;

      if (rememberMe) {
        await prefs.setString(_tokenKey, newToken);
        final rotatedCookie = _extractCookiePair(res['__set_cookie']);
        if (rotatedCookie != null && rotatedCookie.isNotEmpty) {
          await prefs.setString(_refreshCookieKey, rotatedCookie);
        }
        await _persistCachedUser();
      }

      notifyListeners();
      return newToken;
    } catch (error) {
      if (error is ApiException && error.isAuthenticationRejection) {
        return null;
      }
      rethrow;
    }
  }

  Future<void> _persistCachedUser() async {
    if (!rememberMe || user == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cachedUserKey, jsonEncode(user));
  }

  String? _extractCookiePair(dynamic rawCookie) {
    final value = rawCookie?.toString();
    if (value == null || value.isEmpty) return null;

    final cookiePair = value.split(';').first.trim();
    if (!cookiePair.contains('=')) return null;
    return cookiePair;
  }
}
