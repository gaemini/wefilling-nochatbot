import 'package:flutter/material.dart';

import '../services/app_update_service.dart';
import '../services/cache/cache_migration_service.dart';
import '../services/firebase_app_check_service.dart';

class ReleaseDiagnosticsScreen extends StatelessWidget {
  const ReleaseDiagnosticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final values = <String, String>{
      ...AppUpdateService.instance.diagnostics.toDisplayMap(),
      'appCheckProvider': FirebaseAppCheckService.instance.providerName,
      'appCheckState': FirebaseAppCheckService.instance.readiness.name,
      'appCheckError': FirebaseAppCheckService.instance.lastErrorCode,
    };
    final migration = CacheMigrationService.instance.lastResult;
    if (migration != null) {
      values.addAll({
        'previousBuild': '${migration.previousBuild}',
        'currentBuild': '${migration.currentBuild}',
        'previousCacheSchema': '${migration.previousSchema}',
        'currentCacheSchema': '${migration.currentSchema}',
        'migrationStatus': migration.status,
      });
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Release diagnostics'),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          itemCount: values.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final entry = values.entries.elementAt(index);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 150,
                    child: Text(
                      entry.key,
                      style: const TextStyle(
                        color: Color(0xFF667085),
                        fontSize: 13,
                      ),
                    ),
                  ),
                  Expanded(
                    child: SelectableText(
                      entry.value.isEmpty ? '-' : entry.value,
                      style: const TextStyle(
                        color: Color(0xFF111827),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
