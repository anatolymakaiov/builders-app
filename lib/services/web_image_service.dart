import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

class WebImageResolution {
  const WebImageResolution({
    required this.url,
    required this.originalUrl,
    this.extension,
    this.contentType,
    this.usedDerivative = false,
    this.unsupported = false,
  });

  final String url;
  final String originalUrl;
  final String? extension;
  final String? contentType;
  final bool usedDerivative;
  final bool unsupported;
}

class WebImageService {
  WebImageService({
    FirebaseStorage? storage,
    FirebaseFunctions? functions,
  })  : _storage = storage ?? FirebaseStorage.instance,
        _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseStorage _storage;
  final FirebaseFunctions _functions;
  final Map<String, Future<WebImageResolution>> _resolutionCache = {};

  static final WebImageService instance = WebImageService();

  Future<WebImageResolution> resolve(String rawUrl) {
    final url = rawUrl.trim();
    return _resolutionCache.putIfAbsent(url, () => _resolve(url));
  }

  Future<WebImageResolution> _resolve(String url) async {
    final extension = detectExtension(url);
    String? contentType;

    try {
      final metadata = await _storage.refFromURL(url).getMetadata();
      contentType = metadata.contentType;
      _debug(
        "WEB IMAGE METADATA url=${sanitizeUrl(url)} "
        "extension=${extension ?? ""} contentType=${contentType ?? ""}",
      );
    } catch (error) {
      _debug(
        "WEB IMAGE METADATA FAILED url=${sanitizeUrl(url)} "
        "extension=${extension ?? ""} error=$error",
      );
    }

    if (_isHeic(extension, contentType)) {
      try {
        final callable = _functions.httpsCallable("getWebCompatibleImage");
        final result = await callable.call({"url": url});
        final data = Map<String, dynamic>.from(result.data as Map);
        final derivativeUrl = data["url"]?.toString().trim() ?? "";
        if (derivativeUrl.isNotEmpty) {
          _debug(
            "WEB IMAGE DERIVATIVE READY original=${sanitizeUrl(url)} "
            "derivative=${sanitizeUrl(derivativeUrl)}",
          );
          return WebImageResolution(
            url: derivativeUrl,
            originalUrl: url,
            extension: extension,
            contentType: contentType,
            usedDerivative: true,
          );
        }
      } catch (error) {
        _debug(
          "WEB IMAGE DERIVATIVE FAILED url=${sanitizeUrl(url)} "
          "extension=${extension ?? ""} contentType=${contentType ?? ""} "
          "error=$error",
        );
      }

      return WebImageResolution(
        url: url,
        originalUrl: url,
        extension: extension,
        contentType: contentType,
        unsupported: true,
      );
    }

    return WebImageResolution(
      url: url,
      originalUrl: url,
      extension: extension,
      contentType: contentType,
    );
  }

  static String sanitizeUrl(String url) {
    final parsed = Uri.tryParse(url);
    if (parsed == null) return "<invalid-url>";
    return parsed
        .replace(query: parsed.hasQuery ? "<redacted>" : "")
        .toString();
  }

  static String? detectExtension(String url) {
    final storagePath = storagePathFromUrl(url);
    final candidate = storagePath ?? Uri.tryParse(url)?.pathSegments.last;
    if (candidate == null || candidate.isEmpty) return null;
    final clean = Uri.decodeComponent(candidate).split("?").first.toLowerCase();
    final dot = clean.lastIndexOf(".");
    if (dot < 0 || dot == clean.length - 1) return null;
    return clean.substring(dot + 1);
  }

  static String? storagePathFromUrl(String url) {
    final parsed = Uri.tryParse(url);
    if (parsed == null) return null;

    if (parsed.scheme == "gs") {
      return parsed.pathSegments.join("/");
    }

    final segments = parsed.pathSegments;
    final objectIndex = segments.indexOf("o");
    if (parsed.host.contains("firebasestorage.googleapis.com") &&
        objectIndex >= 0 &&
        objectIndex + 1 < segments.length) {
      return Uri.decodeComponent(segments.sublist(objectIndex + 1).join("/"));
    }

    if (parsed.host.contains("storage.googleapis.com") &&
        segments.length >= 2) {
      return Uri.decodeComponent(segments.skip(1).join("/"));
    }

    return null;
  }

  static bool _isHeic(String? extension, String? contentType) {
    final ext = extension?.toLowerCase();
    final type = contentType?.toLowerCase();
    return ext == "heic" ||
        ext == "heif" ||
        type == "image/heic" ||
        type == "image/heif";
  }

  static void logFailure(String url, Object error) {
    final extension = detectExtension(url);
    final lower = error.toString().toLowerCase();
    final category = lower.contains("decode") || lower.contains("encodingerror")
        ? "decode_or_unsupported_format"
        : lower.contains("cors") || lower.contains("network")
            ? "network_or_cors"
            : "image_load";
    _debug(
      "WEB IMAGE LOAD FAILED category=$category "
      "url=${sanitizeUrl(url)} extension=${extension ?? ""} error=$error",
    );
  }

  static void _debug(String message) {
    if (kDebugMode) debugPrint(message);
  }
}
