import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../models/release_metadata.dart';

class InstalledReleaseIdentity {
  const InstalledReleaseIdentity({
    required this.versionName,
    required this.buildNumber,
    required this.applicationId,
    required this.installerStore,
  });

  final String versionName;
  final int buildNumber;
  final String applicationId;
  final String installerStore;

  String get fullVersion => '$versionName ($buildNumber)';
}

/// Loads the immutable release manifest bundled into the artifact and the
/// identity reported by the installed Android/iOS package.
class ReleaseMetadataService {
  ReleaseMetadataService._();

  static final ReleaseMetadataService instance = ReleaseMetadataService._();

  Future<void>? _initialization;
  ReleaseMetadata? _metadata;
  InstalledReleaseIdentity? _installed;
  String _identityError = '';

  ReleaseMetadata? get metadata => _metadata;
  InstalledReleaseIdentity? get installed => _installed;
  String get identityError => _identityError;
  bool get identityMatchesManifest {
    final metadata = _metadata;
    final installed = _installed;
    if (metadata == null || installed == null) return false;
    final platform =
        !kIsWeb && Platform.isIOS ? metadata.ios : metadata.android;
    return installed.applicationId == platform.applicationId &&
        installed.versionName == metadata.versionName &&
        installed.buildNumber == metadata.buildNumber;
  }

  Future<void> initialize() {
    final existing = _initialization;
    if (existing != null) return existing;
    final request = _initializeOnce();
    _initialization = request;
    return request;
  }

  Future<void> _initializeOnce() async {
    try {
      _metadata = ReleaseMetadata.decode(
        await rootBundle.loadString('assets/release/release_metadata.json'),
      );
      final package = await PackageInfo.fromPlatform();
      _installed = InstalledReleaseIdentity(
        versionName: package.version,
        buildNumber: int.tryParse(package.buildNumber) ?? 0,
        applicationId: package.packageName,
        installerStore: package.installerStore ?? '',
      );
      if (!identityMatchesManifest) {
        _identityError = 'installed_manifest_mismatch';
      }
    } catch (error) {
      _identityError = 'release_identity_unavailable';
      if (kDebugMode) {
        debugPrint('[Release] identity initialization failed: '
            '${error.runtimeType}');
      }
    }
  }
}
