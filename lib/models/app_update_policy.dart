enum StoreReleaseState {
  draft,
  uploaded,
  storeProcessing,
  storeReady,
  active,
  paused,
  unknown,
}

StoreReleaseState parseStoreReleaseState(String value) {
  switch (value.trim()) {
    case 'draft':
      return StoreReleaseState.draft;
    case 'uploaded':
      return StoreReleaseState.uploaded;
    case 'storeProcessing':
      return StoreReleaseState.storeProcessing;
    case 'storeReady':
      return StoreReleaseState.storeReady;
    case 'active':
      return StoreReleaseState.active;
    case 'paused':
      return StoreReleaseState.paused;
    default:
      return StoreReleaseState.unknown;
  }
}

class AppUpdatePolicy {
  const AppUpdatePolicy({
    required this.killSwitch,
    required this.minimumBuild,
    required this.latestBuild,
    required this.latestVersionName,
    required this.forceUpdate,
    required this.storeUrl,
    required this.releaseState,
    required this.releaseId,
    required this.source,
  });

  final bool killSwitch;
  final int minimumBuild;
  final int latestBuild;
  final String latestVersionName;
  final bool forceUpdate;
  final String storeUrl;
  final StoreReleaseState releaseState;
  final String releaseId;
  final String source;

  bool get isSane =>
      minimumBuild >= 0 &&
      latestBuild >= minimumBuild &&
      Uri.tryParse(storeUrl)?.hasScheme == true;

  bool get canPrompt =>
      !killSwitch &&
      isSane &&
      releaseId.isNotEmpty &&
      (releaseState == StoreReleaseState.storeReady ||
          releaseState == StoreReleaseState.active);

  Map<String, dynamic> toJson() => {
        'killSwitch': killSwitch,
        'minimumBuild': minimumBuild,
        'latestBuild': latestBuild,
        'latestVersionName': latestVersionName,
        'forceUpdate': forceUpdate,
        'storeUrl': storeUrl,
        'releaseState': releaseState.name,
        'releaseId': releaseId,
        'source': source,
      };

  factory AppUpdatePolicy.fromJson(
    Map<String, dynamic> json, {
    required String source,
  }) {
    return AppUpdatePolicy(
      killSwitch: json['killSwitch'] == true,
      minimumBuild: _asInt(json['minimumBuild']),
      latestBuild: _asInt(json['latestBuild']),
      latestVersionName: (json['latestVersionName'] ?? '').toString(),
      forceUpdate: json['forceUpdate'] == true,
      storeUrl: (json['storeUrl'] ?? '').toString(),
      releaseState:
          parseStoreReleaseState((json['releaseState'] ?? '').toString()),
      releaseId: (json['releaseId'] ?? '').toString(),
      source: source,
    );
  }

  static int _asInt(dynamic value) =>
      value is int ? value : int.tryParse(value?.toString() ?? '') ?? 0;
}

enum AppUpdateDecision { none, optional, mandatory }

class AppUpdateEvaluation {
  const AppUpdateEvaluation({
    required this.decision,
    required this.storeVerified,
    required this.reason,
  });

  final AppUpdateDecision decision;
  final bool storeVerified;
  final String reason;
}
