import 'dart:convert';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../services/app_config.dart';

/// Import and resolve locally stored ad images (picked from device storage).
class LocalAdMediaService {
  LocalAdMediaService._();

  static const _subdir = 'kiosk_ads';
  static const localPrefix = 'local_ad://';

  /// Opens the system file picker, copies the image into app storage,
  /// and returns a portable [local_ad://…] URI for [Advertisement.mediaUrl].
  static Future<String?> pickAndImportImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: kIsWeb,
    );
    if (result == null || result.files.isEmpty) return null;

    final picked = result.files.single;
    final ext = _normalizeExt(picked.extension);

    if (kIsWeb) {
      final bytes = picked.bytes;
      if (bytes == null || bytes.isEmpty) return null;
      final b64 = base64Encode(bytes);
      return 'data:image/$ext;base64,$b64';
    }

    final dir = await _adsDir();
    final name = 'ad-${DateTime.now().millisecondsSinceEpoch}.$ext';
    final dest = File('${dir.path}/$name');

    if (picked.path != null && picked.path!.isNotEmpty) {
      await File(picked.path!).copy(dest.path);
    } else if (picked.bytes != null) {
      await dest.writeAsBytes(picked.bytes!);
    } else {
      return null;
    }

    return '$localPrefix$name';
  }

  static Future<File?> resolveFile(String mediaUrl) async {
    if (!mediaUrl.startsWith(localPrefix)) return null;
    final name = mediaUrl.substring(localPrefix.length);
    if (name.contains('..') || name.contains('/')) return null;
    final file = File('${(await _adsDir()).path}/$name');
    return file.existsSync() ? file : null;
  }

  static Future<Directory> _adsDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/$_subdir');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static String _normalizeExt(String? ext) {
    final e = (ext ?? 'jpg').toLowerCase();
    if (e == 'jpeg') return 'jpeg';
    if (e == 'png' || e == 'webp' || e == 'gif') return e;
    return 'jpg';
  }
}

/// Renders an ad image from network URL, bundled asset, or local file.
class AdMediaImage extends StatelessWidget {
  const AdMediaImage({
    super.key,
    required this.mediaUrl,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.error,
  });

  final String mediaUrl;
  final BoxFit fit;
  final Widget? placeholder;
  final Widget? error;

  @override
  Widget build(BuildContext context) {
    final raw = mediaUrl.trim();
    if (raw.isEmpty) return error ?? _black();

    if (raw.startsWith('assets/')) {
      return Image.asset(
        raw,
        fit: fit,
        errorBuilder: (_, __, ___) => error ?? _black(),
      );
    }

    if (raw.startsWith('data:image')) {
      try {
        final b64 = raw.split(',').last;
        return Image.memory(
          base64Decode(b64),
          fit: fit,
          errorBuilder: (_, __, ___) => error ?? _black(),
        );
      } catch (_) {
        return error ?? _black();
      }
    }

    if (raw.startsWith(LocalAdMediaService.localPrefix) ||
        raw.startsWith('file://') ||
        (!kIsWeb && raw.startsWith('/'))) {
      return FutureBuilder<File?>(
        future: _fileFor(raw),
        builder: (context, snap) {
          final file = snap.data;
          if (file == null) {
            return snap.connectionState == ConnectionState.waiting
                ? (placeholder ?? _black())
                : (error ?? _black());
          }
          return Image.file(
            file,
            fit: fit,
            errorBuilder: (_, __, ___) => error ?? _black(),
          );
        },
      );
    }

    return CachedNetworkImage(
      imageUrl: _resolveNetworkUrl(raw),
      fit: fit,
      fadeInDuration: const Duration(milliseconds: 200),
      placeholder: (_, __) => placeholder ?? _black(),
      errorWidget: (_, __, ___) => error ?? _black(),
    );
  }

  static Future<File?> _fileFor(String raw) async {
    if (raw.startsWith(LocalAdMediaService.localPrefix)) {
      return LocalAdMediaService.resolveFile(raw);
    }
    if (raw.startsWith('file://')) {
      final file = File.fromUri(Uri.parse(raw));
      return file.existsSync() ? file : null;
    }
    if (!kIsWeb) {
      final file = File(raw);
      return file.existsSync() ? file : null;
    }
    return null;
  }

  static String _resolveNetworkUrl(String raw) {
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    if (raw.startsWith('/')) {
      final base = AppConfig.apiBaseUrl;
      final origin = Uri.tryParse(base)?.origin ?? base;
      return '$origin$raw';
    }
    return raw;
  }

  static Widget _black() => const ColoredBox(color: Colors.black);
}

/// Short label for admin lists (hides long base64 payloads).
String adMediaLabel(String? mediaUrl) {
  if (mediaUrl == null || mediaUrl.isEmpty) return '(no media)';
  if (mediaUrl.startsWith('data:image')) return 'Local image (picked file)';
  if (mediaUrl.startsWith(LocalAdMediaService.localPrefix)) {
    return 'Local: ${mediaUrl.substring(LocalAdMediaService.localPrefix.length)}';
  }
  return mediaUrl;
}
