import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/user_profile.dart';
import '../../repositories/users_repository.dart';
import '../../utils/responsive_helper.dart';

typedef SnackChatUserIdSearch = Future<SnackChatUserSearchPage> Function(
  String query, {
  String? cursor,
});

/// Snack Chat 생성/추가 초대에서 공통으로 사용하는 참여자 선택기.
///
/// 친구 탭은 로컬 친구 목록을 이름으로 필터링하고, 전체 탭은 친구 관계와
/// 무관하게 고유 닉네임(사용자 ID)을 철자로 검색해 10명씩 조회한다.
class SnackChatParticipantPicker extends StatefulWidget {
  const SnackChatParticipantPicker({
    super.key,
    required this.friends,
    required this.selectedProfiles,
    required this.onToggle,
    this.excludedUserIds = const <String>{},
    this.maxSelectionCount = 49,
    this.searchUserById,
    this.showSelectedStrip = true,
  });

  final List<UserProfile> friends;
  final Map<String, UserProfile> selectedProfiles;
  final ValueChanged<UserProfile> onToggle;
  final Set<String> excludedUserIds;
  final int maxSelectionCount;
  final SnackChatUserIdSearch? searchUserById;
  final bool showSelectedStrip;

  @override
  State<SnackChatParticipantPicker> createState() =>
      _SnackChatParticipantPickerState();
}

class _SnackChatParticipantPickerState extends State<SnackChatParticipantPicker>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  UsersRepository? _usersRepository;
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  String _query = '';
  List<UserProfile> _directoryResults = const <UserProfile>[];
  String? _directoryNextCursor;
  bool _isSearching = false;
  bool _isLoadingMore = false;
  bool _searchFailed = false;
  bool _hasSearched = false;
  int _searchGeneration = 0;

  bool get _isKo => Localizations.localeOf(context).languageCode == 'ko';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this)
      ..addListener(_handleTabChanged);
    _searchController.addListener(_handleSearchChanged);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _tabController
      ..removeListener(_handleTabChanged)
      ..dispose();
    _searchController
      ..removeListener(_handleSearchChanged)
      ..dispose();
    super.dispose();
  }

  void _handleTabChanged() {
    if (_tabController.indexIsChanging) return;
    _searchDebounce?.cancel();
    _searchGeneration++;
    _searchController.clear();
    if (!mounted) return;
    setState(() {
      _query = '';
      _directoryResults = const <UserProfile>[];
      _directoryNextCursor = null;
      _isSearching = false;
      _isLoadingMore = false;
      _searchFailed = false;
      _hasSearched = false;
    });
  }

  void _handleSearchChanged() {
    final next = _searchController.text.trim();
    if (next == _query) return;
    _searchDebounce?.cancel();
    _searchGeneration++;
    setState(() {
      _query = next;
      _directoryResults = const <UserProfile>[];
      _directoryNextCursor = null;
      _searchFailed = false;
      _hasSearched = false;
      _isSearching = false;
      _isLoadingMore = false;
    });
    if (_tabController.index == 1 && next.isNotEmpty) {
      _searchDebounce = Timer(
        const Duration(milliseconds: 240),
        () => _searchDirectory(next),
      );
    }
  }

  Future<void> _searchDirectory(
    String query, {
    bool loadMore = false,
  }) async {
    if (loadMore &&
        (_isSearching || _isLoadingMore || _directoryNextCursor == null)) {
      return;
    }
    final generation = loadMore ? _searchGeneration : ++_searchGeneration;
    setState(() {
      if (loadMore) {
        _isLoadingMore = true;
      } else {
        _isSearching = true;
        _directoryResults = const <UserProfile>[];
        _directoryNextCursor = null;
      }
      _searchFailed = false;
    });
    try {
      final search = widget.searchUserById ??
          (String value, {String? cursor}) => (_usersRepository ??=
                      UsersRepository())
                  .searchSnackChatInviteUsersLikeNameSearch(
                value,
                cursor: cursor,
              );
      final page = await search(
        query,
        cursor: loadMore ? _directoryNextCursor : null,
      );
      if (!mounted || generation != _searchGeneration || _query != query) {
        return;
      }
      final visible = page.users
          .where((profile) => !widget.excludedUserIds.contains(profile.uid));
      setState(() {
        if (loadMore) {
          final merged = <String, UserProfile>{
            for (final profile in _directoryResults) profile.uid: profile,
            for (final profile in visible) profile.uid: profile,
          };
          _directoryResults = merged.values.toList(growable: false);
        } else {
          _directoryResults = visible.toList(growable: false);
        }
        _directoryNextCursor = page.nextCursor;
        _hasSearched = true;
        _isSearching = false;
        _isLoadingMore = false;
      });
    } catch (_) {
      if (!mounted || generation != _searchGeneration || _query != query) {
        return;
      }
      setState(() {
        _searchFailed = true;
        _hasSearched = true;
        _isSearching = false;
        _isLoadingMore = false;
      });
    }
  }

  void _submitSearch() {
    if (_tabController.index != 1) return;
    final query = _searchController.text.trim();
    if (query.isEmpty) return;
    _searchDebounce?.cancel();
    FocusManager.instance.primaryFocus?.unfocus();
    _searchDirectory(query);
  }

  void _toggle(UserProfile profile) {
    final isSelected = widget.selectedProfiles.containsKey(profile.uid);
    if (!isSelected &&
        widget.selectedProfiles.length >= widget.maxSelectionCount) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isKo
                ? '한 채팅방에는 나를 포함해 최대 50명까지 참여할 수 있어요.'
                : 'A room can have up to 50 participants including you.',
          ),
        ),
      );
      return;
    }
    widget.onToggle(profile);
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final horizontalPadding = width < 360
        ? 12.0
        : width < 600
            ? 16.0
            : 24.0;
    final availableHeight = MediaQuery.sizeOf(context).height -
        MediaQuery.viewInsetsOf(context).bottom;
    final showSelectedStrip = widget.showSelectedStrip &&
        (widget.selectedProfiles.isNotEmpty || availableHeight >= 300);
    final compactSelectedStrip = availableHeight < 360;
    final searchFontSize = context.rf(14).clamp(13, 15).toDouble();

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showSelectedStrip)
                _SelectedParticipantStrip(
                  profiles:
                      widget.selectedProfiles.values.toList(growable: false),
                  onRemove: _toggle,
                  isKo: _isKo,
                  horizontalPadding: horizontalPadding,
                  compact: compactSelectedStrip,
                ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  showSelectedStrip ? 0 : context.rs(6),
                  horizontalPadding,
                  0,
                ),
                child: SizedBox(
                  height: context.rh(44, min: 42, max: 48),
                  child: TabBar(
                    controller: _tabController,
                    dividerColor: Colors.transparent,
                    indicatorSize: TabBarIndicatorSize.tab,
                    indicator: const UnderlineTabIndicator(
                      borderSide: BorderSide(
                        color: Color(0xFF111827),
                        width: 2,
                      ),
                      insets: EdgeInsets.symmetric(horizontal: 20),
                    ),
                    labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                    labelColor: const Color(0xFF111827),
                    unselectedLabelColor: const Color(0xFF667085),
                    labelStyle: TextStyle(
                      fontFamily: 'Inter',
                      fontFamilyFallback: const ['NotoSansKR'],
                      fontSize: context.rf(13.5).clamp(12.5, 14.5).toDouble(),
                      fontWeight: FontWeight.w700,
                    ),
                    unselectedLabelStyle: TextStyle(
                      fontFamily: 'Inter',
                      fontFamilyFallback: const ['NotoSansKR'],
                      fontSize: context.rf(13.5).clamp(12.5, 14.5).toDouble(),
                      fontWeight: FontWeight.w600,
                    ),
                    tabs: [
                      Tab(text: _isKo ? '친구' : 'Friends'),
                      Tab(
                        text: _isKo ? '전체 · 아이디 검색' : 'All · ID search',
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  context.rs(4).clamp(2, 6).toDouble(),
                  horizontalPadding,
                  context.rs(6).clamp(4, 8).toDouble(),
                ),
                child: TextField(
                  controller: _searchController,
                  textInputAction: TextInputAction.search,
                  autocorrect: false,
                  enableSuggestions: _tabController.index == 0,
                  onSubmitted: (_) => _submitSearch(),
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontFamilyFallback: const ['NotoSansKR'],
                    fontSize: searchFontSize,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF111827),
                  ),
                  decoration: InputDecoration(
                    hintText: _tabController.index == 0
                        ? (_isKo ? '친구 이름 검색' : 'Search friends')
                        : (_isKo ? '사용자 아이디 검색' : 'Search user IDs'),
                    hintStyle: TextStyle(
                      fontFamily: 'Inter',
                      fontFamilyFallback: const ['NotoSansKR'],
                      fontSize: searchFontSize,
                      fontWeight: FontWeight.w400,
                      color: const Color(0xFF98A2B3),
                    ),
                    prefixIcon: IconButton(
                      key: const Key('snack_chat_participant_search_button'),
                      tooltip: _isKo ? '아이디 검색' : 'Search by ID',
                      onPressed:
                          _tabController.index == 1 ? _submitSearch : null,
                      padding: EdgeInsets.zero,
                      icon: Icon(
                        Icons.search_rounded,
                        size: context.ri(20).clamp(19, 22).toDouble(),
                      ),
                      color: const Color(0xFF667085),
                      disabledColor: const Color(0xFF667085),
                    ),
                    prefixIconConstraints: const BoxConstraints(
                      minWidth: 40,
                      minHeight: 44,
                    ),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: MaterialLocalizations.of(context)
                                .deleteButtonTooltip,
                            onPressed: _searchController.clear,
                            icon: Icon(
                              Icons.close_rounded,
                              size: context.ri(18).clamp(17, 20).toDouble(),
                            ),
                          ),
                    suffixIconConstraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 44,
                    ),
                    border: const UnderlineInputBorder(
                      borderSide: BorderSide(color: Color(0xFFEAECF0)),
                    ),
                    enabledBorder: const UnderlineInputBorder(
                      borderSide: BorderSide(color: Color(0xFFEAECF0)),
                    ),
                    focusedBorder: const UnderlineInputBorder(
                      borderSide: BorderSide(
                        color: Color(0xFF667085),
                        width: 1.4,
                      ),
                    ),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 0,
                      vertical: context.rs(11).clamp(9, 13).toDouble(),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildFriendsList(horizontalPadding),
                    _buildDirectoryResult(horizontalPadding),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFriendsList(double horizontalPadding) {
    final normalized = _query.toLowerCase();
    final visible = widget.friends.where((friend) {
      if (widget.excludedUserIds.contains(friend.uid)) return false;
      return normalized.isEmpty ||
          friend.displayNameOrNickname.toLowerCase().contains(normalized);
    }).toList(growable: false);
    if (visible.isEmpty) {
      return _PickerMessage(
        icon: Icons.people_outline_rounded,
        title: _isKo ? '초대할 친구가 없어요' : 'No friends to invite',
        description: _isKo
            ? '전체 탭에서 사용자 아이디로 찾아보세요.'
            : 'Try finding someone by user ID in the All tab.',
      );
    }
    return ListView.builder(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(
        horizontalPadding - 8,
        0,
        horizontalPadding - 8,
        20,
      ),
      itemCount: visible.length,
      itemBuilder: (_, index) => _ParticipantTile(
        profile: visible[index],
        selected: widget.selectedProfiles.containsKey(visible[index].uid),
        onTap: () => _toggle(visible[index]),
      ),
    );
  }

  Widget _buildDirectoryResult(double horizontalPadding) {
    if (_query.isEmpty) {
      return _PickerMessage(
        icon: Icons.alternate_email_rounded,
        title: _isKo ? '사용자 아이디로 초대해요' : 'Invite by user ID',
        description: _isKo
            ? '아이디 철자를 입력하면 친구 여부와 관계없이\n전체 사용자에서 찾아요.'
            : 'Enter the spelling of an ID to search all users,\nwhether or not you are friends.',
      );
    }
    if (_isSearching) {
      return const Center(
        child: SizedBox.square(
          dimension: 24,
          child: CircularProgressIndicator(strokeWidth: 2.2),
        ),
      );
    }
    if (_searchFailed) {
      return _PickerMessage(
        icon: Icons.wifi_off_rounded,
        title: _isKo ? '검색하지 못했어요' : 'Could not search',
        description: _isKo
            ? '연결을 확인하고 다시 시도해 주세요.'
            : 'Check your connection and try again.',
        actionLabel: _isKo ? '다시 검색' : 'Try again',
        onAction: () => _searchDirectory(_query),
      );
    }
    if (_hasSearched && _directoryResults.isEmpty) {
      return _PickerMessage(
        icon: Icons.person_search_outlined,
        title: _isKo ? '일치하는 사용자가 없어요' : 'No matching user',
        description:
            _isKo ? '아이디 철자를 확인해 주세요.' : 'Check the ID spelling and try again.',
        actionLabel: _directoryNextCursor == null
            ? null
            : (_isKo ? '다음 10명 보기' : 'View next 10'),
        onAction: _directoryNextCursor == null
            ? null
            : () => _searchDirectory(_query, loadMore: true),
      );
    }
    if (_directoryResults.isEmpty) return const SizedBox.shrink();
    final hasNextPage = _directoryNextCursor != null;
    return ListView.builder(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(
        horizontalPadding - 8,
        0,
        horizontalPadding - 8,
        20,
      ),
      itemCount: _directoryResults.length + (hasNextPage ? 1 : 0),
      itemBuilder: (_, index) {
        if (index == _directoryResults.length) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: _isLoadingMore
                  ? const SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : TextButton(
                      key: const Key('snack_chat_load_more_users'),
                      onPressed: () => _searchDirectory(
                        _query,
                        loadMore: true,
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF344054),
                        minimumSize: const Size(44, 40),
                      ),
                      child: Text(_isKo ? '10명 더 보기' : 'Load 10 more'),
                    ),
            ),
          );
        }
        final profile = _directoryResults[index];
        return _ParticipantTile(
          profile: profile,
          selected: widget.selectedProfiles.containsKey(profile.uid),
          showIdPrefix: true,
          onTap: () => _toggle(profile),
        );
      },
    );
  }
}

class _SelectedParticipantStrip extends StatelessWidget {
  const _SelectedParticipantStrip({
    required this.profiles,
    required this.onRemove,
    required this.isKo,
    required this.horizontalPadding,
    required this.compact,
  });

  final List<UserProfile> profiles;
  final ValueChanged<UserProfile> onRemove;
  final bool isKo;
  final double horizontalPadding;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (profiles.isEmpty) {
      return Padding(
        padding: EdgeInsets.fromLTRB(
          horizontalPadding,
          context.rs(18).clamp(14, 20).toDouble(),
          horizontalPadding,
          context.rs(10).clamp(8, 12).toDouble(),
        ),
        child: Text(
          isKo ? '초대할 사람을 선택해 주세요.' : 'Select people to invite.',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: 'Inter',
            fontFamilyFallback: const ['NotoSansKR'],
            fontSize: context.rf(13).clamp(12, 14).toDouble(),
            fontWeight: FontWeight.w600,
            color: const Color(0xFF667085),
          ),
        ),
      );
    }

    final avatarSize = compact
        ? context.ri(36).clamp(34, 38).toDouble()
        : context.ri(42).clamp(39, 46).toDouble();
    final itemWidth = compact
        ? context.rs(48).clamp(46, 52).toDouble()
        : context.rs(56).clamp(52, 60).toDouble();
    final nameFontSize = compact
        ? context.rf(10.5).clamp(10, 11.5).toDouble()
        : context.rf(11.5).clamp(11, 12.5).toDouble();
    final nameGap = context.rs(compact ? 2 : 3).clamp(2, 4).toDouble();
    final scaledNameHeight =
        MediaQuery.textScalerOf(context).scale(nameFontSize) * 1.15;
    // 아바타와 한 줄 이름의 실제 스케일 높이를 합산해 소수점 단위의
    // RenderFlex overflow도 발생하지 않도록 안전 여백을 둔다.
    final contentHeight = avatarSize + nameGap + scaledNameHeight + 3;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        context
            .rs(compact ? 6 : 10)
            .clamp(compact ? 4 : 8, compact ? 8 : 12)
            .toDouble(),
        horizontalPadding,
        context
            .rs(compact ? 4 : 8)
            .clamp(compact ? 3 : 6, compact ? 6 : 10)
            .toDouble(),
      ),
      child: SizedBox(
        height: contentHeight,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          itemCount: profiles.length,
          separatorBuilder: (_, __) =>
              SizedBox(width: context.rs(8).clamp(6, 10).toDouble()),
          itemBuilder: (_, index) {
            final profile = profiles[index];
            return GestureDetector(
              onTap: () => onRemove(profile),
              child: SizedBox(
                width: itemWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        _ParticipantAvatar(
                          profile: profile,
                          size: avatarSize,
                        ),
                        Positioned(
                          right: -2,
                          top: -2,
                          child: Container(
                            width: 18,
                            height: 18,
                            decoration: const BoxDecoration(
                              color: Color(0xFF111827),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.close_rounded,
                              size: 12,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: nameGap),
                    Text(
                      profile.displayNameOrNickname,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontFamilyFallback: const ['NotoSansKR'],
                        fontSize: nameFontSize,
                        fontWeight: FontWeight.w600,
                        height: 1.15,
                        color: const Color(0xFF374151),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ParticipantTile extends StatelessWidget {
  const _ParticipantTile({
    required this.profile,
    required this.selected,
    required this.onTap,
    this.showIdPrefix = false,
  });

  final UserProfile profile;
  final bool selected;
  final VoidCallback onTap;
  final bool showIdPrefix;

  @override
  Widget build(BuildContext context) {
    final avatarSize = context.ri(42).clamp(40, 46).toDouble();
    return Semantics(
      button: true,
      selected: selected,
      label: profile.displayNameOrNickname,
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: 0,
              vertical: context.rs(8).clamp(7, 10).toDouble(),
            ),
            child: Row(
              children: [
                _ParticipantAvatar(profile: profile, size: avatarSize),
                SizedBox(width: context.rs(12).clamp(10, 14).toDouble()),
                Expanded(
                  child: Text(
                    showIdPrefix
                        ? '@${profile.displayNameOrNickname}'
                        : profile.displayNameOrNickname,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontFamilyFallback: const ['NotoSansKR'],
                      fontSize: context.rf(14).clamp(13, 15).toDouble(),
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF111827),
                    ),
                  ),
                ),
                SizedBox(width: context.rs(8).clamp(6, 10).toDouble()),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  width: context.ri(22).clamp(21, 24).toDouble(),
                  height: context.ri(22).clamp(21, 24).toDouble(),
                  decoration: BoxDecoration(
                    color:
                        selected ? const Color(0xFF344054) : Colors.transparent,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected
                          ? const Color(0xFF344054)
                          : const Color(0xFFD0D5DD),
                      width: 1.5,
                    ),
                  ),
                  child: selected
                      ? const Icon(
                          Icons.check_rounded,
                          size: 15,
                          color: Colors.white,
                        )
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ParticipantAvatar extends StatelessWidget {
  const _ParticipantAvatar({required this.profile, required this.size});

  final UserProfile profile;
  final double size;

  @override
  Widget build(BuildContext context) {
    final name = profile.displayNameOrNickname.trim();
    final fallback = name.isEmpty ? '?' : String.fromCharCode(name.runes.first);
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(
        color: Color(0xFFF2F4F7),
        shape: BoxShape.circle,
      ),
      child: profile.hasProfileImage
          ? Image.network(
              profile.photoURL!,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _AvatarFallback(
                label: fallback,
                size: size,
              ),
            )
          : _AvatarFallback(label: fallback, size: size),
    );
  }
}

class _AvatarFallback extends StatelessWidget {
  const _AvatarFallback({required this.label, required this.size});

  final String label;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontFamily: 'Inter',
          fontFamilyFallback: const ['NotoSansKR'],
          fontSize: size * 0.34,
          fontWeight: FontWeight.w700,
          color: const Color(0xFF475467),
        ),
      ),
    );
  }
}

class _PickerMessage extends StatelessWidget {
  const _PickerMessage({
    required this.icon,
    required this.title,
    required this.description,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String description;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 190;
        final verticalPadding = compact ? 8.0 : context.rs(20).clamp(14, 24);
        return SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(
            24,
            verticalPadding.toDouble(),
            24,
            verticalPadding.toDouble(),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: (constraints.maxHeight - verticalPadding * 2)
                  .clamp(0, double.infinity)
                  .toDouble(),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    color: const Color(0xFF667085),
                    size: context
                        .ri(compact ? 25 : 30)
                        .clamp(compact ? 23 : 27, compact ? 28 : 33)
                        .toDouble(),
                  ),
                  SizedBox(
                    height: context
                        .rs(compact ? 8 : 12)
                        .clamp(compact ? 6 : 10, compact ? 10 : 14)
                        .toDouble(),
                  ),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontFamilyFallback: const ['NotoSansKR'],
                      fontSize: context.rf(15).clamp(14, 16).toDouble(),
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1D2939),
                    ),
                  ),
                  SizedBox(height: context.rs(5).clamp(4, 7).toDouble()),
                  Text(
                    description,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontFamilyFallback: const ['NotoSansKR'],
                      fontSize: context.rf(12.5).clamp(12, 13.5).toDouble(),
                      fontWeight: FontWeight.w500,
                      height: 1.45,
                      color: const Color(0xFF667085),
                    ),
                  ),
                  if (actionLabel != null && onAction != null) ...[
                    SizedBox(height: context.rs(8).clamp(6, 10).toDouble()),
                    TextButton(
                      onPressed: onAction,
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF344054),
                        minimumSize: const Size(44, 40),
                      ),
                      child: Text(actionLabel!),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
