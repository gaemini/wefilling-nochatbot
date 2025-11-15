// lib/ui/widgets/optimized_currentMeetup_card.dart
// 성능 최적화된 모임 카드 위젯
// const 생성자, 메모이제이션, 이미지 최적화

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import '../../models/meetup.dart';
import 'package:intl/intl.dart';
import '../../l10n/app_localizations.dart';
import '../../models/meetup_participant.dart';
import '../../utils/image_utils.dart';
import '../../design/tokens.dart';
import '../../services/meetup_service.dart';
import '../dialogs/report_dialog.dart';
import '../dialogs/block_dialog.dart';
import '../../screens/edit_meetup_screen.dart';
import '../../screens/review_approval_screen.dart';
import '../../screens/meetup_review_screen.dart';
import 'package:url_launcher/url_launcher.dart';

/// 최적화된 모임 카드
class OptimizedMeetupCard extends StatefulWidget {
  final Meetup meetup;
  final int index;
  final VoidCallback onTap;
  final bool preloadImage;
  final VoidCallback? onMeetupDeleted; // 삭제 후 콜백 추가
  final VoidCallback? onParticipationChanged; // 참여 상태 변경 콜백 추가

  const OptimizedMeetupCard({
    super.key,
    required this.meetup,
    required this.index,
    required this.onTap,
    this.preloadImage = false,
    this.onMeetupDeleted,
    this.onParticipationChanged,
  });

  @override
  State<OptimizedMeetupCard> createState() => _OptimizedMeetupCardState();
}

class _OptimizedMeetupCardState extends State<OptimizedMeetupCard> {
  late Meetup currentMeetup;
  bool isParticipating = false;
  bool isCheckingParticipation = true;
  bool isJoinLeaveProcessing = false; // 참여/나가기 처리 중 상태
  StreamSubscription<DocumentSnapshot>? _meetupSubscription;

  @override
  void initState() {
    super.initState();
    currentMeetup = widget.meetup;
    
    // 초기 상태 로깅
    print('🚀 [OptimizedMeetupCard-Init] 카드 초기화:');
    print('   - 모임 ID: ${currentMeetup.id}');
    print('   - 제목: ${currentMeetup.title}');
    print('   - hasReview: ${currentMeetup.hasReview}');
    print('   - isClosed: ${currentMeetup.isClosed}');
    
    _checkParticipationStatus();
    _setupMeetupStream();
  }

  @override
  void dispose() {
    _meetupSubscription?.cancel();
    super.dispose();
  }

  /// 실시간 모임 데이터 스트림 설정
  void _setupMeetupStream() {
    _meetupSubscription = FirebaseFirestore.instance
        .collection('meetups')
        .doc(currentMeetup.id)
        .snapshots()
        .listen((snapshot) {
      if (snapshot.exists && mounted) {
        final data = snapshot.data()!;
        data['id'] = snapshot.id;
        
        final oldHasReview = currentMeetup.hasReview;
        final oldIsClosed = currentMeetup.isClosed;
        final newMeetup = Meetup.fromJson(data);
        final newHasReview = newMeetup.hasReview;
        final newIsClosed = newMeetup.isClosed;
        
        // 상태 변경 감지 및 상세 로깅
        if (oldHasReview != newHasReview || oldIsClosed != newIsClosed) {
          print('🔄 [OptimizedMeetupCard-Stream] 실시간 상태 변경 감지:');
          print('   - 모임 ID: ${currentMeetup.id}');
          print('   - hasReview: $oldHasReview → $newHasReview');
          print('   - isClosed: $oldIsClosed → $newIsClosed');
          print('   - isCompleted: ${newMeetup.isCompleted}');
          print('   - reviewId: ${newMeetup.reviewId}');
          print('   - 타임스탬프: ${DateTime.now()}');
        } else {
          print('🔄 [OptimizedMeetupCard-Stream] 상태 변경 없음: hasReview=$newHasReview, isClosed=$newIsClosed');
        }
        
        setState(() {
          currentMeetup = newMeetup;
        });
        
        // 상태 변경 후 버튼 로직 재확인
        if (oldHasReview != newHasReview || oldIsClosed != newIsClosed) {
          print('🔍 [OptimizedMeetupCard-Stream] 업데이트 후 상태: hasReview=$newHasReview, isClosed=$newIsClosed');
        }
      }
    }, onError: (error) {
      print('❌ [OptimizedMeetupCard-Stream] 실시간 스트림 오류: $error');
    });
  }

  /// 현재 사용자의 참여 상태 확인 (meetup_participants 컬렉션 기반)
  Future<void> _checkParticipationStatus() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      setState(() {
        isCheckingParticipation = false;
      });
      return;
    }

    try {
      // meetup_participants 컬렉션에서 참여 정보 확인
      final participantId = '${currentMeetup.id}_${currentUser.uid}';
      final participantDoc = await FirebaseFirestore.instance
          .collection('meetup_participants')
          .doc(participantId)
          .get();
      
      if (mounted) {
        setState(() {
          // 문서가 존재하고 status가 'approved'이면 참여 중
          isParticipating = participantDoc.exists && 
                           (participantDoc.data()?['status'] == 'approved' ||
                            participantDoc.data()?['status'] == ParticipantStatus.approved);
          isCheckingParticipation = false;
        });
      }
    } catch (e) {
      print('참여 상태 확인 오류: $e');
      if (mounted) {
        setState(() {
          isCheckingParticipation = false;
        });
      }
    }
  }

  /// URL 여부 확인
  bool _isUrl(String text) {
    return text.startsWith('http://') || 
           text.startsWith('https://') ||
           text.startsWith('www.');
  }

  /// 위치 URL 열기
  Future<void> _openLocationUrl(String location) async {
    if (!_isUrl(location)) return;

    try {
      final Uri url = Uri.parse(location);
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.cannotOpenLink ?? ""),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      print('URL 열기 오류: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.error ?? ""),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      color: Colors.white, // 흰색 배경 ✨
      elevation: 0.3, // 0.5 → 0.3 (더 얇은 그림자)
      margin: const EdgeInsets.only(bottom: 8), // 12 → 8 (카드 간격 줄임)
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12), // 16 → 12 (모서리 덜 둥글게)
        side: BorderSide(color: colorScheme.outline.withOpacity(0.15)), // 0.2 → 0.15 (더 얇은 테두리)
      ),
      child: InkWell(
        onTap: () async {
          // 카드 탭 시 강제 데이터 새로고침 후 원래 onTap 실행
          print('👆 [OptimizedMeetupCard-Tap] 카드 탭됨, 강제 새로고침 시작');
          try {
            await _refreshMeetupData();
            print('👆 [OptimizedMeetupCard-Tap] 새로고침 완료, 상세 화면으로 이동');
            widget.onTap();
          } catch (e) {
            print('❌ [OptimizedMeetupCard-Tap] 새로고침 실패: $e');
            // 실패해도 상세 화면으로 이동
            widget.onTap();
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 12), // 상단 여백만 16으로 증가하여 대칭 맞춤
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // 제목 + 공개범위 배지 (오른쪽 상단)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                currentMeetup.title,
                      style: const TextStyle(
                  fontWeight: FontWeight.w700,
                        color: Colors.black,
                        fontSize: 24, // 28 → 24 (제목 크기 약간 줄임)
                        height: 1.1, // 1.2 → 1.1 (줄간격 줄임)
                        letterSpacing: -0.5,
                ),
                      maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
                  ),
                  const SizedBox(width: 6), // 8 → 6
                  _buildVisibilityBadge(colorScheme),
                ],
              ),

              const SizedBox(height: 14), // 20 → 14 (간격 줄임)

              // 위치
              _buildInfoRow(
                icon: Icons.location_on,
                text: currentMeetup.location,
                colorScheme: colorScheme,
                onTap: _isUrl(currentMeetup.location) 
                    ? () => _openLocationUrl(currentMeetup.location)
                              : null,
                        ),

              const SizedBox(height: 8), // 12 → 8 (간격 줄임)

              // 참가자 수
              _buildInfoRow(
                icon: Icons.people,
                text: '${currentMeetup.currentParticipants}/${currentMeetup.maxParticipants}${AppLocalizations.of(context)!.peopleUnit}',
                colorScheme: colorScheme,
              ),

              const SizedBox(height: 14), // 20 → 14 (간격 줄임)

              // 하단 바 (회색 배경 + 작성자 + 참여 버튼)
              _buildBottomBar(context, colorScheme),
            ],
          ),
        ),
      ),
    );
  }

  /// 공개범위 배지 (오른쪽 상단)
  Widget _buildVisibilityBadge(ColorScheme colorScheme) {
    final bool isFriendsOnly = currentMeetup.visibility == 'friends' || 
                               currentMeetup.visibility == 'category';
    final Color badgeColor = isFriendsOnly ? Colors.orange[600]! : Colors.green[600]!;
    final String visibilityText = isFriendsOnly 
        ? (AppLocalizations.of(context)!.visibilityFriends ?? "") : AppLocalizations.of(context)!.visibilityPublic;
    final IconData icon = isFriendsOnly ? Icons.people : Icons.public;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
        color: badgeColor.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
                      border: Border.all(
          color: badgeColor.withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
            icon,
            size: 12,
            color: badgeColor,
                        ),
          const SizedBox(width: 4),
                    Text(
            visibilityText,
                      style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: badgeColor,
                      ),
                    ),
                      ],
                    ),
    );
  }

  /// 정보 행 빌드 (아이콘 + 텍스트)
  Widget _buildInfoRow({
    required IconData icon,
    required String text,
    required ColorScheme colorScheme,
    VoidCallback? onTap,
  }) {
    final widget = Row(
      children: [
        Icon(
          icon,
          size: 18, // 22 → 18 (아이콘 크기 줄임)
          color: Colors.grey[500],
        ),
        const SizedBox(width: 8), // 12 → 8 (간격 줄임)
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 15, // 17 → 15 (폰트 크기 줄임)
              color: _isUrl(text) ? colorScheme.primary : Colors.grey[600],
              fontWeight: FontWeight.w500,
              letterSpacing: -0.2, // -0.3 → -0.2
              decoration: _isUrl(text) ? TextDecoration.underline : null,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
              ),
            ],
    );

    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        child: widget,
    );
    }
    return widget;
  }

  /// 하단 바 (작성자 + 참여 버튼)
  Widget _buildBottomBar(BuildContext context, ColorScheme colorScheme) {
    return Column(
      children: [
        // 구분선
        Divider(
          color: Colors.grey[300],
          thickness: 0.8, // 1 → 0.8 (더 얇은 선)
          height: 18, // 16 → 18 (상단 여백 증가에 맞춰 약간 조정)
        ),
        
        // 작성자 정보 + 참여 정보/버튼
        Row(
      children: [
            // 프로필 사진 (36x36)
            CircleAvatar(
              radius: 18, // 20 → 18 (프로필 사진 크기 줄임)
              backgroundColor: Colors.grey[200],
              backgroundImage: currentMeetup.hostPhotoURL.isNotEmpty
                  ? NetworkImage(currentMeetup.hostPhotoURL)
                  : null,
              child: currentMeetup.hostPhotoURL.isEmpty
                  ? Icon(Icons.person, size: 18, color: Colors.grey[600]) // 20 → 18
                  : null,
        ),
            const SizedBox(width: 10), // 12 → 10 (간격 줄임)
            
            // 작성자 이름
        Expanded(
          child: Text(
            currentMeetup.hostNickname ?? currentMeetup.host,
                style: const TextStyle(
                  fontSize: 16, // 18 → 16 (폰트 크기 줄임)
              fontWeight: FontWeight.w600,
                  color: Colors.black,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
            
            const SizedBox(width: 10), // 12 → 10 (간격 줄임)
            
            // 참가자 배지 또는 참여 버튼
            _buildCompactButton(context, colorScheme),
          ],
        ),
      ],
    );
  }

  /// 참가자 배지 또는 참여 버튼
  Widget _buildCompactButton(BuildContext context, ColorScheme colorScheme) {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return const SizedBox.shrink();
    
    // 내가 만든 모임이면 아무것도 표시하지 않음 (위쪽에 이미 참가자 수 표시됨)
    if (currentMeetup.userId == currentUser.uid) {
      print('🏠 [OptimizedMeetupCard-Button] 주최자이므로 버튼 숨김');
      return const SizedBox.shrink();
    }
    
    // 버튼 빌드 시점에 강제 데이터 새로고침 (디버깅용)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshMeetupData();
    });
    
    // 참여 상태 확인 중이면 로딩
    if (isCheckingParticipation) {
      return const SizedBox(
        width: 100,
        height: 40,
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    
    // 전체 상황 파악을 위한 종합 로깅
    print('🎯 [OptimizedMeetupCard-Button] =====버튼 결정 시작=====');
    print('   📋 모임 정보:');
    print('      - ID: ${currentMeetup.id}');
    print('      - 제목: ${currentMeetup.title}');
    print('      - 주최자: ${currentMeetup.userId}');
    print('      - 현재 사용자: ${currentUser.uid}');
    print('   🔄 상태 정보:');
    print('      - hasReview: ${currentMeetup.hasReview}');
    print('      - isClosed: ${currentMeetup.isClosed}');
    print('      - isCompleted: ${currentMeetup.isCompleted}');
    print('      - reviewId: ${currentMeetup.reviewId}');
    print('   👤 사용자 정보:');
    print('      - isParticipating: $isParticipating');
    print('      - isCheckingParticipation: $isCheckingParticipation');
    print('      - isJoinLeaveProcessing: $isJoinLeaveProcessing');
    
    final current = currentMeetup.currentParticipants;
    final max = currentMeetup.maxParticipants;
    final isOpen = current < max;
    
    print('   📊 참여자 정보:');
    print('      - 현재 참여자: $current');
    print('      - 최대 참여자: $max');
    print('      - 참여 가능: $isOpen');
    
    // 참여 중: 상세 페이지와 동일한 로직 적용
    if (isParticipating) {
      // 디버깅: 현재 후기 상태 로그
      print('🔍 [OptimizedMeetupCard-Button] 참여자 버튼 로직 (상세 페이지와 동일):');
      print('   - 모임 ID: ${currentMeetup.id}');
      print('   - hasReview: ${currentMeetup.hasReview}');
      print('   - isClosed: ${currentMeetup.isClosed}');
      print('   - isCompleted: ${currentMeetup.isCompleted}');
      
      // 상세 페이지와 동일한 로직: hasReview가 있으면 후기 확인 버튼, 없으면 나가기 버튼
      if (currentMeetup.hasReview == true) {
        print('✅ [OptimizedMeetupCard-Button] 후기 확인 버튼 선택됨 (hasReview=true)');
        
        // 사용자가 이미 후기를 확인했는지 체크
        final user = FirebaseAuth.instance.currentUser;
        final hasAccepted = user != null ? currentMeetup.hasUserAcceptedReview(user.uid) : false;
        
        return ElevatedButton(
          onPressed: hasAccepted ? null : () => _navigateToReviewScreen(currentMeetup),
          style: ElevatedButton.styleFrom(
            backgroundColor: hasAccepted ? Colors.grey[300] : const Color(0xFF22C55E), // 더 선명한 녹색
            foregroundColor: hasAccepted ? Colors.grey[600] : Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            minimumSize: const Size(100, 40),
                shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
                ),
          ),
          child: Text(
            hasAccepted 
                ? AppLocalizations.of(context)!.reviewChecked
                : AppLocalizations.of(context)!.checkReview,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      } else {
        // 후기가 없는 경우 - 모임 확정되었으면 나가기 버튼 숨기고 "모임 확정" 칩 표시
        if (currentMeetup.isCompleted) {
          print('✅ [OptimizedMeetupCard-Button] 모임 확정 표시 (isCompleted=true)');
          return _buildConfirmedChip();
        }
        
        print('🔶 [OptimizedMeetupCard-Button] 나가기 버튼 선택됨 (hasReview=false, isClosed=false)');
        return ElevatedButton(
          onPressed: isJoinLeaveProcessing ? null : () => _leaveMeetup(currentMeetup),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange[600],
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            minimumSize: const Size(80, 32),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          child: isJoinLeaveProcessing 
              ? const SizedBox(
                  height: 14,
                  width: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : Text(
                  AppLocalizations.of(context)!.leaveMeetup ?? '나가기',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
        );
      }
    }
    
    // 비참여자 로직
    print('🔍 [OptimizedMeetupCard-Button] 비참여자 버튼 로직:');
    print('   - isClosed: ${currentMeetup.isClosed}');
    print('   - isOpen: $isOpen (current: $current, max: $max)');
    
    // 모집 마감된 경우 - 버튼 숨김 (모임 확정으로 보이게)
    if (currentMeetup.isClosed) {
      print('🚫 [OptimizedMeetupCard-Button] 비참여자 버튼 숨김 (isClosed=true)');
      return const SizedBox.shrink();
    }
    
    // 마감된 모임: 배지 표시
    if (!isOpen) {
      print('⚪ [OptimizedMeetupCard-Button] 정원 초과 배지 표시');
      return _buildParticipantBadge();
    }
    
    // 참여하기 버튼
    print('🔵 [OptimizedMeetupCard-Button] 참여하기 버튼 선택됨');
    return ElevatedButton(
      onPressed: isJoinLeaveProcessing ? null : () => _joinMeetup(currentMeetup),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF6B7FDE),
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8), // 24,12 → 18,8 (패딩 줄임)
        minimumSize: const Size(80, 32), // 100,40 → 80,32 (크기 줄임)
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6), // 8 → 6 (모서리 덜 둥글게)
        ),
      ),
      child: isJoinLeaveProcessing 
          ? const SizedBox(
              height: 14,
              width: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            )
          : Text(
        AppLocalizations.of(context)!.joinMeetup,
        style: const TextStyle(
          fontSize: 14, // 15 → 14 (폰트 크기 줄임)
          fontWeight: FontWeight.w600,
                          ),
                        ),
    );
  }

  /// 참가자 수 배지 (연한 파란색)
  Widget _buildParticipantBadge() {
    final current = currentMeetup.currentParticipants;
    final max = currentMeetup.maxParticipants;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), // 16,10 → 12,6 (패딩 줄임)
      decoration: BoxDecoration(
        color: const Color(0xFFD6E4FF), // 연한 파란색 배경
        borderRadius: BorderRadius.circular(16), // 20 → 16 (모서리 덜 둥글게)
      ),
      child: Text(
        '$current/$max ${AppLocalizations.of(context)!.peopleUnit}',
        style: const TextStyle(
          fontSize: 14, // 15 → 14 (폰트 크기 줄임)
          fontWeight: FontWeight.w600,
          color: Color(0xFF4A5FCC), // 진한 파란색 텍스트
        ),
          ),
    );
  }

  /// 모임 확정 칩 (참여자에게 버튼 대신 표시)
  Widget _buildConfirmedChip() {
    final Color bg = const Color(0xFFE6F4EA); // 연한 초록 배경
    final Color fg = const Color(0xFF1E7D4E); // 진한 초록 텍스트
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: fg.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle, size: 16, color: fg),
          const SizedBox(width: 6),
          Text(
            AppLocalizations.of(context)!.meetupConfirmed,
            style: TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }

  /// 헤더용 컴팩트 공개 범위 배지
  Widget _buildCompactVisibilityBadge(BuildContext context, ColorScheme colorScheme) {
    // 'friends' 또는 'category'는 친구공개로 표시
    // 'public'만 전체공개로 표시
    final bool isFriendsOnly = currentMeetup.visibility == 'friends' || 
                               currentMeetup.visibility == 'category';
    
    if (isFriendsOnly) {
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
          color: const Color(0xFFFFF3E0), // 주황색 배경
          borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
            const Icon(
              Icons.group_outlined,
              size: 15, // 통일된 크기
              color: Color(0xFFFF8A65), // 주황색
          ),
            const SizedBox(width: 6),
          Text(
              AppLocalizations.of(context)!.visibilityFriends ?? "친구 공개",
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 12, // 통일된 크기
                fontWeight: FontWeight.w700,
                color: Color(0xFFFF8A65), // 주황색
            ),
          ),
        ],
      ),
    );
    }
    
    // 전체 공개는 표시하지 않음 (게시글 카드와 동일)
    return const SizedBox.shrink();
  }

  /// 헤더 빌드 (카테고리 뱃지 + 더 많은 옵션)
  Widget _buildHeader(BuildContext context, ColorScheme colorScheme) {
    final currentUser = FirebaseAuth.instance.currentUser;
    
    if (currentUser == null) {
      return Row(
        children: [
          _buildCategoryBadge(currentMeetup.category, colorScheme),
          const Spacer(),
        ],
      );
    }

    return FutureBuilder<bool>(
      future: _checkIsMyMeetup(currentUser),
      builder: (context, snapshot) {
        final isMyMeetup = snapshot.data ?? false;
        
        print('🔍🔍🔍 [OptimizedMeetupCard] 권한 체크 상세 정보:');
        print('   - 현재 사용자 UID: ${currentUser.uid}');
        print('   - 모임 ID: ${currentMeetup.id}');
        print('   - 모임 제목: ${currentMeetup.title}');
        print('   - 모임 userId: ${currentMeetup.userId}');
        print('   - 모임 hostNickname: ${currentMeetup.hostNickname}');
        print('   - 모임 host: ${currentMeetup.host}');
        print('   - isMyMeetup 결과: $isMyMeetup');
        print('   - 표시될 메뉴: ${isMyMeetup ? "수정/삭제" : "신고/차단"}');

        return _buildHeaderContent(context, colorScheme, currentUser, isMyMeetup);
      },
    );
  }

  /// 현재 사용자가 모임 작성자인지 확인
  Future<bool> _checkIsMyMeetup(User currentUser) async {
    try {
      print('🔍 [_checkIsMyMeetup] 시작');
      print('   - 현재 사용자 UID: ${currentUser.uid}');
      print('   - 모임 userId: ${currentMeetup.userId}');
      print('   - 모임 hostNickname: ${currentMeetup.hostNickname}');
      
      // 1. userId가 있으면 userId로 비교 (새로운 데이터)
      if (currentMeetup.userId != null && currentMeetup.userId!.isNotEmpty) {
        final result = currentMeetup.userId == currentUser.uid;
        print('   - userId 비교 결과: $result (${currentMeetup.userId} == ${currentUser.uid})');
        return result;
      } 
      
      print('   - userId가 없음, hostNickname으로 비교 시도');
      
      // 2. userId가 없으면 hostNickname 또는 host로 비교 (기존 데이터 호환성)
      final hostToCheck = currentMeetup.hostNickname ?? currentMeetup.host;
      print('   - hostToCheck: $hostToCheck (hostNickname: ${currentMeetup.hostNickname}, host: ${currentMeetup.host})');
      
      if (hostToCheck != null && hostToCheck.isNotEmpty) {
        print('   - Firestore에서 현재 사용자 닉네임 조회 중...');
        
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(currentUser.uid)
            .get();
        
        print('   - userDoc.exists: ${userDoc.exists}');
        
        if (userDoc.exists) {
          final userData = userDoc.data();
          print('   - 전체 userData: $userData');
          
          final currentUserNickname = userData?['nickname'] as String?;
          
          print('   - 현재 사용자 닉네임: "$currentUserNickname"');
          print('   - 모임 hostToCheck: "$hostToCheck"');
          print('   - 닉네임 타입 확인: currentUserNickname.runtimeType = ${currentUserNickname.runtimeType}');
          print('   - hostToCheck 타입 확인: hostToCheck.runtimeType = ${hostToCheck.runtimeType}');
          
          if (currentUserNickname != null && currentUserNickname.isNotEmpty) {
            // 문자열 비교를 더 엄격하게
            final trimmedCurrentNickname = currentUserNickname.trim();
            final trimmedHostToCheck = hostToCheck.trim();
            
            print('   - 트림된 현재 사용자 닉네임: "$trimmedCurrentNickname"');
            print('   - 트림된 모임 hostToCheck: "$trimmedHostToCheck"');
            
            final result = trimmedHostToCheck == trimmedCurrentNickname;
            print('   - 📋 최종 닉네임 비교 결과: $result');
            print('   - 📋 비교식: "$trimmedHostToCheck" == "$trimmedCurrentNickname"');
            return result;
          } else {
            print('   - 현재 사용자 닉네임이 null이거나 비어있음');
          }
        } else {
          print('   - ❌ 사용자 문서가 존재하지 않음');
        }
      } else {
        print('   - hostNickname과 host 모두 없음');
      }
      
      print('   - 최종 결과: false (내 모임 아님)');
      return false;
    } catch (e) {
      print('❌ 권한 체크 오류: $e');
      return false;
    }
  }

  /// 헤더 콘텐츠 빌드
  Widget _buildHeaderContent(BuildContext context, ColorScheme colorScheme, User currentUser, bool isMyMeetup) {
    // 모임이 완료되었거나 후기가 작성된 경우 메뉴 버튼 숨김
    final isCompleted = currentMeetup.isCompleted;
    final hasReview = currentMeetup.hasReview;
    final shouldHideMenu = isMyMeetup && (isCompleted || hasReview);

    return Row(
      children: [
        // 카테고리 뱃지
        _buildCategoryBadge(currentMeetup.category, colorScheme),
        
        const Spacer(),
        
        // 더 많은 옵션 버튼 (모임 완료/후기 작성 후에는 숨김)
        if (currentUser != null && !shouldHideMenu)
          PopupMenuButton<String>(
            icon: Icon(
              Icons.more_vert,
              size: 20,
              color: colorScheme.onSurfaceVariant,
            ),
            itemBuilder: (context) => isMyMeetup 
                ? [
                    // 내가 쓴 글: 수정/모집마감/삭제 메뉴
                    PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit_outlined, size: 16),
                          SizedBox(width: 8),
                          Text(AppLocalizations.of(context)!.editMeetup ?? ""),
                        ],
                      ),
                    ),
                    if (!currentMeetup.isClosed) // 모집 마감되지 않은 경우에만 표시
                    PopupMenuItem(
                        value: 'close',
                      child: Row(
                        children: [
                            Icon(Icons.close, size: 16, color: Colors.orange[600]),
                          const SizedBox(width: 8),
                            Text(
                              AppLocalizations.of(context)!.closeMeetup,
                              style: TextStyle(color: Colors.orange[600]),
                            ),
                        ],
                      ),
                    ),
                  ]
                : [
                    // 다른 사람이 쓴 글: 신고/차단 메뉴
                    PopupMenuItem(
                      value: 'report',
                      child: Row(
                        children: [
                          Icon(Icons.report_outlined, size: 16, color: Colors.red[600]),
                          const SizedBox(width: 8),
                          Text(AppLocalizations.of(context)!.reportAction ?? ""),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'block',
                      child: Row(
                        children: [
                          Icon(Icons.block, size: 16, color: Colors.red[600]),
                          const SizedBox(width: 8),
                          Text(AppLocalizations.of(context)!.blockAction ?? ""),
                        ],
                      ),
                    ),
                  ],
            onSelected: (value) => _handleMenuAction(context, value),
          ),
      ],
    );
  }

  /// 메뉴 액션 처리
  void _handleMenuAction(BuildContext context, String action) async {
    switch (action) {
      case 'edit':
        // 모임 수정 화면으로 이동
        final result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => EditMeetupScreen(meetup: currentMeetup),
          ),
        );
        
        // 수정이 완료되면 최신 데이터로 새로고침
        if (result == true && mounted) {
          await _refreshMeetupData();
        }
        break;
      case 'close':
        // 모집 마감 확인 다이얼로그
        _showCloseConfirmation(context);
        break;
      case 'report':
        if (currentMeetup.userId != null) {
          showReportDialog(
            context,
            reportedUserId: currentMeetup.userId!,
            targetType: 'meetup',
            targetId: currentMeetup.id,
            targetTitle: currentMeetup.title,
          );
        }
        break;
      case 'block':
        if (currentMeetup.userId != null && currentMeetup.hostNickname != null) {
          showBlockUserDialog(
            context,
            userId: currentMeetup.userId!,
            userName: currentMeetup.hostNickname!,
          );
        }
        break;
    }
  }



  /// 카테고리 뱃지 빌드
  Widget _buildCategoryBadge(String category, ColorScheme colorScheme) {
    Color badgeColor;
    switch (category) {
      case '스터디':
        badgeColor = BrandColors.study;
        break;
      case '식사':
        badgeColor = BrandColors.food;
        break;
      case '카페':
        badgeColor = BrandColors.hobby;
        break;
      case '문화':
        badgeColor = BrandColors.culture;
        break;
      default:
        badgeColor = BrandColors.general;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), // 8, 4 → 12, 6
      decoration: BoxDecoration(
        color: badgeColor.withOpacity(0.12), // 0.1 → 0.12
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: badgeColor.withOpacity(0.4), width: 1.5), // 0.3, 1 → 0.4, 1.5
      ),
      child: Text(
        category,
        style: TextStyle(
          color: badgeColor,
          fontSize: 14, // 12 → 14
          fontWeight: FontWeight.w700, // w600 → w700
        ),
      ),
    );
  }

  /// 모임 정보 빌드 (날짜, 시간, 장소)
  Widget _buildMeetupInfo(
    Meetup currentMeetup,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    return Column(
      children: [
        // 날짜와 시간
        _buildInfoRow(
          icon: Icons.schedule_outlined,
          text: Localizations.localeOf(context).languageCode == 'ko'
              ? '${currentMeetup.date.year}-${currentMeetup.date.month.toString().padLeft(2, '0')}-${currentMeetup.date.day.toString().padLeft(2, '0')} ${currentMeetup.time}'
              : '${DateFormat('yyyy-MM-dd', 'en').format(currentMeetup.date)} ${currentMeetup.time.isEmpty ? (AppLocalizations.of(context)!.undecided ?? "") : currentMeetup.time}',
          colorScheme: colorScheme,
        ),

        const SizedBox(height: 6),

        // 장소
        _buildInfoRow(
          icon: Icons.location_on_outlined,
          text: currentMeetup.location,
          colorScheme: colorScheme,
        ),
      ],
    );
  }

  /// 참가자 정보와 참여하기 버튼 빌드
  Widget _buildParticipantInfoWithJoinButton(
    Meetup currentMeetup,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    // 안전한 참가자 정보 추출
    final current = currentMeetup.currentParticipants;
    final max = currentMeetup.maxParticipants;

    return Column(
      children: [
        // 참가자 정보
        Row(
          children: [
            // 작성자 아바타
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: colorScheme.surfaceVariant,
                shape: BoxShape.circle,
              ),
              child: currentMeetup.hostPhotoURL.isNotEmpty
                  ? ClipOval(
                      child: Image.network(
                        currentMeetup.hostPhotoURL,
                        width: 24,
                        height: 24,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Icon(
                          IconStyles.person,
                          size: 16,
                          color: BrandColors.neutral500,
                        ),
                      ),
                    )
                  : Icon(
                      IconStyles.person,
                      size: 16,
                      color: BrandColors.neutral500,
                    ),
            ),

            const SizedBox(width: 8),

            // 참가자 수 (안전한 표시)
            if (max > 0)
              Text(
                Localizations.localeOf(context).languageCode == 'ko'
                    ? '$current/$max${AppLocalizations.of(context)!.peopleUnit}'
                    : '$current/$max people',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),

            const Spacer(),

            // 모집 상태
            _buildStatusChip(current, max, theme, colorScheme),
          ],
        ),
        
        // 참여하기 버튼 (내가 만든 모임이 아니고 참여 가능한 경우)
        const SizedBox(height: 8),
        _buildJoinButton(currentMeetup, theme, colorScheme),
      ],
    );
  }

  /// 참가자 정보 빌드 (기존 메서드 유지)
  Widget _buildParticipantInfo(
    Meetup currentMeetup,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    // 안전한 참가자 정보 추출
    final current = currentMeetup.currentParticipants;
    final max = currentMeetup.maxParticipants;

    return Row(
      children: [
        // 작성자 아바타
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: colorScheme.surfaceVariant,
            shape: BoxShape.circle,
          ),
          child: currentMeetup.hostPhotoURL.isNotEmpty
              ? ClipOval(
                  child: Image.network(
                    currentMeetup.hostPhotoURL,
                    width: 24,
                    height: 24,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Icon(
                      IconStyles.person,
                      size: 16,
                      color: BrandColors.neutral500,
                    ),
                  ),
                )
              : Icon(
                  IconStyles.person,
                  size: 16,
                  color: BrandColors.neutral500,
                ),
        ),

        const SizedBox(width: 8),

        // 참가자 수 (안전한 표시)
        if (max > 0)
          Text(
            '$current/$max명',
            style: theme.textTheme.bodyMedium?.copyWith( // bodySmall → bodyMedium
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600, // w500 → w600
              fontSize: 14, // 명시적 크기 지정
            ),
          ),

        const Spacer(),

        // 모집 상태
        _buildStatusChip(current, max, theme, colorScheme),
      ],
    );
  }

  /// 참가자 아바타들 빌드
  Widget _buildParticipantAvatars(
    List<dynamic> participants,
    ColorScheme colorScheme,
  ) {
    const maxAvatars = 3;
    final safeParticipants = participants.where((p) => p != null).toList();
    final displayCount = safeParticipants.length > maxAvatars ? maxAvatars : safeParticipants.length;

    if (participants.isEmpty) {
      return Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: colorScheme.surfaceVariant,
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.person_outline,
          size: 16,
          color: colorScheme.onSurfaceVariant,
        ),
      );
    }

    return SizedBox(
      width: displayCount * 20.0 + 4,
      height: 24,
      child: Stack(
        children: [
          for (int i = 0; i < displayCount; i++)
            if (i < safeParticipants.length)
              Positioned(
                left: i * 16.0,
                child: OptimizedAvatarImage(
                  imageUrl: safeParticipants[i] is Map ? 
                    safeParticipants[i]['profileImageUrl'] : null,
                  size: 24,
                  fallbackText: safeParticipants[i] is Map ? 
                    (safeParticipants[i]['displayName'] ?? '') : '',
                  preload: widget.index < 3, // 상위 3개 카드만 프리로드
                ),
              ),

          // 더 많은 참가자가 있는 경우 "+N" 표시
          if (participants.length > maxAvatars)
            Positioned(
              left: maxAvatars * 16.0,
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withOpacity(0.1),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: colorScheme.primary.withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Center(
                  child: Text(
                    '+${participants.length - maxAvatars}',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.primary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 모집 상태 칩 빌드
  Widget _buildStatusChip(
    int current,
    int max,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    if (max == 0) return const SizedBox.shrink(); // 최대값이 없으면 표시하지 않음

    final isOpen = current < max;
    final statusColor = isOpen ? Colors.green : Colors.red;
    final statusText = isOpen
        ? (AppLocalizations.of(context)!.openStatus ?? "") : AppLocalizations.of(context)!.closedStatus;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), // padding 증가
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.15), // 배경 불투명도 증가
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: statusColor.withOpacity(0.4), width: 1.5), // 테두리 추가
      ),
      child: Text(
        statusText,
        style: theme.textTheme.labelMedium?.copyWith( // labelSmall → labelMedium
          color: statusColor,
          fontWeight: FontWeight.w700, // w600 → w700
          fontSize: 14, // 명시적으로 크기 지정
        ),
      ),
    );
  }

  /// 참여하기/참여취소 버튼 빌드
  Widget _buildJoinButton(
    Meetup currentMeetup,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return const SizedBox.shrink();

    // 내가 만든 모임이면 버튼 표시 안함
    if (currentMeetup.userId == currentUser.uid) {
      return const SizedBox.shrink();
    }

    // 참여 상태 확인 중이면 로딩 표시
    if (isCheckingParticipation) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: null,
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: const SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    final current = currentMeetup.currentParticipants;
    final max = currentMeetup.maxParticipants;
    final isOpen = current < max;

    // 참여 중인 경우: 상세 페이지와 동일한 로직 적용 (hasReview만 체크)
    if (isParticipating) {
      // 디버깅: 현재 후기 상태 로그
      print('🔍 [OptimizedMeetupCard-JoinButton] 참여자 버튼 로직 (상세 페이지와 동일):');
      print('   - 모임 ID: ${currentMeetup.id}');
      print('   - hasReview: ${currentMeetup.hasReview}');
      print('   - reviewId: ${currentMeetup.reviewId}');
      
      // 상세 페이지와 동일한 로직: hasReview가 있으면 후기 확인 버튼, 없으면 나가기 버튼
      if (currentMeetup.hasReview == true) {
        print('✅ [OptimizedMeetupCard-JoinButton] 후기 확인 버튼 선택됨 (hasReview=true)');
        
        // 사용자가 이미 후기를 확인했는지 체크
        final user = FirebaseAuth.instance.currentUser;
        final hasAccepted = user != null ? currentMeetup.hasUserAcceptedReview(user.uid) : false;
        
        return SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: hasAccepted ? null : () => _navigateToReviewScreen(currentMeetup),
            icon: Icon(
              hasAccepted ? Icons.check_circle : Icons.rate_review, 
              size: 18,
            ),
            label: Text(
              hasAccepted 
                  ? AppLocalizations.of(context)!.reviewChecked
                  : AppLocalizations.of(context)!.checkReview,
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: hasAccepted ? Colors.grey[300] : const Color(0xFF22C55E), // 더 선명한 녹색
              foregroundColor: hasAccepted ? Colors.grey[600] : Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        );
      } else {
        // 후기가 없는 경우 - 모임 확정되었으면 나가기 버튼 숨기고 "모임 확정" 칩 표시
        if (currentMeetup.isCompleted) {
          print('✅ [OptimizedMeetupCard-JoinButton] 모임 확정 표시 (isCompleted=true)');
          return SizedBox(
            width: double.infinity,
            child: Align(
              alignment: Alignment.centerRight,
              child: _buildConfirmedChip(),
            ),
          );
        }
        
        print('🔶 [OptimizedMeetupCard-JoinButton] 나가기 버튼 선택됨 (hasReview=false, isClosed=false)');
        return SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: isJoinLeaveProcessing ? null : () => _leaveMeetup(currentMeetup),
            icon: isJoinLeaveProcessing 
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(Icons.exit_to_app, size: 18),
            label: Text(
              isJoinLeaveProcessing 
                  ? "처리 중..." 
                  : (AppLocalizations.of(context)!.leaveMeetup ?? "나가기")
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange[600],
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        );
      }
    }

    // 모집 마감된 모임은 버튼 표시 안함 (모임 확정으로 보이게)
    if (currentMeetup.isClosed) {
      print('🚫 [OptimizedMeetupCard-JoinButton] 모집 마감으로 참여 버튼 숨김 (isClosed=true)');
      return const SizedBox.shrink();
    }
    
    // 마감된 모임은 버튼 표시 안함
    if (!isOpen) return const SizedBox.shrink();

    // 참여하기 버튼
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: isJoinLeaveProcessing ? null : () => _joinMeetup(currentMeetup),
        icon: isJoinLeaveProcessing 
            ? const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : const Icon(Icons.group_add, size: 18),
        label: Text(
          isJoinLeaveProcessing 
              ? "처리 중..." 
              : (AppLocalizations.of(context)!.joinMeetup ?? "")
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: Colors.white, // 글씨 색상을 흰색으로 변경
          padding: const EdgeInsets.symmetric(vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }

  /// 후기 확인 및 수락 화면으로 이동
  Future<void> _viewAndRespondToReview(Meetup currentMeetup) async {
    try {
      final meetupService = MeetupService();
      String? reviewId = currentMeetup.reviewId;

      // 최신 meetups 문서로 보강 (reviewId/hasReview 누락 대비)
      if (reviewId == null || currentMeetup.hasReview == false) {
        final fresh = await meetupService.getMeetupById(currentMeetup.id);
        if (fresh != null) {
          setState(() {
            this.currentMeetup = fresh;
          });
          reviewId = fresh.reviewId;
        }
      }

      if (reviewId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppLocalizations.of(context)!.reviewNotFound ?? "")),
          );
        }
        return;
      }

      final reviewData = await meetupService.getMeetupReview(reviewId);
      if (reviewData == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppLocalizations.of(context)!.reviewLoadFailed ?? "")),
          );
        }
        return;
      }

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // 수신자용 요청 조회
      final reqQuery = await FirebaseFirestore.instance
          .collection('review_requests')
          .where('recipientId', isEqualTo: user.uid)
          .where('metadata.reviewId', isEqualTo: reviewId)
          .limit(1)
          .get();

      String requestId;
      if (reqQuery.docs.isEmpty) {
        // 없으면 생성 (알림 누락 대비)
        final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        final recipientName = userDoc.data()?['nickname'] ?? userDoc.data()?['displayName'] ?? 'User';
        final requesterId = currentMeetup.userId ?? '';
        final requesterName = reviewData['authorName'] ?? currentMeetup.hostNickname ?? currentMeetup.host;

        final newReq = await FirebaseFirestore.instance.collection('review_requests').add({
          'meetupId': currentMeetup.id,
          'requesterId': requesterId,
          'requesterName': requesterName,
          'recipientId': user.uid,
          'recipientName': recipientName,
          'meetupTitle': currentMeetup.title,
          'message': reviewData['content'] ?? '',
          'imageUrls': [reviewData['imageUrl'] ?? ''],
          'status': 'pending',
          'createdAt': FieldValue.serverTimestamp(),
          'respondedAt': null,
          'expiresAt': Timestamp.fromDate(DateTime.now().add(const Duration(days: 7))),
          'metadata': {'reviewId': reviewId},
        });
        requestId = newReq.id;
      } else {
        requestId = reqQuery.docs.first.id;
      }

      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ReviewApprovalScreen(
            requestId: requestId,
            reviewId: reviewId!,
            meetupTitle: currentMeetup.title,
            imageUrl: reviewData['imageUrl'] ?? '',
            content: reviewData['content'] ?? '',
            authorName: reviewData['authorName'] ?? '익명',
          ),
        ),
      );
    } catch (e) {
      print('후기 확인 이동 오류: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${AppLocalizations.of(context)!.error}: $e')),
        );
      }
    }
  }

  /// 모임 참여하기 (낙관적 업데이트)
  Future<void> _joinMeetup(Meetup currentMeetup) async {
    if (isJoinLeaveProcessing) return; // 중복 처리 방지
    
    // 1. 즉시 UI 업데이트 (낙관적 업데이트)
    final originalParticipants = this.currentMeetup.currentParticipants;
    final originalIsParticipating = isParticipating;
    
        setState(() {
      isJoinLeaveProcessing = true;
          this.currentMeetup = this.currentMeetup.copyWith(
            currentParticipants: this.currentMeetup.currentParticipants + 1,
          );
      isParticipating = true;
        });

    try {
      // 2. 서버 요청
      final meetupService = MeetupService();
      final success = await meetupService.joinMeetup(currentMeetup.id);

      if (success) {
        // 3. 성공 시 성공 메시지 표시 및 부모 위젯에 알림
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.meetupJoined ?? "모임에 참여했습니다"),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
          
          // 부모 위젯에 참여 상태 변경 알림
          widget.onParticipationChanged?.call();
        }
        print('✅ [OptimizedMeetupCard] 모임 참여 성공: ${currentMeetup.id}');
      } else {
        // 4. 실패 시 원래 상태로 롤백
        setState(() {
          this.currentMeetup = this.currentMeetup.copyWith(
            currentParticipants: originalParticipants,
          );
          isParticipating = originalIsParticipating;
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.meetupJoinFailed ?? "모임 참여에 실패했습니다"),
              backgroundColor: Colors.red,
            ),
          );
        }
        print('❌ [OptimizedMeetupCard] 모임 참여 실패: ${currentMeetup.id}');
      }
    } catch (e) {
      // 5. 오류 시 원래 상태로 롤백
      setState(() {
        this.currentMeetup = this.currentMeetup.copyWith(
          currentParticipants: originalParticipants,
        );
        isParticipating = originalIsParticipating;
      });
      
      print('❌ [OptimizedMeetupCard] 모임 참여 오류: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('모임 참여 중 오류가 발생했습니다: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      // 6. 로딩 상태 해제
      if (mounted) {
        setState(() {
          isJoinLeaveProcessing = false;
        });
      }
    }
  }

  /// 모임 참여취소 (낙관적 업데이트)
  Future<void> _leaveMeetup(Meetup currentMeetup) async {
    if (isJoinLeaveProcessing) return; // 중복 처리 방지
    
    try {
      // 최신 데이터로 후기 상태 재확인
      await _refreshMeetupData();
      
      // 후기가 작성된 경우 나가기 방지
      if (this.currentMeetup.hasReview) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('주최자가 후기를 작성한 모임은 나갈 수 없습니다. 후기를 확인해주세요.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }
      
      // 1. 즉시 UI 업데이트 (낙관적 업데이트)
      final originalParticipants = this.currentMeetup.currentParticipants;
      final originalIsParticipating = isParticipating;
      
        setState(() {
        isJoinLeaveProcessing = true;
          this.currentMeetup = this.currentMeetup.copyWith(
            currentParticipants: this.currentMeetup.currentParticipants - 1,
          );
        isParticipating = false;
        });

      // 2. 서버 요청
      final meetupService = MeetupService();
      final success = await meetupService.leaveMeetup(currentMeetup.id);

      if (success) {
        // 3. 성공 시 성공 메시지 표시 및 부모 위젯에 알림
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.leaveMeetup ?? "모임에서 나갔습니다"),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 2),
            ),
          );
          
          // 부모 위젯에 참여 상태 변경 알림
          widget.onParticipationChanged?.call();
        }
        print('✅ [OptimizedMeetupCard] 모임 나가기 성공: ${currentMeetup.id}');
      } else {
        // 4. 실패 시 원래 상태로 롤백
        setState(() {
          this.currentMeetup = this.currentMeetup.copyWith(
            currentParticipants: originalParticipants,
          );
          isParticipating = originalIsParticipating;
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.leaveMeetupFailed ?? "모임 나가기에 실패했습니다"),
              backgroundColor: Colors.red,
            ),
          );
        }
        print('❌ [OptimizedMeetupCard] 모임 나가기 실패: ${currentMeetup.id}');
      }
    } catch (e) {
      // 5. 오류 시 원래 상태로 롤백 (만약 이미 UI가 업데이트되었다면)
      if (isJoinLeaveProcessing) {
        final originalParticipants = this.currentMeetup.currentParticipants + 1; // 원래 값으로 복원
        setState(() {
          this.currentMeetup = this.currentMeetup.copyWith(
            currentParticipants: originalParticipants,
          );
          isParticipating = true;
        });
      }
      
      print('❌ [OptimizedMeetupCard] 모임 나가기 오류: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('모임 나가기 중 오류가 발생했습니다: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      // 6. 로딩 상태 해제
      if (mounted) {
        setState(() {
          isJoinLeaveProcessing = false;
        });
      }
    }
  }


  /// 모임 이미지 빌드 (기본 이미지 포함)
  Widget _buildMeetupImage(Meetup currentMeetup) {
    // 리스트에서는 작은 크기로, 상세 페이지에서는 큰 크기로 표시
    const double imageHeight = 120; // 리스트에서는 120px로 축소
    
    // 모임에서 표시할 이미지 URL 가져오기 (기본 이미지 포함)
    final String displayImageUrl = currentMeetup.getDisplayImageUrl();
    final bool isDefaultImage = currentMeetup.isDefaultImage();
    
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: isDefaultImage
          ? _buildDefaultImage(displayImageUrl, imageHeight)
          : _buildNetworkImage(displayImageUrl, imageHeight),
    );
  }

  /// 기본 이미지 빌드 (이제 아이콘 기반 이미지를 직접 생성)
  Widget _buildDefaultImage(String assetPath, double height) {
    // asset 이미지 대신 카테고리별 아이콘 이미지를 직접 생성
    return _buildCategoryIconImage(height);
  }

  /// 네트워크 이미지 빌드
  Widget _buildNetworkImage(String imageUrl, double height) {
    return OptimizedNetworkImage(
      imageUrl: imageUrl,
      targetSize: Size(double.infinity, height),
      fit: BoxFit.cover,
      preload: widget.index < 3, // 상위 3개 카드만 프리로드
          lazy: widget.index >= 3, // 하위 카드들은 지연 로딩
      semanticLabel: '모임 이미지',
      placeholder: Container(
        height: height,
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Center(
          child: Icon(Icons.image_outlined, size: 32, color: Colors.grey),
        ),
      ),
      // 이미지 로드 실패 시 기본 이미지로 대체
      errorWidget: _buildDefaultImage(currentMeetup.getDefaultImageUrl(), height),
    );
  }

  /// 카테고리별 아이콘 이미지 빌드 (기본 이미지 대신 사용)
  Widget _buildCategoryIconImage(double height) {
    return Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            currentMeetup.getCategoryBackgroundColor(),
            currentMeetup.getCategoryBackgroundColor().withOpacity(0.8),
          ],
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: currentMeetup.getCategoryColor().withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                currentMeetup.getCategoryIcon(),
                size: 32,
                color: currentMeetup.getCategoryColor(),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              currentMeetup.category,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: currentMeetup.getCategoryColor(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 후기 확인 화면으로 이동
  Future<void> _navigateToReviewScreen(Meetup meetup) async {
    try {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => MeetupReviewScreen(
            meetupId: meetup.id,
            reviewId: meetup.reviewId,
          ),
        ),
      );
      
      // 화면에서 돌아온 후 모임 데이터 새로고침
      await _refreshMeetupData();
    } catch (e) {
      print('후기 화면 이동 오류: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('후기 화면으로 이동하는 중 오류가 발생했습니다.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// 모임 데이터 새로고침
  Future<void> _refreshMeetupData() async {
    try {
      print('🔄 [OptimizedMeetupCard-Refresh] 모임 데이터 새로고침 시작: ${currentMeetup.id}');
      
      final doc = await FirebaseFirestore.instance
          .collection('meetups')
          .doc(currentMeetup.id)
          .get();

      if (doc.exists && mounted) {
        final data = doc.data()!;
        data['id'] = doc.id; // doc.id를 데이터에 추가
        
        final oldHasReview = currentMeetup.hasReview;
        final oldIsClosed = currentMeetup.isClosed;
        final newHasReview = data['hasReview'] ?? false;
        final newIsClosed = data['isClosed'] ?? false;
        
        // 상태 변경 상세 로깅
        if (oldHasReview != newHasReview || oldIsClosed != newIsClosed) {
          print('🔄 [OptimizedMeetupCard-Refresh] 상태 변경 감지:');
          print('   - hasReview: $oldHasReview → $newHasReview');
          print('   - isClosed: $oldIsClosed → $newIsClosed');
        } else {
          print('🔄 [OptimizedMeetupCard-Refresh] 상태 변경 없음: hasReview=$newHasReview, isClosed=$newIsClosed');
        }
        
        setState(() {
          currentMeetup = Meetup.fromJson(data);
        });
        
        print('✅ [OptimizedMeetupCard-Refresh] 모임 데이터 새로고침 완료');
      } else {
        print('⚠️ [OptimizedMeetupCard-Refresh] 문서가 존재하지 않거나 위젯이 unmounted됨');
      }
    } catch (e) {
      print('❌ [OptimizedMeetupCard-Refresh] 모임 데이터 새로고침 오류: $e');
    }
  }

  /// 모집 마감 확인 다이얼로그
  void _showCloseConfirmation(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.help_outline, color: Colors.orange[600]),
            const SizedBox(width: 8),
            Text(AppLocalizations.of(context)!.closeMeetupConfirm),
          ],
        ),
        content: Text(
          Localizations.localeOf(context).languageCode == 'ko'
              ? '모집을 마감하면 더 이상 새로운 참여자가 참여할 수 없습니다.'
              : 'Once closed, no new participants can join this meetup.',
          style: const TextStyle(fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _closeMeetup();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange[600],
              foregroundColor: Colors.white,
            ),
            child: Text(AppLocalizations.of(context)!.closeMeetup),
          ),
        ],
      ),
    );
  }

  /// 모집 마감 처리 (낙관적 업데이트)
  Future<void> _closeMeetup() async {
    // 1. 즉시 UI 업데이트 (낙관적 업데이트)
    final originalIsClosed = currentMeetup.isClosed;
    
    setState(() {
      currentMeetup = currentMeetup.copyWith(isClosed: true);
    });

    try {
      // 2. 서버 요청
      final meetupService = MeetupService();
      final success = await meetupService.closeMeetup(currentMeetup.id);

      if (success) {
        // 3. 성공 시 성공 메시지 표시
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.closeMeetupSuccess),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        }
        print('✅ [OptimizedMeetupCard] 모집 마감 성공: ${currentMeetup.id}');
      } else {
        // 4. 실패 시 원래 상태로 롤백
        setState(() {
          currentMeetup = currentMeetup.copyWith(isClosed: originalIsClosed);
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.closeMeetupFailed),
              backgroundColor: Colors.red,
            ),
          );
        }
        print('❌ [OptimizedMeetupCard] 모집 마감 실패: ${currentMeetup.id}');
      }
    } catch (e) {
      // 5. 오류 시 원래 상태로 롤백
      setState(() {
        currentMeetup = currentMeetup.copyWith(isClosed: originalIsClosed);
      });
      
      print('❌ [OptimizedMeetupCard] 모집 마감 오류: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('모집 마감 중 오류가 발생했습니다: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

}
