import 'dart:convert';

class PlatformReleaseMetadata {
  const PlatformReleaseMetadata({
    required this.applicationId,
    required this.storeUrl,
    required this.releaseState,
    this.flavor = '',
    this.entryPoint = '',
    this.scheme = '',
    this.configuration = '',
    this.teamId = '',
    this.firebaseAppId = '',
    this.appStoreId = '',
  });

  final String applicationId;
  final String storeUrl;
  final String releaseState;
  final String flavor;
  final String entryPoint;
  final String scheme;
  final String configuration;
  final String teamId;
  final String firebaseAppId;
  final String appStoreId;

  factory PlatformReleaseMetadata.fromJson(
    Map<String, dynamic> json, {
    required bool ios,
  }) {
    return PlatformReleaseMetadata(
      applicationId:
          (json[ios ? 'bundleId' : 'applicationId'] ?? '').toString(),
      storeUrl: (json['storeUrl'] ?? '').toString(),
      releaseState: (json['releaseState'] ?? 'draft').toString(),
      flavor: (json['flavor'] ?? '').toString(),
      entryPoint: (json['entryPoint'] ?? '').toString(),
      scheme: (json['scheme'] ?? '').toString(),
      configuration: (json['configuration'] ?? '').toString(),
      teamId: (json['teamId'] ?? '').toString(),
      firebaseAppId: (json['firebaseAppId'] ?? '').toString(),
      appStoreId: (json['appStoreId'] ?? '').toString(),
    );
  }
}

class ReleaseMetadata {
  const ReleaseMetadata({
    required this.schemaVersion,
    required this.versionName,
    required this.buildNumber,
    required this.cacheSchemaVersion,
    required this.releaseChannel,
    required this.releaseId,
    required this.firebaseProjectId,
    required this.android,
    required this.ios,
    required this.migrations,
  });

  final int schemaVersion;
  final String versionName;
  final int buildNumber;
  final int cacheSchemaVersion;
  final String releaseChannel;
  final String releaseId;
  final String firebaseProjectId;
  final PlatformReleaseMetadata android;
  final PlatformReleaseMetadata ios;
  final Map<int, List<String>> migrations;

  factory ReleaseMetadata.decode(String source) {
    final json = jsonDecode(source) as Map<String, dynamic>;
    final rawMigrations =
        (json['migrations'] as Map<String, dynamic>?) ?? const {};
    final migrations = <int, List<String>>{};
    for (final entry in rawMigrations.entries) {
      final version = int.tryParse(entry.key);
      if (version == null || entry.value is! List) continue;
      migrations[version] = (entry.value as List)
          .map((value) => value.toString())
          .where((value) => value.isNotEmpty)
          .toList(growable: false);
    }
    return ReleaseMetadata(
      schemaVersion: _int(json['schemaVersion']),
      versionName: (json['versionName'] ?? '').toString(),
      buildNumber: _int(json['buildNumber']),
      cacheSchemaVersion: _int(json['cacheSchemaVersion']),
      releaseChannel: (json['releaseChannel'] ?? '').toString(),
      releaseId: (json['releaseId'] ?? '').toString(),
      firebaseProjectId: (json['firebaseProjectId'] ?? '').toString(),
      android: PlatformReleaseMetadata.fromJson(
        (json['android'] as Map?)?.cast<String, dynamic>() ?? const {},
        ios: false,
      ),
      ios: PlatformReleaseMetadata.fromJson(
        (json['ios'] as Map?)?.cast<String, dynamic>() ?? const {},
        ios: true,
      ),
      migrations: migrations,
    );
  }

  static int _int(dynamic value) =>
      value is int ? value : int.tryParse(value?.toString() ?? '') ?? 0;
}
