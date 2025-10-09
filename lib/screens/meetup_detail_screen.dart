// lib/screens/meetup_detail_screen.dart
// 모임 상세화면, 모임 정보 표시
// 모임 참여 및 취소 기능

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/meetup.dart';
import '../services/meetup_service.dart';
import '../widgets/country_flag_circle.dart';
import '../design/tokens.dart';
import '../ui/dialogs/report_dialog.dart';
import '../ui/dialogs/block_dialog.dart';
import 'meetup_participants_screen.dart';
import 'edit_meetup_screen.dart';

class MeetupDetailScreen extends StatefulWidget {
  final Meetup meetup;
  final String meetupId;
  final Function onMeetupDeleted;

  const MeetupDetailScreen({
    Key? key,
    required this.meetup,
    required this.meetupId,
    required this.onMeetupDeleted,
  }) : super(key: key);

  @override
  State<MeetupDetailScreen> createState() => _MeetupDetailScreenState();
}

class _MeetupDetailScreenState extends State<MeetupDetailScreen> {
  final MeetupService _meetupService = MeetupService();
  bool _isLoading = false;
  bool _isHost = false;
  late Meetup _currentMeetup;

  @override
  void initState() {
    super.initState();
    _currentMeetup = widget.meetup;
    _checkIfUserIsHost();
  }

  Future<void> _checkIfUserIsHost() async {
    final isHost = await _meetupService.isUserHostOfMeetup(widget.meetupId);
    if (mounted) {
      setState(() {
        _isHost = isHost;
      });
    }
  }

  Future<void> _cancelMeetup() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final success = await _meetupService.deleteMeetup(widget.meetupId);

      if (success) {
        if (mounted) {
          // 콜백 호출하여 부모 화면 업데이트
          widget.onMeetupDeleted();

          Navigator.of(context).pop();
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('모임이 성공적으로 취소되었습니다.')));
        }
      } else if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('모임 취소에 실패했습니다. 다시 시도해주세요.')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('오류가 발생했습니다: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _currentMeetup.getStatus();
    final isUpcoming = status == '예정';
    final size = MediaQuery.of(context).size;

    return Dialog(
      backgroundColor: Colors.white,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: double.infinity,
        constraints: BoxConstraints(
          maxWidth: min(500, size.width - 40),
          maxHeight: size.height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 헤더
            Container(
              decoration: BoxDecoration(
                color: Colors.blue,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          status,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const Spacer(),
                      _buildHeaderButtons(),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _currentMeetup.title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(
                        Icons.calendar_today,
                        size: 14,
                        color: Colors.white70,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${_currentMeetup.date.month}월 ${_currentMeetup.date.day}일',
                        style: const TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(width: 16),
                      const Icon(
                        Icons.access_time,
                        size: 14,
                        color: Colors.white70,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _currentMeetup.time,
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // 내용
            Flexible(
              child: ListView(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                children: [
                  _buildInfoItem(
                    Icons.calendar_today,
                    Colors.blue,
                    '날짜 및 시간',
                    '${_currentMeetup.date.month}월 ${_currentMeetup.date.day}일 (${_currentMeetup.getFormattedDayOfWeek()}) ${_currentMeetup.time}',
                  ),
                  _buildInfoItem(
                    Icons.location_on,
                    Colors.red,
                    '모임 장소',
                    _currentMeetup.location,
                  ),
                  _buildInfoItem(
                    Icons.people,
                    Colors.amber,
                    '참가 인원',
                    '${_currentMeetup.currentParticipants}/${_currentMeetup.maxParticipants}명',
                  ),
                  _buildInfoItem(
                    Icons.person,
                    Colors.green,
                    '주최자',
                    "${_currentMeetup.host} (국적: ${_currentMeetup.hostNationality.isEmpty ? '없음' : _currentMeetup.hostNationality})",
                    suffix:
                        _currentMeetup.hostNationality.isNotEmpty
                            ? CountryFlagCircle(
                              nationality: _currentMeetup.hostNationality,
                              size: 24, // 20 → 24로 증가
                            )
                            : null,
                  ),
                  _buildInfoItem(
                    Icons.category,
                    _getCategoryColor(_currentMeetup.category),
                    '카테고리',
                    _currentMeetup.category,
                  ),

                  // 모임 이미지
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: _buildMeetupImage(),
                  ),
                  
                  // 모임 설명
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '모임 설명',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _currentMeetup.description,
                          style: const TextStyle(fontSize: 14),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // 하단 버튼 (모임장만 취소 버튼 표시)
            if (_isHost) 
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: ElevatedButton(
                  onPressed: _isLoading ? null : () => _showCancelConfirmation(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                      : const Text('모임 취소'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoItem(
    IconData icon,
    Color color,
    String title,
    String content, {
    Widget? suffix,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                Row(
                  children: [
                    Text(
                      content,
                      style: const TextStyle(fontSize: 14),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (suffix != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 8.0),
                        child: suffix,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 카테고리별 색상 반환 메서드
  Color _getCategoryColor(String category) {
    switch (category) {
      case '스터디':
        return Colors.blue;
      case '식사':
        return Colors.orange;
      case '취미':
        return Colors.green;
      case '문화':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  /// 모임 이미지 빌드 (기본 이미지 포함)
  Widget _buildMeetupImage() {
    const double imageHeight = 200; // 상세화면에서는 더 큰 크기
    
    // 모임에서 표시할 이미지 URL 가져오기 (기본 이미지 포함)
    final String displayImageUrl = _currentMeetup.getDisplayImageUrl();
    final bool isDefaultImage = _currentMeetup.isDefaultImage();
    
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: isDefaultImage
            ? _buildDefaultImage(displayImageUrl, imageHeight)
            : _buildNetworkImage(displayImageUrl, imageHeight),
      ),
    );
  }

  /// 기본 이미지 빌드 (이제 아이콘 기반 이미지를 직접 생성)
  Widget _buildDefaultImage(String assetPath, double height) {
    // asset 이미지 대신 카테고리별 아이콘 이미지를 직접 생성
    return _buildCategoryIconImage(height);
  }

  /// 네트워크 이미지 빌드
  Widget _buildNetworkImage(String imageUrl, double height) {
    return Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Image.network(
        imageUrl,
        height: height,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Container(
            height: height,
            child: Center(
              child: CircularProgressIndicator(
                value: loadingProgress.expectedTotalBytes != null
                    ? loadingProgress.cumulativeBytesLoaded / 
                      loadingProgress.expectedTotalBytes!
                    : null,
              ),
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) {
          // 이미지 로드 실패 시 기본 이미지로 대체
          return _buildDefaultImage(_currentMeetup.getDefaultImageUrl(), height);
        },
      ),
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
            _currentMeetup.getCategoryBackgroundColor(),
            _currentMeetup.getCategoryBackgroundColor().withOpacity(0.8),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _currentMeetup.getCategoryColor().withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _currentMeetup.getCategoryIcon(),
                size: 48,
                color: _currentMeetup.getCategoryColor(),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _currentMeetup.category,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: _currentMeetup.getCategoryColor(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 헤더 버튼들 빌드 (수정/삭제 또는 신고/차단)
  Widget _buildHeaderButtons() {
    final currentUser = FirebaseAuth.instance.currentUser;
    
    if (currentUser == null) {
      return const SizedBox.shrink();
    }

    return FutureBuilder<bool>(
      future: _checkIsMyMeetup(currentUser),
      builder: (context, snapshot) {
        final isMyMeetup = snapshot.data ?? false;
        
        print('🔍🔍🔍 [MeetupDetailScreen] 권한 체크 상세 정보:');
        print('   - 현재 사용자 UID: ${currentUser.uid}');
        print('   - 모임 ID: ${widget.meetup.id}');
        print('   - 모임 제목: ${widget.meetup.title}');
        print('   - 모임 userId: ${widget.meetup.userId}');
        print('   - 모임 hostNickname: ${widget.meetup.hostNickname}');
        print('   - 모임 host: ${widget.meetup.host}');
        print('   - isMyMeetup 결과: $isMyMeetup');
        print('   - 표시될 메뉴: ${isMyMeetup ? "수정/삭제" : "신고/차단"}');

        return _buildHeaderButtonsContent(currentUser, isMyMeetup);
      },
    );
  }

  /// 현재 사용자가 모임 작성자인지 확인
  Future<bool> _checkIsMyMeetup(User currentUser) async {
    try {
      print('🔍 [MeetupDetailScreen._checkIsMyMeetup] 시작');
      print('   - 현재 사용자 UID: ${currentUser.uid}');
      print('   - 모임 userId: ${widget.meetup.userId}');
      print('   - 모임 hostNickname: ${widget.meetup.hostNickname}');
      
      // 1. userId가 있으면 userId로 비교 (새로운 데이터)
      if (widget.meetup.userId != null && widget.meetup.userId!.isNotEmpty) {
        final result = widget.meetup.userId == currentUser.uid;
        print('   - userId 비교 결과: $result (${widget.meetup.userId} == ${currentUser.uid})');
        return result;
      } 
      
      print('   - userId가 없음, hostNickname으로 비교 시도');
      
      // 2. userId가 없으면 hostNickname 또는 host로 비교 (기존 데이터 호환성)
      final hostToCheck = widget.meetup.hostNickname ?? widget.meetup.host;
      print('   - hostToCheck: $hostToCheck (hostNickname: ${widget.meetup.hostNickname}, host: ${widget.meetup.host})');
      
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

  /// 헤더 버튼 콘텐츠 빌드
  Widget _buildHeaderButtonsContent(User currentUser, bool isMyMeetup) {

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isMyMeetup) ...[
          // 본인 모임인 경우: 수정/삭제 메뉴
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            itemBuilder: (context) => [
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
            ],
            onSelected: (value) => _handleOwnerMenuAction(value),
          ),
        ] else if (currentUser != null) ...[
          // 다른 사용자 모임인 경우: 신고/차단 메뉴
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            itemBuilder: (context) => [
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
            onSelected: (value) => _handleUserMenuAction(value),
          ),
        ],
        
        // 닫기 버튼
        IconButton(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  /// 모임 주최자 메뉴 액션 처리
  void _handleOwnerMenuAction(String action) {
    switch (action) {
      case 'edit':
        _showEditMeetup();
        break;
      case 'cancel':
        _showCancelConfirmation();
        break;
    }
  }

  /// 일반 사용자 메뉴 액션 처리
  void _handleUserMenuAction(String action) {
    switch (action) {
      case 'report':
        if (_currentMeetup.userId != null) {
          showReportDialog(
            context,
            reportedUserId: _currentMeetup.userId!,
            targetType: 'meetup',
            targetId: _currentMeetup.id,
            targetTitle: _currentMeetup.title,
          );
        }
        break;
      case 'block':
        if (_currentMeetup.userId != null && _currentMeetup.hostNickname != null) {
          showBlockUserDialog(
            context,
            userId: _currentMeetup.userId!,
            userName: _currentMeetup.hostNickname!,
          );
        }
        break;
    }
  }

  /// 모임 수정 화면으로 이동
  Future<void> _showEditMeetup() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditMeetupScreen(meetup: _currentMeetup),
      ),
    );

    // 수정이 완료되면 최신 데이터로 새로고침
    if (result == true && mounted) {
      await _refreshMeetupData();
    }
  }

  /// 모임 데이터 새로고침
  Future<void> _refreshMeetupData() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('meetups')
          .doc(widget.meetupId)
          .get();

      if (doc.exists && mounted) {
        final data = doc.data()!;
        data['id'] = doc.id; // doc.id를 데이터에 추가
        
        setState(() {
          _currentMeetup = Meetup.fromJson(data);
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('모임 정보가 업데이트되었습니다.'),
            backgroundColor: Colors.blue,
            duration: Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      print('모임 데이터 새로고침 오류: $e');
    }
  }

  /// 모임 취소 확인 다이얼로그
  void _showCancelConfirmation() {
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
              '정말로 "${_currentMeetup.title}" 모임을 취소하시겠습니까?',
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
              _cancelMeetup();
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
}
