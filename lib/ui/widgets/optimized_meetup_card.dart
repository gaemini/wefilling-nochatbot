// lib/ui/widgets/optimized_currentMeetup_card.dart
// 성능 최적화된 모임 카드 위젯
// const 생성자, 메모이제이션, 이미지 최적화

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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
import 'package:url_launcher/url_launcher.dart';

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
              content: Text(AppLocalizations.of(context)!.cannotOpenLink),
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
            content: Text(AppLocalizations.of(context)!.error),
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
      elevation: 0.5,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outline.withOpacity(0.2)),
      ),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // 헤더 (작성자 + 더보기 버튼만)
              _buildCompactHeader(context, colorScheme),

              const SizedBox(height: 10),

              // 모임 제목
              Text(
                currentMeetup.title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurface,
                  fontSize: 16,
                  height: 1.3,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),

              const SizedBox(height: 8),

              // 위치
              Row(
                children: [
                  Icon(
                    Icons.location_on,
                    size: 16,
                    color: colorScheme.primary.withOpacity(0.7),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _openLocationUrl(currentMeetup.location),
                      child: Text(
                        currentMeetup.location,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: _isUrl(currentMeetup.location)
                              ? colorScheme.primary
                              : colorScheme.onSurfaceVariant,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          decoration: _isUrl(currentMeetup.location)
                              ? TextDecoration.underline
                              : null,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              // 참가자 수 + 참여하기 버튼 (같은 줄)
              Row(
                children: [
                  // 참가자 수 (세련된 배지)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: colorScheme.primary.withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.people,
                          size: 16,
                          color: colorScheme.primary,
                        ),
                    const SizedBox(width: 6),
                    Text(
                      '${currentMeetup.currentParticipants}/${currentMeetup.maxParticipants}${AppLocalizations.of(context)!.peopleUnit}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: colorScheme.primary,
                      ),
                    ),
                      ],
                    ),
                  ),

                  const Spacer(),

                  // 참여하기/나가기 버튼 (오른쪽)
                  _buildCompactJoinButton(currentMeetup, theme, colorScheme),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 컴팩트 헤더 (작성자 + 더보기 버튼)
  Widget _buildCompactHeader(BuildContext context, ColorScheme colorScheme) {
    final currentUser = FirebaseAuth.instance.currentUser;
    final theme = Theme.of(context);
    
    return Row(
      children: [
        // 작성자 정보 (더 명확하게)
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: colorScheme.surfaceVariant,
            shape: BoxShape.circle,
            border: Border.all(
              color: colorScheme.primary.withOpacity(0.3),
              width: 1.5,
            ),
          ),
          child: currentMeetup.hostPhotoURL.isNotEmpty
              ? ClipOval(
                  child: Image.network(
                    currentMeetup.hostPhotoURL,
                    width: 24,
                    height: 24,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Icon(
                      Icons.person,
                      size: 14,
                      color: BrandColors.neutral500,
                    ),
                  ),
                )
              : Icon(
                  Icons.person,
                  size: 14,
                  color: BrandColors.neutral500,
                ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            currentMeetup.hostNickname ?? currentMeetup.host,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurface,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        // 공개 범위 배지 (항상 표시)
        const SizedBox(width: 6),
        _buildCompactVisibilityBadge(context, colorScheme),
        // 더보기 버튼만 (카테고리 뱃지 없이)
        if (currentUser != null)
          FutureBuilder<bool>(
            future: _checkIsMyMeetup(currentUser),
            builder: (context, snapshot) {
              final isMyMeetup = snapshot.data ?? false;
              final shouldHideMenu = isMyMeetup && (currentMeetup.isCompleted || currentMeetup.hasReview);
              
              if (shouldHideMenu) return const SizedBox.shrink();
              
              return Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: colorScheme.surfaceVariant.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: PopupMenuButton<String>(
                  padding: EdgeInsets.zero,
                  iconSize: 20,
                  icon: Icon(
                    Icons.more_vert,
                    size: 20,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  itemBuilder: (context) => isMyMeetup 
                      ? [
                          PopupMenuItem(
                            value: 'edit',
                            child: Row(
                              children: [
                                const Icon(Icons.edit_outlined, size: 16),
                                const SizedBox(width: 8),
                                Text(AppLocalizations.of(context)!.editMeetup),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'cancel',
                            child: Row(
                              children: [
                                const Icon(Icons.cancel_outlined, size: 16, color: Colors.red),
                                const SizedBox(width: 8),
                                Text(
                                  AppLocalizations.of(context)!.cancelMeetupButton,
                                  style: const TextStyle(color: Colors.red),
                                ),
                              ],
                            ),
                          ),
                        ]
                      : [
                          PopupMenuItem(
                            value: 'report',
                            child: Row(
                              children: [
                                Icon(Icons.report_outlined, size: 16, color: Colors.red[600]),
                                const SizedBox(width: 8),
                                Text(AppLocalizations.of(context)!.reportAction),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'block',
                            child: Row(
                              children: [
                                Icon(Icons.block, size: 16, color: Colors.red[600]),
                                const SizedBox(width: 8),
                                Text(AppLocalizations.of(context)!.blockAction),
                              ],
                            ),
                          ),
                        ],
                  onSelected: (value) => _handleMenuAction(context, value),
                ),
              );
            },
          ),
      ],
    );
  }

  /// 컴팩트 참여 버튼
  Widget _buildCompactJoinButton(
    Meetup currentMeetup,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return const SizedBox.shrink();

    // 내가 만든 모임이면 버튼 숨김
    if (currentMeetup.userId == currentUser.uid) {
      return const SizedBox.shrink();
    }

    // 참여 상태 확인 중이면 로딩
    if (isCheckingParticipation) {
      return ElevatedButton(
        onPressed: null,
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          minimumSize: const Size(80, 32),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        child: const SizedBox(
          height: 16,
          width: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    final current = currentMeetup.currentParticipants;
    final max = currentMeetup.maxParticipants;
    final isOpen = current < max;

    // 참여 중인 경우 - 나가기 버튼
    if (isParticipating) {
      if (currentMeetup.hasReview == true) {
        return ElevatedButton(
          onPressed: () => _viewAndRespondToReview(currentMeetup),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green[600],
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            minimumSize: const Size(80, 32),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: Text(
            AppLocalizations.of(context)!.checkReview,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        );
      } else {
        return ElevatedButton(
          onPressed: () => _leaveMeetup(currentMeetup),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange[600],
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            minimumSize: const Size(80, 32),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: Text(
            AppLocalizations.of(context)!.leaveMeetup,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        );
      }
    }

    // 마감된 모임
    if (!isOpen) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        constraints: const BoxConstraints(minWidth: 80, minHeight: 32),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey[400]!, width: 1),
        ),
        child: Text(
          AppLocalizations.of(context)!.fullShort,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Colors.grey[700],
            letterSpacing: 0.3,
          ),
        ),
      );
    }

    // 참여 가능한 모임 - 참여하기 버튼
    return ElevatedButton(
      onPressed: () => _joinMeetup(currentMeetup),
      style: ElevatedButton.styleFrom(
        backgroundColor: colorScheme.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        minimumSize: const Size(80, 32),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      child: Text(
        AppLocalizations.of(context)!.joinMeetup,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  /// 헤더용 컴팩트 공개 범위 배지
  Widget _buildCompactVisibilityBadge(BuildContext context, ColorScheme colorScheme) {
    // 'friends' 또는 'category'는 친구공개로 표시
    // 'public'만 전체공개로 표시
    final bool isFriendsOnly = currentMeetup.visibility == 'friends' || 
                               currentMeetup.visibility == 'category';
    final Color badgeColor = isFriendsOnly ? Colors.orange : Colors.green;
    final String visibilityText = isFriendsOnly 
        ? AppLocalizations.of(context)!.visibilityFriends
        : AppLocalizations.of(context)!.visibilityPublic;
    final IconData icon = isFriendsOnly ? Icons.people : Icons.public;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: badgeColor.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: badgeColor.withOpacity(0.25),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 10,
            color: badgeColor,
          ),
          const SizedBox(width: 3),
          Text(
            visibilityText,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: badgeColor,
            ),
          ),
        ],
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
                    // 내가 쓴 글: 수정/삭제 메뉴 (모임 완료 전에만)
                    PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit_outlined, size: 16),
                          SizedBox(width: 8),
                          Text(AppLocalizations.of(context)!.editMeetup),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'cancel',
                      child: Row(
                        children: [
                          Icon(Icons.cancel_outlined, size: 16, color: Colors.red),
                          const SizedBox(width: 8),
                          Text(AppLocalizations.of(context)!.cancelMeetupButton, style: const TextStyle(color: Colors.red)),
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
                          Text(AppLocalizations.of(context)!.reportAction),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'block',
                      child: Row(
                        children: [
                          Icon(Icons.block, size: 16, color: Colors.red[600]),
                          const SizedBox(width: 8),
                          Text(AppLocalizations.of(context)!.blockAction),
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
            Text(AppLocalizations.of(context)!.cancelMeetupConfirm),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              Localizations.localeOf(context).languageCode == 'ko'
                  ? '정말로 "${currentMeetup.title}" 모임을 취소하시겠습니까?'
                  : 'Are you sure you want to cancel the meetup "${currentMeetup.title}"?',
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
                        Localizations.localeOf(context).languageCode == 'ko' ? '주의사항' : 'Notice',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.orange[700],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    Localizations.localeOf(context).languageCode == 'ko'
                        ? '• 취소된 모임은 복구할 수 없습니다\n• 참여 중인 모든 사용자에게 알림이 발송됩니다'
                        : '• Cancelled meetups cannot be restored\n• All participants will be notified',
                    style: const TextStyle(
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
            child: Text(
              AppLocalizations.of(context)!.no,
              style: const TextStyle(
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
            child: Text(
              Localizations.localeOf(context).languageCode == 'ko' ? '예, 취소합니다' : 'Yes, cancel',
              style: const TextStyle(
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
              : '${DateFormat('yyyy-MM-dd', 'en').format(currentMeetup.date)} ${currentMeetup.time.isEmpty ? AppLocalizations.of(context)!.undecided : currentMeetup.time}',
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
        ? AppLocalizations.of(context)!.openStatus
        : AppLocalizations.of(context)!.closedStatus;

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

    // 참여 중인 경우: 후기 존재 시 "후기 확인 및 수락" 버튼, 아니면 참여취소 버튼
    if (isParticipating) {
      if (currentMeetup.hasReview == true) {
        return SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => _viewAndRespondToReview(currentMeetup),
            icon: const Icon(Icons.rate_review, size: 18),
            label: Text(AppLocalizations.of(context)!.viewAndRespondToReview),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green[600],
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        );
      } else {
        return SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => _leaveMeetup(currentMeetup),
            icon: const Icon(Icons.exit_to_app, size: 18),
            label: Text(AppLocalizations.of(context)!.leaveMeetup),
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

    // 마감된 모임은 버튼 표시 안함
    if (!isOpen) return const SizedBox.shrink();

    // 참여하기 버튼
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () => _joinMeetup(currentMeetup),
        icon: const Icon(Icons.group_add, size: 18),
        label: Text(AppLocalizations.of(context)!.joinMeetup),
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
            SnackBar(content: Text(AppLocalizations.of(context)!.reviewNotFound)),
          );
        }
        return;
      }

      final reviewData = await meetupService.getMeetupReview(reviewId);
      if (reviewData == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppLocalizations.of(context)!.reviewLoadFailed)),
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
            SnackBar(
              content: Text(AppLocalizations.of(context)!.meetupJoined),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.meetupJoinFailed),
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
            content: Text('${AppLocalizations.of(context)!.error}: $e'),
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
            SnackBar(
              content: Text(AppLocalizations.of(context)!.leaveMeetup),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.leaveMeetupFailed),
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
            content: Text('${AppLocalizations.of(context)!.error}: $e'),
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
