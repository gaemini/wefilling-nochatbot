// lib/widgets/highlight_reels.dart
// 하이라이트 릴 컴포넌트
// 수평 스크롤 가능한 썸네일 표시
// 64dp diameter 원형 썸네일

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/feature_flag_service.dart';

class HighlightItem {
  final String id;
  final String title;
  final String? thumbnailUrl;
  final Color? backgroundColor;

  const HighlightItem({
    required this.id,
    required this.title,
    this.thumbnailUrl,
    this.backgroundColor,
  });
}

class HighlightReels extends StatelessWidget {
  final List<HighlightItem> highlights;
  final Function(HighlightItem)? onHighlightTap;
  final VoidCallback? onAddHighlight;
  final bool canEdit;

  const HighlightReels({
    Key? key,
    required this.highlights,
    this.onHighlightTap,
    this.onAddHighlight,
    this.canEdit = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Feature Flag 체크
    if (!FeatureFlagService().isFeatureEnabled(FeatureFlagService.FEATURE_PROFILE_GRID)) {
      return const SizedBox.shrink();
    }

    // 하이라이트가 없고 편집 권한도 없으면 숨김
    if (highlights.isEmpty && !canEdit) {
      return const SizedBox.shrink();
    }

    return Container(
      height: 100, // 64dp 썸네일 + 여백
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: highlights.length + (canEdit ? 1 : 0),
        itemBuilder: (context, index) {
          // 마지막 아이템이 추가 버튼인지 확인
          if (canEdit && index == highlights.length) {
            return _buildAddButton(context);
          }

          final highlight = highlights[index];
          return _buildHighlightItem(context, highlight);
        },
      ),
    );
  }

  /// 개별 하이라이트 아이템 구성
  Widget _buildHighlightItem(BuildContext context, HighlightItem highlight) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: Column(
        children: [
          // 64dp 원형 썸네일
          GestureDetector(
            onTap: () => onHighlightTap?.call(highlight),
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: colorScheme.outline.withOpacity(0.2),
                  width: 1.5,
                ),
              ),
              child: ClipOval(
                child: _buildThumbnail(highlight),
              ),
            ),
          ),
          
          const SizedBox(height: 8),
          
          // 하이라이트 제목
          SizedBox(
            width: 64,
            child: Text(
              highlight.title,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 11,
                color: colorScheme.onSurface.withOpacity(0.8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 썸네일 이미지 또는 기본 배경 구성
  Widget _buildThumbnail(HighlightItem highlight) {
    if (highlight.thumbnailUrl != null && highlight.thumbnailUrl!.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: highlight.thumbnailUrl!,
        fit: BoxFit.cover,
        placeholder: (context, url) => Container(
          color: highlight.backgroundColor ?? Colors.grey[200],
          child: const Center(
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
        errorWidget: (context, url, error) => _buildDefaultThumbnail(highlight),
      );
    } else {
      return _buildDefaultThumbnail(highlight);
    }
  }

  /// 기본 썸네일 (이미지가 없을 때)
  Widget _buildDefaultThumbnail(HighlightItem highlight) {
    return Container(
      color: highlight.backgroundColor ?? Colors.grey[200],
      child: Icon(
        Icons.collections_outlined,
        size: 24,
        color: Colors.grey[600],
      ),
    );
  }

  /// 하이라이트 추가 버튼
  Widget _buildAddButton(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: Column(
        children: [
          // 64dp 원형 추가 버튼
          GestureDetector(
            onTap: onAddHighlight,
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: colorScheme.outline.withOpacity(0.3),
                  width: 1.5,
                  style: BorderStyle.solid,
                ),
                color: colorScheme.surface,
              ),
              child: Icon(
                Icons.add,
                size: 24,
                color: colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
          ),
          
          const SizedBox(height: 8),
          
          // '새 하이라이트' 텍스트
          SizedBox(
            width: 64,
            child: Text(
              '새로 만들기',
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 11,
                color: colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 하이라이트 생성을 위한 다이얼로그
class CreateHighlightDialog extends StatefulWidget {
  final Function(String title)? onCreateHighlight;

  const CreateHighlightDialog({
    Key? key,
    this.onCreateHighlight,
  }) : super(key: key);

  @override
  State<CreateHighlightDialog> createState() => _CreateHighlightDialogState();
}

class _CreateHighlightDialogState extends State<CreateHighlightDialog> {
  final TextEditingController _titleController = TextEditingController();

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('새 하이라이트'),
      content: TextField(
        controller: _titleController,
        decoration: const InputDecoration(
          labelText: '하이라이트 제목',
          hintText: '예: 여행, 음식, 취미 등',
        ),
        maxLength: 20,
        autofocus: true,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        ElevatedButton(
          onPressed: () {
            final title = _titleController.text.trim();
            if (title.isNotEmpty) {
              widget.onCreateHighlight?.call(title);
              Navigator.pop(context);
            }
          },
          child: const Text('만들기'),
        ),
      ],
    );
  }
}
