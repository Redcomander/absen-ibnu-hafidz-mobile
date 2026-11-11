import 'package:flutter/foundation.dart';

bool hasAccess(Map<String, dynamic>? user, String permission) {
  final roles = user?['roles'];
  if (roles is! List) return false;
  return roles.whereType<Map>().any(
    (role) =>
        (role['permissions'] is List &&
        (role['permissions'] as List).whereType<Map>().any(
          (p) => p['name'] == permission,
        )),
  );
}

bool canReviewHalaqoh(Map<String, dynamic>? user) =>
    (user?['roles'] as List? ?? []).whereType<Map>().any(
      (r) => ['admin', 'super_admin'].contains(r['name']),
    );
Map<String, dynamic> mapValue(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : {};
List<Map<String, dynamic>> listValue(dynamic v) =>
    v is List ? v.whereType<Map>().map(mapValue).toList() : [];
String errorMessage(Object error) {
  debugPrint('Request failed: ${error.runtimeType}');
  return 'Data belum dapat dimuat. Periksa koneksi dan hak akses, lalu coba lagi.';
}
