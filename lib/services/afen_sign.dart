import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Request signing for AFEN Open Platform REST API.
///
/// Supports `md5` and `hmac-sha256` per the integration guide.
class AfenSign {
  /// Builds the `sign` query param from [queryParams] (excluding `sign`).
  static String build({
    required String appSecret,
    required Map<String, String> queryParams,
    required String signMethod,
    String bodyJson = '',
  }) {
    final sorted = Map<String, String>.from(queryParams)
      ..remove('sign');
    final keys = sorted.keys.toList()..sort();

    final buffer = StringBuffer();
    for (final key in keys) {
      final value = sorted[key];
      if (value == null || value.isEmpty) continue;
      buffer.write(key);
      buffer.write(value);
    }
    final paramStr = buffer.toString();

    if (signMethod == 'hmac-sha256') {
      final hmac = Hmac(sha256, utf8.encode(appSecret));
      final digest = hmac.convert(utf8.encode(paramStr + bodyJson));
      return digest.toString().toUpperCase();
    }

    // Default: md5 — secret + sorted(key+value) + secret
    final md5Input = appSecret + paramStr + bodyJson + appSecret;
    return md5.convert(utf8.encode(md5Input)).toString().toUpperCase();
  }

  /// UTC timestamp: yyyy-MM-dd HH:mm:ss
  static String utcTimestamp() {
    final now = DateTime.now().toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${now.year}-${two(now.month)}-${two(now.day)} '
        '${two(now.hour)}:${two(now.minute)}:${two(now.second)}';
  }
}
