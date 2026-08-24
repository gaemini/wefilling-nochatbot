import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/post_category.dart';
import '../../utils/responsive_helper.dart';

bool _isKorean(BuildContext context) =>
    Localizations.localeOf(context).languageCode.toLowerCase() == 'ko';

/// 포스트 생성·수정 화면 안에서 바로 선택하는 다중 태그 목록입니다.
///
/// 별도의 시트나 두 번째 화면을 열지 않으므로 사용자는 전체 선택지를 한눈에
/// 확인할 수 있고, 태그를 누르는 즉시 선택 상태가 저장 화면에 반영됩니다.
class PostCategorySelector extends StatelessWidget {
  const PostCategorySelector({
    super.key,
    required this.selected,
    required this.onChanged,
    this.enabled = true,
    this.showError = false,
    this.showHeader = true,
  });

  final Set<PostCategory> selected;
  final ValueChanged<Set<PostCategory>> onChanged;
  final bool enabled;
  final bool showError;
  final bool showHeader;

  void _toggle(PostCategory tag) {
    if (!enabled) return;
    final next = Set<PostCategory>.from(selected);
    if (!next.remove(tag)) next.add(tag);
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isKorean = _isKorean(context);

    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.25,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showHeader) ...[
            Text(
              isKorean ? '태그' : 'Tags',
              style: TextStyle(
                fontFamily: 'Inter',
                fontFamilyFallback: const ['NotoSansKR'],
                fontSize: context.rf(15).clamp(14, 16).toDouble(),
                fontWeight: FontWeight.w800,
                color: const Color(0xFF111827),
              ),
            ),
            SizedBox(height: context.rs(5).clamp(4, 7).toDouble()),
            Text(
              isKorean
                  ? '글과 관련된 태그를 모두 선택해 주세요.'
                  : 'Select all tags that match your post.',
              style: TextStyle(
                fontFamily: 'Inter',
                fontFamilyFallback: const ['NotoSansKR'],
                fontSize: context.rf(12).clamp(11, 13).toDouble(),
                fontWeight: FontWeight.w500,
                color: const Color(0xFF667085),
                height: 1.35,
              ),
            ),
            SizedBox(height: context.rs(10).clamp(8, 12).toDouble()),
          ],
          LayoutBuilder(
            builder: (context, constraints) => Wrap(
              spacing: context.rs(7).clamp(6, 9).toDouble(),
              runSpacing: context.rs(7).clamp(6, 9).toDouble(),
              children: PostCategory.ordered
                  .map(
                    (tag) => _PostTagChoice(
                      label: tag.label(l10n),
                      selected: selected.contains(tag),
                      enabled: enabled,
                      maxWidth: constraints.maxWidth,
                      onTap: () => _toggle(tag),
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
          if (showError) ...[
            const SizedBox(height: 7),
            Text(
              isKorean ? '태그를 한 개 이상 선택해 주세요.' : 'Choose at least one tag.',
              style: TextStyle(
                fontFamily: 'Inter',
                fontFamilyFallback: const ['NotoSansKR'],
                fontSize: context.rf(12).clamp(11, 13).toDouble(),
                fontWeight: FontWeight.w700,
                color: const Color(0xFFB42318),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PostTagChoice extends StatelessWidget {
  const _PostTagChoice({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.maxWidth,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final double maxWidth;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = !enabled
        ? const Color(0xFF98A2B3)
        : selected
            ? const Color(0xFF157DB8)
            : const Color(0xFF475467);

    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: '#$label',
      child: Material(
        color: selected ? const Color(0xFFEAF6FC) : const Color(0xFFF5F6F8),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(18),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: 40, maxWidth: maxWidth),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    selected ? Icons.check_circle_rounded : Icons.tag_rounded,
                    size: context.ri(17).clamp(16, 18).toDouble(),
                    color: foreground,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontFamilyFallback: const ['NotoSansKR'],
                        fontSize: context.rf(13).clamp(12, 14).toDouble(),
                        fontWeight:
                            selected ? FontWeight.w800 : FontWeight.w600,
                        color: foreground,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
