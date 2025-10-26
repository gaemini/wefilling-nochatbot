// lib/screens/meetup_detail_screen.dart
// 모임 상세화면, 모임 정보 표시
// 모임 참여 및 취소 기능

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/meetup.dart';
import '../models/meetup_participant.dart';
import '../services/meetup_service.dart';
import '../widgets/country_flag_circle.dart';
import 'package:intl/intl.dart';
import '../utils/country_flag_helper.dart';
import '../design/tokens.dart';
import '../ui/dialogs/report_dialog.dart';
import '../ui/dialogs/block_dialog.dart';
import '../l10n/app_localizations.dart';
import 'meetup_participants_screen.dart';
import 'edit_meetup_screen.dart';
import 'create_meetup_review_screen.dart';
import 'review_approval_screen.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:url_launcher/url_launcher.dart';

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
  bool _isParticipant = false; // 현재 사용자가 승인된 참여자인지
  late Meetup _currentMeetup;
  List<MeetupParticipant> _participants = [];
  bool _isLoadingParticipants = true;

  @override
  void initState() {
    super.initState();
    _currentMeetup = widget.meetup;
    _checkIfUserIsHost();
    _checkIfUserIsParticipant();
    _loadParticipants();
  }

  Future<void> _loadParticipants() async {
    try {
      print('🔄 모임 참여자 로드 시작: ${widget.meetupId}');
      
      // 먼저 모든 참여자 조회 (디버깅용)
      final allParticipants = await _meetupService.getMeetupParticipants(widget.meetupId);
      print('📋 전체 참여자 수: ${allParticipants.length}');
      for (var p in allParticipants) {
        print('  - ${p.userName} (status: ${p.status})');
      }
      
      // 승인된 참여자만 필터링
      final participants = await _meetupService.getMeetupParticipantsByStatus(
        widget.meetupId,
        ParticipantStatus.approved,
      );

      // 방장을 참여자 목록 맨 앞에 포함
      final hostId = _currentMeetup.userId;
      final hostName = _currentMeetup.hostNickname ?? _currentMeetup.host;
      final hostProfile = MeetupParticipant(
        id: '${widget.meetupId}_${hostId ?? 'host'}',
        meetupId: widget.meetupId,
        userId: hostId ?? 'host',
        userName: hostName ?? 'Host',
        userEmail: '',
        userProfileImage: _currentMeetup.hostPhotoURL.isNotEmpty ? _currentMeetup.hostPhotoURL : null,
        joinedAt: _currentMeetup.date,
        status: ParticipantStatus.approved,
        message: null,
      );

      // 중복 방지 (이미 목록에 있으면 추가하지 않음)
      final hasHost = participants.any((p) => p.userId == hostId);
      final combined = [if (!hasHost) hostProfile, ...participants];
      print('✅ 승인된 참여자 ${participants.length}명 로드 완료');
      
      if (mounted) {
        setState(() {
          _participants = combined;
          _isLoadingParticipants = false;
          // 현재 사용자 승인 여부 동기화 (버튼 노출 조건 반영)
          final currentUid = FirebaseAuth.instance.currentUser?.uid;
          if (currentUid != null) {
            _isParticipant = combined.any((p) => p.userId == currentUid);
          }
        });
        print('🎨 UI 업데이트 완료: ${_participants.length}명 표시');
        print('현재 _participants 목록:');
        for (var p in _participants) {
          print('  ✓ ${p.userName} (${p.userId})');
        }
      }
    } catch (e, stackTrace) {
      print('❌ 참여자 목록 로드 오류: $e');
      print('Stack trace: $stackTrace');
      if (mounted) {
        setState(() {
          _isLoadingParticipants = false;
        });
      }
    }
  }

  Future<void> _checkIfUserIsHost() async {
    final isHost = await _meetupService.isUserHostOfMeetup(widget.meetupId);
    if (mounted) {
      setState(() {
        _isHost = isHost;
      });
    }
  }

  /// 현재 사용자가 승인된 참여자인지 확인
  Future<void> _checkIfUserIsParticipant() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() {
          _isParticipant = false;
        });
        return;
      }

      final participantStatus = await _meetupService.getUserParticipationStatus(widget.meetupId);
      if (mounted) {
        setState(() {
          _isParticipant = participantStatus?.status == ParticipantStatus.approved;
        });
      }
    } catch (e) {
      print('❌ 참여자 확인 오류: $e');
      if (mounted) {
        setState(() {
          _isParticipant = false;
        });
      }
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
          ).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context)!.meetupCancelledSuccessfully)));
        }
      } else if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.cancelMeetupFailed)),
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
    final currentLang = Localizations.localeOf(context).languageCode;
    final status = _currentMeetup.getStatus(languageCode: currentLang);
    final isUpcoming = status == AppLocalizations.of(context)!.scheduled;
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
                        currentLang == 'ko'
                            ? '${_currentMeetup.date.month}월 ${_currentMeetup.date.day}일'
                            : DateFormat('MMM d', 'en').format(_currentMeetup.date),
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
                    AppLocalizations.of(context)!.dateAndTime,
                    currentLang == 'ko'
                        ? '${_currentMeetup.date.month}월 ${_currentMeetup.date.day}일 (${_currentMeetup.getFormattedDayOfWeek(languageCode: currentLang)}) ${_currentMeetup.time}'
                        : '${DateFormat('MMM d', 'en').format(_currentMeetup.date)} (${_currentMeetup.getFormattedDayOfWeek(languageCode: 'en')}) ${_currentMeetup.time.isEmpty ? AppLocalizations.of(context)!.undecided : _currentMeetup.time}',
                  ),
                  _buildInfoItem(
                    Icons.location_on,
                    Colors.red,
                    AppLocalizations.of(context)!.venue,
                    _currentMeetup.location,
                  ),
                  _buildInfoItem(
                    Icons.people,
                    Colors.amber,
                    AppLocalizations.of(context)!.numberOfParticipants,
                    currentLang == 'ko'
                        ? '${_currentMeetup.currentParticipants}/${_currentMeetup.maxParticipants}${AppLocalizations.of(context)!.peopleUnit}'
                        : '${_currentMeetup.currentParticipants}/${_currentMeetup.maxParticipants} people',
                  ),
                  _buildInfoItem(
                    Icons.person,
                    Colors.green,
                    AppLocalizations.of(context)!.organizer,
                    currentLang == 'ko'
                        ? "${_currentMeetup.host} (국적: ${_currentMeetup.hostNationality.isEmpty ? '없음' : _currentMeetup.hostNationality})"
                        : "${_currentMeetup.host} (${AppLocalizations.of(context)!.nationality}: ${_currentMeetup.hostNationality.isEmpty ? 'N/A' : CountryFlagHelper.getCountryInfo(_currentMeetup.hostNationality)?.english ?? _currentMeetup.hostNationality})",
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
                    AppLocalizations.of(context)!.category,
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
                        Text(
                          AppLocalizations.of(context)!.meetupDetails,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Linkify(
                          onOpen: (link) async {
                            final uri = Uri.parse(link.url);
                            if (await canLaunchUrl(uri)) {
                              await launchUrl(
                                uri,
                                mode: LaunchMode.externalApplication,
                              );
                            } else {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('${AppLocalizations.of(context)!.error}: URL을 열 수 없습니다'),
                                  ),
                                );
                              }
                            }
                          },
                          text: _currentMeetup.description,
                          style: const TextStyle(fontSize: 14),
                          linkStyle: const TextStyle(
                            fontSize: 14,
                            color: Colors.blue,
                            decoration: TextDecoration.underline,
                          ),
                          maxLines: 10,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),

                  // 참여자 목록
                  _buildParticipantsSection(),
                ],
              ),
            ),

            // 하단 버튼 (모임장 또는 참여자)
            if (_isHost || (_isParticipant && _currentMeetup.hasReview)) 
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: _isHost 
                    ? _buildHostActionButton() 
                    : _buildParticipantActionButton(),
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
    // URL이 포함되어 있는지 확인 (간단한 정규식)
    final urlPattern = RegExp(r'https?://[^\s]+');
    final hasUrl = urlPattern.hasMatch(content);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
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
                const SizedBox(height: 4),
                if (hasUrl)
                  // URL이 있으면 Linkify 사용
                  Linkify(
                    onOpen: (link) async {
                      final uri = Uri.parse(link.url);
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(
                          uri,
                          mode: LaunchMode.externalApplication,
                        );
                      } else {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('${AppLocalizations.of(context)!.error}: URL을 열 수 없습니다'),
                            ),
                          );
                        }
                      }
                    },
                    text: content,
                    style: const TextStyle(fontSize: 14),
                    linkStyle: const TextStyle(
                      fontSize: 14,
                      color: Colors.blue,
                      decoration: TextDecoration.underline,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  )
                else
                  // URL이 없으면 일반 Text 사용
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          content,
                          style: const TextStyle(fontSize: 14),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
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
      case '카페':
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
    // 모임이 완료되었거나 후기가 작성된 경우 수정/취소 메뉴 숨김
    final isCompleted = _currentMeetup.isCompleted;
    final hasReview = _currentMeetup.hasReview;
    final shouldHideEditMenu = isCompleted || hasReview;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isMyMeetup && !shouldHideEditMenu) ...[
          // 본인 모임인 경우: 수정/삭제 메뉴 (모임 완료 전에만 표시)
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            itemBuilder: (context) => [
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
            ],
            onSelected: (value) => _handleOwnerMenuAction(value),
          ),
        ] else if (currentUser != null && !isMyMeetup) ...[
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
          SnackBar(
            content: Text(AppLocalizations.of(context)!.meetupInfoRefreshed),
            backgroundColor: Colors.blue,
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      print('모임 데이터 새로고침 오류: $e');
    }
  }

  /// 모임장 액션 버튼 (상태에 따라 다른 버튼 표시)
  Widget _buildHostActionButton() {
    final isFull = _currentMeetup.isFull();
    final isCompleted = _currentMeetup.isCompleted;
    final hasReview = _currentMeetup.hasReview;

    // 1. 모임 마감 전 or 마감 후이지만 완료 안됨 → 모임 취소 버튼
    if (!isCompleted) {
      return ElevatedButton(
        onPressed: _isLoading ? null : () {
          if (isFull) {
            // 마감된 모임이면 완료 처리 옵션 제공
            _showCompleteMeetupDialog();
          } else {
            // 마감 안된 모임이면 취소 옵션만 제공
            _showCancelConfirmation();
          }
        },
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
            : Text(isFull
                ? AppLocalizations.of(context)!.completeOrCancelMeetup
                : AppLocalizations.of(context)!.cancelMeetup),
      );
    }

    // 2. 모임 완료 & 후기 없음 → 모임 후기 쓰기 버튼
    if (!hasReview) {
      return ElevatedButton(
        onPressed: _isLoading ? null : () => _navigateToCreateReview(),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.blue,
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
            : Text(AppLocalizations.of(context)!.writeMeetupReview),
      );
    }

    // 3. 모임 완료 & 후기 있음 → 후기 수정 버튼만 표시 (삭제 불가)
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isLoading ? null : () => _navigateToEditReview(),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.blue,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
        child: Text(AppLocalizations.of(context)!.editReview),
      ),
    );
  }

  /// 참여자 액션 버튼 (후기 수락)
  Widget _buildParticipantActionButton() {
    return ElevatedButton(
      onPressed: _isLoading ? null : () => _navigateToReviewApproval(),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.green,
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
          : Text(AppLocalizations.of(context)!.viewAndRespondToReview),
    );
  }

  /// 후기 확인 다이얼로그 표시 (review_requests 기반)
  Future<void> _navigateToReviewApproval() async {
    if (_currentMeetup.reviewId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.reviewNotFound)),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // review_requests에서 현재 사용자의 요청 찾기 (캐시 무시하고 서버에서 최신 데이터 가져오기)
      final requestsSnapshot = await FirebaseFirestore.instance
          .collection('review_requests')
          .where('recipientId', isEqualTo: user.uid)
          .where('meetupId', isEqualTo: _currentMeetup.id)
          .limit(1)
          .get(const GetOptions(source: Source.server)); // 서버에서 최신 데이터 강제 조회

      String? requestId;
      String imageUrl = '';
      String content = '';
      String authorName = _currentMeetup.hostNickname ?? _currentMeetup.host;
      String status = 'pending';

      if (requestsSnapshot.docs.isNotEmpty) {
        // 요청이 있으면 해당 데이터 사용
        final requestData = requestsSnapshot.docs.first.data();
        requestId = requestsSnapshot.docs.first.id;
        imageUrl = (requestData['imageUrls'] as List?)?.firstOrNull ?? '';
        content = requestData['message'] ?? '';
        authorName = requestData['requesterName'] ?? authorName;
        status = requestData['status'] ?? 'pending';
        
        // 디버깅 로그
        print('📋 후기 요청 상태 확인:');
        print('  - requestId: $requestId');
        print('  - status: $status');
        print('  - recipientId: ${user.uid}');
        print('  - meetupId: ${_currentMeetup.id}');
      } else {
        // 요청이 없으면 MeetupService를 통해 후기 요청 재전송
        print('⚠️ review_request가 없음. 후기 요청 재전송 시도...');
        
        if (_currentMeetup.reviewId != null) {
          // MeetupService를 통해 후기 요청 재전송
          final success = await _meetupService.sendReviewApprovalRequests(
            reviewId: _currentMeetup.reviewId!,
            participantIds: [user.uid],
          );
          
          if (success) {
            print('✅ 후기 요청 재전송 성공');
            // 다시 조회 (서버에서 최신 데이터)
            final retrySnapshot = await FirebaseFirestore.instance
                .collection('review_requests')
                .where('recipientId', isEqualTo: user.uid)
                .where('meetupId', isEqualTo: _currentMeetup.id)
                .limit(1)
                .get(const GetOptions(source: Source.server));
            
            if (retrySnapshot.docs.isNotEmpty) {
              final requestData = retrySnapshot.docs.first.data();
              requestId = retrySnapshot.docs.first.id;
              imageUrl = (requestData['imageUrls'] as List?)?.firstOrNull ?? '';
              content = requestData['message'] ?? '';
              authorName = requestData['requesterName'] ?? authorName;
              status = requestData['status'] ?? 'pending';
              
              print('📋 재전송 후 상태: $status');
            }
          } else {
            print('❌ 후기 요청 재전송 실패');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(AppLocalizations.of(context)!.reviewLoadFailed)),
              );
            }
            return;
          }
        } else {
          print('❌ reviewId가 없음');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(AppLocalizations.of(context)!.reviewNotFound)),
            );
          }
          return;
        }
      }

      if (mounted && requestId != null) {
        // 다이얼로그로 후기 표시
        await _showReviewApprovalDialog(
          requestId: requestId,
          imageUrl: imageUrl,
          content: content,
          authorName: authorName,
          currentStatus: status,
        );
      }
    } catch (e) {
      print('❌ 후기 확인 이동 오류: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${AppLocalizations.of(context)!.error}: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// 후기 수락/거절 다이얼로그
  Future<void> _showReviewApprovalDialog({
    required String requestId,
    required String imageUrl,
    required String content,
    required String authorName,
    required String currentStatus,
  }) async {
    // 이미 응답한 경우 상태 표시 다이얼로그
    final bool alreadyResponded = currentStatus != 'pending';
    final String statusText = currentStatus == 'accepted' 
        ? AppLocalizations.of(context)!.reviewAccepted
        : currentStatus == 'rejected'
            ? AppLocalizations.of(context)!.reviewRejected
            : '';
    final MaterialColor statusColor = currentStatus == 'accepted' 
        ? Colors.green 
        : Colors.red;
    
    return showDialog(
      context: context,
      barrierDismissible: !alreadyResponded,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 500, maxHeight: 700),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 헤더
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: alreadyResponded 
                        ? [statusColor.shade400, statusColor.shade600]
                        : [Colors.deepPurple.shade400, Colors.deepPurple.shade600],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      alreadyResponded 
                          ? (currentStatus == 'accepted' ? Icons.check_circle : Icons.cancel)
                          : Icons.rate_review, 
                      color: Colors.white, 
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            alreadyResponded 
                                ? statusText
                                : AppLocalizations.of(context)!.reviewApprovalRequestTitle,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$authorName • ${_currentMeetup.title}',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // 컨텐츠
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 이미 응답한 경우 안내 메시지
                      if (alreadyResponded)
                        Container(
                          padding: const EdgeInsets.all(16),
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: statusColor.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: statusColor.shade200),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.info_outline, color: statusColor.shade700, size: 24),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  AppLocalizations.of(context)!.reviewAlreadyResponded,
                                  style: TextStyle(
                                    fontSize: 15,
                                    color: statusColor.shade900,
                                    fontWeight: FontWeight.w500,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      
                      // 이미지
                      if (imageUrl.isNotEmpty)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(
                            imageUrl,
                            height: 250,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => Container(
                              height: 250,
                              color: Colors.grey[200],
                              child: const Icon(Icons.image_not_supported, size: 64),
                            ),
                          ),
                        ),
                      const SizedBox(height: 16),

                      // 후기 내용
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey[200]!),
                        ),
                        child: Text(
                          content.isEmpty ? AppLocalizations.of(context)!.noContent : content,
                          style: const TextStyle(
                            fontSize: 15,
                            height: 1.6,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // 안내 메시지 (pending인 경우만)
                      if (currentStatus == 'pending')
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blue[50],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.blue[200]!),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.info_outline, color: Colors.blue[700], size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  AppLocalizations.of(context)!.reviewRequestInfo,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.blue[900],
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              // 버튼들
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  border: Border(top: BorderSide(color: Colors.grey[200]!)),
                ),
                child: currentStatus == 'pending'
                    ? Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                Navigator.pop(context);
                                await _handleReviewResponse(requestId, false);
                              },
                              icon: const Icon(Icons.close),
                              label: Text(AppLocalizations.of(context)!.reviewReject),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red[600],
                                side: BorderSide(color: Colors.red[400]!, width: 1.5),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () async {
                                Navigator.pop(context);
                                await _handleReviewResponse(requestId, true);
                              },
                              icon: const Icon(Icons.check),
                              label: Text(AppLocalizations.of(context)!.reviewAccept),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green[600],
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                elevation: 2,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      )
                    : SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(AppLocalizations.of(context)!.close),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: statusColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 후기 수락/거절 처리
  Future<void> _handleReviewResponse(String requestId, bool accept) async {
    try {
      final success = await _meetupService.respondToReviewRequest(
        requestId: requestId,
        accept: accept,
      );

      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              accept
                  ? AppLocalizations.of(context)!.reviewAccepted
                  : AppLocalizations.of(context)!.reviewRejected,
            ),
            backgroundColor: accept ? Colors.green : Colors.orange,
          ),
        );
        await _refreshMeetupData();
      } else if (mounted) {
        // 실패 시: 이미 응답했을 가능성이 높음
        print('⚠️ 후기 응답 실패 - 이미 응답했거나 권한 없음');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.reviewAlreadyResponded),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      print('❌ 후기 응답 처리 오류: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${AppLocalizations.of(context)!.error}: $e')),
        );
      }
    }
  }

  /// 모임 완료 확인 다이얼로그 (마감된 모임용)
  void _showCompleteMeetupDialog() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        elevation: 8,
        child: Container(
          padding: const EdgeInsets.all(24),
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 아이콘
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.blue.shade400, Colors.blue.shade600],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.blue.shade200.withOpacity(0.5),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.check_circle_outline,
                  size: 48,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 24),
              
              // 제목
              Text(
                AppLocalizations.of(context)!.meetupCompleteTitle,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              
              // 설명
              Text(
                AppLocalizations.of(context)!.meetupCompleteMessage,
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.grey[700],
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              
              // 버튼들
              Column(
                children: [
                  // 완료 처리 버튼 (주요 액션)
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: () async {
                        Navigator.pop(context);
                        await _markMeetupAsCompleted();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade600,
                        foregroundColor: Colors.white,
                        elevation: 2,
                        shadowColor: Colors.blue.shade300,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.check_circle, size: 22),
                          const SizedBox(width: 8),
                          Text(
                            AppLocalizations.of(context)!.markAsCompleted,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  // 모임 취소 버튼 (보조 액션)
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        _showCancelConfirmation();
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red.shade600,
                        side: BorderSide(color: Colors.red.shade400, width: 1.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.cancel_outlined, size: 22),
                          const SizedBox(width: 8),
                          Text(
                            AppLocalizations.of(context)!.cancelMeetup,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  // 닫기 버튼
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.grey[600],
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        AppLocalizations.of(context)!.close,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 모임 완료 처리
  Future<void> _markMeetupAsCompleted() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final success = await _meetupService.markMeetupAsCompleted(widget.meetupId);

      if (success && mounted) {
        setState(() {
          _currentMeetup = _currentMeetup.copyWith(isCompleted: true);
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.meetupMarkedCompleted)),
        );
      } else if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.meetupMarkCompleteFailed)),
        );
      }
    } catch (e) {
      print('❌ 모임 완료 처리 오류: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('오류가 발생했습니다')),
        );
      }
    }
  }

  /// 후기 작성 화면으로 이동
  Future<void> _navigateToCreateReview() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CreateMeetupReviewScreen(meetup: _currentMeetup),
      ),
    );

    if (result == true && mounted) {
      // 후기 작성 완료 후 모임 정보 새로고침
      await _refreshMeetupData();
    }
  }

  /// 후기 수정 화면으로 이동
  Future<void> _navigateToEditReview() async {
    if (_currentMeetup.reviewId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.reviewNotFound)),
      );
      return;
    }

    // 후기 정보 가져오기
    final reviewData = await _meetupService.getMeetupReview(_currentMeetup.reviewId!);
      if (reviewData == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.reviewLoadFailed)),
        );
      }
      return;
    }

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CreateMeetupReviewScreen(
          meetup: _currentMeetup,
          existingReviewId: _currentMeetup.reviewId!,
          existingImageUrl: reviewData['imageUrl'],
          existingContent: reviewData['content'],
        ),
      ),
    );

    if (result == true && mounted) {
      // 후기 수정 완료 후 모임 정보 새로고침
      await _refreshMeetupData();
    }
  }

  /// 후기 삭제 확인 다이얼로그
  void _showDeleteReviewConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.deleteReviewTitle),
        content: Text(AppLocalizations.of(context)!.deleteReviewConfirmMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _deleteReview();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: Text(AppLocalizations.of(context)!.delete),
          ),
        ],
      ),
    );
  }

  /// 후기 삭제
  Future<void> _deleteReview() async {
    if (_currentMeetup.reviewId == null) {
      print('⚠️ reviewId가 null입니다');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.reviewDeleteFailed),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      print('🗑️ UI: 후기 삭제 시작 - reviewId: ${_currentMeetup.reviewId}');
      
      final success = await _meetupService.deleteMeetupReview(_currentMeetup.reviewId!);

      print('✅ UI: 후기 삭제 결과 - success: $success');

      if (success && mounted) {
        setState(() {
          _currentMeetup = _currentMeetup.copyWith(
            hasReview: false,
            reviewId: null,
          );
          _isLoading = false;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.reviewDeleted),
            backgroundColor: Colors.green,
          ),
        );
        
        // 모임 데이터 새로고침
        await _refreshMeetupData();
      } else if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.reviewDeleteFailed),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      print('❌ UI: 후기 삭제 오류: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        
        // 에러 메시지를 더 명확하게 표시
        String errorMessage = AppLocalizations.of(context)!.error;
        if (e.toString().contains('로그인이 필요합니다')) {
          errorMessage = AppLocalizations.of(context)!.loginRequired;
        } else if (e.toString().contains('후기를 찾을 수 없습니다')) {
          errorMessage = AppLocalizations.of(context)!.reviewNotFound;
        } else if (e.toString().contains('작성자만')) {
          errorMessage = AppLocalizations.of(context)!.noPermission;
        } else {
          errorMessage = '${AppLocalizations.of(context)!.reviewDeleteFailed}: ${e.toString()}';
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
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
            Text(AppLocalizations.of(context)!.cancelMeetupConfirm),
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

  // 참여자 목록 섹션
  Widget _buildParticipantsSection() {
    print('🎨 _buildParticipantsSection 호출됨');
    print('   - _isLoadingParticipants: $_isLoadingParticipants');
    print('   - _participants.length: ${_participants.length}');
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
                Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.people, size: 20, color: Colors.blue[700]),
                  const SizedBox(width: 8),
                        Text(
                          Localizations.localeOf(context).languageCode == 'ko'
                              ? AppLocalizations.of(context)!.participantsCountLabel(_participants.length)
                              : 'Participants (${_participants.length})',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              if (_participants.length > 3)
                TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => MeetupParticipantsScreen(
                          meetup: _currentMeetup,
                        ),
                      ),
                    );
                  },
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    '모두 보기',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.blue[700],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _isLoadingParticipants
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20.0),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : _participants.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Column(
                          children: [
                            Text(
                              AppLocalizations.of(context)!.noParticipantsYet,
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '(디버그: 로딩=$_isLoadingParticipants, 수=${_participants.length})',
                              style: TextStyle(
                                color: Colors.red[300],
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : Column(
                      children: _participants
                          .take(3)
                          .map((participant) => _buildParticipantItem(participant))
                          .toList(),
                    ),
        ],
      ),
    );
  }

  // 참여자 아이템
  Widget _buildParticipantItem(MeetupParticipant participant) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          // 프로필 이미지
          CircleAvatar(
            radius: 20,
            backgroundColor: Colors.blue[100],
            backgroundImage: participant.userProfileImage != null &&
                    participant.userProfileImage!.isNotEmpty
                ? NetworkImage(participant.userProfileImage!)
                : null,
            child: participant.userProfileImage == null ||
                    participant.userProfileImage!.isEmpty
                ? Icon(Icons.person, color: Colors.blue[700], size: 24)
                : null,
          ),
          const SizedBox(width: 12),
          // 사용자 이름 + 국기
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildParticipantNameWithFlag(participant),
                if (participant.message != null && participant.message!.isNotEmpty)
                  Text(
                    participant.message!,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          // 승인 상태 표시 (주최자인 경우)
          if (_isHost)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: participant.getStatusColor().withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                participant.getStatusTextLocalized(Localizations.localeOf(context).languageCode),
                style: TextStyle(
                  fontSize: 11,
                  color: participant.getStatusColor(),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 참가자 이름 옆에 개인 국기 표시 (users/{uid}.nationality 활용)
  Widget _buildParticipantNameWithFlag(MeetupParticipant participant) {
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('users').doc(participant.userId).get(),
      builder: (context, snapshot) {
        String? nationality;
        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data() as Map<String, dynamic>?;
          nationality = data?['nationality'];
        }

        return Row(
          children: [
            Expanded(
              child: Text(
                participant.userName,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            if (nationality != null && nationality!.isNotEmpty)
              Text(
                CountryFlagHelper.getFlagEmoji(nationality!),
                style: const TextStyle(fontSize: 16),
              ),
          ],
        );
      },
    );
  }
}
