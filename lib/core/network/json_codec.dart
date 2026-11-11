import 'dart:convert';
import 'package:flutter/foundation.dart';

/// Keep large API/cache serialization off the frame-producing isolate.
class BackgroundJson {
  static const threshold = 32 * 1024;

  static Future<dynamic> decode(String source) => source.length < threshold
      ? Future.value(jsonDecode(source))
      : compute(_decode, source, debugLabel: 'json.decode');

  static Future<String> encode(Object? value) => _weight(value) < threshold
      ? Future.value(jsonEncode(value))
      : compute(_encode, value, debugLabel: 'json.encode');

  // Stop scanning as soon as the budget is reached. Small writes avoid spawning
  // an isolate; large strings and collections cannot monopolize a frame.
  static int _weight(Object? value) {
    if (value is String) return value.length;
    var size = 8;
    final Iterable<Object?> values;
    if (value is Map) {
      values = value.entries.expand((e) => [e.key, e.value]);
    } else if (value is Iterable) {
      values = value;
    } else {
      return size;
    }
    for (final item in values) {
      size += _weight(item);
      if (size >= threshold) break;
    }
    return size;
  }
}

dynamic _decode(String value) => jsonDecode(value);
String _encode(Object? value) => jsonEncode(value);
