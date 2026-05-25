import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'app_config.dart';

/// Result of an update-check round trip with vms-cloud.
class UpdateInfo {
  final bool   available;
  final int    versionCode;
  final String versionName;
  final String apkUrl;
  final String? sha256;
  final int?   sizeBytes;
  final bool   mandatory;
  final String releaseNotes;

  const UpdateInfo.none()
      : available    = false,
        versionCode  = 0,
        versionName  = '',
        apkUrl       = '',
        sha256       = null,
        sizeBytes    = null,
        mandatory    = false,
        releaseNotes = '';

  const UpdateInfo({
    required this.available,
    required this.versionCode,
    required this.versionName,
    required this.apkUrl,
    required this.sha256,
    required this.sizeBytes,
    required this.mandatory,
    required this.releaseNotes,
  });
}

/// Manages remote APK updates from vms-cloud.
///
/// Flow:
///   1. [check] polls /api/v1/kiosk/update-check with our current versionCode
///   2. If a newer version is offered, [downloadAndInstall] fetches it to a
///      temp file, then asks the native side (ApkInstallerChannel) to launch
///      the Android PackageInstaller intent.
///   3. After admin taps "Install" on the system prompt, the app reinstalls
///      itself in-place and relaunches. Settings/PINs are preserved because
///      the package signature matches.
class UpdateService {
  UpdateService._();

  static const _channel = MethodChannel('vmfs.kiosk/apk_installer');

  static bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Current installed versionCode (build.gradle: versionCode).
  static Future<int> currentVersionCode() async {
    final info = await PackageInfo.fromPlatform();
    return int.tryParse(info.buildNumber) ?? 0;
  }

  /// Current installed versionName (e.g. "1.2.0").
  static Future<String> currentVersionName() async {
    final info = await PackageInfo.fromPlatform();
    return info.version;
  }

  /// Poll the backend for a newer version.
  static Future<UpdateInfo> check() async {
    final code = await currentVersionCode();
    final url = Uri.parse('${AppConfig.apiBaseUrl}/kiosk/update-check')
        .replace(queryParameters: {'current_version_code': code.toString()});

    final response = await http
        .get(url, headers: {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw UpdateException('Update check failed (HTTP ${response.statusCode}).');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (body['update_available'] != true) return const UpdateInfo.none();

    return UpdateInfo(
      available:    true,
      versionCode:  (body['version_code'] as num?)?.toInt() ?? 0,
      versionName:  body['version_name']?.toString() ?? '',
      apkUrl:       body['apk_url']?.toString() ?? '',
      sha256:       body['apk_sha256']?.toString(),
      sizeBytes:    (body['apk_size_bytes'] as num?)?.toInt(),
      mandatory:    body['mandatory'] == true,
      releaseNotes: body['release_notes']?.toString() ?? '',
    );
  }

  /// Resolves the backend's APK URL to a fully-qualified, properly-encoded
  /// URI. The vms-cloud admin can store paths in three different shapes
  /// (legacy migrations, the old uploader, and the current Filament form
  /// don't agree), so we have to be tolerant of all of them:
  ///
  ///   - `https://cloud.vmfsusa.com/storage/...apk` → already absolute, use as-is
  ///   - `/storage/kiosk-updates/foo.apk`           → root-relative, prefix with API origin
  ///   - `kiosk-updates/foo.apk`                    → relative, prefix with API origin + /storage/
  ///
  /// Also `Uri.parse` doesn't URL-encode the path automatically, so a
  /// filename like `app-release (4).apk` (Filament adds the "(N)" suffix
  /// when an upload would overwrite an existing file) becomes invalid.
  /// `Uri.encodeFull` fixes that without re-encoding existing %20 etc.
  static Uri _resolveApkUri(String raw) {
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      return Uri.parse(Uri.encodeFull(raw));
    }
    final base = AppConfig.apiBaseUrl; // e.g. https://cloud.vmfsusa.com/api/v1
    final origin = Uri.tryParse(base)?.origin ?? base;
    final path = raw.startsWith('/')
        ? raw
        : '/storage/$raw';
    return Uri.parse(Uri.encodeFull('$origin$path'));
  }

  /// Downloads the APK to a temp file. Returns the file path on success.
  /// Calls [onProgress] with (downloadedBytes, totalBytes) for UI updates.
  static Future<String> download(
    UpdateInfo info, {
    void Function(int downloaded, int total)? onProgress,
  }) async {
    if (!_isAndroid) {
      throw const UpdateException('Updates are only supported on Android.');
    }
    if (info.apkUrl.isEmpty) {
      throw const UpdateException('Backend did not provide an APK URL.');
    }

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/vmfs-kiosk-${info.versionCode}.apk');
    if (await file.exists()) await file.delete();

    final resolvedUri = _resolveApkUri(info.apkUrl);
    debugPrint('[update] downloading APK from $resolvedUri '
        '(raw value from backend: "${info.apkUrl}")');
    final request = http.Request('GET', resolvedUri);
    final streamed = await request.send().timeout(const Duration(seconds: 30));
    if (streamed.statusCode != 200) {
      throw UpdateException('APK download failed (HTTP ${streamed.statusCode}).');
    }

    final total = streamed.contentLength ?? info.sizeBytes ?? 0;
    final sink = file.openWrite();
    int received = 0;
    try {
      // 25s stall timeout — if no bytes arrive for that long, abort
      // instead of hanging the dialog indefinitely on a flaky link.
      await for (final chunk
          in streamed.stream.timeout(const Duration(seconds: 25))) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
    } on TimeoutException {
      await sink.close();
      if (await file.exists()) await file.delete();
      throw const UpdateException(
          'Download stalled. Check the kiosk\'s internet connection and try again.');
    }
    await sink.flush();
    await sink.close();

    if (total > 0 && received < total) {
      if (await file.exists()) await file.delete();
      throw UpdateException(
          'Download incomplete ($received of $total bytes). Try again.');
    }

    return file.path;
  }

  /// Has the user granted the "install unknown apps" permission for our package?
  static Future<bool> canRequestInstalls() async {
    if (!_isAndroid) return false;
    try {
      return (await _channel.invokeMethod<bool>('canRequestInstalls')) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Opens Android Settings → "Install unknown apps" so the admin can allow
  /// installs for our package. After they tap Allow, [canRequestInstalls]
  /// will return true and [installApk] can run without the user-grant step.
  static Future<bool> openInstallSettings() async {
    if (!_isAndroid) return false;
    try {
      return (await _channel.invokeMethod<bool>('openInstallSettings')) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Launches the PackageInstaller intent. Returns true if Android opened
  /// the install prompt — the admin still has to confirm the install on
  /// the system dialog (this can't be silent without Device Owner).
  static Future<bool> installApk(String path) async {
    if (!_isAndroid) return false;
    try {
      return (await _channel.invokeMethod<bool>('installApk', {'path': path})) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Silent install via `su pm install -r`. The Reyeah tablets are
  /// pre-rooted so this path works without user interaction — same
  /// trick the factory APK uses for its OTA updates. Returns false if
  /// su isn't granted or pm fails; callers should fall back to
  /// [installApk] for the dialog-based flow.
  static Future<bool> installApkSilent(String path) async {
    if (!_isAndroid) return false;
    try {
      return (await _channel.invokeMethod<bool>(
              'installApkSilent', {'path': path})) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// Convenience: full check → download → install pipeline.
  /// Returns the [UpdateInfo] for the version that's about to be installed,
  /// or `UpdateInfo.none()` if no update was available.
  static Future<UpdateInfo> checkDownloadAndInstall({
    void Function(int downloaded, int total)? onProgress,
  }) async {
    final info = await check();
    if (!info.available) return info;

    final path = await download(info, onProgress: onProgress);
    await installApk(path);
    return info;
  }
}

class UpdateException implements Exception {
  final String message;
  const UpdateException(this.message);
  @override
  String toString() => message;
}
