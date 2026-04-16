import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/network/api_client.dart';

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
  String? token;
  String? lastUsername;
  Map<String, dynamic>? user;
  Future<String?>? _refreshFuture;

  AuthController() {
    ApiClient.refreshAuthToken = _refreshAccessToken;
  }

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    rememberMe = prefs.getBool(_rememberMeKey) ?? true;
    lastUsername = prefs.getString(_lastUsernameKey);
    token = prefs.getString(_tokenKey);

    if (token != null && token!.isNotEmpty) {
      try {
        final me = await ApiClient.get('/auth/me', token: token);
        user = me['user'] is Map<String, dynamic> ? me['user'] : me;
        isAuthenticated = true;
        isOfflineSession = false;
        await _persistCachedUser();
      } catch (_) {
        final restored = await restoreCachedSession();
        if (!restored) {
          await logout();
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

  Future<void> login(
    String username,
    String password, {
    bool? rememberMe,
  }) async {
    if (rememberMe != null) {
      await setRememberMe(rememberMe);
    }

    final res = await ApiClient.post(
      '/auth/login',
      body: {
        'username': username,
        'password': password,
      },
      retryOnAuthError: false,
      queueOnOffline: false,
    );

    final accessToken =
        (res['access_token'] ?? res['data']?['access_token'])?.toString();
    if (accessToken == null || accessToken.isEmpty) {
      throw ApiException(500, 'Access token missing');
    }

    final refreshCookie = _extractCookiePair(res['__set_cookie']);

    token = accessToken;
    user = (res['user'] ?? res['data']?['user']) as Map<String, dynamic>?;
    lastUsername = username;
    isOfflineSession = false;

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

    await _persistCachedUser();
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
    notifyListeners();
    return true;
  }

  bool shouldUseOfflineFallback(Object error) {
    return error is! ApiException;
  }

  Future<void> logout() async {
    token = null;
    user = null;
    isAuthenticated = false;
    isOfflineSession = false;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_refreshCookieKey);
    await prefs.remove(_cachedUserKey);
    await prefs.remove(_lastUsernameKey);
    notifyListeners();
  }

  Future<String?> _refreshAccessToken() {
    _refreshFuture ??= _doRefreshAccessToken().whenComplete(() {
      _refreshFuture = null;
    });
    return _refreshFuture!;
  }

  Future<String?> _doRefreshAccessToken() async {
    final prefs = await SharedPreferences.getInstance();
    final refreshCookie = prefs.getString(_refreshCookieKey);

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

      final newToken =
          (res['access_token'] ?? res['data']?['access_token'])?.toString();
      if (newToken == null || newToken.isEmpty) {
        return null;
      }

      token = newToken;
      user = (res['user'] ?? res['data']?['user']) as Map<String, dynamic>? ??
          user;
      isAuthenticated = true;
      isOfflineSession = false;

      if (rememberMe) {
        await prefs.setString(_tokenKey, newToken);
        await _persistCachedUser();
      }

      notifyListeners();
      return newToken;
    } catch (_) {
      return null;
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
