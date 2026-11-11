import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ibnu_hafidz_flutter/core/updates/app_update_model.dart';
import 'package:ibnu_hafidz_flutter/core/updates/app_update_service.dart';
import 'package:ibnu_hafidz_flutter/core/updates/app_update_controller.dart';
import 'package:ibnu_hafidz_flutter/core/updates/update_gate.dart';

AppUpdate release({int code = 12, int minimum = 0, String? hash}) => AppUpdate(
  version: '1.1.0',
  code: code,
  minimum: minimum,
  url: 'https://ibnuhafidz.ponpes.id/api/app/download/1',
  sha256: hash ?? sha256.convert([1, 2, 3]).toString(),
  size: 3,
  notes: 'Perbaikan aplikasi',
  package: 'id.ponpes.ibnuhafidz.absensi',
);

class FakeUpdates extends AppUpdateService {
  InstalledApp app = const InstalledApp(
    '1.0.0',
    11,
    'id.ponpes.ibnuhafidz.absensi',
  );
  AppUpdate result = release();
  int checks = 0;
  bool fail = false, installerFail = false;
  Completer<AppUpdate>? pending;
  @override
  bool get supported => true;
  @override
  Future<InstalledApp> installed() async => app;
  @override
  Future<AppUpdate> check(InstalledApp app) async {
    checks++;
    if (fail) throw const HttpException('offline');
    return pending?.future ?? Future.value(result);
  }

  @override
  Future<void> requireUpdate(bool required) async {}
  @override
  Future<void> cleanup() async {}
  @override
  Future<File> download(
    AppUpdate update,
    void Function(double) progress,
  ) async {
    progress(.5);
    await Future<void>.delayed(Duration.zero);
    return File('test.apk');
  }

  @override
  Future<String> install(File file, AppUpdate update) async {
    if (installerFail) throw const HttpException('failed');
    return 'opened';
  }
}

class FakeHeaders extends Fake implements HttpHeaders {
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}
  @override
  String? value(String name) => null;
}

class FakeResponse extends Stream<List<int>> implements HttpClientResponse {
  FakeResponse(this.chunks, {this.statusCode = 200, this.contentLength = 3});
  final Stream<List<int>> chunks;
  @override
  final int statusCode;
  @override
  final int contentLength;
  @override
  HttpHeaders get headers => FakeHeaders();
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => chunks.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeRequest extends Fake implements HttpClientRequest {
  FakeRequest(this.response);
  final HttpClientResponse response;
  @override
  HttpHeaders get headers => FakeHeaders();
  bool redirects = true;
  @override
  set followRedirects(bool value) {
    redirects = value;
  }

  @override
  Future<HttpClientResponse> close() async {
    expect(redirects, false);
    return response;
  }
}

class FakeClient extends Fake implements HttpClient {
  FakeClient(this.response);
  final HttpClientResponse response;
  @override
  set connectionTimeout(Duration? timeout) {}
  @override
  Future<HttpClientRequest> getUrl(Uri url) async => FakeRequest(response);
  @override
  void close({bool force = false}) {}
}

class DownloadService extends AppUpdateService {
  DownloadService(this.dir, HttpClient client)
    : super(clientFactory: () => client);
  final Directory dir;
  @override
  Future<Directory> updateDirectory() async => dir;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('numeric version codes and minimum policy determine updates', () {
    final update = release(minimum: 10);
    expect(update.newerThan(11), true);
    expect(update.newerThan(12), false);
    expect(update.newerThan(13), false);
    expect(update.mandatoryFor(9), true);
    expect(update.mandatoryFor(10), false);
    expect(
      () => AppUpdate.parse({
        ...update.toJson(),
        'minimum_supported_version_code': 13,
      }),
      throwsFormatException,
    );
  });
  test('untrusted URLs, HTTP, credentials and unsafe paths are rejected', () {
    final service = AppUpdateService();
    for (final url in [
      'http://ibnuhafidz.ponpes.id/api/app/download/1',
      'https://evil.test/api/app/download/1',
      'https://user@ibnuhafidz.ponpes.id/api/app/download/1',
      'https://ibnuhafidz.ponpes.id/uploads/app.apk',
      'https://ibnuhafidz.ponpes.id/api/app/download/1?redirect=evil',
    ]) {
      expect(
        () => service.validate(url, download: true),
        throwsFormatException,
      );
    }
  });
  test(
    'verified downloads report progress and hash mismatch deletes temporary data',
    () async {
      final dir = await Directory.systemTemp.createTemp('ibnu-update-test');
      addTearDown(() => dir.delete(recursive: true));
      final progress = <double>[];
      final good = DownloadService(
        dir,
        FakeClient(
          FakeResponse(
            Stream.fromIterable([
              [1],
              [2, 3],
            ]),
          ),
        ),
      );
      final file = await good.download(release(), progress.add);
      expect(await file.readAsBytes(), [1, 2, 3]);
      expect(progress.last, 1);
      await file.delete();
      final bad = DownloadService(
        dir,
        FakeClient(FakeResponse(Stream.value([1, 2, 3]))),
      );
      await expectLater(
        bad.download(release(hash: '0' * 64), (_) {}),
        throwsFormatException,
      );
      expect(await dir.list().toList(), isEmpty);
    },
  );
  test('server failures and incomplete APK downloads are rejected', () async {
    final dir = await Directory.systemTemp.createTemp('ibnu-update-test');
    addTearDown(() => dir.delete(recursive: true));
    final failure = DownloadService(
      dir,
      FakeClient(FakeResponse(Stream.value([]), statusCode: 500)),
    );
    await expectLater(
      failure.download(release(), (_) {}),
      throwsA(isA<HttpException>()),
    );
    final short = DownloadService(
      dir,
      FakeClient(FakeResponse(Stream.value([1]), contentLength: -1)),
    );
    await expectLater(short.download(release(), (_) {}), throwsFormatException);
    expect(await dir.list().toList(), isEmpty);
  });
  test('redirects are rejected before APK content is accepted', () async {
    final dir = await Directory.systemTemp.createTemp('ibnu-update-test');
    addTearDown(() => dir.delete(recursive: true));
    final service = DownloadService(
      dir,
      FakeClient(FakeResponse(Stream.value([1, 2, 3]), statusCode: 302)),
    );
    await expectLater(
      service.download(release(), (_) {}),
      throwsA(isA<HttpException>()),
    );
  });
  test(
    'cancelled downloads remove incomplete files and remain retryable',
    () async {
      final dir = await Directory.systemTemp.createTemp('ibnu-update-test');
      addTearDown(() => dir.delete(recursive: true));
      final service = DownloadService(
        dir,
        FakeClient(
          FakeResponse(
            Stream.fromIterable([
              [1],
              [2, 3],
            ]),
          ),
        ),
      );
      await expectLater(
        service.download(release(), (_) => service.cancel()),
        throwsA(isA<UpdateCancelled>()),
      );
      expect(await dir.list().toList(), isEmpty);
    },
  );
  test('a stable no-release response does not block normal startup', () async {
    final service = FakeUpdates()
      ..result = AppUpdate.parse({
        'latest_version': '',
        'latest_version_code': 0,
        'minimum_supported_version_code': 0,
        'download_url': '',
        'sha256': '',
        'file_size': 0,
        'changelog': '',
        'package_name': 'id.ponpes.ibnuhafidz.absensi',
      });
    final controller = AppUpdateController(service: service);
    await controller.check();
    expect(controller.available, false);
    expect(controller.mandatory, false);
    expect(controller.message, contains('versi terbaru'));
    controller.dispose();
  });
  test(
    'checks deduplicate, throttle and do not claim installation success',
    () async {
      final service = FakeUpdates()..pending = Completer<AppUpdate>();
      final controller = AppUpdateController(service: service);
      final one = controller.check(), two = controller.check();
      await Future<void>.delayed(Duration.zero);
      expect(service.checks, 1);
      service.pending!.complete(release());
      await Future.wait([one, two]);
      await controller.check();
      expect(service.checks, 1);
      await controller.download();
      expect(controller.progress, .5);
      service.installerFail = true;
      await controller.install();
      expect(controller.error, isNotNull);
      service.installerFail = false;
      await controller.install();
      expect(controller.message, contains('Installer Android telah dibuka'));
      expect(controller.available, true);
      service.app = const InstalledApp(
        '1.1.0',
        12,
        'id.ponpes.ibnuhafidz.absensi',
      );
      await controller.resume();
      expect(controller.available, false);
      expect(service.checks, 1);
      controller.dispose();
    },
  );
  test(
    'previously verified mandatory policy survives unavailable server',
    () async {
      SharedPreferences.setMockInitialValues({
        'verified_update_policy': jsonEncode(release(minimum: 12).toJson()),
      });
      final service = FakeUpdates()..fail = true;
      final controller = AppUpdateController(service: service);
      await controller.check();
      expect(controller.mandatory, true);
      controller.dismiss();
      expect(controller.visible, true);
      controller.dispose();
    },
  );
  for (final minimum in [0, 12]) {
    testWidgets(
      'update UI supports ${minimum == 0 ? 'optional dismissal' : 'mandatory blocking'}',
      (tester) async {
        final service = FakeUpdates()..result = release(minimum: minimum);
        final controller = AppUpdateController(service: service);
        await controller.check();
        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: controller,
            child: const MaterialApp(
              home: AppUpdateGate(
                child: Scaffold(body: Text('Private app content')),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(
            minimum == 0 ? 'Pembaruan tersedia' : 'Pembaruan diperlukan',
          ),
          findsOneWidget,
        );
        expect(
          find.text('Nanti Saja'),
          minimum == 0 ? findsOneWidget : findsNothing,
        );
        if (minimum == 0) {
          await tester.tap(find.text('Nanti Saja'));
          await tester.pumpAndSettle();
          expect(find.text('Private app content'), findsOneWidget);
        }
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      },
    );
  }
}
