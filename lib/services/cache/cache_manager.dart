// lib/services/cache/cache_manager.dart
// 캐시 시스템 초기화 및 전역 관리

import 'package:hive_flutter/hive_flutter.dart';
import '../../utils/logger.dart';
import '../../models/cache/cache_metadata.dart';
import '../../models/cache/cached_post.dart';
import '../../models/cache/cached_comment.dart';
import 'my_page_cache_service.dart';

/// 캐시 시스템 관리자
/// Hive 초기화, 어댑터 등록, 박스 열기 등을 담당합니다.
class CacheManager {
  static bool _initialized = false;

  /// 캐시 시스템 초기화
  /// 앱 시작 시 main()에서 호출해야 합니다.
  static Future<void> initialize() async {
    if (_initialized) {
      Logger.log('⚠️ 캐시 시스템은 이미 초기화되어 있습니다.');
      return;
    }

    try {
      // Hive 초기화
      await Hive.initFlutter();

      // 어댑터 등록
      Hive.registerAdapter(CacheMetadataAdapter());
      Hive.registerAdapter(CachedPostAdapter());
      Hive.registerAdapter(CachedCommentAdapter());
      // 추가 어댑터는 다음 Phase에서 등록
      // Hive.registerAdapter(CachedMeetupAdapter());
      // Hive.registerAdapter(CachedMessageAdapter());

      // 박스 열기
      await Hive.openBox<CacheMetadata>('metadata');
      await Hive.openBox<CachedPost>('posts');
      await Hive.openBox<CachedComment>('comments');
      // DM 메시지 로컬 캐시(문자앱 UX): 타입 어댑터 없이 dynamic(Map/List)로 저장한다.
      // - Hive 초기화만 되면 언제든 접근 가능
      // - 실패해도 DM은 네트워크 경로로 계속 동작 (best-effort)
      try {
        await Hive.openBox<dynamic>('dm_messages_v1');
      } catch (e) {
        Logger.error('⚠️ DM 메시지 캐시 박스 오픈 실패(무시): $e');
      }
      try {
        await Hive.openBox<dynamic>('my_page_tabs_v1');
      } catch (e) {
        Logger.error('⚠️ 마이페이지 캐시 박스 오픈 실패(무시): $e');
      }
      try {
        await Hive.openBox<dynamic>('snack_chat_state_v1');
        await Hive.openBox<dynamic>('user_profiles_v2');
      } catch (e) {
        Logger.error('⚠️ 스낵챗 캐시 박스 오픈 실패(무시): $e');
      }
      // 추가 박스는 다음 Phase에서 열기
      // await Hive.openBox<CachedMeetup>('meetups');
      // await Hive.openBox<CachedMessage>('messages');

      _initialized = true;
    } catch (e, stackTrace) {
      Logger.error('❌ 캐시 시스템 초기화 실패 (앱은 정상 작동): $e');
      Logger.error('스택 트레이스: $stackTrace');
      // 초기화 실패해도 앱은 계속 실행
      // 캐시 없이 네트워크만 사용
    }
  }

  /// 모든 캐시 삭제
  /// 로그아웃 시 또는 캐시 초기화가 필요할 때 호출합니다.
  static Future<void> clearAll() async {
    try {
      Logger.log('🗑️ 모든 캐시 삭제 시작...');
      MyPageCacheService.clearMemory();

      await Hive.deleteBoxFromDisk('metadata');
      await Hive.deleteBoxFromDisk('posts');
      await Hive.deleteBoxFromDisk('comments');
      await Hive.deleteBoxFromDisk('dm_messages_v1');
      await Hive.deleteBoxFromDisk('my_page_tabs_v1');
      await Hive.deleteBoxFromDisk('snack_chat_state_v1');
      await Hive.deleteBoxFromDisk('user_profiles_v2');
      // 추가 박스는 다음 Phase에서 삭제
      // await Hive.deleteBoxFromDisk('meetups');
      // await Hive.deleteBoxFromDisk('messages');

      Logger.log('✅ 모든 캐시 삭제 완료');
    } catch (e) {
      Logger.error('캐시 삭제 실패 (무시): $e');
    }
  }

  /// 캐시 시스템 초기화 여부 확인
  static bool get isInitialized => _initialized;

  /// 특정 박스가 열려있는지 확인
  static bool isBoxOpen(String boxName) {
    try {
      return Hive.isBoxOpen(boxName);
    } catch (e) {
      return false;
    }
  }

  /// 캐시 시스템 통계
  static Map<String, dynamic> getStats() {
    try {
      final stats = <String, dynamic>{
        'initialized': _initialized,
        'boxes': <String, int>{},
      };

      // 열려있는 박스의 크기 확인
      if (isBoxOpen('metadata')) {
        stats['boxes']['metadata'] = Hive.box<CacheMetadata>('metadata').length;
      }
      if (isBoxOpen('posts')) {
        stats['boxes']['posts'] = Hive.box<CachedPost>('posts').length;
      }
      if (isBoxOpen('comments')) {
        stats['boxes']['comments'] = Hive.box<CachedComment>('comments').length;
      }

      return stats;
    } catch (e) {
      Logger.error('캐시 통계 조회 실패: $e');
      return {'error': e.toString()};
    }
  }
}
