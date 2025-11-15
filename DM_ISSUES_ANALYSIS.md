# DM 기능 문제점 분석 및 해결 방안

## 🔍 발견된 주요 문제점들

### 1. 코드 품질 문제
- ✅ **해결됨**: 사용하지 않는 import 및 변수들 제거
- ✅ **해결됨**: 중복된 메서드 및 로직 정리
- ⚠️ **남은 문제**: 과도한 print 문들 (프로덕션에서 성능 저하 가능)

### 2. 복잡한 로직 구조
#### 문제점:
- `sendMessage` 메서드가 너무 복잡함 (150+ 라인)
- 대화방 생성과 메시지 전송이 하나의 메서드에 혼재
- 에러 처리가 중첩되어 디버깅 어려움

#### 해결 방안:
```dart
// 현재: sendMessage가 모든 것을 처리
Future<bool> sendMessage(String conversationId, String text) {
  // 1. 대화방 존재 확인
  // 2. 대화방 없으면 생성
  // 3. 메시지 추가
  // 4. 대화방 정보 업데이트
  // 5. 알림 전송
}

// 개선안: 책임 분리
Future<bool> sendMessage(String conversationId, String text) async {
  await _ensureConversationExists(conversationId);
  return await _addMessageToConversation(conversationId, text);
}
```

### 3. 메시지 가시성 로직 복잡성
#### 문제점:
- `userLeftAt`, `rejoinedAt` 로직이 여러 곳에 분산
- 메시지 필터링이 클라이언트와 서버에서 중복 처리
- 재입장 시점 계산이 복잡함

#### 해결 방안:
```dart
// 현재: 여러 곳에서 가시성 계산
DateTime? getMessageVisibilityStartTime(String conversationId) {
  // 복잡한 userLeftAt/rejoinedAt 계산
}

// 개선안: 단순화된 상태 관리
enum ConversationState { active, left, rejoined }
ConversationState getUserConversationState(String userId);
```

### 4. 에러 처리 불일치
#### 문제점:
- 일부 메서드는 예외를 던지고, 일부는 null/false 반환
- 사용자에게 보여지는 에러 메시지가 일관성 없음
- Firebase 에러와 일반 에러 처리가 혼재

#### 해결 방안:
```dart
// 통일된 에러 처리 클래스
class DMResult<T> {
  final T? data;
  final String? error;
  final bool success;
  
  DMResult.success(this.data) : error = null, success = true;
  DMResult.error(this.error) : data = null, success = false;
}
```

### 5. 성능 문제
#### 문제점:
- 메시지 스트림에서 불필요한 재계산
- 캐시 활용 부족
- 과도한 Firestore 쿼리

#### 해결 방안:
```dart
// 현재: 매번 새로운 스트림 생성
Stream<List<DMMessage>> getMessages(String conversationId) {
  return _firestore.collection('conversations')...
}

// 개선안: 스트림 캐싱 및 재사용
final Map<String, Stream<List<DMMessage>>> _messageStreams = {};
Stream<List<DMMessage>> getMessages(String conversationId) {
  return _messageStreams[conversationId] ??= _createMessageStream(conversationId);
}
```

## 🚀 즉시 적용 가능한 해결책

### 1. 메시지 전송 로직 단순화
```dart
Future<bool> sendMessage(String conversationId, String text) async {
  try {
    // 1. 기본 검증
    if (!_validateMessage(text)) return false;
    
    // 2. 대화방 준비
    final conversation = await _prepareConversation(conversationId);
    if (conversation == null) return false;
    
    // 3. 메시지 전송
    return await _sendMessageToConversation(conversation, text);
  } catch (e) {
    _handleSendMessageError(e);
    return false;
  }
}
```

### 2. 에러 처리 통일
```dart
class DMException implements Exception {
  final String message;
  final String code;
  
  DMException(this.message, this.code);
  
  static DMException permissionDenied() => 
    DMException('권한이 없습니다', 'permission_denied');
  static DMException userNotFound() => 
    DMException('사용자를 찾을 수 없습니다', 'user_not_found');
}
```

### 3. 상태 관리 단순화
```dart
class ConversationStatus {
  final bool isActive;
  final DateTime? leftAt;
  final DateTime? rejoinedAt;
  
  bool get hasLeft => leftAt != null;
  bool get hasRejoined => rejoinedAt != null;
  bool get isCurrentlyLeft => hasLeft && (!hasRejoined || leftAt!.isAfter(rejoinedAt!));
  
  DateTime? get messageVisibilityStart {
    if (!hasLeft) return null;
    return hasRejoined ? rejoinedAt : leftAt;
  }
}
```

## 📋 우선순위별 개선 계획

### 🔥 긴급 (즉시 수정 필요)
1. **메시지 전송 실패 문제 해결**
   - Firestore Rules 확인
   - 권한 에러 처리 개선
   
2. **메모리 누수 방지**
   - 스트림 구독 해제 로직 추가
   - 캐시 크기 제한

### ⚡ 중요 (1주일 내)
1. **코드 리팩토링**
   - sendMessage 메서드 분할
   - 에러 처리 통일
   
2. **성능 최적화**
   - 불필요한 쿼리 제거
   - 캐싱 전략 개선

### 📈 개선 (1개월 내)
1. **아키텍처 개선**
   - Repository 패턴 적용
   - 상태 관리 라이브러리 도입
   
2. **테스트 코드 추가**
   - 단위 테스트
   - 통합 테스트

## 🛠️ 즉시 적용할 수 있는 수정사항

### 1. Print 문 제거 (프로덕션 성능 개선)
```dart
// 개발용 로깅 유틸리티 생성
class DMLogger {
  static const bool _isDebug = kDebugMode;
  
  static void log(String message) {
    if (_isDebug) print(message);
  }
  
  static void error(String message, [Object? error]) {
    if (_isDebug) print('❌ $message${error != null ? ': $error' : ''}');
  }
}
```

### 2. 메시지 전송 안정성 개선
```dart
Future<bool> _sendMessageSafely(String conversationId, String text) async {
  const maxRetries = 3;
  
  for (int attempt = 1; attempt <= maxRetries; attempt++) {
    try {
      return await _sendMessageAttempt(conversationId, text);
    } catch (e) {
      if (attempt == maxRetries) rethrow;
      await Future.delayed(Duration(seconds: attempt));
    }
  }
  return false;
}
```

### 3. 스트림 메모리 관리
```dart
class DMService {
  final Map<String, StreamSubscription> _activeSubscriptions = {};
  
  void dispose() {
    for (final subscription in _activeSubscriptions.values) {
      subscription.cancel();
    }
    _activeSubscriptions.clear();
  }
}
```

이러한 개선사항들을 단계적으로 적용하면 DM 기능의 안정성과 성능을 크게 향상시킬 수 있습니다.
