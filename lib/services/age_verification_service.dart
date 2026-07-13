import 'dart:convert';
import 'package:http/http.dart' as http;
import 'app_config.dart';

/// Status of an age-verification session on vms-cloud.
enum AgeVerificationStatus {
  pending,
  uploaded,
  processing,
  verified,
  rejected,
  expired,
  unknown,
}

/// A server-side age-verification session. The kiosk shows a QR code pointing
/// at [verifyUrl]; the customer uploads their ID on their phone; vms-cloud
/// forwards the image to a third-party verifier (Jumio, Veriff, etc.).
class AgeVerificationSession {
  final String sessionId;
  final String verifyUrl;
  final DateTime? expiresAt;

  const AgeVerificationSession({
    required this.sessionId,
    required this.verifyUrl,
    this.expiresAt,
  });

  factory AgeVerificationSession.fromJson(Map<String, dynamic> json) {
    DateTime? expires;
    final raw = json['expires_at']?.toString();
    if (raw != null && raw.isNotEmpty) {
      expires = DateTime.tryParse(raw);
    }
    return AgeVerificationSession(
      sessionId: json['session_id']?.toString() ?? '',
      verifyUrl: json['verify_url']?.toString() ?? '',
      expiresAt: expires,
    );
  }
}

/// Poll result from GET /age-verification/sessions/{id}.
class AgeVerificationPollResult {
  final AgeVerificationStatus status;
  final bool ageVerified;
  final String? message;

  const AgeVerificationPollResult({
    required this.status,
    this.ageVerified = false,
    this.message,
  });
}

class AgeVerificationException implements Exception {
  final String message;
  const AgeVerificationException(this.message);
  @override
  String toString() => message;
}

class AgeVerificationService {
  static String get _baseUrl => AppConfig.apiBaseUrl;
  static String get _machineNo => AppConfig.machineNo;

  /// POST /api/v1/age-verification/sessions
  ///
  /// Creates a one-time session. The backend returns a [verifyUrl] for the QR
  /// code and stores the session until the customer uploads an ID document.
  static Future<AgeVerificationSession> createSession() async {
    final url = Uri.parse('$_baseUrl/age-verification/sessions');

    final response = await http
        .post(
          url,
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'machine_no': _machineNo}),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode == 201 || response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final session = AgeVerificationSession.fromJson(body);
      if (session.sessionId.isEmpty) {
        throw const AgeVerificationException(
          'Invalid session response from server.',
        );
      }
      // Backend may omit verify_url — build one from the web base + session id.
      if (session.verifyUrl.isEmpty) {
        return AgeVerificationSession(
          sessionId: session.sessionId,
          verifyUrl: AppConfig.ageVerificationVerifyUrl(session.sessionId),
          expiresAt: session.expiresAt,
        );
      }
      return session;
    }

    if (response.statusCode == 404 || response.statusCode == 501) {
      throw const AgeVerificationException(
        'Age verification is not enabled on this server yet.',
      );
    }

    final body = _tryDecode(response.body);
    final msg = body?['message']?.toString();
    throw AgeVerificationException(
      msg ?? 'Could not start verification (${response.statusCode}).',
    );
  }

  /// GET /api/v1/age-verification/sessions/{sessionId}
  static Future<AgeVerificationPollResult> pollStatus(
    String sessionId,
  ) async {
    final url = Uri.parse('$_baseUrl/age-verification/sessions/$sessionId');

    final response = await http
        .get(url, headers: {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return AgeVerificationPollResult(
        status: _parseStatus(body['status']?.toString()),
        ageVerified: body['age_verified'] == true,
        message: body['message']?.toString(),
      );
    }

    if (response.statusCode == 404) {
      return const AgeVerificationPollResult(
        status: AgeVerificationStatus.expired,
        message: 'Session expired. Please try again.',
      );
    }

    throw AgeVerificationException(
      'Status check failed (${response.statusCode}).',
    );
  }

  static AgeVerificationStatus _parseStatus(String? raw) {
    switch (raw?.toLowerCase()) {
      case 'pending':
        return AgeVerificationStatus.pending;
      case 'uploaded':
        return AgeVerificationStatus.uploaded;
      case 'processing':
        return AgeVerificationStatus.processing;
      case 'verified':
        return AgeVerificationStatus.verified;
      case 'rejected':
        return AgeVerificationStatus.rejected;
      case 'expired':
        return AgeVerificationStatus.expired;
      default:
        return AgeVerificationStatus.unknown;
    }
  }

  static Map<String, dynamic>? _tryDecode(String body) {
    try {
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}
