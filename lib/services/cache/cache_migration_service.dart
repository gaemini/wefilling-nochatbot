import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/release_metadata.dart';
import 'app_image_cache_manager.dart';

class CacheMigrationResult {
  const CacheMigrationResult({
    required this.previousBuild,
    required this.currentBuild,
    required this.previousSchema,
    required this.currentSchema,
    required this.status,
    required this.invalidatedStores,
  });

  final int previousBuild;
  final int currentBuild;
  final int previousSchema;
  final int currentSchema;
  final String status;
  final List<String> invalidatedStores;
}

/// Selectively invalidates disposable caches before any cache consumer opens.
/// Auth/session, sign-up drafts, DM history, unread Snack Chat state and upload
/// queues are deliberately outside this migration.
class CacheMigrationService {
  CacheMigrationService._();

  static final CacheMigrationService instance = CacheMigrationService._();

  static const _buildKey = 'release.last_successful_build';
  static const _schemaKey = 'release.cache_schema';
  static const _statusKey = 'release.cache_migration_status';
  static const _fromBuildKey = 'release.cache_migration_from_build';
  static const _toBuildKey = 'release.cache_migration_to_build';
  static const _fromSchemaKey = 'release.cache_migration_from_schema';
  static const _toSchemaKey = 'release.cache_migration_to_schema';

  CacheMigrationResult? _lastResult;
  CacheMigrationResult? get lastResult => _lastResult;

  Future<CacheMigrationResult> migrate(ReleaseMetadata metadata) async {
    final prefs = await SharedPreferences.getInstance();
    final previousBuild = prefs.getInt(_buildKey) ?? 0;
    final previousSchema = prefs.getInt(_schemaKey) ?? 0;
    final targetBuild = metadata.buildNumber;
    final targetSchema = metadata.cacheSchemaVersion;

    if (previousSchema >= targetSchema) {
      await prefs.setInt(_buildKey, targetBuild);
      await prefs.setString(_statusKey, 'not_required');
      return _record(
        previousBuild,
        targetBuild,
        previousSchema,
        targetSchema,
        'not_required',
        const [],
      );
    }

    await prefs.setString(_statusKey, 'in_progress');
    await prefs.setInt(_fromBuildKey, previousBuild);
    await prefs.setInt(_toBuildKey, targetBuild);
    await prefs.setInt(_fromSchemaKey, previousSchema);
    await prefs.setInt(_toSchemaKey, targetSchema);
    if (kDebugMode) {
      debugPrint('[ReleaseEvent] event=cacheMigrationStarted '
          'previousBuild=$previousBuild currentBuild=$targetBuild '
          'previousSchema=$previousSchema currentSchema=$targetSchema');
    }

    final stores = <String>{};
    for (var schema = previousSchema + 1; schema <= targetSchema; schema++) {
      final step = metadata.migrations[schema];
      if (step == null) {
        await prefs.setString(_statusKey, 'missing_plan');
        throw StateError('Missing cache migration plan for schema $schema');
      }
      stores.addAll(step);
    }

    try {
      for (final store in stores) {
        if (store == AppImageCacheManager.cacheKey) {
          await AppImageCacheManager.clear();
          continue;
        }
        if (Hive.isBoxOpen(store)) {
          await Hive.box<dynamic>(store).close();
        }
        await Hive.deleteBoxFromDisk(store);
      }
      await prefs.setInt(_schemaKey, targetSchema);
      await prefs.setInt(_buildKey, targetBuild);
      await prefs.setString(_statusKey, 'completed');
      return _record(
        previousBuild,
        targetBuild,
        previousSchema,
        targetSchema,
        'completed',
        stores.toList(growable: false),
      );
    } catch (error) {
      // The schema is intentionally not advanced. Re-entering this method is
      // safe because deleting an already deleted disposable cache is a no-op.
      await prefs.setString(_statusKey, 'failed');
      _record(
        previousBuild,
        targetBuild,
        previousSchema,
        targetSchema,
        'failed',
        stores.toList(growable: false),
      );
      rethrow;
    }
  }

  CacheMigrationResult _record(
    int previousBuild,
    int currentBuild,
    int previousSchema,
    int currentSchema,
    String status,
    List<String> stores,
  ) {
    final result = CacheMigrationResult(
      previousBuild: previousBuild,
      currentBuild: currentBuild,
      previousSchema: previousSchema,
      currentSchema: currentSchema,
      status: status,
      invalidatedStores: stores,
    );
    _lastResult = result;
    if (kDebugMode) {
      debugPrint('[ReleaseMigration] previousBuild=$previousBuild '
          'currentBuild=$currentBuild previousSchema=$previousSchema '
          'currentSchema=$currentSchema status=$status stores=${stores.length}');
    }
    return result;
  }
}
