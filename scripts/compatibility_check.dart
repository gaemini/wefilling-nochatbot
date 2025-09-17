#!/usr/bin/env dart
// scripts/compatibility_check.dart
// 기존 기능과의 호환성 검증 스크립트
// CI/CD 파이프라인에서 실행 가능한 호환성 체크

import 'dart:io';
import 'dart:convert';

/// 호환성 검증 결과
class CompatibilityResult {
  final String testName;
  final bool passed;
  final String message;
  final Duration duration;

  CompatibilityResult({
    required this.testName,
    required this.passed,
    required this.message,
    required this.duration,
  });

  @override
  String toString() {
    final status = passed ? '✅' : '❌';
    return '$status $testName (${duration.inMilliseconds}ms): $message';
  }
}

/// 호환성 검증 테스트 러너
class CompatibilityChecker {
  final List<CompatibilityResult> results = [];

  /// 모든 호환성 테스트 실행
  Future<bool> runAllTests() async {
    print('🔍 기존 기능 호환성 검증 시작...\n');

    final tests = [
      _testFlutterAnalyze,
      _testFlutterTest,
      _testExistingImports,
      _testModelCompatibility,
      _testServiceCompatibility,
      _testUICompatibility,
      _testFirestoreRulesCompatibility,
      _testFeatureFlagIsolation,
      _testPerformanceImpact,
      _testMemoryUsage,
    ];

    for (final test in tests) {
      await _runTest(test);
    }

    _printResults();
    return results.every((r) => r.passed);
  }

  /// 개별 테스트 실행 및 결과 기록
  Future<void> _runTest(Future<CompatibilityResult> Function() test) async {
    try {
      final result = await test();
      results.add(result);
    } catch (e) {
      results.add(CompatibilityResult(
        testName: 'Unknown Test',
        passed: false,
        message: 'Exception: $e',
        duration: Duration.zero,
      ));
    }
  }

  /// Flutter Analyze 실행
  Future<CompatibilityResult> _testFlutterAnalyze() async {
    final stopwatch = Stopwatch()..start();
    
    try {
      final result = await Process.run('flutter', ['analyze', '--no-pub']);
      stopwatch.stop();

      final passed = result.exitCode == 0;
      final message = passed 
          ? 'No analysis issues found'
          : 'Analysis issues detected:\n${result.stdout}\n${result.stderr}';

      return CompatibilityResult(
        testName: 'Flutter Analyze',
        passed: passed,
        message: message,
        duration: stopwatch.elapsed,
      );
    } catch (e) {
      stopwatch.stop();
      return CompatibilityResult(
        testName: 'Flutter Analyze',
        passed: false,
        message: 'Failed to run flutter analyze: $e',
        duration: stopwatch.elapsed,
      );
    }
  }

  /// Flutter Test 실행
  Future<CompatibilityResult> _testFlutterTest() async {
    final stopwatch = Stopwatch()..start();
    
    try {
      final result = await Process.run('flutter', ['test', '--no-pub']);
      stopwatch.stop();

      final passed = result.exitCode == 0;
      final message = passed 
          ? 'All tests passed'
          : 'Test failures detected:\n${result.stdout}\n${result.stderr}';

      return CompatibilityResult(
        testName: 'Flutter Test',
        passed: passed,
        message: message,
        duration: stopwatch.elapsed,
      );
    } catch (e) {
      stopwatch.stop();
      return CompatibilityResult(
        testName: 'Flutter Test',
        passed: false,
        message: 'Failed to run flutter test: $e',
        duration: stopwatch.elapsed,
      );
    }
  }

  /// 기존 imports 호환성 검증
  Future<CompatibilityResult> _testExistingImports() async {
    final stopwatch = Stopwatch()..start();
    
    try {
      final libDir = Directory('lib');
      final dartFiles = await _findDartFiles(libDir);
      
      final conflicts = <String>[];
      final newImports = [
        'review_consensus_service',
        'review_adapter_service',
        'feature_flag_service',
        'review_request',
        'review_consensus',
      ];

      for (final file in dartFiles) {
        final content = await file.readAsString();
        
        // 기존 파일이 새로운 import를 사용하는지 확인
        for (final newImport in newImports) {
          if (content.contains(newImport) && 
              !file.path.contains('review_') && 
              !file.path.contains('feature_flag')) {
            conflicts.add('${file.path} imports $newImport');
          }
        }
      }

      stopwatch.stop();

      final passed = conflicts.isEmpty;
      final message = passed 
          ? 'No import conflicts detected'
          : 'Import conflicts found:\n${conflicts.join('\n')}';

      return CompatibilityResult(
        testName: 'Import Compatibility',
        passed: passed,
        message: message,
        duration: stopwatch.elapsed,
      );
    } catch (e) {
      stopwatch.stop();
      return CompatibilityResult(
        testName: 'Import Compatibility',
        passed: false,
        message: 'Failed to check imports: $e',
        duration: stopwatch.elapsed,
      );
    }
  }

  /// 모델 호환성 검증
  Future<CompatibilityResult> _testModelCompatibility() async {
    final stopwatch = Stopwatch()..start();
    
    try {
      final modelsDir = Directory('lib/models');
      if (!await modelsDir.exists()) {
        stopwatch.stop();
        return CompatibilityResult(
          testName: 'Model Compatibility',
          passed: false,
          message: 'Models directory not found',
          duration: stopwatch.elapsed,
        );
      }

      final modelFiles = await _findDartFiles(modelsDir);
      final existingModels = [
        'post.dart',
        'meetup.dart',
        'comment.dart',
        'app_notification.dart',
        'user_profile.dart',
      ];

      final missingModels = <String>[];
      for (final model in existingModels) {
        final exists = modelFiles.any((f) => f.path.endsWith(model));
        if (!exists) {
          missingModels.add(model);
        }
      }

      // 새로운 모델들이 기존 모델을 변경했는지 확인
      final modifications = <String>[];
      for (final file in modelFiles) {
        if (existingModels.any((m) => file.path.endsWith(m))) {
          final content = await file.readAsString();
          // 새로운 필드나 메서드가 추가되었는지 확인
          if (content.contains('review') && !content.contains('// REVIEW_CONSENSUS:')) {
            modifications.add('${file.path} may have been modified for review feature');
          }
        }
      }

      stopwatch.stop();

      final passed = missingModels.isEmpty && modifications.isEmpty;
      final message = passed 
          ? 'All existing models are intact'
          : 'Issues found:\nMissing: ${missingModels.join(', ')}\nModifications: ${modifications.join('\n')}';

      return CompatibilityResult(
        testName: 'Model Compatibility',
        passed: passed,
        message: message,
        duration: stopwatch.elapsed,
      );
    } catch (e) {
      stopwatch.stop();
      return CompatibilityResult(
        testName: 'Model Compatibility',
        passed: false,
        message: 'Failed to check models: $e',
        duration: stopwatch.elapsed,
      );
    }
  }

  /// 서비스 호환성 검증
  Future<CompatibilityResult> _testServiceCompatibility() async {
    final stopwatch = Stopwatch()..start();
    
    try {
      final servicesDir = Directory('lib/services');
      final serviceFiles = await _findDartFiles(servicesDir);
      
      final coreServices = [
        'auth_service.dart',
        'post_service.dart',
        'meetup_service.dart',
        'notification_service.dart',
        'storage_service.dart',
      ];

      final issues = <String>[];
      
      for (final service in coreServices) {
        final file = serviceFiles.firstWhere(
          (f) => f.path.endsWith(service),
          orElse: () => File(''),
        );

        if (!await file.exists()) {
          issues.add('Missing service: $service');
          continue;
        }

        final content = await file.readAsString();
        
        // 기존 public API가 변경되었는지 확인
        final criticalMethods = {
          'auth_service.dart': ['signInWithGoogle', 'signOut', 'currentUser'],
          'post_service.dart': ['addPost', 'getAllPosts', 'deletePost'],
          'meetup_service.dart': ['createMeetup', 'getMeetups', 'joinMeetup'],
          'notification_service.dart': ['createNotification', 'getUserNotifications'],
          'storage_service.dart': ['uploadImage'],
        };

        final requiredMethods = criticalMethods[service] ?? [];
        for (final method in requiredMethods) {
          if (!content.contains(method)) {
            issues.add('$service: Missing method $method');
          }
        }
      }

      stopwatch.stop();

      final passed = issues.isEmpty;
      final message = passed 
          ? 'All core services are compatible'
          : 'Service compatibility issues:\n${issues.join('\n')}';

      return CompatibilityResult(
        testName: 'Service Compatibility',
        passed: passed,
        message: message,
        duration: stopwatch.elapsed,
      );
    } catch (e) {
      stopwatch.stop();
      return CompatibilityResult(
        testName: 'Service Compatibility',
        passed: false,
        message: 'Failed to check services: $e',
        duration: stopwatch.elapsed,
      );
    }
  }

  /// UI 호환성 검증
  Future<CompatibilityResult> _testUICompatibility() async {
    final stopwatch = Stopwatch()..start();
    
    try {
      final screensDir = Directory('lib/screens');
      final screenFiles = await _findDartFiles(screensDir);
      
      final coreScreens = [
        'main_screen.dart',
        'home_screen.dart',
        'create_post_screen.dart',
        'create_meetup_screen.dart',
        'notification_screen.dart',
      ];

      final issues = <String>[];
      
      for (final screen in coreScreens) {
        final file = screenFiles.firstWhere(
          (f) => f.path.endsWith(screen),
          orElse: () => File(''),
        );

        if (!await file.exists()) {
          issues.add('Missing screen: $screen');
          continue;
        }

        final content = await file.readAsString();
        
        // 새로운 import가 기존 화면에 추가되었는지 확인
        final newImports = [
          'review_request_screen',
          'review_accept_screen',
          'feature_flag_service',
        ];

        for (final import in newImports) {
          if (content.contains(import)) {
            // Feature Flag로 보호되어 있는지 확인
            if (!content.contains('FeatureFlagService') || 
                !content.contains('isReviewConsensusEnabled')) {
              issues.add('$screen uses $import without feature flag protection');
            }
          }
        }
      }

      stopwatch.stop();

      final passed = issues.isEmpty;
      final message = passed 
          ? 'UI components are compatible'
          : 'UI compatibility issues:\n${issues.join('\n')}';

      return CompatibilityResult(
        testName: 'UI Compatibility',
        passed: passed,
        message: message,
        duration: stopwatch.elapsed,
      );
    } catch (e) {
      stopwatch.stop();
      return CompatibilityResult(
        testName: 'UI Compatibility',
        passed: false,
        message: 'Failed to check UI: $e',
        duration: stopwatch.elapsed,
      );
    }
  }

  /// Firestore 규칙 호환성 검증
  Future<CompatibilityResult> _testFirestoreRulesCompatibility() async {
    final stopwatch = Stopwatch()..start();
    
    try {
      final rulesFile = File('firestore.rules');
      if (!await rulesFile.exists()) {
        stopwatch.stop();
        return CompatibilityResult(
          testName: 'Firestore Rules',
          passed: false,
          message: 'firestore.rules file not found',
          duration: stopwatch.elapsed,
        );
      }

      final content = await rulesFile.readAsString();
      
      // 기존 규칙들이 여전히 존재하는지 확인
      final existingRules = [
        'match /users/{userId}',
        'match /posts/{postId}',
        'match /comments/{commentId}',
        'match /meetups/{meetupId}',
        'match /notifications/{notificationId}',
      ];

      final missingRules = <String>[];
      for (final rule in existingRules) {
        if (!content.contains(rule)) {
          missingRules.add(rule);
        }
      }

      // 새로운 규칙들이 추가되었는지 확인
      final newRules = [
        'match /admin_settings/{document}',
        'match /meetings/{meetupId}/pendingReviews/{reviewId}',
        'match /meetings/{meetupId}/reviews/{consensusId}',
      ];

      final missingNewRules = <String>[];
      for (final rule in newRules) {
        if (!content.contains(rule)) {
          missingNewRules.add(rule);
        }
      }

      stopwatch.stop();

      final passed = missingRules.isEmpty && missingNewRules.isEmpty;
      final message = passed 
          ? 'Firestore rules are properly configured'
          : 'Rules issues:\nMissing existing: ${missingRules.join(', ')}\nMissing new: ${missingNewRules.join(', ')}';

      return CompatibilityResult(
        testName: 'Firestore Rules',
        passed: passed,
        message: message,
        duration: stopwatch.elapsed,
      );
    } catch (e) {
      stopwatch.stop();
      return CompatibilityResult(
        testName: 'Firestore Rules',
        passed: false,
        message: 'Failed to check Firestore rules: $e',
        duration: stopwatch.elapsed,
      );
    }
  }

  /// Feature Flag 격리 검증
  Future<CompatibilityResult> _testFeatureFlagIsolation() async {
    final stopwatch = Stopwatch()..start();
    
    try {
      final libDir = Directory('lib');
      final dartFiles = await _findDartFiles(libDir);
      
      final violations = <String>[];
      
      for (final file in dartFiles) {
        final content = await file.readAsString();
        
        // 새로운 기능이 Feature Flag 없이 사용되는지 확인
        if (file.path.contains('review_') || 
            content.contains('ReviewConsensusService') ||
            content.contains('ReviewRequest') ||
            content.contains('ReviewConsensus')) {
          
          // Feature Flag로 보호되어 있는지 확인
          if (!content.contains('FeatureFlagService') && 
              !content.contains('_executeIfEnabled') &&
              !file.path.endsWith('_test.dart') &&
              !file.path.contains('models/') &&
              !file.path.contains('adapter_service.dart')) {
            violations.add('${file.path} uses review features without feature flag');
          }
        }
      }

      stopwatch.stop();

      final passed = violations.isEmpty;
      final message = passed 
          ? 'Feature flag isolation is properly maintained'
          : 'Feature flag violations:\n${violations.join('\n')}';

      return CompatibilityResult(
        testName: 'Feature Flag Isolation',
        passed: passed,
        message: message,
        duration: stopwatch.elapsed,
      );
    } catch (e) {
      stopwatch.stop();
      return CompatibilityResult(
        testName: 'Feature Flag Isolation',
        passed: false,
        message: 'Failed to check feature flag isolation: $e',
        duration: stopwatch.elapsed,
      );
    }
  }

  /// 성능 영향 검증
  Future<CompatibilityResult> _testPerformanceImpact() async {
    final stopwatch = Stopwatch()..start();
    
    try {
      // 새로운 서비스들이 앱 시작 시 초기화되는지 확인
      final mainFile = File('lib/main.dart');
      if (!await mainFile.exists()) {
        stopwatch.stop();
        return CompatibilityResult(
          testName: 'Performance Impact',
          passed: false,
          message: 'main.dart not found',
          duration: stopwatch.elapsed,
        );
      }

      final content = await mainFile.readAsString();
      
      final performanceIssues = <String>[];
      
      // 새로운 서비스들이 main에서 즉시 초기화되는지 확인
      final heavyServices = [
        'ReviewConsensusService',
        'FeatureFlagService',
        'ReviewImageAdapter',
      ];

      for (final service in heavyServices) {
        if (content.contains(service) && content.contains('main()')) {
          performanceIssues.add('$service is initialized in main() - consider lazy loading');
        }
      }

      // pubspec.yaml에서 새로운 의존성 확인
      final pubspecFile = File('pubspec.yaml');
      if (await pubspecFile.exists()) {
        final pubspecContent = await pubspecFile.readAsString();
        
        // 새로운 무거운 의존성이 추가되었는지 확인
        final heavyDependencies = [
          'video_player',
          'camera',
          'ml_kit',
          'tensorflow',
        ];

        for (final dep in heavyDependencies) {
          if (pubspecContent.contains(dep)) {
            performanceIssues.add('Heavy dependency added: $dep');
          }
        }
      }

      stopwatch.stop();

      final passed = performanceIssues.isEmpty;
      final message = passed 
          ? 'No significant performance impact detected'
          : 'Performance concerns:\n${performanceIssues.join('\n')}';

      return CompatibilityResult(
        testName: 'Performance Impact',
        passed: passed,
        message: message,
        duration: stopwatch.elapsed,
      );
    } catch (e) {
      stopwatch.stop();
      return CompatibilityResult(
        testName: 'Performance Impact',
        passed: false,
        message: 'Failed to check performance impact: $e',
        duration: stopwatch.elapsed,
      );
    }
  }

  /// 메모리 사용량 검증
  Future<CompatibilityResult> _testMemoryUsage() async {
    final stopwatch = Stopwatch()..start();
    
    try {
      // 새로운 클래스들이 싱글톤 패턴을 사용하는지 확인
      final servicesDir = Directory('lib/services');
      final serviceFiles = await _findDartFiles(servicesDir);
      
      final memoryIssues = <String>[];
      
      for (final file in serviceFiles) {
        if (file.path.contains('review_') || 
            file.path.contains('feature_flag')) {
          
          final content = await file.readAsString();
          
          // 싱글톤 패턴 사용 여부 확인
          if (content.contains('class ') && 
              content.contains('Service') &&
              !content.contains('_instance') &&
              !content.contains('factory')) {
            memoryIssues.add('${file.path} may not use singleton pattern');
          }
          
          // 대용량 캐시 사용 여부 확인
          if (content.contains('Map<') && 
              content.contains('cache') &&
              !content.contains('clear')) {
            memoryIssues.add('${file.path} uses cache without clear mechanism');
          }
        }
      }

      stopwatch.stop();

      final passed = memoryIssues.isEmpty;
      final message = passed 
          ? 'Memory usage patterns are acceptable'
          : 'Memory concerns:\n${memoryIssues.join('\n')}';

      return CompatibilityResult(
        testName: 'Memory Usage',
        passed: passed,
        message: message,
        duration: stopwatch.elapsed,
      );
    } catch (e) {
      stopwatch.stop();
      return CompatibilityResult(
        testName: 'Memory Usage',
        passed: false,
        message: 'Failed to check memory usage: $e',
        duration: stopwatch.elapsed,
      );
    }
  }

  /// 결과 출력
  void _printResults() {
    print('\n📊 호환성 검증 결과:\n');
    
    for (final result in results) {
      print(result.toString());
    }

    final passed = results.where((r) => r.passed).length;
    final total = results.length;
    final percentage = (passed / total * 100).toStringAsFixed(1);

    print('\n' + '=' * 50);
    print('총 $total개 테스트 중 $passed개 통과 ($percentage%)');
    
    if (passed == total) {
      print('🎉 모든 호환성 테스트 통과!');
    } else {
      print('⚠️  ${total - passed}개 테스트 실패');
    }
    print('=' * 50);
  }

  /// Dart 파일 검색
  Future<List<File>> _findDartFiles(Directory dir) async {
    final files = <File>[];
    
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File && entity.path.endsWith('.dart')) {
        files.add(entity);
      }
    }
    
    return files;
  }
}

/// 메인 실행 함수
Future<void> main(List<String> args) async {
  final checker = CompatibilityChecker();
  final success = await checker.runAllTests();
  
  exit(success ? 0 : 1);
}
