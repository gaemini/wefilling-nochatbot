// lib/ui/widgets/optimized_currentMeetup_card.dart
// 성능 최적화된 모임 카드 위젯
// const 생성자, 메모이제이션, 이미지 최적화

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/meetup.dart';
import '../../utils/image_utils.dart';
import '../../design/tokens.dart';
import '../../services/meetup_service.dart';
import '../dialogs/report_dialog.dart';
import '../dialogs/block_dialog.dart';
import '../../screens/edit_meetup_screen.dart';

/// 최적화된 모임 카드
class OptimizedMeetupCard extends StatefulWidget {
  final Meetup meetup;
  final int index;
  final VoidCallback onTap;
  final bool preloadImage;
  final VoidCallback? onMeetupDeleted; // 삭제 후 콜백 추가

  const OptimizedMeetupCard({
    super.key,
    required this.meetup,
    required this.index,
    required this.onTap,
    this.preloadImage = false,
    this.onMeetupDeleted,
  });

  @override
  State<OptimizedMeetupCard> createState() => _OptimizedMeetupCardState();
}

class _OptimizedMeetupCardState extends State<OptimizedMeetupCard> {
  late Meetup currentMeetup;
  bool isParticipating = false;
  bool isCheckingParticipation = true;

  @override
  void initState() {
    super.initState();
    currentMeetup = widget.meetup;
    _checkParticipationStatus();
  }

  /// 현재 사용자의 참여 상태 확인 (participants 배열 기반)
  Future<void> _checkParticipationStatus() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      setState(() {
        isCheckingParticipation = false;
      });
      return;
    }

    try {
      // Firestore에서 직접 모임 문서를 조회하여 participants 배열 확인
      final meetupDoc = await FirebaseFirestore.instance
          .collection('meetups')
          .doc(currentMeetup.id)
          .get();
      
      if (meetupDoc.exists) {
        final data = meetupDoc.data()!;
        final participants = List<String>.from(data['participants'] ?? []);
        
        setState(() {
          isParticipating = participants.contains(currentUser.uid);
          isCheckingParticipation = false;
        });
      } else {
        setState(() {
          isCheckingParticipation = false;
        });
      }
    } catch (e) {
      print('참여 상태 확인 오류: $e');
      setState(() {
        isCheckingParticipation = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outline.withOpacity(0.2)),
      ),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 헤더 (카테고리 뱃지 + 더 많은 옵션)
              _buildHeader(context, colorScheme),

              const SizedBox(height: 12),

              // 모임 제목
              Text(
                currentMeetup.title,
                style: theme.textTheme.titleLarge?.copyWith( // titleMedium → titleLarge
                  fontWeight: FontWeight.w700, // w600 → w700
                  color: colorScheme.onSurface,
                  fontSize: 18, // 명시적 크기 지정
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),

              const SizedBox(height: 10), // 8 → 10

              // 모임 설명
              if (currentMeetup.description.isNotEmpty) ...[
                Text(
                  currentMeetup.description,
                  style: theme.textTheme.bodyLarge?.copyWith( // bodyMedium → bodyLarge
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 15, // 명시적 크기 지정
                    height: 1.4, // 줄 높이 추가
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 12),
              ],

              // 모임 정보 (날짜, 시간, 장소)
              _buildMeetupInfo(currentMeetup, theme, colorScheme),

              const SizedBox(height: 12),

              // 참가자 정보와 참여하기 버튼
              _buildParticipantInfoWithJoinButton(currentMeetup, theme, colorScheme),

              // 모임 이미지 (항상 표시 - 없으면 기본 이미지)
              const SizedBox(height: 12),
              _buildMeetupImage(currentMeetup),
            ],
          ),
        ),
      ),
    );
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

    return Row(
      children: [
        // 카테고리 뱃지
        _buildCategoryBadge(currentMeetup.category, colorScheme),
        
        const Spacer(),
        
        // 더 많은 옵션 버튼
        if (currentUser != null)
          PopupMenuButton<String>(
            icon: Icon(
              Icons.more_vert,
              size: 20,
              color: colorScheme.onSurfaceVariant,
            ),
            itemBuilder: (context) => isMyMeetup 
                ? [
                    // 내가 쓴 글: 수정/삭제 메뉴
                    const PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit_outlined, size: 16),
                          SizedBox(width: 8),
                          Text('모임 수정'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'cancel',
                      child: Row(
                        children: [
                          Icon(Icons.cancel_outlined, size: 16, color: Colors.red),
                          const SizedBox(width: 8),
                          const Text('모임 취소', style: TextStyle(color: Colors.red)),
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
                          const Text('신고하기'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'block',
                      child: Row(
                        children: [
                          Icon(Icons.block, size: 16, color: Colors.red[600]),
                          const SizedBox(width: 8),
                          const Text('사용자 차단'),
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
      case 'cancel':
        // 모임 취소 확인 다이얼로그
        _showCancelConfirmation(context);
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

  /// 실제 모임 취소 처리
  Future<void> _cancelMeetup(BuildContext context) async {
    try {
      final meetupService = MeetupService();
      final success = await meetupService.deleteMeetup(currentMeetup.id);

      if (success) {
        if (context.mounted) {
          // 취소 성공 시 콜백 호출
          widget.onMeetupDeleted?.call();
          
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('모임이 성공적으로 취소되었습니다.'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('모임 취소에 실패했습니다. 다시 시도해주세요.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('오류가 발생했습니다: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// 모임 취소 확인 다이얼로그
  void _showCancelConfirmation(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false, // 바깥 영역 터치로 닫기 방지
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.help_outline, color: Colors.orange[600]),
            const SizedBox(width: 8),
            const Text('모임 취소 확인'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '정말로 "${currentMeetup.title}" 모임을 취소하시겠습니까?',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.warning_amber, 
                           size: 16, 
                           color: Colors.orange[700]),
                      const SizedBox(width: 4),
                      Text(
                        '주의사항',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.orange[700],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '• 취소된 모임은 복구할 수 없습니다\n'
                    '• 참여 중인 모든 사용자에게 알림이 발송됩니다',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: const Text(
              '아니오',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _cancelMeetup(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red[600],
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: const Text(
              '예, 취소합니다',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        buttonPadding: const EdgeInsets.symmetric(horizontal: 8),
      ),
    );
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
      case '취미':
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
          text: '${currentMeetup.date} ${currentMeetup.time}',
          theme: theme,
          colorScheme: colorScheme,
        ),

        const SizedBox(height: 6),

        // 장소
        _buildInfoRow(
          icon: Icons.location_on_outlined,
          text: currentMeetup.location,
          theme: theme,
          colorScheme: colorScheme,
        ),
      ],
    );
  }

  /// 정보 행 빌드
  Widget _buildInfoRow({
    required IconData icon,
    required String text,
    required ThemeData theme,
    required ColorScheme colorScheme,
  }) {
    return Row(
      children: [
        Icon(icon, size: 18, color: BrandColors.neutral500), // 16 → 18
        const SizedBox(width: 8), // 6 → 8
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodyMedium?.copyWith( // bodySmall → bodyMedium
              color: colorScheme.onSurfaceVariant,
              fontSize: 14, // 명시적 크기 지정
              fontWeight: FontWeight.w500, // 굵기 추가
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
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
                '$current/$max명',
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
    final statusText = isOpen ? '모집중' : '마감';

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

    // 참여 중인 경우 참여취소 버튼 표시
    if (isParticipating) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: () => _leaveMeetup(currentMeetup),
          icon: const Icon(Icons.exit_to_app, size: 18),
          label: const Text('참여취소'),
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

    // 마감된 모임은 버튼 표시 안함
    if (!isOpen) return const SizedBox.shrink();

    // 참여하기 버튼
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () => _joinMeetup(currentMeetup),
        icon: const Icon(Icons.group_add, size: 18),
        label: const Text('참여하기'),
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

  /// 모임 참여하기
  Future<void> _joinMeetup(Meetup currentMeetup) async {
    try {
      final meetupService = MeetupService();
      final success = await meetupService.joinMeetup(currentMeetup.id);

      if (success) {
        // 참여 성공 시 UI 업데이트
        setState(() {
          this.currentMeetup = this.currentMeetup.copyWith(
            currentParticipants: this.currentMeetup.currentParticipants + 1,
          );
          isParticipating = true; // 참여 상태 업데이트
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('모임에 참여했습니다!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('모임 참여에 실패했습니다. 다시 시도해주세요.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      print('모임 참여 오류: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('오류가 발생했습니다: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// 모임 참여취소
  Future<void> _leaveMeetup(Meetup currentMeetup) async {
    try {
      final meetupService = MeetupService();
      final success = await meetupService.leaveMeetup(currentMeetup.id);

      if (success) {
        // 참여취소 성공 시 UI 업데이트
        setState(() {
          this.currentMeetup = this.currentMeetup.copyWith(
            currentParticipants: this.currentMeetup.currentParticipants - 1,
          );
          isParticipating = false; // 참여 상태 업데이트
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('모임 참여를 취소했습니다.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('참여취소에 실패했습니다. 다시 시도해주세요.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      print('모임 참여취소 오류: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('오류가 발생했습니다: $e'),
            backgroundColor: Colors.red,
          ),
        );
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

  /// 모임 데이터 새로고침
  Future<void> _refreshMeetupData() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('meetups')
          .doc(currentMeetup.id)
          .get();

      if (doc.exists && mounted) {
        final data = doc.data()!;
        data['id'] = doc.id; // doc.id를 데이터에 추가
        
        setState(() {
          currentMeetup = Meetup.fromJson(data);
        });
      }
    } catch (e) {
      print('모임 데이터 새로고침 오류: $e');
    }
  }

}
