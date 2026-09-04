// lib/screens/search_result_page.dart
// 검색 결과 페이지 - 모임게시판/정보게시판 타입별 다른 스타일 적용

import 'package:flutter/material.dart';
import 'dart:async';
import '../models/post.dart';
import '../models/meetup.dart';
import '../services/post_service.dart';
import '../services/meetup_service.dart';
import '../ui/widgets/app_icon_button.dart';
import 'meetup_detail_screen.dart';
import 'post_detail_screen.dart';
import '../l10n/app_localizations.dart';
import '../utils/logger.dart';
import '../services/user_info_cache_service.dart';
import '../utils/latest_request_guard.dart';
import '../ui/widgets/empty_state.dart';
import '../ui/widgets/hanyang_verification_gate.dart';

class SearchResultPage extends StatefulWidget {
  final String boardType; // 'meeting' 또는 'info'
  final String? initialQuery;

  const SearchResultPage({
    Key? key,
    required this.boardType,
    this.initialQuery,
  }) : super(key: key);

  @override
  State<SearchResultPage> createState() => _SearchResultPageState();
}

class _SearchResultPageState extends State<SearchResultPage> {
  final TextEditingController _searchController = TextEditingController();
  final PostService _postService = PostService();
  final MeetupService _meetupService = MeetupService();

  Timer? _debounceTimer;
  List<dynamic> _searchResults = [];
  bool _isLoading = false;
  bool _hasSearched = false;
  Object? _searchError;
  final LatestRequestGuard _searchRequestGuard = LatestRequestGuard();

  @override
  void initState() {
    super.initState();
    final initialQuery = widget.initialQuery?.trim() ?? '';
    if (initialQuery.isNotEmpty) {
      _searchController.text = initialQuery;
      _performSearch(initialQuery);
    }
  }

  @override
  void dispose() {
    _searchRequestGuard.invalidate();
    _searchController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    _searchRequestGuard.invalidate();
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) {
      setState(() {
        _searchResults.clear();
        _isLoading = false;
        _hasSearched = false;
        _searchError = null;
      });
      return;
    }

    // 디바운스 중 이전 검색어의 결과가 현재 입력의 결과처럼 보이지 않게
    // 즉시 로딩 상태로 전환한다.
    setState(() {
      _searchResults.clear();
      _isLoading = true;
      _hasSearched = true;
      _searchError = null;
    });
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      _performSearch(normalizedQuery);
    });
  }

  Future<void> _performSearch(String query) async {
    final normalizedQuery = query.trim();
    if (!mounted || normalizedQuery.isEmpty) return;
    final requestToken = _searchRequestGuard.begin();
    if (Logger.isVerboseEnabled) {
      Logger.log('🔍 검색 시작: "$query", 타입: ${widget.boardType}');
    }
    setState(() {
      _isLoading = true;
      _hasSearched = true;
      _searchError = null;
    });

    try {
      if (widget.boardType == 'meeting') {
        // 모임 검색
        if (Logger.isVerboseEnabled) Logger.log('🔍 모임 검색 실행...');
        final meetups =
            await _meetupService.searchMeetupsAsync(normalizedQuery);
        if (!mounted || !_searchRequestGuard.isCurrent(requestToken)) return;
        if (Logger.isVerboseEnabled) {
          Logger.log('🔍 모임 검색 결과: ${meetups.length}개');
        }
        setState(() {
          _searchResults = meetups;
          _isLoading = false;
        });
      } else {
        // 정보게시판 검색 - 카테고리 필터 제거하고 전체 검색
        if (Logger.isVerboseEnabled) Logger.log('🔍 게시글 검색 실행...');
        final posts =
            await _postService.searchPosts(normalizedQuery); // category 파라미터 제거
        if (!mounted || !_searchRequestGuard.isCurrent(requestToken)) return;
        if (Logger.isVerboseEnabled) {
          Logger.log('🔍 게시글 검색 결과: ${posts.length}개');
        }
        setState(() {
          _searchResults = posts;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted || !_searchRequestGuard.isCurrent(requestToken)) return;
      setState(() {
        _searchResults.clear();
        _isLoading = false;
        _searchError = e;
      });
      Logger.error('🔍 검색 오류: $e');
    }
  }

  String _pageTitle(BuildContext context) {
    return widget.boardType == 'meeting'
        ? AppLocalizations.of(context)!.activityBoard
        : AppLocalizations.of(context)!.infoBoard;
  }

  String _searchHint(BuildContext context) {
    return AppLocalizations.of(context)!.enterSearchQuery;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        shadowColor: Colors.black12,
        leading: AppIconButton(
          icon: Icons.arrow_back,
          onPressed: () => Navigator.pop(context),
          semanticLabel: '뒤로가기',
        ),
        title: Text(
          _pageTitle(context),
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
      ),
      body: Column(
        children: [
          // 검색창
          Container(
            padding: const EdgeInsets.all(16),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF5F6F8),
                borderRadius: BorderRadius.circular(22),
              ),
              child: TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                onSubmitted: (query) {
                  _debounceTimer?.cancel();
                  _searchRequestGuard.invalidate();
                  _performSearch(query);
                },
                textInputAction: TextInputAction.search,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: _searchHint(context),
                  hintStyle: const TextStyle(
                    color: Colors.black54,
                    fontSize: 14,
                  ),
                  prefixIcon: const Icon(
                    Icons.search,
                    color: Colors.black54,
                    size: 20,
                  ),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? GestureDetector(
                          onTap: () {
                            _debounceTimer?.cancel();
                            _searchRequestGuard.invalidate();
                            _searchController.clear();
                            setState(() {
                              _searchResults.clear();
                              _isLoading = false;
                              _hasSearched = false;
                              _searchError = null;
                            });
                          },
                          child: const Icon(
                            Icons.clear,
                            color: Colors.black54,
                            size: 18,
                          ),
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                style: const TextStyle(fontSize: 14),
              ),
            ),
          ),

          // 검색 결과
          Expanded(
            child: _buildSearchResults(),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResults() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
        ),
      );
    }

    if (!_hasSearched) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search,
              size: 64,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              AppLocalizations.of(context)!.pleaseEnterSearchQuery,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      );
    }

    if (_searchError != null) {
      final l10n = AppLocalizations.of(context)!;
      return AppErrorState(
        title: l10n.error,
        description: l10n.errorOccurred,
        retryText: l10n.retryAction,
        onRetry: () {
          final query = _searchController.text.trim();
          if (query.isNotEmpty) _performSearch(query);
        },
      );
    }

    if (_searchResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 64,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              AppLocalizations.of(context)!.noSearchResults,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      );
    }

    if (widget.boardType == 'meeting') {
      return _buildMeetingResults();
    } else {
      return _buildInfoResults();
    }
  }

  // 모임게시판 결과 (카드 스타일)
  Widget _buildMeetingResults() {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _searchResults.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final meetup = _searchResults[index] as Meetup;
        final hostName = (meetup.hostNickname ?? '').trim().isNotEmpty
            ? meetup.hostNickname!.trim()
            : meetup.host;
        final isHanyangLocked = HanyangVerificationGate.isLockedForCurrentUser(
          context,
          meetup.requiresHanyangVerification,
        );
        return HanyangVerificationGate(
          locked: isHanyangLocked,
          compact: true,
          child: InkWell(
            onTap: isHanyangLocked ? null : () => _showMeetupDetail(meetup),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFE9F1FF),
                borderRadius: BorderRadius.circular(16),
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 상단: 제목 + 오늘 예정 라벨
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          meetup.title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.blue,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          meetup.getFormattedDate(context),
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),

                  // 호스트 닉네임
                  Text(
                    '${AppLocalizations.of(context)!.host}: $hostName',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.black.withValues(alpha: 0.7),
                      fontWeight: FontWeight.w500, // 폰트 굵기 추가
                    ),
                  ),
                  const SizedBox(height: 8),

                  // 본문
                  Text(
                    meetup.description,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.black.withValues(alpha: 0.6),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 12),

                  // 하단: 위치 + 참여 현황
                  Row(
                    children: [
                      Icon(
                        Icons.location_on,
                        size: 14,
                        color: Colors.red.shade400,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          meetup.location,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.black.withValues(alpha: 0.6),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Icon(
                        Icons.people,
                        size: 16,
                        color: Colors.blue.shade700,
                      ),
                      const SizedBox(width: 4),
                      FutureBuilder<int>(
                        future: _meetupService
                            .getRealTimeParticipantCount(meetup.id),
                        builder: (context, snapshot) {
                          final participantCount =
                              snapshot.data ?? meetup.currentParticipants;
                          return Text(
                            '$participantCount/${meetup.maxParticipants}',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.blue.shade700,
                              fontWeight: FontWeight.w600,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // 모임 상세 화면으로 이동
  void _showMeetupDetail(Meetup meetup) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MeetupDetailScreen(
          meetup: meetup,
          meetupId: meetup.id,
          onMeetupDeleted: () {
            // 모임이 삭제되면 검색 결과 새로고침
            final query = _searchController.text.trim();
            if (query.isNotEmpty) {
              _performSearch(query);
            }
          },
        ),
      ),
    );
  }

  // 정보게시판 결과 (단일 라인)
  Widget _buildInfoResults() {
    return ListView.separated(
      itemCount: _searchResults.length,
      separatorBuilder: (context, index) => Divider(
        height: 1,
        color: Colors.grey.shade200,
      ),
      itemBuilder: (context, index) {
        final post = _searchResults[index] as Post;
        final isHanyangLocked = HanyangVerificationGate.isLockedForCurrentUser(
          context,
          post.requiresHanyangVerification,
        );
        return HanyangVerificationGate(
          locked: isHanyangLocked,
          compact: true,
          child: InkWell(
            onTap: isHanyangLocked ? null : () => _showPostDetail(post),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 좌측: 하트/댓글 아이콘
                  Column(
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.favorite_border,
                            size: 16,
                            color: Colors.red.shade400,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            '${post.likes}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.red.shade400,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.chat_bubble_outline,
                            size: 16,
                            color: Colors.blue.shade400,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            '${post.commentCount}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.blue.shade400,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(width: 12),

                  // 중앙: 내용
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 닉네임 + 시간
                        Row(
                          children: [
                            _buildPostAuthor(post),
                            const SizedBox(width: 8),
                            Text(
                              post.getFormattedTime(context),
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.black.withValues(alpha: 0.87),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),

                        // 제목/본문 구분이 없는 포스트의 단일 본문
                        Text(
                          post.displayText,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.black,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPostAuthor(Post post) {
    final style = TextStyle(
      fontSize: 13,
      color: Colors.black.withValues(alpha: 0.87),
      fontWeight: FontWeight.w500,
    );
    final l10n = AppLocalizations.of(context)!;
    if (post.isAnonymous) return Text(l10n.anonymous, style: style);
    if (post.userId.isEmpty || post.userId == 'deleted') {
      return Text(l10n.deletedAccount, style: style);
    }

    final cache = UserInfoCacheService();
    return StreamBuilder<DMUserInfo?>(
      stream: cache.watchUserInfo(post.userId),
      initialData: cache.getCachedUserInfo(post.userId),
      builder: (context, snapshot) {
        final latest = snapshot.data;
        final name = latest?.isDeletedAccount == true
            ? l10n.deletedAccount
            : ((latest?.nickname ?? '').trim().isNotEmpty
                ? latest!.nickname
                : post.author);
        return Text(name, style: style);
      },
    );
  }

  // 게시글 상세 화면으로 이동
  void _showPostDetail(Post post) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PostDetailScreen(post: post),
      ),
    );
  }
}
