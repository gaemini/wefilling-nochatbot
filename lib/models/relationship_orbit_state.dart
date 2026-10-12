// lib/models/relationship_orbit_state.dart
// 아바타 주변 관계 오빗이 표현하는 상태와 공통 맥락 신호.
// 서버 관계 상태(RelationshipStatus)를 시각 상태로 축약한다.

import 'relationship_status.dart';

/// 오빗이 표현하는 관계 상태.
///
/// - [notConnected]: 비친구. 270° 열린 호 + 4시 방향 `+` 노드
/// - [requestSent]: 친구 요청 또는 첫 응답 요청을 보냄. 점선 진행 링
/// - [friend]: 상호 친구. 끊기지 않는 연속 링
enum OrbitRelationshipState { notConnected, requestSent, friend }

/// 아바타 주변에 최대 3개까지 겹쳐 보이는 공통 맥락 조각.
enum OrbitContextSignal { interest, community, meetup, language }

/// 친구 관계 상태를 오빗 상태로 축약한다.
///
/// 차단 관계는 오빗이 표현할 상태가 아니므로 비친구로 다루되,
/// `+` 노드 노출 여부는 호출 측이 [canRequestFriendship]로 따로 결정한다.
OrbitRelationshipState orbitStateFromRelationship(
  RelationshipStatus status, {
  bool firstResponsePending = false,
}) {
  switch (status) {
    case RelationshipStatus.friends:
      return OrbitRelationshipState.friend;
    case RelationshipStatus.pendingOut:
      return OrbitRelationshipState.requestSent;
    case RelationshipStatus.pendingIn:
    case RelationshipStatus.none:
    case RelationshipStatus.blocked:
    case RelationshipStatus.blockedBy:
      return firstResponsePending
          ? OrbitRelationshipState.requestSent
          : OrbitRelationshipState.notConnected;
  }
}

/// `+` 노드로 친구 요청을 보낼 수 있는지.
bool canRequestFriendship(RelationshipStatus status) =>
    status == RelationshipStatus.none;

/// 최대 3개로 정리하고 중복을 제거한다. 순서는 입력 순서를 유지한다.
List<OrbitContextSignal> normalizeContextSignals(
  Iterable<OrbitContextSignal> signals,
) {
  final result = <OrbitContextSignal>[];
  for (final signal in signals) {
    if (result.contains(signal)) continue;
    result.add(signal);
    if (result.length == 3) break;
  }
  return List<OrbitContextSignal>.unmodifiable(result);
}
