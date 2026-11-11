import 'dart:convert';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ibnu_hafidz_flutter/core/network/api_client.dart';
import 'package:ibnu_hafidz_flutter/features/auth/auth_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    ApiClient.refreshAuthToken = null;
    ApiClient.canUseNetwork = null;
    ApiClient.queueOfflineWrite = null;
  });

  test(
    'remembered account opens before validation and logout cancels stale validation',
    () async {
      SharedPreferences.setMockInitialValues({
        'auth_token': 'saved-token',
        'cached_user': jsonEncode({'id': 1}),
        'remember_me': true,
      });
      final auth = AuthController();
      final started = Completer<void>();
      final response = Completer<http.Response>();
      await http.runWithClient(
        () async {
          final loading = auth.init();
          await started.future;
          expect(auth.isLoading, isFalse);
          expect(auth.isAuthenticated, isTrue);
          await auth.logout();
          response.complete(http.Response('{"user":{"id":1}}', 200));
          await loading;
          expect(auth.isAuthenticated, isFalse);
          expect(auth.user, isNull);
        },
        () => MockClient((_) {
          started.complete();
          return response.future;
        }),
      );
      auth.dispose();
    },
  );

  test(
    'HTML server failure preserves saved session and reconnect recovers',
    () async {
      SharedPreferences.setMockInitialValues({
        'auth_token': 'saved-token',
        'cached_user': jsonEncode({'id': 1, 'name': 'Teacher'}),
        'remember_me': true,
      });
      final auth = AuthController();
      await http.runWithClient(
        auth.init,
        () => MockClient(
          (_) async => http.Response('<html>Server error</html>', 500),
        ),
      );
      expect(auth.isAuthenticated, isTrue);
      expect(auth.isOfflineSession, isTrue);
      expect(auth.sessionWarning, contains('HTTP 500'));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('auth_token'), 'saved-token');
      await http.runWithClient(
        () async => expect(await auth.reconnect(), isTrue),
        () => MockClient(
          (_) async =>
              http.Response(jsonEncode({'id': 1, 'name': 'Teacher'}), 200),
        ),
      );
      expect(auth.isOfflineSession, isFalse);
      expect(auth.sessionWarning, isNull);
      auth.dispose();
    },
  );

  test(
    'server HTML and malformed JSON never queue attendance as offline',
    () async {
      SharedPreferences.setMockInitialValues({});
      var queued = 0;
      ApiClient.canUseNetwork = () async => true;
      ApiClient.queueOfflineWrite =
          (path, {token, body, required encoding}) async {
            queued++;
            return {'queued': true};
          };
      for (final status in [500, 200]) {
        await http.runWithClient(
          () async {
            await expectLater(
              ApiClient.post(
                '/attendance',
                token: 'token',
                body: {},
                queueOnOffline: false,
              ),
              throwsA(
                isA<ApiException>().having(
                  (error) => error.statusCode,
                  'status',
                  status == 500 ? 500 : 502,
                ),
              ),
            );
          },
          () => MockClient(
            (_) async => http.Response('<html>Not JSON</html>', status),
          ),
        );
      }
      expect(queued, 0);
    },
  );

  test(
    'Imunify block preserves remembered account and refresh credentials',
    () async {
      SharedPreferences.setMockInitialValues({
        'auth_token': 'saved-token',
        'refresh_cookie': 'refresh_token=saved',
        'cached_user': jsonEncode({'id': 1}),
        'remember_me': true,
      });
      final auth = AuthController();
      await http.runWithClient(
        auth.init,
        () => MockClient(
          (_) async => http.Response(
            '<html>Access denied by Imunify360 bot-protection</html>',
            403,
          ),
        ),
      );
      expect(auth.isAuthenticated, isTrue);
      expect(auth.sessionWarning, contains('Imunify360'));
      await http.runWithClient(
        () async => expect(await auth.reconnect(), isFalse),
        () => MockClient(
          (_) async => http.Response(
            '<html>Access denied by Imunify360 bot-protection</html>',
            403,
          ),
        ),
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('auth_token'), 'saved-token');
      expect(prefs.getString('refresh_cookie'), 'refresh_token=saved');
      auth.dispose();
    },
  );

  test(
    'Imunify challenge never refreshes credentials or becomes successful JSON',
    () async {
      var refreshes = 0;
      ApiClient.refreshAuthToken = () async {
        refreshes++;
        return 'new';
      };
      for (final status in [200, 401, 403, 503]) {
        await http.runWithClient(
          () async {
            await expectLater(
              ApiClient.get('/auth/me', token: 'saved'),
              throwsA(
                isA<ApiException>()
                    .having((e) => e.isServerProtection, 'protection', isTrue)
                    .having(
                      (e) => e.isAuthenticationRejection,
                      'auth rejection',
                      isFalse,
                    ),
              ),
            );
          },
          () => MockClient(
            (_) async => http.Response(
              '<html>Access denied by Imunify360 bot-protection</html>',
              status,
            ),
          ),
        );
      }
      expect(refreshes, 0);
    },
  );

  test(
    'unbranded production browser verification is a hosting block',
    () async {
      await http.runWithClient(
        () async {
          await expectLater(
            ApiClient.post('/auth/login', body: {}),
            throwsA(
              isA<ApiException>().having(
                (e) => e.isServerProtection,
                'protection',
                isTrue,
              ),
            ),
          );
        },
        () => MockClient(
          (_) async => http.Response(
            '<html><title>One moment, please...</title>'
            '<script>window.location.reload();</script>'
            'Please wait while your request is being verified...</html>',
            200,
          ),
        ),
      );
    },
  );

  test('persists rotated refresh cookies for the next refresh', () async {
    SharedPreferences.setMockInitialValues({
      'refresh_cookie': 'refresh_token=old',
      'remember_me': true,
    });
    final auth = AuthController();
    final sentCookies = <String?>[];
    await http.runWithClient(
      () async {
        await ApiClient.refreshAuthToken!();
        await ApiClient.refreshAuthToken!();
      },
      () => MockClient((request) async {
        sentCookies.add(request.headers['cookie']);
        return http.Response(
          jsonEncode({
            'access_token': 'new-token',
            'user': {'id': 1, 'name': 'Teacher'},
          }),
          200,
          headers: {'set-cookie': 'refresh_token=rotated; HttpOnly; Path=/'},
        );
      }),
    );
    expect(sentCookies, ['refresh_token=old', 'refresh_token=rotated']);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('refresh_cookie'), 'refresh_token=rotated');
    auth.dispose();
  });

  test('rejected session does not restore cached offline access', () async {
    SharedPreferences.setMockInitialValues({
      'auth_token': 'rejected-token',
      'cached_user': jsonEncode({'id': 1, 'name': 'Old user'}),
      'remember_me': true,
    });
    final auth = AuthController();
    await http.runWithClient(
      auth.init,
      () => MockClient(
        (_) async => http.Response('{"message":"Unauthorized"}', 401),
      ),
    );
    expect(auth.isAuthenticated, isFalse);
    expect(auth.isOfflineSession, isFalse);
    expect(auth.user, isNull);
    auth.dispose();
  });
}
