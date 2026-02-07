import 'package:flutter/material.dart';
import '../constants/app_constants.dart';
import '../l10n/app_localizations.dart';
import '../services/recommended_places_service.dart';

class MeetupCategorySelectionResult {
  final String categoryKey;
  final String? placeUrl;
  final String? placeMainImageUrl;
  final String? placeMapImageUrl;

  const MeetupCategorySelectionResult({
    required this.categoryKey,
    this.placeUrl,
    this.placeMainImageUrl,
    this.placeMapImageUrl,
  });
}

class MeetupCategorySelectScreen extends StatefulWidget {
  final String? initialSelectedCategoryKey;

  const MeetupCategorySelectScreen({
    super.key,
    required this.initialSelectedCategoryKey,
  });

  @override
  State<MeetupCategorySelectScreen> createState() =>
      _MeetupCategorySelectScreenState();
}

class _MeetupCategorySelectScreenState extends State<MeetupCategorySelectScreen> {
  String? _selectedCategoryKey;

  final RecommendedPlacesService _recommendedPlacesService =
      RecommendedPlacesService();
  List<RecommendedPlace> _recommendedPlaces = [];
  bool _isLoadingPlaces = false;

  static const List<String> _categoryKeys = [
    'study',
    'meal',
    'cafe',
    'drink',
    'culture',
  ];

  @override
  void initState() {
    super.initState();
    _selectedCategoryKey = widget.initialSelectedCategoryKey;
    if (_selectedCategoryKey != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadRecommendedPlaces(_selectedCategoryKey!);
      });
    }
  }

  String _labelForKey(AppLocalizations l10n, String key) {
    switch (key) {
      case 'study':
        return l10n.study;
      case 'meal':
        return l10n.meal;
      case 'cafe':
        return l10n.cafe;
      case 'drink':
        return l10n.drink;
      case 'culture':
        return l10n.culture;
      default:
        return key;
    }
  }

  Future<void> _loadRecommendedPlaces(String categoryKey) async {
    setState(() {
      _isLoadingPlaces = true;
    });

    final places =
        await _recommendedPlacesService.getRecommendedPlaces(categoryKey);

    if (!mounted) return;
    setState(() {
      _recommendedPlaces = places;
      _isLoadingPlaces = false;
    });
  }

  Widget _buildCategoryChip(AppLocalizations l10n, String key) {
    final isSelected = _selectedCategoryKey == key;
    return InkWell(
      onTap: () {
        if (_selectedCategoryKey == key) return;
        setState(() {
          _selectedCategoryKey = key;
        });
        _loadRecommendedPlaces(key);
      },
      borderRadius: BorderRadius.circular(18),
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? AppColors.pointColor : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected ? AppColors.pointColor : const Color(0xFFE1E6EE),
            width: 1,
          ),
        ),
        child: Text(
          _labelForKey(l10n, key),
          style: TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 13,
            fontWeight: FontWeight.w700,
            height: 1.0,
            color: isSelected ? Colors.white : const Color(0xFF111827),
          ),
        ),
      ),
    );
  }

  Widget _buildRecommendedPlacesSection(AppLocalizations l10n) {
    // 선택 전: 빈 상태를 자연스럽게 안내
    if (_selectedCategoryKey == null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F9FA),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE1E6EE)),
        ),
        child: Text(
          l10n.pleaseSelectCategory,
          style: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 14,
            fontWeight: FontWeight.w500,
            height: 1.25,
            color: Color(0xFF6B7280),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.recommendedPlaces,
          style: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 14,
            fontWeight: FontWeight.w700,
            height: 1.2,
            letterSpacing: -0.1,
            color: Color(0xFFFF8A65),
          ),
        ),
        const SizedBox(height: 12),
        if (_isLoadingPlaces)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else if (_recommendedPlaces.isEmpty)
          Text(
            l10n.noRecommendedPlaces,
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 14,
              fontWeight: FontWeight.w500,
              height: 1.25,
              color: Color(0xFF6B7280),
            ),
          )
        else
          Column(
            children: [
              ...List.generate(
                _recommendedPlaces.length,
                (index) => _buildPlaceItem(_recommendedPlaces[index], index + 1),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildPlaceItem(RecommendedPlace place, int displayIndex) {
    final thumbUrl = place.thumbnailUrl;
    final hasImage = (thumbUrl ?? '').trim().isNotEmpty;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: _selectedCategoryKey == null
            ? null
            : () {
                // 추천 장소를 누르면: 선택된 카테고리 + URL을 함께 반환해서
                // 모임 생성 화면의 "장소" 필드에 자동 입력되도록 한다.
                Navigator.of(context).pop(
                  MeetupCategorySelectionResult(
                    categoryKey: _selectedCategoryKey!,
                    placeUrl: place.url,
                    placeMainImageUrl:
                        (place.mainImageUrl?.trim().isNotEmpty == true)
                            ? place.mainImageUrl!.trim()
                            : (place.imageUrl?.trim().isNotEmpty == true)
                                ? place.imageUrl!.trim()
                                : null,
                    placeMapImageUrl:
                        (place.mapImageUrl?.trim().isNotEmpty == true)
                            ? place.mapImageUrl!.trim()
                            : null,
                  ),
                );
              },
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: const Color(0xFFE5E7EB),
                  ),
                ),
                child: Text(
                  '$displayIndex',
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    height: 1.0,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  place.name,
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    height: 1.25,
                    color: Color(0xFF111827),
                  ),
                ),
              ),
              if (hasImage) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: SizedBox(
                    width: 72,
                    height: 72,
                    child: Image.network(
                      thumbUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: const Color(0xFFF3F4F6),
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.image_not_supported_outlined,
                          size: 20,
                          color: Color(0xFF9CA3AF),
                        ),
                      ),
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;
                        return Container(
                          color: const Color(0xFFF3F4F6),
                          alignment: Alignment.center,
                          child: const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 2),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: const Color(0xFFFAFBFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF1A1A1A)),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          l10n.selectCategoryRequired,
          style: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 20,
            fontWeight: FontWeight.w700,
            height: 1.2,
            letterSpacing: -0.2,
            color: Color(0xFF111827),
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 1,
            color: const Color(0xFFE6EAF0),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 카테고리 버튼: 한 줄(가로 스크롤)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: [
                  ..._categoryKeys.asMap().entries.map((entry) {
                    final index = entry.key;
                    final key = entry.value;
                    return Padding(
                      padding: EdgeInsets.only(
                        right: index == _categoryKeys.length - 1 ? 0 : 10,
                      ),
                      child: _buildCategoryChip(l10n, key),
                    );
                  }).toList(),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // 추천 장소: 이 화면에서 모두 표시
            _buildRecommendedPlacesSection(l10n),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: SizedBox(
            height: 52,
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _selectedCategoryKey == null
                  ? null
                  : () => Navigator.of(context).pop(
                        MeetupCategorySelectionResult(
                          categoryKey: _selectedCategoryKey!,
                        ),
                      ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.pointColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
                disabledBackgroundColor: const Color(0xFFE5E7EB),
                disabledForegroundColor: const Color(0xFF9CA3AF),
              ),
              child: Text(
                l10n.done,
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  height: 1.1,
                  letterSpacing: -0.1,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

