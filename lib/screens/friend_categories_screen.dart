// lib/screens/friend_categories_screen.dart
// 친구 카테고리 관리 화면

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/friend_category.dart';
import '../services/friend_category_service.dart';
import '../ui/widgets/shape_icon.dart';
import '../constants/app_constants.dart';
import '../design/tokens.dart';
import '../ui/widgets/app_fab.dart';
import '../ui/widgets/empty_state.dart';
import '../ui/widgets/category_shapes_illustration.dart';
import '../providers/auth_provider.dart';
import 'category_detail_screen.dart';
import 'create_category_screen.dart';
import 'create_snack_chat_screen.dart';
import 'snack_chat_tab_view.dart';
import '../l10n/app_localizations.dart';
import '../utils/logger.dart';

/// Stable internal tab mapping used by direct-entry routes.
const int snackChatTabIndex = 0;
const int groupsTabIndex = 1;

class FriendCategoriesScreen extends StatefulWidget {
  final int initialTabIndex;
  const FriendCategoriesScreen({
    super.key,
    this.initialTabIndex = snackChatTabIndex,
  });

  @override
  State<FriendCategoriesScreen> createState() => _FriendCategoriesScreenState();
}

class _FriendCategoriesScreenState extends State<FriendCategoriesScreen>
    with SingleTickerProviderStateMixin {
  final FriendCategoryService _categoryService = FriendCategoryService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  late VoidCallback _cleanupCallback;
  AuthProvider? _authProvider;
  static const int _maxCategories = FriendCategoryService.maxCategoriesPerUser;
  late TabController _tabController;

  /// 카테고리 스트림 구독 – 마지막 데이터를 state에 보관해
  /// TabBarView 탭 전환 시에도 로딩 스피너 없이 즉시 표시된다.
  StreamSubscription<List<FriendCategory>>? _categoriesSub;
  List<FriendCategory> _categories = [];
  bool _categoriesLoading = true;

  /// 카테고리 ID → 실제 친구 수 캐시 (세션 내 재사용)
  final Map<String, int> _friendCountCache = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(
        snackChatTabIndex,
        groupsTabIndex,
      ),
    );
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _subscribeCategories();

    // 스트림 정리 콜백 등록
    _cleanupCallback = () {
      _categoryService.dispose();
    };

    // initState에서 listen:false로 읽는 것은 안전하며,
    // post-frame 콜백에서 (이미 dispose된) context를 조회하는 레이스를 제거한다.
    _authProvider = Provider.of<AuthProvider>(context, listen: false);
    _authProvider?.registerStreamCleanup(_cleanupCallback);
  }

  void _subscribeCategories() {
    _categoriesSub?.cancel();
    _categoriesSub = _categoryService.getCategoriesStream().listen(
      (cats) {
        if (mounted) {
          setState(() {
            _categories = cats;
            _categoriesLoading = false;
          });
        }
      },
      onError: (_) {
        if (mounted) setState(() => _categoriesLoading = false);
      },
    );
  }

  @override
  void dispose() {
    // AuthProvider에서 콜백 제거
    // dispose에서는 context로 ancestor lookup을 하지 않는다.
    _authProvider?.unregisterStreamCleanup(_cleanupCallback);

    _categoriesSub?.cancel();

    // 서비스 정리
    _categoryService.dispose();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: BrandColors.surface,
      appBar: AppBar(
        toolbarHeight: 0,
        elevation: 0,
        backgroundColor: Colors.white,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: TabBar(
            controller: _tabController,
            indicator: const UnderlineTabIndicator(
              borderSide: BorderSide(
                color: AppColors.pointColor,
                width: 2.5,
              ),
              borderRadius: BorderRadius.vertical(top: Radius.circular(2)),
            ),
            labelColor: const Color(0xFF111827),
            unselectedLabelColor: const Color(0xFF9CA3AF),
            labelStyle: const TextStyle(
              fontFamily: 'Inter',
              fontFamilyFallback: const ['NotoSansKR'],
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
            unselectedLabelStyle: const TextStyle(
              fontFamily: 'Inter',
              fontFamilyFallback: const ['NotoSansKR'],
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
            tabs: [
              Tab(
                height: 46,
                child: Semantics(
                  label: l10n.snackChatTabSemantic,
                  selected: _tabController.index == snackChatTabIndex,
                  button: true,
                  excludeSemantics: true,
                  child: Text(l10n.snackChat),
                ),
              ),
              Tab(
                height: 46,
                child: Semantics(
                  label: l10n.groupsTabSemantic,
                  selected: _tabController.index == groupsTabIndex,
                  button: true,
                  excludeSemantics: true,
                  child: Text(l10n.groups),
                ),
              ),
            ],
          ),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: SizedBox(
            width: double.infinity,
            child: TabBarView(
              controller: _tabController,
              children: [
                const SnackChatTabView(),
                _buildGroupsTab(),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: _tabController.index == snackChatTabIndex
          ? _buildSnackChatFab()
          : _buildCategoryFab(),
    );
  }

  Widget _buildSnackChatFab() {
    return AppFab(
      icon: IconStyles.add,
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CreateSnackChatScreen()),
        );
      },
      semanticLabel: AppLocalizations.of(context)!.createSnackChat,
      tooltip: AppLocalizations.of(context)!.createSnackChat,
      heroTag: 'create_snack_chat_fab',
    );
  }

  Widget _buildCategoryFab() {
    return AppFab(
      icon: IconStyles.add,
      onPressed: () {
        if (_categories.length >= _maxCategories) {
          _showCategoryLimitReachedSnackBar();
          return;
        }
        _showCreateCategoryDialog();
      },
      semanticLabel: AppLocalizations.of(context)!.newCategoryCreate,
      tooltip: AppLocalizations.of(context)!.addCategory,
      heroTag: 'add_category_fab',
    );
  }

  Widget _buildGroupsTab() {
    // 최초 로드 중일 때만 스피너 표시 (탭 전환 시에는 기존 데이터 즉시 사용)
    if (_categoriesLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_categories.isEmpty) {
      return SafeArea(
        child: AppEmptyState(
          icon: IconStyles.group,
          title: AppLocalizations.of(context)!.createFirstCategory,
          description:
              AppLocalizations.of(context)!.createFirstCategoryDescription,
          illustration: const Center(
            child: CategoryShapesIllustration(),
          ),
          centerVertically: true,
        ),
      );
    }

    // 안드로이드 하단 네비게이션 바 높이 감지
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    final horizontalPadding = _responsiveHorizontalPadding(context);

    return SafeArea(
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(
              horizontal: horizontalPadding,
              vertical: 10,
            ),
            decoration: const BoxDecoration(
              color: BrandColors.surface,
              border: Border(
                bottom: BorderSide(color: BrandColors.divider),
              ),
            ),
            child: Text(
              isKo ? '그룹을 통해 공개범위를 설정하세요.' : 'Set visibility through groups.',
              style: const TextStyle(
                fontFamily: 'Inter',
                fontFamilyFallback: const ['NotoSansKR'],
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Color(0xFF6B7280),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.only(
                bottom: bottomPadding > 0 ? bottomPadding + 72 : 72,
              ),
              itemCount: _categories.length,
              itemBuilder: (context, index) {
                return _buildCategoryCard(_categories[index]);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryCard(FriendCategory category) {
    // 색상 안전하게 파싱 (null 체크 포함)
    final color = _parseColor(category.color ??
        '#${AppColors.pointColor.value.toRadixString(16).substring(2)}');
    final iconName = _normalizeIconName(category.iconName);
    final l10n = AppLocalizations.of(context)!;
    final horizontalPadding = _responsiveHorizontalPadding(context);
    final isCompact = MediaQuery.sizeOf(context).width < 360;

    return DecoratedBox(
      key: ValueKey('friend-category-${category.id}'),
      decoration: const BoxDecoration(
        color: BrandColors.surface,
        border: Border(
          bottom: BorderSide(color: BrandColors.divider),
        ),
      ),
      child: ListTile(
        minTileHeight: 68,
        minLeadingWidth: 40,
        horizontalTitleGap: isCompact ? 8 : 10,
        minVerticalPadding: 4,
        contentPadding: EdgeInsets.symmetric(
          horizontal: horizontalPadding,
          vertical: 2,
        ),
        leading: SizedBox(
          width: 40,
          height: 40,
          child: Center(
            child: ShapeIcon(
              iconName: iconName,
              color: color,
              size: isCompact ? 26 : 28,
            ),
          ),
        ),
        title: Text(
          category.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontFamily: 'Inter',
            fontFamilyFallback: const ['NotoSansKR'],
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: Color(0xFF111827),
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: _FriendCountSubtitle(
            key: ValueKey('friend-count-${category.id}'),
            category: category,
            cache: _friendCountCache,
            firestore: _firestore,
          ),
        ),
        trailing: PopupMenuButton<String>(
          tooltip: MaterialLocalizations.of(context).showMenuTooltip,
          child: const SizedBox(
            width: 44,
            height: 44,
            child: Center(
              child: Icon(
                IconStyles.more,
                color: Color(0xFF6B7280),
                size: 20,
              ),
            ),
          ),
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 6,
          color: Colors.white,
          surfaceTintColor: Colors.white,
          shadowColor: const Color(0x24000000),
          offset: const Offset(0, 6),
          onSelected: (value) {
            switch (value) {
              case 'edit':
                _showEditCategoryDialog(category);
                break;
              case 'delete':
                _showDeleteConfirmDialog(category);
                break;
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'edit',
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Icon(
                    IconStyles.edit,
                    size: 19,
                    color: Color(0xFF6B7280),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    l10n.editAction ?? "",
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontFamilyFallback: const ['NotoSansKR'],
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF111827),
                    ),
                  ),
                ],
              ),
            ),
            const PopupMenuDivider(height: 1),
            PopupMenuItem(
              value: 'delete',
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Icon(
                    Icons.delete_outline_rounded,
                    size: 19,
                    color: BrandColors.error,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    l10n.delete,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontFamilyFallback: const ['NotoSansKR'],
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: BrandColors.error,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        onTap: () {
          // 카테고리 상세 화면으로 이동 (친구 목록 표시)
          _navigateToCategoryDetail(category);
        },
      ),
    );
  }

  double _responsiveHorizontalPadding(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    return (screenWidth * 0.05).clamp(16.0, 24.0).toDouble();
  }

  void _showCreateCategoryDialog() {
    _navigateToCreateCategory();
  }

  void _showEditCategoryDialog(FriendCategory category) {
    _navigateToEditCategory(category);
  }

  Future<void> _navigateToCreateCategory() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (context) => const CreateCategoryScreen(),
      ),
    );

    if (!mounted || result == null) return;

    final success = await _categoryService.createCategory(
      name: result['name'] as String,
      description: '',
      color: result['color'] as String,
      iconName: result['iconName'] as String,
    );

    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success != null ? l10n.categoryCreated : l10n.categoryCreateFailed,
        ),
      ),
    );
  }

  Future<void> _navigateToEditCategory(FriendCategory category) async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (context) => CreateCategoryScreen(category: category),
      ),
    );

    if (!mounted || result == null) return;

    final success = await _categoryService.updateCategory(
      categoryId: category.id,
      name: result['name'] as String,
      description: '',
      color: result['color'] as String,
      iconName: result['iconName'] as String,
    );

    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? (l10n.categoryUpdated ?? "")
              : (l10n.categoryUpdateFailed ?? ""),
        ),
      ),
    );
  }

  void _showCategoryLimitReachedSnackBar() {
    if (!mounted) return;
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isKo ? '그룹은 최대 10개까지 생성할 수 있어요.' : 'You can create up to 10 groups.',
        ),
      ),
    );
  }

  void _showDeleteConfirmDialog(FriendCategory category) {
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          AppLocalizations.of(context)!.deleteCategory ?? "",
          style: const TextStyle(
            fontFamily: 'Inter',
            fontFamilyFallback: const ['NotoSansKR'],
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Color(0xFF111827),
          ),
        ),
        content: Text(
          AppLocalizations.of(context)!.deleteCategoryConfirm(category.name),
          style: const TextStyle(
            fontFamily: 'Inter',
            fontFamilyFallback: const ['NotoSansKR'],
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: Color(0xFF6B7280),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              AppLocalizations.of(context)!.cancel ?? "",
              style: const TextStyle(
                fontFamily: 'Inter',
                fontFamilyFallback: const ['NotoSansKR'],
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF6B7280),
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () async {
              final success =
                  await _categoryService.deleteCategory(category.id);
              if (!context.mounted) return;
              Navigator.pop(context);
              if (!mounted) return;

              if (success) {
                setState(() {
                  _friendCountCache.removeWhere(
                    (key, _) => key.startsWith('${category.id}_'),
                  );
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content: Text(
                          AppLocalizations.of(context)!.categoryDeleted ?? "")),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content: Text(
                          AppLocalizations.of(context)!.categoryDeleteFailed ??
                              "")),
                );
              }
            },
            child: Text(
              AppLocalizations.of(context)!.delete ?? "",
              style: const TextStyle(
                fontFamily: 'Inter',
                fontFamilyFallback: const ['NotoSansKR'],
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _navigateToCategoryDetail(FriendCategory category) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CategoryDetailScreen(category: category),
      ),
    );
  }

  Future<void> _createDefaultCategoriesIfNeeded() async {
    try {
      final success = await _categoryService.createDefaultCategories();
      if (success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  AppLocalizations.of(context)!.defaultCategoryCreated ?? ""),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      Logger.error('기본 카테고리 생성 UI 오류: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text(AppLocalizations.of(context)!.defaultCategoryFailed ?? ""),
            backgroundColor: BrandColors.error,
          ),
        );
      }
    }
  }

  /// 색상 문자열을 Color 객체로 파싱 (안전한 fallback 포함)
  Color _parseColor(String hexColor) {
    // null 또는 빈 문자열 체크
    if (hexColor.isEmpty) {
      Logger.error('⚠️ 빈 색상 문자열 감지, 기본 색상 사용');
      return const Color(0xFF6366F1); // 명시적인 기본 색상
    }

    // '#' 접두사 확인
    if (!hexColor.startsWith('#')) {
      Logger.error('⚠️ 잘못된 색상 포맷: $hexColor (# 없음)');
      return const Color(0xFF6366F1);
    }

    // Hex 색상 포맷 검증 (#RRGGBB)
    final hexPattern = RegExp(r'^#[0-9A-Fa-f]{6}$');
    if (!hexPattern.hasMatch(hexColor)) {
      Logger.error('⚠️ 잘못된 Hex 색상 포맷: $hexColor');
      return const Color(0xFF6366F1);
    }

    try {
      final colorValue = int.parse(hexColor.replaceFirst('#', '0xFF'));
      return Color(colorValue);
    } catch (e) {
      Logger.error('❌ 색상 파싱 실패: $hexColor - $e');
      return const Color(0xFF6366F1); // 안전한 fallback
    }
  }

  String _normalizeIconName(String? iconName) {
    const allowed = {
      'shape_triangle',
      'shape_circle',
      'shape_square',
      'shape_star',
    };

    if (iconName == null || iconName.isEmpty) return 'shape_circle';
    if (allowed.contains(iconName)) return iconName;

    // 더 이상 제공하지 않는 아이콘은 원으로 폴백
    if (iconName == 'shape_heart' || iconName == 'shape_cross') {
      return 'shape_circle';
    }

    // 구버전 아이콘 키 → 새 키로 매핑
    switch (iconName) {
      case 'shape_circle_filled':
      case 'shape_circle_outline':
        return 'shape_circle';
      case 'shape_square_filled':
      case 'shape_square_outline':
        return 'shape_square';
      case 'shape_star_filled':
      case 'shape_star_outline':
        return 'shape_star';
      default:
        return 'shape_circle';
    }
  }

  /// 아이콘 이름을 IconData로 파싱 (안전한 fallback 포함)
  IconData _parseIcon(String iconName) {
    // 빈 문자열 체크
    if (iconName.isEmpty) {
      Logger.error('⚠️ 빈 아이콘 이름 감지, 기본 아이콘 사용');
      return Icons.group;
    }

    switch (iconName) {
      case 'shape_circle':
        return Icons.circle;
      case 'shape_square':
        return Icons.stop;
      case 'shape_star':
        return Icons.star;
      // 하트/십자가는 더 이상 사용하지 않음(기존 데이터는 원으로 폴백)
      case 'shape_cross':
        return Icons.circle;
      case 'shape_circle_filled':
        return Icons.circle;
      case 'shape_circle_outline':
        return Icons.radio_button_unchecked;
      case 'shape_square_filled':
        return Icons.stop;
      case 'shape_square_outline':
        return Icons.crop_square;
      case 'shape_triangle':
        return Icons.navigation;
      case 'shape_star_filled':
        return Icons.star;
      case 'shape_star_outline':
        return Icons.star_border;
      // 하트/십자가는 더 이상 사용하지 않음(기존 데이터는 원으로 폴백)
      case 'shape_heart':
        return Icons.circle;
      case 'school':
        return Icons.school;
      case 'work':
        return Icons.work;
      case 'palette':
        return Icons.palette;
      case 'sports':
        return Icons.sports_soccer;
      case 'music':
        return Icons.music_note;
      case 'book':
        return Icons.book;
      case 'home':
        return Icons.home;
      case 'group':
        return Icons.group;
      default:
        Logger.error('⚠️ 알 수 없는 아이콘 이름: $iconName, 기본 아이콘 사용');
        return Icons.group;
    }
  }
}

/// 카테고리 카드의 친구 수 표시 위젯
///
/// - 캐시에 있으면 즉시 표시 (Firestore 호출 없음)
/// - 캐시에 없으면 friendIds.length를 즉시 보여주고 백그라운드에서 실제 수를 확인
class _FriendCountSubtitle extends StatefulWidget {
  final FriendCategory category;
  final Map<String, int> cache;
  final FirebaseFirestore firestore;

  const _FriendCountSubtitle({
    super.key,
    required this.category,
    required this.cache,
    required this.firestore,
  });

  @override
  State<_FriendCountSubtitle> createState() => _FriendCountSubtitleState();
}

class _FriendCountSubtitleState extends State<_FriendCountSubtitle> {
  late int _count;

  /// 카테고리 ID와 실제 구성원 집합을 함께 키로 사용한다. 같은 인원 수라도
  /// 구성원이 바뀐 경우 이전 그룹의 비동기 결과를 재사용하지 않는다.
  String get _cacheKey {
    final ids = widget.category.friendIds.toSet().toList()..sort();
    return '${widget.category.id}_${Object.hashAll(ids)}';
  }

  @override
  void initState() {
    super.initState();
    // 캐시에 있으면 즉시 반영, 없으면 리스트 길이로 임시 표시 후 백그라운드 조회
    _count = widget.cache[_cacheKey] ?? widget.category.friendIds.length;
    if (!widget.cache.containsKey(_cacheKey)) {
      _fetchAndCache();
    }
  }

  @override
  void didUpdateWidget(_FriendCountSubtitle oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldIds = oldWidget.category.friendIds.toSet().toList()..sort();
    final newKey = _cacheKey;
    final oldKey = '${oldWidget.category.id}_${Object.hashAll(oldIds)}';
    if (oldKey != newKey) {
      _count = widget.cache[newKey] ?? widget.category.friendIds.length;
      if (!widget.cache.containsKey(newKey)) {
        _fetchAndCache();
      }
    }
  }

  Future<void> _fetchAndCache() async {
    final requestedKey = _cacheKey;
    final requestedFriendIds =
        widget.category.friendIds.toSet().toList(growable: false);
    if (requestedFriendIds.isEmpty) {
      widget.cache[requestedKey] = 0;
      if (mounted && _cacheKey == requestedKey) setState(() => _count = 0);
      return;
    }
    try {
      // 병렬로 existence 체크
      final results = await Future.wait(
        requestedFriendIds.map(
          (id) => widget.firestore.collection('users').doc(id).get(),
        ),
      );
      final actual = results.where((d) => d.exists).length;
      widget.cache[requestedKey] = actual;
      if (mounted && _cacheKey == requestedKey) {
        setState(() => _count = actual);
      }
    } catch (_) {
      // 실패 시 리스트 길이 유지
    }
  }

  @override
  Widget build(BuildContext context) {
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    final baseStyle = const TextStyle(
      fontFamily: 'Inter',
      fontFamilyFallback: const ['NotoSansKR'],
      fontSize: 12,
      fontWeight: FontWeight.w500,
      color: Color(0xFF4B5563),
    );
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$_count',
            style: baseStyle.copyWith(
              fontWeight: FontWeight.w700,
              color: const Color(0xFF111827),
            ),
          ),
          TextSpan(
            text: isKo ? '명의 친구' : ' friend(s)',
            style: baseStyle,
          ),
        ],
      ),
    );
  }
}
