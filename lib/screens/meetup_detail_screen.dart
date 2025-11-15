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
import 'meetup_review_screen.dart';
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

class _MeetupDetailScreenState extends State<MeetupDetailScreen> with WidgetsBindingObserver {
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
    WidgetsBinding.instance.addObserver(this);
    _checkIfUserIsHost();
    _checkIfUserIsParticipant();
    _loadParticipants();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // 앱이 다시 활성화될 때 참여자 목록 새로고침
    if (state == AppLifecycleState.resumed && mounted) {
      _loadParticipants();
    }
  }

  /// 테스트를 위한 기본 국가 정보 반환
  String _getDefaultCountryForUser(String userName) {
    // 테스트용 기본 국가 매핑
    final defaultCountries = {
      '차재민': '한국',
      '남태평양는': '미국',
      'dev99': '한국',
    };
    
    return defaultCountries[userName] ?? '한국'; // 기본값은 한국
  }

  /// 국가명을 현재 언어로 변환
  String _getLocalizedCountryName(String countryName) {
    final languageCode = Localizations.localeOf(context).languageCode;
    final countryInfo = CountryFlagHelper.getCountryInfo(countryName);
    
    if (countryInfo != null) {
      return countryInfo.getLocalizedName(languageCode);
    }
    
    // CountryFlagHelper에 없는 경우 기존 매핑 사용
    if (languageCode != 'en') return countryName; // 한국어면 그대로 반환
    
    // 영어 변환 매핑 (fallback)
    final countryMap = {
      '한국': 'South Korea',
      '미국': 'United States',
      '일본': 'Japan',
      '중국': 'China',
      '우크라이나': AppLocalizations.of(context)!.ukraine,
      '독일': 'Germany',
      '프랑스': 'France',
      '영국': 'United Kingdom',
      '캐나다': 'Canada',
      '호주': 'Australia',
    };
    
    return countryMap[countryName] ?? countryName;
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

      // 각 참여자의 국가 정보를 사용자 프로필에서 가져와서 업데이트
      for (int i = 0; i < participants.length; i++) {
        final participant = participants[i];
        if (participant.userCountry == null || participant.userCountry!.isEmpty) {
          try {
            final userDoc = await FirebaseFirestore.instance
                .collection('users')
                .doc(participant.userId)
                .get();
            
            if (userDoc.exists) {
              final userData = userDoc.data()!;
              final userCountry = userData['nationality'] ?? userData['country'] ?? '';
              
              if (userCountry.isNotEmpty) {
                participants[i] = participant.copyWith(userCountry: userCountry);
                print('✅ ${participant.userName}의 국가 정보 업데이트: $userCountry');
              } else {
                // 테스트를 위한 기본 국가 정보 설정
                final defaultCountry = _getDefaultCountryForUser(participant.userName);
                if (defaultCountry.isNotEmpty) {
                  participants[i] = participant.copyWith(userCountry: defaultCountry);
                  print('🔧 ${participant.userName}의 기본 국가 정보 설정: $defaultCountry');
                }
              }
            }
          } catch (e) {
            print('❌ ${participant.userName}의 국가 정보 로드 실패: $e');
            // 오류 발생 시에도 기본 국가 정보 설정
            final defaultCountry = _getDefaultCountryForUser(participant.userName);
            if (defaultCountry.isNotEmpty) {
              participants[i] = participant.copyWith(userCountry: defaultCountry);
              print('🔧 ${participant.userName}의 기본 국가 정보 설정 (오류 후): $defaultCountry');
            }
          }
        } else {
          print('ℹ️ ${participant.userName}은 이미 국가 정보가 있음: ${participant.userCountry}');
        }
      }

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
        userCountry: _currentMeetup.hostNationality, // 호스트 국가 정보 추가
      );

      // 중복 방지 (이미 목록에 있으면 추가하지 않음)
      final hasHost = participants.any((p) => p.userId == hostId);
      final combined = [if (!hasHost) hostProfile, ...participants];
      print('✅ 승인된 참여자 ${participants.length}명 로드 완료 (호스트 포함 총 ${combined.length}명)');
      
      // 새로고침 시 setState로 UI 업데이트
      if (mounted) {
        setState(() {
          _participants = combined;
          _isLoadingParticipants = false;
          // 현재 사용자 승인 여부 동기화 (버튼 노출 조건 반영)
          final currentUid = FirebaseAuth.instance.currentUser?.uid;
          if (currentUid != null) {
            _isParticipant = combined.any((p) => p.userId == currentUid);
          }
          // 모임 데이터의 참여자 수 업데이트 (호스트 포함)
          _currentMeetup = _currentMeetup.copyWith(
            currentParticipants: combined.length, // 호스트 포함
          );
        });
        print('🎨 UI 업데이트 완료: ${_participants.length}명 (표시)');
        print('📊 모임 참여자 수 업데이트: ${combined.length}/${_currentMeetup.maxParticipants} (호스트 포함)');
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
          ).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context)!.meetupCancelledSuccessfully ?? '모임이 성공적으로 취소되었습니다')));
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
        ).showSnackBar(SnackBar(content: Text('${AppLocalizations.of(context)!.error ?? '오류'}: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Meetup?>(
      stream: _meetupService.getMeetupStream(widget.meetupId),
      builder: (context, snapshot) {
        // 스트림에서 데이터를 받으면 _currentMeetup 업데이트
        if (snapshot.hasData && snapshot.data != null) {
          _currentMeetup = snapshot.data!;
          // 호스트 및 참여자 상태 업데이트
          _checkIfUserIsHost();
          _checkIfUserIsParticipant();
        }

    final currentLang = Localizations.localeOf(context).languageCode;
    final status = _currentMeetup.getStatus(languageCode: currentLang);
    final isUpcoming = status == (AppLocalizations.of(context)!.scheduled ?? '예정됨');

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 상단 네비게이션 바 (헤더 없이)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.black),
                        onPressed: () => Navigator.pop(context),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                  _buildHeaderButtons(),
                ],
              ),
            ),

          // 내용
          Expanded(
            child: RefreshIndicator(
              color: const Color(0xFF5865F2),
              backgroundColor: Colors.white,
              onRefresh: () async {
                // 새로고침 시 로딩 표시와 함께 데이터 업데이트
                await Future.wait([
                  _refreshMeetupData(),
                  // 최소 지연 시간 추가로 로딩 표시가 보이도록 함
                  Future.delayed(const Duration(milliseconds: 500)),
                ]);
              },
              child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  children: [
                  const SizedBox(height: 20),
                  
                  // 제목 (매우 큰 굵은 폰트)
                  Text(
                    _currentMeetup.title,
                          style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF000000),
                      height: 1.2,
                      letterSpacing: -0.5,
                    ),
                  ),
                  
                  const SizedBox(height: 28),
                  
                  // 날짜/시간 정보
                  _buildSimpleInfoRow(
                    Icons.access_time,
                    currentLang == 'ko'
                        ? '${_currentMeetup.date.month}월 ${_currentMeetup.date.day}일 (${_currentMeetup.getFormattedDayOfWeek(languageCode: currentLang)}) ${_currentMeetup.time.isEmpty || _currentMeetup.time == '미정' ? '시간 미정' : _currentMeetup.time}'
                        : '${DateFormat('MMM d', 'en').format(_currentMeetup.date)} (${_currentMeetup.getFormattedDayOfWeek(languageCode: 'en')}) ${_currentMeetup.time.isEmpty || _currentMeetup.time == '미정' ? 'Time TBD' : _currentMeetup.time}',
                  ),
                  
                  const SizedBox(height: 20),
                  
                  // 장소 정보
                  _buildSimpleInfoRow(
                    Icons.location_on,
                    _currentMeetup.location,
                  ),
                  
                  const SizedBox(height: 28),
                  
                  // 주최자 정보 섹션
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(
                        AppLocalizations.of(context)!.host,
                    style: const TextStyle(
                          fontFamily: 'Pretendard',
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF64748B),
                        ),
                      ),
                      const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                            _currentMeetup.host,
                            style: const TextStyle(
                              fontFamily: 'Pretendard',
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                          // 주최자 국가 플래그 표시 (테두리 없이 큰 크기)
                          if (_currentMeetup.hostNationality.isNotEmpty) ...[
                            const SizedBox(width: 12),
                      Text(
                              CountryFlagHelper.getFlagEmoji(_currentMeetup.hostNationality),
                              style: const TextStyle(fontSize: 24),
                            ),
                          ],
                    ],
                  ),
                ],
                  ),
                  
                  const SizedBox(height: 20),
                  
                  // 구분선
                  Divider(
                    color: Color(0xFFE2E8F0),
                    thickness: 1,
                    height: 28,
                  ),
                  
                  // 모임 설명 섹션
                        Text(
                          AppLocalizations.of(context)!.meetupDetails,
                          style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                      letterSpacing: -0.3,
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // 모임 설명 내용
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
                                    content: Text('${AppLocalizations.of(context)!.error ?? "오류"}: URL을 열 수 없습니다'),
                                  ),
                                );
                              }
                            }
                          },
                          text: _currentMeetup.description,
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 16,
                      height: 1.6,
                      color: Color(0xFF334155),
                      fontWeight: FontWeight.w400,
                    ),
                          linkStyle: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 16,
                      color: Color(0xFF5865F2),
                            decoration: TextDecoration.underline,
                      fontWeight: FontWeight.w500,
                          ),
                          maxLines: 10,
                          overflow: TextOverflow.ellipsis,
                        ),
                  
                  const SizedBox(height: 20),
                  
                  // 구분선 (모임 설명과 참여자 정보 사이)
                  Divider(
                    color: Color(0xFFE2E8F0),
                    thickness: 1,
                    height: 28,
                  ),

                  // 참여자 목록
                  _buildParticipantsSection(),
                  
                  // 모임 이미지 (실제 첨부 이미지가 있는 경우에만 표시)
                  if (_currentMeetup.imageUrl.isNotEmpty || _currentMeetup.thumbnailImageUrl.isNotEmpty) ...[
                    const SizedBox(height: 32),
                    _buildMeetupImage(),
                  ],
                  
                  // 하단 여백
                  const SizedBox(height: 24),
                ],
                ),
              ),
            ),

            // 하단 버튼 (모임장 또는 참여자) - 새로운 디자인
            if (_isHost || _isParticipant) 
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                child: _isHost 
                    ? _buildNewHostActionButton() 
                    : (_currentMeetup.hasReview 
                        ? _buildNewParticipantActionButton()
                        : (_currentMeetup.isCompleted 
                            ? SizedBox(
                                width: double.infinity,
                                height: 56, // 다른 버튼들과 동일한 두께
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.grey[300], // 카드와 동일한 회색 톤
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Center(
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.check_circle, size: 20, color: Colors.grey[700]),
                                        const SizedBox(width: 8),
                                        Text(
                                          AppLocalizations.of(context)!.meetupConfirmed,
                                          style: TextStyle(
                                            fontFamily: 'Pretendard',
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.grey[700],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              )
                            : _buildLeaveButton())),
              ),
            // 참여하지 않은 사용자를 위한 참여 버튼
            if (!_isHost && !_isParticipant && !_currentMeetup.isFull() && !_currentMeetup.isCompleted && !_currentMeetup.isClosed)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                child: _buildJoinButton(),
              ),
          ],
        ),
      ),
    );
      },
    );
  }

  // 새로운 심플한 정보 행 위젯
  Widget _buildSimpleInfoRow(IconData icon, String content) {
    // URL인지 확인
    bool isUrl = Uri.tryParse(content) != null && 
                 (content.startsWith('http://') || content.startsWith('https://'));
    
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 20,
          color: Color(0xFF64748B),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: isUrl 
            ? GestureDetector(
                onTap: () async {
                  final uri = Uri.parse(content);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  } else {
                    // URL을 열 수 없는 경우 스낵바로 알림
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('링크를 열 수 없습니다: $content'),
                          backgroundColor: Colors.red[600],
                        ),
                      );
                    }
                  }
                },
                child: Text(
                  content,
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF5865F2), // 링크 색상 (WeFilling 블루)
                    height: 1.4,
                    decoration: TextDecoration.underline,
                  ),
                ),
              )
            : Text(
                content,
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF1E293B),
                  height: 1.4,
                ),
              ),
        ),
      ],
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
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF64748B), // 적절한 회색 (WCAG 준수)
                    letterSpacing: -0.1,
                  ),
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
                              content: Text('${AppLocalizations.of(context)!.error ?? "오류"}: URL을 열 수 없습니다'),
                            ),
                          );
                        }
                      }
                    },
                    text: content,
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 15,
                      height: 1.5,
                      color: Color(0xFF1E293B), // 진한 회색 (본문용)
                      fontWeight: FontWeight.w500,
                    ),
                    linkStyle: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 15,
                      color: Color(0xFF5865F2), // 위필링 시그니처 블루
                      decoration: TextDecoration.underline,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  )
                else
                  // URL이 없으면 일반 Text 사용
                  Row(
                    children: [
                      Expanded(
                        child:                         Text(
                          content,
                          style: const TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: 15,
                            height: 1.5,
                            color: Color(0xFF1E293B), // 진한 회색 (본문용)
                            fontWeight: FontWeight.w500,
                            letterSpacing: -0.1,
                          ),
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
    const double imageHeight = 250; // 상세화면에서는 더 큰 크기
    
    // 모임에서 표시할 이미지 URL 가져오기 (imageUrl 우선, 없으면 thumbnailImageUrl)
    String displayImageUrl = '';
    if (_currentMeetup.imageUrl.isNotEmpty) {
      displayImageUrl = _currentMeetup.imageUrl;
    } else if (_currentMeetup.thumbnailImageUrl.isNotEmpty) {
      displayImageUrl = _currentMeetup.thumbnailImageUrl;
    } else {
      displayImageUrl = _currentMeetup.getDisplayImageUrl(); // 기본 이미지
    }
    
    final bool isDefaultImage = _currentMeetup.imageUrl.isEmpty && _currentMeetup.thumbnailImageUrl.isEmpty;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 이미지 섹션 제목
        Text(
          AppLocalizations.of(context)!.meetupImage ?? '모임 이미지',
          style: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 12),
        
        // 이미지 컨테이너
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(
            maxHeight: 300, // 최대 높이 제한
          ),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Color(0xFFE2E8F0),
              width: 1,
            ),
          ),
      child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
        child: isDefaultImage
            ? _buildDefaultImage(displayImageUrl, imageHeight)
                : GestureDetector(
                    onTap: () {
                      // 이미지 뷰어로 이동 (전체 화면)
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => Scaffold(
                            backgroundColor: Colors.black,
                            body: SafeArea(
                              child: Stack(
                                children: [
                                  // 전체 화면 이미지
                                  Center(
                                    child: InteractiveViewer(
                                      minScale: 0.5,
                                      maxScale: 4.0,
                                      child: Image.network(
                                        displayImageUrl,
                                        fit: BoxFit.contain,
                                        width: double.infinity,
                                      ),
                                    ),
                                  ),
                                  // 닫기 버튼
                                  Positioned(
                                    top: 16,
                                    right: 16,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.black.withOpacity(0.5),
                                        shape: BoxShape.circle,
                                      ),
                                      child: IconButton(
                                        icon: const Icon(
                                          Icons.close,
                                          color: Colors.white,
                                          size: 28,
                                        ),
                                        onPressed: () => Navigator.pop(context),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                    child: Hero(
                      tag: 'meetup_image_${_currentMeetup.id}',
                      child: _buildNetworkImage(displayImageUrl, imageHeight),
                    ),
                  ),
          ),
        ),
      ],
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

    // 동기적으로 userId 비교 (FutureBuilder 불필요)
    final isMyMeetup = widget.meetup.userId == currentUser.uid;
    
    return _buildHeaderButtonsContent(currentUser, isMyMeetup);
  }


  /// 헤더 버튼 콘텐츠 빌드
  Widget _buildHeaderButtonsContent(User currentUser, bool isMyMeetup) {
    if (isMyMeetup) {
      // 본인 모임인 경우: 수정하기 아이콘 버튼 표시
      // 모임이 완료되었거나 후기가 작성된 경우에는 수정 불가
    final isCompleted = _currentMeetup.isCompleted;
    final hasReview = _currentMeetup.hasReview;
      final canEdit = !isCompleted && !hasReview;
      
      if (canEdit) {
        return IconButton(
          onPressed: () => _showEditMeetup(),
          icon: const Icon(
            Icons.edit_outlined,
            size: 24,
            color: Colors.black,
          ),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        );
      } else {
        // 수정할 수 없는 상태에서는 아무것도 표시하지 않음
        return const SizedBox.shrink();
      }
    } else if (currentUser != null) {
      // 다른 사용자 모임인 경우: 항상 신고/차단 케밥 메뉴 표시
      return PopupMenuButton<String>(
        icon: const Icon(
          Icons.more_vert, 
          size: 24,
          color: Colors.black,
        ),
        padding: EdgeInsets.zero,
        itemBuilder: (context) => [
              PopupMenuItem(
            value: 'report',
                child: Row(
                  children: [
                Icon(Icons.report_outlined, size: 18, color: Colors.red[600]),
                const SizedBox(width: 12),
                Text(
                  AppLocalizations.of(context)!.reportAction,
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                ),
              ),
            ],
                ),
              ),
              PopupMenuItem(
                value: 'block',
                child: Row(
                  children: [
                Icon(Icons.block, size: 18, color: Colors.red[600]),
                const SizedBox(width: 12),
                Text(
                  AppLocalizations.of(context)!.blockAction,
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                ),
              ),
            ],
            ),
          ),
        ],
        onSelected: (value) => _handleUserMenuAction(value),
      );
    }
    
    return const SizedBox.shrink();
  }

  /// 모임 주최자 메뉴 액션 처리
  void _handleOwnerMenuAction(String action) {
    switch (action) {
      case 'edit':
        _showEditMeetup();
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
      // 모임 정보 가져오기
      final doc = await FirebaseFirestore.instance
          .collection('meetups')
          .doc(widget.meetupId)
          .get();

      if (doc.exists && mounted) {
        final data = doc.data()!;
        data['id'] = doc.id;
        
        // 참여자 목록도 강제로 새로고침
        await _loadParticipants();
        
        // 모임 정보 업데이트
        setState(() {
          _currentMeetup = Meetup.fromJson(data);
          // 참여자 수 업데이트
          if (_participants.isNotEmpty) {
            _currentMeetup = _currentMeetup.copyWith(
              currentParticipants: _participants.length,
            );
          }
        });
        
        // 참여자 상태 확인
        await _checkIfUserIsParticipant();
        
        // 새로고침 알림(스낵바) 제거: 페이지 이탈 시 불필요한 알림 방지
      }
    } catch (e) {
      print('모임 데이터 새로고침 오류: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${AppLocalizations.of(context)!.error ?? "오류"}: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// 새로운 디자인의 모임장 액션 버튼
  Widget _buildNewHostActionButton() {
    final isFull = _currentMeetup.isFull();
    final isCompleted = _currentMeetup.isCompleted;
    final hasReview = _currentMeetup.hasReview;
    final isClosed = _currentMeetup.isClosed;

    // 1. 모집 마감되지 않은 경우 → 모임 취소 버튼 표시
    if (!isCompleted && !isClosed) {
      return SizedBox(
        width: double.infinity,
        height: 56,
        child: ElevatedButton(
          onPressed: _isLoading ? null : () {
            if (isFull) {
              _showCompleteMeetupDialog();
            } else {
              _showCancelConfirmation();
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Color(0xFFEF4444), // 빨간색
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
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
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.cancel_outlined, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      isFull
                          ? (AppLocalizations.of(context)!.completeOrCancelMeetup ?? "") 
                          : AppLocalizations.of(context)!.cancelMeetup,
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
        ),
      );
    }

    // 2. 모집 마감되었지만 완료되지 않은 경우 → 모임 확정 버튼 표시
    if (isClosed && !isCompleted) {
      return SizedBox(
        width: double.infinity,
        height: 56,
        child: ElevatedButton(
          onPressed: _isLoading ? null : () => _showCompleteMeetupDialog(),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF10B981), // 녹색
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
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
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      AppLocalizations.of(context)!.completeMeetup ?? '모임 확정',
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
        ),
      );
    }

    // 3. 모임 완료 & 후기 없음 → 모임 후기 쓰기 버튼
    if (!hasReview) {
      return SizedBox(
        width: double.infinity,
        height: 56,
        child: ElevatedButton(
          onPressed: _isLoading ? null : () => _navigateToCreateReview(),
          style: ElevatedButton.styleFrom(
            backgroundColor: Color(0xFF5865F2), // 위필링 시그니처 블루
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
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
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.rate_review_outlined, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      AppLocalizations.of(context)!.writeMeetupReview,
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
        ),
      );
    }

    // 3. 모임 완료 & 후기 있음 → 후기 수정 버튼
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: _isLoading ? null : () => _navigateToEditReview(),
        style: ElevatedButton.styleFrom(
          backgroundColor: Color(0xFF5865F2),
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.edit_outlined, size: 20),
            const SizedBox(width: 8),
            Text(
              AppLocalizations.of(context)!.editReview,
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 새로운 디자인의 참여자 액션 버튼
  Widget _buildNewParticipantActionButton() {
    // 사용자가 이미 후기를 확인했는지 체크
    final user = FirebaseAuth.instance.currentUser;
    final hasAccepted = user != null ? _currentMeetup.hasUserAcceptedReview(user.uid) : false;
    
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: (_isLoading || hasAccepted) ? null : () => _navigateToReviewScreen(),
        style: ElevatedButton.styleFrom(
          backgroundColor: hasAccepted ? Colors.grey[300] : const Color(0xFF22C55E), // 더 선명한 녹색
          foregroundColor: hasAccepted ? Colors.grey[600] : Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              hasAccepted ? Icons.check_circle : Icons.rate_review, 
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              hasAccepted 
                  ? AppLocalizations.of(context)!.reviewChecked
                  : AppLocalizations.of(context)!.checkReview,
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 참여하기 버튼
  Widget _buildJoinButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: _isLoading ? null : () => _joinMeetup(),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF5865F2), // 위필링 시그니처 블루
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
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
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.group_add, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    AppLocalizations.of(context)!.joinMeetup,
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  /// 나가기 버튼
  Widget _buildLeaveButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: _isLoading ? null : () => _leaveMeetup(),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFEF4444), // 빨간색
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
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
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.exit_to_app, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    AppLocalizations.of(context)!.leaveMeetup ?? '나가기',
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  /// 모임 참여하기
  Future<void> _joinMeetup() async {
    // 즉시 로컬 상태 업데이트 (깜빡임 방지)
    if (mounted) {
      setState(() {
        _isLoading = true;
        _isParticipant = true;
        _currentMeetup = _currentMeetup.copyWith(
          currentParticipants: _currentMeetup.currentParticipants + 1,
        );
      });
    }

    try {
      final success = await _meetupService.joinMeetup(widget.meetupId);

      if (success) {
        // 백그라운드에서 참여자 목록 새로고침
        Future.microtask(() async {
          await _loadParticipants();
          _checkIfUserIsParticipant();
        });

        if (mounted) {
          setState(() {
            _isLoading = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.meetupJoined ?? '모임에 참여했습니다'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } else {
        // 실패 시 상태 롤백
        if (mounted) {
          setState(() {
            _isParticipant = false;
            _currentMeetup = _currentMeetup.copyWith(
              currentParticipants: _currentMeetup.currentParticipants > 0 
                  ? _currentMeetup.currentParticipants - 1 
                  : 0,
            );
            _isLoading = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.meetupJoinFailed ?? '모임 참여에 실패했습니다'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      print('모임 참여 오류: $e');
      // 오류 시 상태 롤백
      if (mounted) {
        setState(() {
          _isParticipant = false;
          _currentMeetup = _currentMeetup.copyWith(
            currentParticipants: _currentMeetup.currentParticipants > 0 
                ? _currentMeetup.currentParticipants - 1 
                : 0,
          );
          _isLoading = false;
        });
        
        String errorMessage = '모임 참여에 실패했습니다';
        if (e.toString().contains('permission-denied')) {
          errorMessage = '권한이 없습니다. 다시 시도해주세요';
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  /// 모임 나가기
  Future<void> _leaveMeetup() async {
    // 즉시 로컬 상태 업데이트 (깜빡임 방지)
    if (mounted) {
      setState(() {
        _isLoading = true;
        _isParticipant = false;
        _currentMeetup = _currentMeetup.copyWith(
          currentParticipants: _currentMeetup.currentParticipants > 0 
              ? _currentMeetup.currentParticipants - 1 
              : 0,
        );
      });
    }

    try {
      final success = await _meetupService.cancelMeetupParticipation(widget.meetupId);

      if (success) {
        // 백그라운드에서 참여자 목록 새로고침
        Future.microtask(() async {
          await _loadParticipants();
          _checkIfUserIsParticipant();
        });

        if (mounted) {
          setState(() {
            _isLoading = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.leaveMeetup ?? '모임에서 나갔습니다'),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } else {
        // 실패 시 상태 롤백
        if (mounted) {
          setState(() {
            _isParticipant = true;
            _currentMeetup = _currentMeetup.copyWith(
              currentParticipants: _currentMeetup.currentParticipants + 1,
            );
            _isLoading = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.leaveMeetupFailed ?? '모임 나가기에 실패했습니다'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      print('모임 나가기 오류: $e');
      // 오류 시 상태 롤백
      if (mounted) {
        setState(() {
          _isParticipant = true;
          _currentMeetup = _currentMeetup.copyWith(
            currentParticipants: _currentMeetup.currentParticipants + 1,
          );
          _isLoading = false;
        });
        
        String errorMessage = '모임 나가기에 실패했습니다';
        if (e.toString().contains('permission-denied')) {
          errorMessage = '권한이 없습니다. 다시 시도해주세요';
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
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
                ? (AppLocalizations.of(context)!.completeOrCancelMeetup ?? "") : AppLocalizations.of(context)!.cancelMeetup),
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
            : Text(AppLocalizations.of(context)!.writeMeetupReview ?? ""),
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
        child: Text(AppLocalizations.of(context)!.editReview ?? ""),
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
          : Text(AppLocalizations.of(context)!.viewAndRespondToReview ?? ""),
    );
  }

  /// 후기 확인 다이얼로그 표시 (review_requests 기반)
  Future<void> _navigateToReviewApproval() async {
    if (_currentMeetup.reviewId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.reviewNotFound ?? "")),
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
                SnackBar(content: Text(AppLocalizations.of(context)!.reviewLoadFailed ?? "")),
              );
            }
            return;
          }
        } else {
          print('❌ reviewId가 없음');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(AppLocalizations.of(context)!.reviewNotFound ?? "")),
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
          SnackBar(content: Text('${AppLocalizations.of(context)!.error ?? "오류"}: $e')),
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
        ? (AppLocalizations.of(context)!.reviewAccepted ?? "") : currentStatus == 'rejected'
            ? (AppLocalizations.of(context)!.reviewRejected ?? "") : '';
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
                          content.isEmpty ? (AppLocalizations.of(context)!.noContent ?? "") : content,
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
                              label: Text(AppLocalizations.of(context)!.reviewReject ?? ""),
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
                              label: Text(AppLocalizations.of(context)!.reviewAccept ?? ""),
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
                          child: Text(AppLocalizations.of(context)!.close ?? ""),
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
                  ? (AppLocalizations.of(context)!.reviewAccepted ?? "") : AppLocalizations.of(context)!.reviewRejected,
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
            content: Text(AppLocalizations.of(context)!.reviewAlreadyResponded ?? ""),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      print('❌ 후기 응답 처리 오류: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${AppLocalizations.of(context)!.error ?? "오류"}: $e')),
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
        // 성공 시 데이터 새로고침
        await _refreshMeetupData();
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.meetupMarkedCompleted ?? "모임이 완료되었습니다"),
            backgroundColor: Colors.green,
          ),
        );
        print('✅ [MeetupDetailScreen] 모임 완료 처리 성공: ${widget.meetupId}');
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.meetupMarkCompleteFailed ?? "모임 완료 처리에 실패했습니다"),
            backgroundColor: Colors.red,
          ),
        );
        print('❌ [MeetupDetailScreen] 모임 완료 처리 실패: ${widget.meetupId}');
      }
    } catch (e) {
      print('❌ 모임 완료 처리 오류: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('모임 완료 처리 중 오류가 발생했습니다: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      // 로딩 상태 해제
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
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
        SnackBar(content: Text(AppLocalizations.of(context)!.reviewNotFound ?? "")),
      );
      return;
    }

    // 후기 정보 가져오기
    final reviewData = await _meetupService.getMeetupReview(_currentMeetup.reviewId!);
      if (reviewData == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.reviewLoadFailed ?? "")),
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
        title: Text(AppLocalizations.of(context)!.deleteReviewTitle ?? ""),
        content: Text(AppLocalizations.of(context)!.deleteReviewConfirmMessage ?? ""),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppLocalizations.of(context)!.cancel ?? ""),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _deleteReview();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: Text(AppLocalizations.of(context)!.delete ?? ""),
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
            content: Text(AppLocalizations.of(context)!.reviewDeleteFailed ?? ""),
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
            content: Text(AppLocalizations.of(context)!.reviewDeleted ?? ""),
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
            content: Text(AppLocalizations.of(context)!.reviewDeleteFailed ?? ""),
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
        String errorMessage = AppLocalizations.of(context)!.error ?? "오류";
        if (e.toString().contains('로그인이 필요합니다')) {
          errorMessage = AppLocalizations.of(context)!.loginRequired ?? "";
        } else if (e.toString().contains('후기를 찾을 수 없습니다')) {
          errorMessage = AppLocalizations.of(context)!.reviewNotFound ?? "";
        } else if (e.toString().contains('작성자만')) {
          errorMessage = AppLocalizations.of(context)!.noPermission ?? "";
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

  // 참여자 목록 섹션 (새로운 디자인)
  Widget _buildParticipantsSection() {
    return StreamBuilder<List<MeetupParticipant>>(
      stream: _meetupService.getParticipantsStream(widget.meetupId),
      builder: (context, snapshot) {
        List<MeetupParticipant> participants = [];
        bool isLoading = !snapshot.hasData;
        
        if (snapshot.hasData) {
          participants = snapshot.data!;
          
          // 호스트를 참여자 목록 맨 앞에 포함
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
            userCountry: _currentMeetup.hostNationality,
          );
          
          // 중복 방지 (이미 목록에 있으면 추가하지 않음)
          final hasHost = participants.any((p) => p.userId == hostId);
          final combined = [if (!hasHost) hostProfile, ...participants];
          participants = combined;
          
          // 로컬 상태 동기화
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _participants.length != participants.length) {
              setState(() {
                _participants = participants;
                _isLoadingParticipants = false;
                
                // 참여자 상태 업데이트
                final currentUser = FirebaseAuth.instance.currentUser;
                if (currentUser != null) {
                  _isParticipant = participants.any((p) => p.userId == currentUser.uid);
                }
                
                // 모임 데이터의 참여자 수도 실시간으로 업데이트
                _currentMeetup = _currentMeetup.copyWith(
                  currentParticipants: participants.length,
                );
              });
            }
          });
        } else if (snapshot.hasError) {
          print('❌ 참여자 스트림 오류: ${snapshot.error}');
        }
        
        // 표시할 참여자 결정
        final displayParticipants = participants.isNotEmpty ? participants : _participants;
        final displayCount = displayParticipants.length;
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
        // 참여자 섹션 제목 (전체 참가자 수 포함)
                Row(
            children: [
                        Text(
                          '${AppLocalizations.of(context)!.participants} ($displayCount)',
                    style: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0F172A),
                letterSpacing: -0.3,
              ),
            ),
            const Spacer(),
            Row(
              children: [
                Icon(
                  Icons.people,
                  size: 20,
                  color: Color(0xFF64748B),
                ),
                const SizedBox(width: 4),
                Text(
                  isLoading && _participants.isEmpty
                    ? '${_currentMeetup.currentParticipants}/${_currentMeetup.maxParticipants} ${AppLocalizations.of(context)!.peopleUnit}'
                    : '$displayCount/${_currentMeetup.maxParticipants} ${AppLocalizations.of(context)!.peopleUnit}',
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1E293B),
                    ),
                  ),
                ],
              ),
          ],
        ),
        
        const SizedBox(height: 16),
        
        // 참여자 목록 또는 로딩/빈 상태
        isLoading && _participants.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(20.0),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : displayParticipants.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Text(
                        AppLocalizations.of(context)!.noParticipantsYet,
                        style: const TextStyle(
                          fontFamily: 'Pretendard',
                          color: Color(0xFF64748B),
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  )
                : Column(
                    children: [
                      // 참여자 목록 (최대 3명)
                      ...(displayParticipants.take(3).map((participant) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: _buildSimpleParticipantItem(participant),
                        );
                      }).toList()),
                      
                      // "모두 보기" 버튼 (3명 초과시)
              if (displayParticipants.length > 3)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: TextButton(
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
                  child: Text(
                    '모두 보기',
                    style: TextStyle(
                                fontFamily: 'Pretendard',
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF5865F2),
                              ),
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
      },
    );
  }

  // 새로운 심플한 참여자 아이템
  Widget _buildSimpleParticipantItem(MeetupParticipant participant) {
    return Row(
      children: [
        // 프로필 이미지
        CircleAvatar(
          radius: 20,
          backgroundColor: Colors.grey[200],
          backgroundImage: participant.userProfileImage != null &&
                  participant.userProfileImage!.isNotEmpty
              ? NetworkImage(participant.userProfileImage!)
              : null,
          child: participant.userProfileImage == null ||
                  participant.userProfileImage!.isEmpty
              ? Icon(Icons.person, color: Color(0xFF5865F2), size: 20)
              : null,
        ),
        const SizedBox(width: 12),
        
        // 이름과 상태
        Expanded(
                        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                          children: [
                            Text(
                    participant.userName,
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                  const Spacer(), // 이름과 국가 정보 사이 공간
                  // 참여자 국가 정보 (오른쪽 정렬, 국가명 + 국기 순서)
                  if (participant.userCountry != null && participant.userCountry!.isNotEmpty) ...[
                            Text(
                      _getLocalizedCountryName(participant.userCountry!),
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF475569),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      CountryFlagHelper.getFlagEmoji(participant.userCountry!),
                      style: const TextStyle(fontSize: 20),
                    ),
                  ],
                ],
              ),
              if (participant.message != null && participant.message!.isNotEmpty)
                Text(
                  participant.message!,
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 13,
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w400,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                    ),
        ],
      ),
        ),
      ],
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
                ? Icon(Icons.person, color: Color(0xFF5865F2), size: 24)
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
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 13,
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w400,
                      height: 1.4,
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
                  fontFamily: 'Pretendard',
                  fontSize: 12,
                  color: participant.getStatusColor(),
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.1,
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
                  fontFamily: 'Pretendard',
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1E293B), // 진한 회색
                  letterSpacing: -0.1,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            if (nationality != null && nationality!.isNotEmpty)
              Text(
                CountryFlagHelper.getFlagEmoji(nationality!),
                style: const TextStyle(fontSize: 22), // 국기 가독성 향상
              ),
          ],
        );
      },
    );
  }

  /// 후기 확인 화면으로 이동
  Future<void> _navigateToReviewScreen() async {
    try {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => MeetupReviewScreen(
            meetupId: _currentMeetup.id,
            reviewId: _currentMeetup.reviewId,
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

  /// 모임 취소 확인 다이얼로그
  void _showCancelConfirmation() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_outlined, color: Colors.red[600]),
            const SizedBox(width: 8),
            Text(AppLocalizations.of(context)!.cancelMeetup),
          ],
        ),
        content: Text(
          Localizations.localeOf(context).languageCode == 'ko'
              ? '정말로 모임을 취소하시겠습니까? 취소된 모임은 복구할 수 없습니다.'
              : 'Are you sure you want to cancel this meetup? Cancelled meetups cannot be restored.',
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
              _cancelMeetup();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red[600],
              foregroundColor: Colors.white,
            ),
            child: Text(AppLocalizations.of(context)!.cancelMeetup),
          ),
        ],
      ),
    );
  }

  /// 모집 마감 처리 (낙관적 업데이트)
  Future<void> _closeMeetup() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // 서버 요청
      final meetupService = MeetupService();
      final success = await meetupService.closeMeetup(_currentMeetup.id);

      if (success) {
        // 성공 시 데이터 새로고침
        await _refreshMeetupData();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.closeMeetupSuccess),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        }
        print('✅ [MeetupDetailScreen] 모집 마감 성공: ${_currentMeetup.id}');
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.closeMeetupFailed),
              backgroundColor: Colors.red,
            ),
          );
        }
        print('❌ [MeetupDetailScreen] 모집 마감 실패: ${_currentMeetup.id}');
      }
    } catch (e) {
      print('❌ [MeetupDetailScreen] 모집 마감 오류: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('모집 마감 중 오류가 발생했습니다: $e'),
            backgroundColor: Colors.red,
          ),
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
}
