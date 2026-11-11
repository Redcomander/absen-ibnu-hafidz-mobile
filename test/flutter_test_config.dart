import 'dart:async';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ibnu_hafidz_flutter/core/network/sync_store.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;
  SyncStore.testPath = inMemoryDatabasePath;
  await testMain();
}
