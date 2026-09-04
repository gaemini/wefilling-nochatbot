// lib/screens/meetup_search_screen.dart
// 게시글 검색 화면 (기존 모임 검색에서 게시글 검색으로 변경)

import 'package:flutter/material.dart';
import 'dart:async';
import '../models/post.dart';
import '../services/post_service.dart';
import '../widgets/post_search_card.dart';
import '../l10n/app_localizations.dart';
import '../utils/logger.dart';
import '../utils/latest_request_guard.dart';
import '../ui/widgets/empty_state.dart';
import 'package:flutter/foundation.dart';

class MeetupSearchScreen extends StatefulWidget {
  const MeetupSearchScreen({Key? key}) : super(key: key);

  @override
  State<MeetupSearchScreen> createState() => _MeetupSearchScreenState();
}

class _MeetupSearchScreenState extends State<MeetupSearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final PostService _postService = PostService();
  String _searchQuery = '';
  bool _isLoading = false;
  bool _hasSearchError = false;
  List<Post> _searchResults = [];
  final LatestRequestGuard _searchRequestGuard = LatestRequestGuard();

  // 포커스 노드
  final FocusNode _searchFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    // 화면이 로드되면 검색 필드에 포커스
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchRequestGuard.invalidate();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  // 검색 실행
  Future<void> _performSearch() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      _searchRequestGuard.invalidate();
      setState(() {
        _searchResults = [];
        _isLoading = false;
        _hasSearchError = false;
        _searchQuery = '';
      });
      return;
    }

    final requestToken = _searchRequestGuard.begin();
    _searchQuery = query;
    if (Logger.isVerboseEnabled) Logger.log('🔍 게시글 검색 시작: "$_searchQuery"');

    setState(() {
      _isLoading = true;
      _hasSearchError = false;
      _searchResults = []; // 이전 결과 초기화
    });

    try {
      if (Logger.isVerboseEnabled) Logger.log('📡 검색 시작');

      // 게시글 서비스를 통해 검색 실행
      final searchResults = await _postService.searchPosts(_searchQuery.trim());

      if (Logger.isVerboseEnabled) {
        Logger.log('✅ 검색 결과 수신: ${searchResults.length}개');
      }
      if (mounted && _searchRequestGuard.isCurrent(requestToken)) {
        setState(() {
          _searchResults = searchResults;
          _isLoading = false;
        });
        // 디버그 모드에서 데이터 확인
        _checkPostData();
      }
    } catch (e) {
      Logger.error('❌ 검색 오류: $e');
      if (mounted && _searchRequestGuard.isCurrent(requestToken)) {
        setState(() {
          _isLoading = false;
          _hasSearchError = true;
          _searchResults = [];
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.errorOccurred),
          ),
        );
      }
    }
  }

  // 디버그용 데이터 확인
  void _checkPostData() {
    if (!kDebugMode) return;

    for (final post in _searchResults) {
      if (Logger.isVerboseEnabled) Logger.log('🔍 게시글 데이터 확인: ${post.title}');
      if (Logger.isVerboseEnabled) Logger.log('   - ID: ${post.id}');
      if (Logger.isVerboseEnabled) Logger.log('   - 좋아요: ${post.likes}');
      if (Logger.isVerboseEnabled) Logger.log('   - 댓글수: ${post.commentCount}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          Localizations.localeOf(context).languageCode == 'ko'
              ? '포스트 검색'
              : 'Search posts',
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
      ),
      backgroundColor: Colors.grey[50],
      body: Column(
        children: [
          // 검색 입력 영역
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // 검색 입력 필드
                Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 12),
                      Icon(Icons.search, color: Colors.grey[600]),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          focusNode: _searchFocusNode,
                          textInputAction: TextInputAction.search,
                          decoration: InputDecoration(
                            hintText:
                                Localizations.localeOf(context).languageCode ==
                                        'ko'
                                    ? '포스트를 검색하세요...'
                                    : 'Search posts...',
                            hintStyle: TextStyle(color: Colors.grey[500]),
                            border: InputBorder.none,
                          ),
                          onChanged: (_) {
                            // 명시적 검색 버튼을 누르기 전에는 이전 검색어의
                            // 결과가 현재 입력의 결과처럼 보이지 않게 한다.
                            _searchRequestGuard.invalidate();
                            setState(() {
                              _searchResults = [];
                              _searchQuery = '';
                              _isLoading = false;
                              _hasSearchError = false;
                            });
                          },
                          onSubmitted: (_) {
                            _performSearch();
                          },
                        ),
                      ),
                      if (_searchController.text.isNotEmpty)
                        IconButton(
                          icon: const Icon(Icons.clear, color: Colors.grey),
                          onPressed: () {
                            _searchRequestGuard.invalidate();
                            _searchController.clear();
                            setState(() {
                              _searchResults = [];
                              _searchQuery = '';
                              _isLoading = false;
                              _hasSearchError = false;
                            });
                          },
                        ),
                      IconButton(
                        icon: const Icon(Icons.search, color: Colors.blue),
                        onPressed: _performSearch,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 검색 결과 영역
          Expanded(
            child: _isLoading
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        Text(AppLocalizations.of(context)!.searching),
                      ],
                    ),
                  )
                : _hasSearchError
                    ? AppErrorState(
                        title: AppLocalizations.of(context)!.error,
                        description:
                            AppLocalizations.of(context)!.errorOccurred,
                        retryText: AppLocalizations.of(context)!.retryAction,
                        onRetry: _performSearch,
                      )
                    : _searchResults.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.search_off,
                                  size: 64,
                                  color: Colors.grey[400],
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  _searchQuery.isEmpty
                                      ? AppLocalizations.of(context)!
                                          .pleaseEnterSearchQuery
                                      : AppLocalizations.of(context)!
                                          .noSearchResults,
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                if (_searchQuery.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    '"$_searchQuery"${Localizations.localeOf(context).languageCode == 'ko' ? '에 대한 결과를 찾을 수 없습니다' : ' - No results found'}',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey[500],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          )
                        : Container(
                            color: Colors.grey[50],
                            child: ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: _searchResults.length,
                              itemBuilder: (context, index) {
                                final post = _searchResults[index];
                                return PostSearchCard(post: post);
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}
