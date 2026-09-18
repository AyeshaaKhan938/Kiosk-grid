import 'app_config.dart';

/// Headers for vms-cloud routes protected by [EnsureKioskDeviceToken].
Map<String, String> kioskDeviceAuthHeaders({bool jsonBody = false}) {
  final headers = <String, String>{
    'Accept': 'application/json',
  };
  if (jsonBody) {
    headers['Content-Type'] = 'application/json';
  }
  final token = AppConfig.deviceToken.trim();
  if (token.isNotEmpty) {
    headers['Authorization'] = 'Bearer $token';
  }
  return headers;
}

bool get kioskHasDeviceAuth => AppConfig.hasDeviceToken;
