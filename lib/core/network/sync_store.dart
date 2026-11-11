import 'json_codec.dart';
import 'dart:math';

import 'package:sqflite/sqflite.dart';

import '../config/app_config.dart';

class SyncStore {
  static final instance = SyncStore();
  static String? testPath;
  Future<Database>? _database;
  static String account(Object id) => '${AppConfig.baseUrl}|$id';
  static String newId() => List.generate(
    24,
    (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();

  Future<Database> get database => _database ??= _open();
  Future<Database> _open() async => openDatabase(
    testPath ?? '${await getDatabasesPath()}/ibnu_sync_v2.db',
    version: 1,
    onConfigure: (db) async {
      await db.rawQuery('PRAGMA busy_timeout = 10000');
    },
    onCreate: (db, _) async {
      await db.execute(
        'CREATE TABLE settings (account TEXT PRIMARY KEY, mode TEXT NOT NULL DEFAULT \'any_network\', last_success TEXT)',
      );
      await db.execute(
        'CREATE TABLE queue (id TEXT PRIMARY KEY, account TEXT NOT NULL, path TEXT NOT NULL, body TEXT NOT NULL, encoding TEXT NOT NULL, created_at TEXT NOT NULL, state TEXT NOT NULL DEFAULT \'pending\', attempts INTEGER NOT NULL DEFAULT 0, error TEXT)',
      );
      await db.execute(
        'CREATE INDEX queue_account ON queue(account, created_at)',
      );
      await db.execute(
        'CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
      );
      await db.execute(
        'CREATE TABLE leases (name TEXT PRIMARY KEY, owner TEXT NOT NULL, expires INTEGER NOT NULL)',
      );
    },
  );

  Future<String?> getMeta(String key) async {
    final rows = await (await database).query(
      'meta',
      where: 'key = ?',
      whereArgs: [key],
    );
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  Future<void> setMeta(String key, String value) async =>
      (await database).insert('meta', {
        'key': key,
        'value': value,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
  Future<String> mode(String account) async {
    final rows = await (await database).query(
      'settings',
      where: 'account = ?',
      whereArgs: [account],
    );
    return rows.isEmpty ? 'any_network' : rows.first['mode'] as String;
  }

  Future<void> setMode(String account, String mode) async {
    if (!['wifi_only', 'any_network'].contains(mode)) {
      throw ArgumentError('Invalid sync mode');
    }
    final db = await database;
    await db.insert('settings', {
      'account': account,
      'mode': mode,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    await db.update(
      'settings',
      {'mode': mode},
      where: 'account = ?',
      whereArgs: [account],
    );
  }

  Future<String> enqueue(
    String account,
    String path,
    Object? body,
    String encoding, {
    String? id,
    String? state,
  }) async {
    final actionId = id ?? newId();
    await (await database).insert('queue', {
      'id': actionId,
      'account': account,
      'path': path,
      'body': await BackgroundJson.encode(body),
      'encoding': encoding,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'state': state ?? 'pending',
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    return actionId;
  }

  Future<List<Map<String, Object?>>> entries(
    String account, {
    int? limit,
    bool includeBody = true,
    String? path,
  }) async => (await database).query(
    'queue',
    columns: includeBody
        ? null
        : [
            'id',
            'account',
            'path',
            'encoding',
            'created_at',
            'state',
            'attempts',
            'error',
          ],
    where: path == null ? 'account = ?' : 'account = ? AND path = ?',
    whereArgs: path == null ? [account] : [account, path],
    orderBy: 'created_at, id',
    limit: limit,
  );
  Future<String?> body(String account, String id) async {
    final rows = await (await database).query(
      'queue',
      columns: ['body'],
      where: 'account = ? AND id = ?',
      whereArgs: [account, id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['body'] as String;
  }

  Future<bool> hasEntries(String account, {String? id}) async {
    final rows = await (await database).query(
      'queue',
      columns: ['id'],
      where: id == null ? 'account = ?' : 'account = ? AND id = ?',
      whereArgs: id == null ? [account] : [account, id],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<void> acknowledge(String account, String id) async {
    final db = await database;
    await db.transaction((tx) async {
      await tx.delete(
        'queue',
        where: 'account = ? AND id = ?',
        whereArgs: [account, id],
      );
      await tx.insert('settings', {
        'account': account,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      await tx.update(
        'settings',
        {'last_success': DateTime.now().toUtc().toIso8601String()},
        where: 'account = ?',
        whereArgs: [account],
      );
    });
  }

  Future<void> fail(
    String account,
    String id,
    String message, {
    bool blocked = false,
  }) async => (await database).rawUpdate(
    'UPDATE queue SET state = ?, error = ?, attempts = attempts + 1 WHERE account = ? AND id = ?',
    [blocked ? 'blocked' : 'pending', message, account, id],
  );
  Future<void> retry(String account) async => (await database).update(
    'queue',
    {'state': 'pending', 'error': null},
    where: 'account = ? AND state = ?',
    whereArgs: [account, 'blocked'],
  );
  Future<String?> lastSuccess(String account) async {
    final rows = await (await database).query(
      'settings',
      where: 'account = ?',
      whereArgs: [account],
    );
    return rows.isEmpty ? null : rows.first['last_success'] as String?;
  }

  Future<String?> acquire(String name) async {
    final owner = newId();
    final now = DateTime.now().millisecondsSinceEpoch;
    return (await database).transaction((tx) async {
      await tx.delete(
        'leases',
        where: 'name = ? AND expires < ?',
        whereArgs: [name, now],
      );
      final rows = await tx.query(
        'leases',
        where: 'name = ?',
        whereArgs: [name],
      );
      if (rows.isNotEmpty) return null;
      await tx.insert('leases', {
        'name': name,
        'owner': owner,
        'expires': now + 180000,
      });
      return owner;
    });
  }

  Future<void> renew(String name, String owner) async =>
      (await database).update(
        'leases',
        {'expires': DateTime.now().millisecondsSinceEpoch + 180000},
        where: 'name = ? AND owner = ?',
        whereArgs: [name, owner],
      );
  Future<void> release(String name, String owner) async =>
      (await database).delete(
        'leases',
        where: 'name = ? AND owner = ?',
        whereArgs: [name, owner],
      );
}
