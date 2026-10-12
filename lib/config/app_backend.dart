import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import '../models/release_metadata.dart';
import '../services/release_metadata_service.dart';

/// Resolves which Cloud Functions region and which Storage bucket the app
/// talks to.
///
/// The values ship inside `assets/release/release_metadata.json` (`backend`)
/// so Store builds, which carry no `--dart-define`, still pick up the Seoul
/// backend. The compile-time defaults below must match that file; the release
/// guard enforces it. Debug builds may override both with
/// `--dart-define=WEFILLING_FUNCTIONS_REGION=...` and
/// `--dart-define=WEFILLING_UPLOAD_BUCKET=...`.
///
/// Firestore is intentionally not configurable here: the migration recreates
/// the `(default)` database in Seoul, so `FirebaseFirestore.instance` is
/// unchanged.
class AppBackend {
  AppBackend._();

  // Must equal assets/release/release_metadata.json `backend` (release guard).
  // 1.3.24 (P2, 2026-10-05): Seoul callables + Seoul upload bucket.
  static const String _defaultFunctionsRegion = String.fromEnvironment(
    'WEFILLING_FUNCTIONS_REGION',
    defaultValue: 'asia-northeast3',
  );
  static const String _defaultUploadBucket = String.fromEnvironment(
    'WEFILLING_UPLOAD_BUCKET',
    defaultValue: 'flutterproject3-af322-kr',
  );

  /// Used when the release manifest is unavailable or not loaded yet.
  static const BackendReleaseMetadata defaults = BackendReleaseMetadata(
    functionsRegion: _defaultFunctionsRegion,
    uploadStorageBucket: _defaultUploadBucket,
    legacyStorageBucket: BackendReleaseMetadata.legacyBucket,
  );

  static BackendReleaseMetadata? _override;

  static BackendReleaseMetadata get config {
    final override = _override;
    if (override != null) return override;
    final metadata = ReleaseMetadataService.instance.metadata;
    final backend = metadata?.backend;
    if (backend != null && backend.isValid) return backend;
    assert(() {
      if (metadata == null) {
        debugPrint('[Backend] release metadata not loaded; using defaults');
      }
      return true;
    }());
    return defaults;
  }

  /// Test seam. Pass null to restore manifest-driven resolution.
  @visibleForTesting
  static void debugOverride(BackendReleaseMetadata? config) {
    _override = config;
  }

  static String get summary {
    final c = config;
    return 'functions=${c.functionsRegion} upload=${c.uploadStorageBucket} '
        'legacy=${c.legacyStorageBucket}';
  }
}

/// Cloud Functions entry point for every callable in the app.
class AppFunctions {
  AppFunctions._();

  static FirebaseFunctions get instance =>
      FirebaseFunctions.instanceFor(region: AppBackend.config.functionsRegion);
}

/// Storage entry points. New objects go to [uploads]; existing objects are
/// opened with [forObject] using the `storageBucket` recorded on their
/// Firestore document (missing means the legacy US bucket).
class AppStorage {
  AppStorage._();

  static FirebaseStorage get legacy =>
      FirebaseStorage.instanceFor(bucket: AppBackend.config.legacyStorageBucket);

  static FirebaseStorage get uploads =>
      FirebaseStorage.instanceFor(bucket: AppBackend.config.uploadStorageBucket);

  /// Bucket name to persist next to a path uploaded through [uploads].
  static String get uploadBucketName => AppBackend.config.uploadStorageBucket;

  static bool get uploadsToLegacyBucket =>
      AppBackend.config.uploadStorageBucket ==
      AppBackend.config.legacyStorageBucket;

  /// Normalizes `gs://name/` to `name`. Empty input stays empty.
  static String normalizeBucketName(String? value) {
    var bucket = (value ?? '').trim();
    if (bucket.startsWith('gs://')) bucket = bucket.substring(5);
    while (bucket.endsWith('/')) {
      bucket = bucket.substring(0, bucket.length - 1);
    }
    return bucket;
  }

  static bool isKnownBucket(String? value) {
    final bucket = normalizeBucketName(value);
    return bucket.isNotEmpty && AppBackend.config.knownBuckets.contains(bucket);
  }

  /// Resolves a recorded bucket name. Unknown names fall back to legacy so a
  /// malformed document can never point the client at a foreign bucket.
  static String resolveBucketName(String? storageBucket) {
    final bucket = normalizeBucketName(storageBucket);
    if (bucket.isEmpty) return AppBackend.config.legacyStorageBucket;
    if (!AppBackend.config.knownBuckets.contains(bucket)) {
      assert(() {
        debugPrint('[Backend] unknown storage bucket "$bucket"; using legacy');
        return true;
      }());
      return AppBackend.config.legacyStorageBucket;
    }
    return bucket;
  }

  static FirebaseStorage forObject(String? storageBucket) =>
      FirebaseStorage.instanceFor(bucket: resolveBucketName(storageBucket));

  /// Reference for an object path recorded together with its bucket.
  static Reference ref(String storagePath, {String? storageBucket}) =>
      forObject(storageBucket).ref(storagePath);

  /// Bucket embedded in a `gs://` or Firebase download URL, or null.
  static String? bucketFromUrl(String url) {
    final value = url.trim();
    if (value.isEmpty) return null;
    if (value.startsWith('gs://')) {
      final rest = value.substring(5);
      final slash = rest.indexOf('/');
      final bucket = slash < 0 ? rest : rest.substring(0, slash);
      return bucket.isEmpty ? null : bucket;
    }
    final uri = Uri.tryParse(value);
    if (uri == null || uri.scheme != 'https') return null;
    final host = uri.host.toLowerCase();
    final segments = uri.pathSegments;
    if (host == 'firebasestorage.googleapis.com') {
      // /v0/b/<bucket>/o/<object>
      final index = segments.indexOf('b');
      if (index >= 0 && index + 1 < segments.length) {
        return segments[index + 1];
      }
      return null;
    }
    if (host == 'storage.googleapis.com' && segments.isNotEmpty) {
      return segments.first;
    }
    if (host.endsWith('.storage.googleapis.com')) {
      return host.substring(0, host.length - '.storage.googleapis.com'.length);
    }
    return null;
  }

  /// Like `FirebaseStorage.refFromURL`, but picks the instance whose bucket
  /// matches the URL so URLs from either bucket resolve.
  static Reference refFromUrl(String url) {
    final bucket = bucketFromUrl(url);
    final storage = bucket == null
        ? legacy
        : FirebaseStorage.instanceFor(bucket: bucket);
    return storage.refFromURL(url.trim());
  }

  /// Every bucket a user's objects may live in (deduplicated).
  static List<FirebaseStorage> get allKnown => AppBackend.config.knownBuckets
      .map((bucket) => FirebaseStorage.instanceFor(bucket: bucket))
      .toList(growable: false);
}
