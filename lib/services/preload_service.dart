// lib/services/preload_service.dart
// 중요 콘텐츠 프리로딩 및 성능 최적화 서비스
// 히어로 콘텐츠 우선 로딩, 하위 콘텐츠 지연 로딩

import 'package:flutter/material.dart';
import '../utils/image_utils.dart';
import '../models/meetup.dart';
import '../models/post.dart';
import '../models/user_profile.dart';

/// 프리로딩 우선순위
enum PreloadPriority {
  critical, // 즉시 로딩 (히어로 콘텐츠)
  high, // 높은 우선순위 (above-the-fold)
  medium, // 중간 우선순위 (below-the-fold)
  low, // 낮은 우선순위 (지연 로딩)
}

/// 콘텐츠 타입
enum ContentType { meetup, post, user, image }

/// 프리로딩 아이템
class PreloadItem {
  final String id;
  final ContentType type;
  final PreloadPriority priority;
  final Map<String, dynamic> data;
  final DateTime createdAt;

  PreloadItem({
    required this.id,
    required this.type,
    required this.priority,
    required this.data,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PreloadItem && other.id == id && other.type == type;
  }

  @override
  int get hashCode => Object.hash(id, type);
}

/// 프리로딩 서비스
class PreloadService {
  static final PreloadService _instance = PreloadService._internal();
  factory PreloadService() => _instance;
  PreloadService._internal();

  final Map<String, PreloadItem> _preloadQueue = {};
  final Map<String, dynamic> _preloadedData = {};
  final Map<String, ImageProvider> _preloadedImages = {};

  bool _isProcessing = false;

  /// 프리로딩 큐에 아이템 추가
  void addToQueue(PreloadItem item) {
    final key = '${item.type.name}_${item.id}';
    _preloadQueue[key] = item;

    // 중요도가 높은 아이템은 즉시 처리
    if (item.priority == PreloadPriority.critical) {
      _processItem(item);
    } else if (!_isProcessing) {
      _processQueue();
    }
  }

  /// 모임 데이터 프리로딩
  void preloadMeetups(
    List<Meetup> meetups, {
    PreloadPriority priority = PreloadPriority.high,
  }) {
    for (int i = 0; i < meetups.length; i++) {
      final meetup = meetups[i];
      final itemPriority =
          i < 3 ? PreloadPriority.critical : priority; // 상위 3개는 중요

      // toMap() 의존 제거 - 이미지 URL만 안전하게 처리
      try {
        // 모임 이미지 프리로딩
        final imageUrl = (meetup as dynamic).imageUrl;
        if (imageUrl is String && imageUrl.isNotEmpty) {
          preloadImage(imageUrl, priority: itemPriority);
        }

        // 작성자 프로필 이미지는 현재 구현되지 않았으므로 주석 처리
        // 추후 필요시 host 기반으로 구현 가능
      } catch (e) {
        // 안전한 실패 처리
        debugPrint('Failed to preload meetup images: $e');
      }
    }
  }

  /// 게시글 데이터 프리로딩
  void preloadPosts(
    List<Post> posts, {
    PreloadPriority priority = PreloadPriority.high,
  }) {
    for (int i = 0; i < posts.length; i++) {
      final post = posts[i];
      final itemPriority =
          i < 3 ? PreloadPriority.critical : priority; // 상위 3개는 중요

      // toMap() 의존 제거 - 이미지 URL만 안전하게 처리
      try {
        // 게시글 이미지 프리로딩
        final imageUrls = (post as dynamic).imageUrls;
        if (imageUrls is List && imageUrls.isNotEmpty) {
          for (final imageUrl in imageUrls) {
            if (imageUrl is String && imageUrl.isNotEmpty) {
              preloadImage(imageUrl, priority: itemPriority);
            }
          }
        }

        // 작성자 프로필 이미지 프리로딩
        final author = (post as dynamic).author;
        if (author != null) {
          final profileImageUrl = (author as dynamic).profileImageUrl;
          if (profileImageUrl is String && profileImageUrl.isNotEmpty) {
            preloadImage(profileImageUrl, priority: PreloadPriority.medium);
          }
        }
      } catch (e) {
        // 안전한 실패 처리
        debugPrint('Failed to preload post images: $e');
      }
    }
  }

  /// 사용자 데이터 프리로딩
  void preloadUsers(
    List<dynamic> users, {
    PreloadPriority priority = PreloadPriority.medium,
  }) {
    for (final user in users) {
      // toMap() 의존 제거 - 이미지 URL만 안전하게 처리
      try {
        final profileImageUrl = (user as dynamic).profileImageUrl;
        if (profileImageUrl is String && profileImageUrl.isNotEmpty) {
          preloadImage(profileImageUrl, priority: priority);
        }
      } catch (e) {
        // 안전한 실패 처리
        debugPrint('Failed to preload user images: $e');
      }
    }
  }

  /// 이미지 프리로딩
  void preloadImage(
    String imageUrl, {
    PreloadPriority priority = PreloadPriority.medium,
  }) {
    addToQueue(
      PreloadItem(
        id: imageUrl,
        type: ContentType.image,
        priority: priority,
        data: {'url': imageUrl},
      ),
    );
  }

  /// 프리로딩된 데이터 가져오기
  T? getPreloadedData<T>(String id, ContentType type) {
    final key = '${type.name}_$id';
    return _preloadedData[key] as T?;
  }

  /// 프리로딩된 이미지 프로바이더 가져오기
  ImageProvider? getPreloadedImage(String imageUrl) {
    return _preloadedImages[imageUrl];
  }

  /// 프리로딩 큐 처리
  Future<void> _processQueue() async {
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      // 우선순위별로 정렬
      final sortedItems =
          _preloadQueue.values.toList()..sort((a, b) {
            final priorityOrder = {
              PreloadPriority.critical: 0,
              PreloadPriority.high: 1,
              PreloadPriority.medium: 2,
              PreloadPriority.low: 3,
            };
            return priorityOrder[a.priority]!.compareTo(
              priorityOrder[b.priority]!,
            );
          });

      // 배치 처리 (한 번에 최대 5개)
      const batchSize = 5;
      for (int i = 0; i < sortedItems.length; i += batchSize) {
        final batch = sortedItems.skip(i).take(batchSize).toList();
        await Future.wait(batch.map(_processItem));

        // CPU 부하 방지를 위한 짧은 지연
        if (i + batchSize < sortedItems.length) {
          await Future.delayed(const Duration(milliseconds: 10));
        }
      }

      _preloadQueue.clear();
    } finally {
      _isProcessing = false;
    }
  }

  /// 개별 아이템 처리
  Future<void> _processItem(PreloadItem item) async {
    final key = '${item.type.name}_${item.id}';

    try {
      switch (item.type) {
        case ContentType.meetup:
          // fromMap 의존 삭제 - 안전한 no-op 처리
          _preloadedData[key] = item.data; // 원본 데이터 그대로 저장
          break;

        case ContentType.post:
          // fromMap 의존 삭제 - 안전한 no-op 처리
          _preloadedData[key] = item.data; // 원본 데이터 그대로 저장
          break;

        case ContentType.user:
          // fromMap 의존 삭제 - 안전한 no-op 처리
          _preloadedData[key] = item.data; // 원본 데이터 그대로 저장
          break;

        case ContentType.image:
          await _preloadImageData(item.data['url'] as String);
          break;
      }
    } catch (e) {
      // 프리로딩 실패는 무시 (실제 로드 시 재시도)
      debugPrint('Preload failed for $key: $e');
    }
  }

  /// 이미지 데이터 프리로딩
  Future<void> _preloadImageData(String imageUrl) async {
    if (_preloadedImages.containsKey(imageUrl)) return;

    final imageProvider = NetworkImage(imageUrl);
    _preloadedImages[imageUrl] = imageProvider;

    // 실제 이미지 로딩은 나중에 수행 (메모리 절약)
  }

  /// 캐시 정리
  void clearCache({ContentType? type}) {
    if (type != null) {
      final keysToRemove =
          _preloadedData.keys
              .where((key) => key.startsWith('${type.name}_'))
              .toList();

      for (final key in keysToRemove) {
        _preloadedData.remove(key);
      }
    } else {
      _preloadedData.clear();
      _preloadedImages.clear();
    }
  }

  /// 메모리 사용량 최적화
  void optimizeMemoryUsage() {
    final now = DateTime.now();
    const maxAge = Duration(minutes: 10);

    // 오래된 프리로드 아이템 제거
    _preloadQueue.removeWhere((key, item) {
      return now.difference(item.createdAt) > maxAge;
    });

    // 메모리 사용량이 많은 이미지 캐시 정리
    if (_preloadedImages.length > 50) {
      final keysToRemove = _preloadedImages.keys.take(25).toList();
      for (final key in keysToRemove) {
        _preloadedImages.remove(key);
      }
    }
  }

  /// 통계 정보
  Map<String, dynamic> getStats() {
    return {
      'queueSize': _preloadQueue.length,
      'preloadedDataCount': _preloadedData.length,
      'preloadedImageCount': _preloadedImages.length,
      'isProcessing': _isProcessing,
    };
  }
}

/// 프리로딩 위젯 믹스인
mixin PreloadMixin<T extends StatefulWidget> on State<T> {
  final PreloadService _preloadService = PreloadService();

  /// 중요 콘텐츠 프리로딩
  void preloadCriticalContent() {
    // 서브클래스에서 구현
  }

  /// 추가 콘텐츠 프리로딩
  void preloadAdditionalContent() {
    // 서브클래스에서 구현
  }

  @override
  void initState() {
    super.initState();

    // 중요 콘텐츠는 즉시 프리로딩
    WidgetsBinding.instance.addPostFrameCallback((_) {
      preloadCriticalContent();

      // 추가 콘텐츠는 지연 프리로딩
      Future.delayed(const Duration(milliseconds: 500), () {
        preloadAdditionalContent();
      });
    });
  }

  @override
  void dispose() {
    // 메모리 최적화
    _preloadService.optimizeMemoryUsage();
    super.dispose();
  }
}

/// 성능 메트릭 수집기
class PerformanceMetrics {
  static final Map<String, List<Duration>> _renderTimes = {};
  static final Map<String, int> _buildCounts = {};

  /// 렌더링 시간 기록
  static void recordRenderTime(String widgetName, Duration renderTime) {
    _renderTimes.putIfAbsent(widgetName, () => []).add(renderTime);

    // 최근 10개 기록만 유지
    if (_renderTimes[widgetName]!.length > 10) {
      _renderTimes[widgetName]!.removeAt(0);
    }
  }

  /// 빌드 횟수 기록
  static void recordBuild(String widgetName) {
    _buildCounts[widgetName] = (_buildCounts[widgetName] ?? 0) + 1;
  }

  /// 평균 렌더링 시간 계산
  static Duration getAverageRenderTime(String widgetName) {
    final times = _renderTimes[widgetName];
    if (times == null || times.isEmpty) return Duration.zero;

    final totalMs = times.fold<int>(
      0,
      (sum, time) => sum + time.inMilliseconds,
    );
    return Duration(milliseconds: totalMs ~/ times.length);
  }

  /// 성능 리포트 생성
  static Map<String, dynamic> generateReport() {
    final report = <String, dynamic>{};

    for (final widgetName in _renderTimes.keys) {
      final avgRenderTime = getAverageRenderTime(widgetName);
      final buildCount = _buildCounts[widgetName] ?? 0;

      report[widgetName] = {
        'averageRenderTime': avgRenderTime.inMilliseconds,
        'buildCount': buildCount,
        'recentRenderTimes':
            _renderTimes[widgetName]?.map((t) => t.inMilliseconds).toList(),
      };
    }

    return report;
  }

  /// 통계 초기화
  static void reset() {
    _renderTimes.clear();
    _buildCounts.clear();
  }
}
