import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../models/social_profile_data.dart';
import '../models/user_profile.dart';
import '../services/content_filter_service.dart';
import '../ui/widgets/user_avatar.dart';
import '../utils/country_flag_helper.dart';
import '../utils/logger.dart';
import '../utils/responsive_helper.dart';
import '../widgets/country_flag_circle.dart';
import 'friend_profile_screen.dart';

enum SocialProfileTagKind {
  interest('interests'),
  activity('preferredActivities');

  const SocialProfileTagKind(this.firestoreField);

  final String firestoreField;
}

class SocialTagPeopleScreen extends StatefulWidget {
  const SocialTagPeopleScreen({
    super.key,
    required this.tagId,
    required this.kind,
  });

  final String tagId;
  final SocialProfileTagKind kind;

  @override
  State<SocialTagPeopleScreen> createState() => _SocialTagPeopleScreenState();
}

class _SocialTagPeopleScreenState extends State<SocialTagPeopleScreen> {
  static const int _pageSize = 24;

  final ScrollController _scrollController = ScrollController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final List<UserProfile> _people = <UserProfile>[];

  DocumentSnapshot<Map<String, dynamic>>? _lastDocument;
  Set<String> _excludedUserIds = const <String>{};
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  Object? _error;
  int _loadGeneration = 0;

  bool get _isKorean =>
      Localizations.localeOf(context).languageCode.toLowerCase() == 'ko';

  String get _tagLabel => SocialProfileCatalog.labelFor(
        widget.tagId,
        widget.kind == SocialProfileTagKind.interest
            ? SocialProfileCatalog.interests
            : SocialProfileCatalog.activities,
        Localizations.localeOf(context).languageCode,
      );

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    _refresh();
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (!_scrollController.hasClients ||
        _isLoading ||
        _isLoadingMore ||
        !_hasMore) {
      return;
    }
    if (_scrollController.position.extentAfter < 280) {
      _loadNextPage();
    }
  }

  Future<void> _refresh() async {
    final generation = ++_loadGeneration;
    if (mounted) {
      setState(() {
        _people.clear();
        _lastDocument = null;
        _hasMore = true;
        _isLoading = true;
        _isLoadingMore = false;
        _error = null;
      });
    }

    try {
      final blockedSets = await Future.wait<Set<String>>(<Future<Set<String>>>[
        ContentFilterService.getBlockedUserIds(),
        ContentFilterService.getBlockedByUserIds(),
      ]);
      if (!mounted || generation != _loadGeneration) return;
      _excludedUserIds = <String>{...blockedSets[0], ...blockedSets[1]};
      await _loadNextPage(generation: generation, initialLoad: true);
    } catch (error, stackTrace) {
      Logger.error('태그 사용자 차단 목록 로드 실패', error, stackTrace);
      if (!mounted || generation != _loadGeneration) return;
      // 차단 목록을 확인할 수 없으면 사람 목록을 노출하지 않는다.
      setState(() {
        _error = error;
        _isLoading = false;
      });
    }
  }

  Future<void> _loadNextPage(
      {int? generation, bool initialLoad = false}) async {
    final expectedGeneration = generation ?? _loadGeneration;
    if (!initialLoad && (_isLoadingMore || !_hasMore)) return;

    if (mounted) {
      setState(() {
        _isLoadingMore = !initialLoad;
        _error = null;
      });
    }

    try {
      final collected = <UserProfile>[];
      var shouldContinue = true;

      // 한 페이지가 전부 차단/비활성 사용자여도 다음 문서를 이어서 찾는다.
      while (shouldContinue && collected.isEmpty) {
        Query<Map<String, dynamic>> query = _firestore
            .collection('users')
            .where(widget.kind.firestoreField, arrayContains: widget.tagId)
            .limit(_pageSize);
        final cursor = _lastDocument;
        if (cursor != null) query = query.startAfterDocument(cursor);

        final result = await query.get();
        if (!mounted || expectedGeneration != _loadGeneration) return;

        final documents = result.docs;
        if (documents.isNotEmpty) _lastDocument = documents.last;
        _hasMore = documents.length == _pageSize;
        shouldContinue = _hasMore;

        for (final document in documents) {
          if (_excludedUserIds.contains(document.id)) continue;
          final data = document.data();
          if (!_isVisibleProfile(data)) continue;
          try {
            collected.add(UserProfile.fromFirestore(document));
          } catch (error, stackTrace) {
            Logger.error(
              '태그 사용자 프로필 파싱 실패 (uid=${document.id})',
              error,
              stackTrace,
            );
          }
        }

        if (documents.isEmpty) shouldContinue = false;
      }

      if (!mounted || expectedGeneration != _loadGeneration) return;
      setState(() {
        _people.addAll(collected);
        _people.sort(
          (left, right) => left.displayNameOrNickname
              .toLowerCase()
              .compareTo(right.displayNameOrNickname.toLowerCase()),
        );
        _isLoading = false;
        _isLoadingMore = false;
      });
    } catch (error, stackTrace) {
      Logger.error(
        '태그 사용자 조회 실패 '
        '(tag=${widget.tagId}, kind=${widget.kind.name})',
        error,
        stackTrace,
      );
      if (!mounted || expectedGeneration != _loadGeneration) return;
      setState(() {
        _error = error;
        _isLoading = false;
        _isLoadingMore = false;
      });
    }
  }

  bool _isVisibleProfile(Map<String, dynamic> data) {
    final status = (data['status'] ?? '').toString().toLowerCase();
    return data['isDeleted'] != true &&
        data['deleted'] != true &&
        data['disabled'] != true &&
        data['isSuspended'] != true &&
        status != 'deleted' &&
        status != 'suspended' &&
        status != 'disabled';
  }

  void _openProfile(UserProfile profile) {
    if (profile.uid == FirebaseAuth.instance.currentUser?.uid) return;
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => FriendProfileScreen(
          userId: profile.uid,
          nickname: profile.nickname,
          photoURL: profile.photoURL,
          email: profile.email,
          university: profile.university,
          allowNonFriendsPreview: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final horizontalPadding = screenWidth < 360
        ? 14.0
        : screenWidth < 600
            ? 18.0
            : 28.0;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: context.rh(56, min: 54, max: 60),
        leadingWidth: 48,
        leading: SizedBox.square(
          dimension: 48,
          child: IconButton(
            onPressed: () => Navigator.of(context).pop(),
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            icon: Icon(
              Icons.arrow_back_rounded,
              size: context.ri(22).clamp(21, 24).toDouble(),
              color: const Color(0xFF111827),
            ),
          ),
        ),
        titleSpacing: 2,
        title: Text(
          _isKorean ? '태그로 사람 찾기' : 'People by tag',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: 'Pretendard',
            fontSize: context.rf(17).clamp(16, 18).toDouble(),
            fontWeight: FontWeight.w700,
            color: const Color(0xFF111827),
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        bottom: true,
        child: MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.25,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding,
                      context.rs(16).clamp(14, 20).toDouble(),
                      horizontalPadding,
                      context.rs(12).clamp(10, 16).toDouble(),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '#$_tagLabel',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: context.rf(22).clamp(20, 24).toDouble(),
                            fontWeight: FontWeight.w700,
                            color: AppColors.pointColor,
                            height: 1.25,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          _isKorean
                              ? '같은 태그를 선택한 사람들을 확인해 보세요.'
                              : 'Meet people who chose the same tag.',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: context.rf(13).clamp(12.5, 14).toDouble(),
                            fontWeight: FontWeight.w500,
                            color: const Color(0xFF6B7280),
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(child: _buildContent(horizontalPadding)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(double horizontalPadding) {
    if (_isLoading) {
      return const Center(
        child: SizedBox.square(
          dimension: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    if (_error != null && _people.isEmpty) {
      return _TagPeopleMessage(
        icon: Icons.refresh_rounded,
        title: _isKorean ? '사람 목록을 불러오지 못했어요' : 'Could not load people',
        actionLabel: _isKorean ? '다시 시도' : 'Try again',
        onAction: _refresh,
      );
    }

    if (_people.isEmpty) {
      return _TagPeopleMessage(
        icon: Icons.people_outline_rounded,
        title: _isKorean
            ? '아직 이 태그를 선택한 사람이 없어요'
            : 'No one has chosen this tag yet',
      );
    }

    return RefreshIndicator(
      color: AppColors.pointColor,
      onRefresh: _refresh,
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          0,
          4,
          0,
          context.rs(20).clamp(16, 28).toDouble(),
        ),
        itemCount: _people.length + (_isLoadingMore || _error != null ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _people.length) {
            if (_isLoadingMore) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: Center(
                  child: SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              );
            }
            return Center(
              child: TextButton(
                onPressed: _loadNextPage,
                child: Text(_isKorean ? '다시 시도' : 'Try again'),
              ),
            );
          }
          return _TagPersonRow(
            profile: _people[index],
            horizontalPadding: horizontalPadding,
            isCurrentUser:
                _people[index].uid == FirebaseAuth.instance.currentUser?.uid,
            onTap: () => _openProfile(_people[index]),
          );
        },
      ),
    );
  }
}

class _TagPersonRow extends StatelessWidget {
  const _TagPersonRow({
    required this.profile,
    required this.horizontalPadding,
    required this.isCurrentUser,
    required this.onTap,
  });

  final UserProfile profile;
  final double horizontalPadding;
  final bool isCurrentUser;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isKorean =
        Localizations.localeOf(context).languageCode.toLowerCase() == 'ko';
    final avatarSize = MediaQuery.sizeOf(context).width < 360 ? 44.0 : 48.0;
    final nationality = profile.nationality?.trim() ?? '';
    final university = profile.university?.trim() ?? '';
    final countryName = nationality.isEmpty
        ? ''
        : CountryFlagHelper.getCountryInfo(nationality)?.getLocalizedName(
              Localizations.localeOf(context).languageCode,
            ) ??
            nationality;
    final supportingText = <String>[
      if (countryName.isNotEmpty) countryName,
      if (university.isNotEmpty) university,
    ].join(' · ');

    return Semantics(
      button: !isCurrentUser,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isCurrentUser ? null : onTap,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              context.rs(10).clamp(9, 12).toDouble(),
              horizontalPadding,
              context.rs(10).clamp(9, 12).toDouble(),
            ),
            child: Row(
              children: [
                UserAvatar(
                  uid: profile.uid,
                  photoUrl: profile.photoURL ?? '',
                  photoVersion: 0,
                  isAnonymous: false,
                  size: avatarSize,
                  placeholderColor: const Color(0xFFF2F4F7),
                  placeholderIcon: Icons.person_outline_rounded,
                ),
                SizedBox(width: context.rs(12).clamp(10, 14).toDouble()),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        profile.displayNameOrNickname,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Pretendard',
                          fontSize: context.rf(15).clamp(14, 16).toDouble(),
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF111827),
                          height: 1.25,
                        ),
                      ),
                      if (supportingText.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            if (nationality.isNotEmpty) ...[
                              CountryFlagCircle(
                                nationality: nationality,
                                size: 15,
                              ),
                              const SizedBox(width: 5),
                            ],
                            Expanded(
                              child: Text(
                                supportingText,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: 'Pretendard',
                                  fontSize:
                                      context.rf(12).clamp(11.5, 13).toDouble(),
                                  fontWeight: FontWeight.w500,
                                  color: const Color(0xFF7C8491),
                                  height: 1.25,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (isCurrentUser)
                  Text(
                    isKorean ? '나' : 'You',
                    style: TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: context.rf(12).clamp(11.5, 13).toDouble(),
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF98A2B3),
                    ),
                  )
                else
                  SizedBox.square(
                    dimension: 40,
                    child: Icon(
                      Icons.chevron_right_rounded,
                      size: context.ri(21).clamp(20, 23).toDouble(),
                      color: const Color(0xFF98A2B3),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TagPeopleMessage extends StatelessWidget {
  const _TagPeopleMessage({
    required this.icon,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 20, 28, 56),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 30, color: const Color(0xFF98A2B3)),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: context.rf(14).clamp(13, 15).toDouble(),
                fontWeight: FontWeight.w600,
                color: const Color(0xFF667085),
                height: 1.4,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 8),
              TextButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
