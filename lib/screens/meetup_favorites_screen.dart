import 'dart:io';
import 'package:flutter/material.dart';
import '../constants/app_constants.dart';
import '../l10n/app_localizations.dart';
import '../models/meetup_favorite_template.dart';
import '../services/meetup_favorites_service.dart';
import '../ui/snackbar/app_snackbar.dart';

const TextStyle _kDialogTitleStyle = TextStyle(
  fontFamily: 'Pretendard',
  fontSize: 18,
  fontWeight: FontWeight.w700,
  color: Color(0xFF111827),
);

const TextStyle _kDialogBodyStyle = TextStyle(
  fontFamily: 'Pretendard',
  fontSize: 14,
  fontWeight: FontWeight.w500,
  color: Color(0xFF6B7280),
  height: 1.35,
);

const TextStyle _kDialogButtonStyle = TextStyle(
  fontFamily: 'Pretendard',
  fontSize: 14,
  fontWeight: FontWeight.w700,
);

class MeetupFavoritesScreen extends StatefulWidget {
  final MeetupFavoriteTemplate? draftFromCreateScreen;

  const MeetupFavoritesScreen({
    super.key,
    this.draftFromCreateScreen,
  });

  @override
  State<MeetupFavoritesScreen> createState() => _MeetupFavoritesScreenState();
}

class _MeetupFavoritesScreenState extends State<MeetupFavoritesScreen> {
  final MeetupFavoritesService _service = MeetupFavoritesService();

  static const int _maxTemplates = 5;

  bool _loading = true;
  List<MeetupFavoriteTemplate> _templates = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await _service.load();
    if (!mounted) return;
    setState(() {
      _templates = list;
      _loading = false;
    });
  }

  String _categoryLabel(AppLocalizations l10n, String key) {
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

  String _timeLabel(AppLocalizations l10n, MeetupFavoriteTemplate t) {
    if (t.isUndecidedTime) return l10n.undecided;
    return t.time ?? l10n.undecided;
  }

  Future<String?> _promptTemplateName({required String initialName}) async {
    return showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return _TemplateNameDialog(initialName: initialName);
      },
    );
  }

  Future<void> _saveDraftAsTemplate() async {
    final l10n = AppLocalizations.of(context)!;
    final draft = widget.draftFromCreateScreen;
    if (draft == null) return;

    final baseName =
        (draft.name.trim().isEmpty ? draft.title.trim() : draft.name.trim()).isEmpty
            ? (Localizations.localeOf(context).languageCode == 'ko'
                ? '새 템플릿'
                : 'New template')
            : (draft.name.trim().isEmpty ? draft.title.trim() : draft.name.trim());

    final savedName = await _promptTemplateName(initialName: baseName);

    if (!mounted || savedName == null || savedName.isEmpty) return;

    // 같은 이름이 있으면 "다른 템플릿"을 늘리지 않고 업데이트로 취급
    final existingByName = _templates
        .where((t) => t.name.trim().toLowerCase() == savedName.trim().toLowerCase())
        .toList();

    final isUpdatingExisting = existingByName.isNotEmpty;
    if (!isUpdatingExisting && _templates.length >= _maxTemplates) {
      final isKo = Localizations.localeOf(context).languageCode == 'ko';
      AppSnackBar.show(
        context,
        message: isKo
            ? '즐겨찾기는 최대 $_maxTemplates개까지 저장할 수 있어요'
            : 'You can save up to $_maxTemplates favorites',
        type: AppSnackBarType.warning,
      );
      return;
    }

    final templateId = isUpdatingExisting
        ? existingByName.first.id
        : 'tmpl_${DateTime.now().microsecondsSinceEpoch}';

    final toSave = draft.copyWith(
      id: templateId,
      name: savedName,
      updatedAt: DateTime.now(),
    );
    final list = await _service.upsert(toSave);

    if (!mounted) return;
    setState(() {
      _templates = list;
    });

    AppSnackBar.show(
      context,
      message: Localizations.localeOf(context).languageCode == 'ko'
          ? '즐겨찾기에 저장했어요'
          : 'Saved to favorites',
      type: AppSnackBarType.success,
    );
  }

  Future<void> _confirmDelete(MeetupFavoriteTemplate t) async {
    final l10n = AppLocalizations.of(context)!;
    final isKo = Localizations.localeOf(context).languageCode == 'ko';

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: Colors.white,
        elevation: 8,
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
        actionsPadding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
        title: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.delete_outline_rounded,
                color: Color(0xFFEF4444),
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Text(isKo ? '삭제할까요?' : 'Delete?', style: _kDialogTitleStyle),
          ],
        ),
        content: Text(
          isKo ? '이 템플릿을 삭제하면 되돌릴 수 없어요.' : 'This template will be permanently deleted.',
          style: _kDialogBodyStyle,
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Colors.grey.shade300, width: 1),
                    ),
                    backgroundColor: Colors.white,
                  ),
                  child: Text(
                    l10n.cancel,
                    style: _kDialogButtonStyle.copyWith(color: const Color(0xFF6B7280)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    backgroundColor: const Color(0xFFEF4444),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(l10n.delete, style: _kDialogButtonStyle),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (!mounted || ok != true) return;
    final list = await _service.deleteById(t.id);
    if (!mounted) return;
    setState(() => _templates = list);
  }

  void _applyTemplate(MeetupFavoriteTemplate t) {
    Navigator.of(context).pop(t);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isKo = Localizations.localeOf(context).languageCode == 'ko';

    final canSaveDraft = widget.draftFromCreateScreen != null &&
        (widget.draftFromCreateScreen!.title.trim().isNotEmpty ||
            widget.draftFromCreateScreen!.location.trim().isNotEmpty ||
            widget.draftFromCreateScreen!.description.trim().isNotEmpty);

    return Scaffold(
      backgroundColor: const Color(0xFFFAFBFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF1A1A1A)),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          isKo ? '즐겨찾기' : 'Favorites',
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
          child: Container(height: 1, color: const Color(0xFFE6EAF0)),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                children: [
                  if (canSaveDraft) ...[
                    SizedBox(
                      height: 52,
                      child: ElevatedButton.icon(
                        onPressed: _saveDraftAsTemplate,
                        icon: const Icon(Icons.star_rounded),
                        label: Text(isKo ? '현재 입력값 저장' : 'Save current'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.pointColor,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  if (_templates.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 24),
                      child: Center(
                        child: Text(
                          isKo
                              ? '저장된 즐겨찾기가 없어요'
                              : 'No saved favorites yet',
                          style: const TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            height: 1.3,
                            color: Color(0xFF6B7280),
                          ),
                        ),
                      ),
                    )
                  else ...[
                    for (final t in _templates) ...[
                      _TemplateCard(
                        template: t,
                        categoryLabel: _categoryLabel(l10n, t.categoryKey),
                        timeLabel: _timeLabel(l10n, t),
                        onTap: () => _applyTemplate(t),
                        onDelete: () => _confirmDelete(t),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ],
                ],
              ),
            ),
    );
  }
}

class _TemplateCard extends StatelessWidget {
  final MeetupFavoriteTemplate template;
  final String categoryLabel;
  final String timeLabel;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _TemplateCard({
    required this.template,
    required this.categoryLabel,
    required this.timeLabel,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    final title = template.name.trim().isNotEmpty
        ? template.name
        : (template.title.trim().isNotEmpty
            ? template.title
            : (isKo ? '(제목 없음)' : '(No title)'));

    final subtitleParts = <String>[
      if (template.location.trim().isNotEmpty) template.location.trim(),
      categoryLabel,
      timeLabel,
      '${template.maxParticipants}${AppLocalizations.of(context)!.people}',
    ];

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE6EAF0)),
          ),
          child: Row(
            children: [
              _ThumbnailPreview(
                path: template.thumbnailImagePath,
                url: template.thumbnailImageUrl,
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
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                        color: Color(0xFF111827),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitleParts.join(' · '),
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                        color: Color(0xFF6B7280),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline_rounded),
                color: const Color(0xFF9CA3AF),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThumbnailPreview extends StatelessWidget {
  final String? path;
  final String? url;

  const _ThumbnailPreview({required this.path, required this.url});

  @override
  Widget build(BuildContext context) {
    final p = path?.trim();
    final file = (p == null || p.isEmpty) ? null : File(p);
    final exists = file != null && file.existsSync();
    final u = url?.trim();
    final hasUrl = u != null && u.isNotEmpty;

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          border: Border.all(color: const Color(0xFFE6EAF0)),
        ),
        child: exists
            ? Image.file(
                file!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.image_not_supported_outlined,
                  color: Color(0xFF9CA3AF),
                  size: 22,
                ),
              )
            : hasUrl
                ? Image.network(
                    u!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.image_not_supported_outlined,
                      color: Color(0xFF9CA3AF),
                      size: 22,
                    ),
                  )
                : const Icon(
                    Icons.image_outlined,
                    color: Color(0xFF9CA3AF),
                    size: 22,
                  ),
      ),
    );
  }
}

class _TemplateNameDialog extends StatefulWidget {
  final String initialName;

  const _TemplateNameDialog({required this.initialName});

  @override
  State<_TemplateNameDialog> createState() => _TemplateNameDialogState();
}

class _TemplateNameDialogState extends State<_TemplateNameDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialName);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isKo = Localizations.localeOf(context).languageCode == 'ko';

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: Colors.white,
      elevation: 8,
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      actionsPadding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
      title: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AppColors.pointColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.star_rounded,
              color: AppColors.pointColor,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Text(isKo ? '템플릿 저장' : 'Save template', style: _kDialogTitleStyle),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(isKo ? '템플릿 이름' : 'Template name', style: _kDialogBodyStyle),
          const SizedBox(height: 10),
          TextField(
            controller: _controller,
            autofocus: true,
            textInputAction: TextInputAction.done,
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF111827),
            ),
            decoration: InputDecoration(
              hintText: isKo ? '예) 오버피팅 모임' : 'e.g. Outfitting meetup',
              hintStyle: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: Color(0xFF9CA3AF),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.pointColor, width: 1.5),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              filled: true,
              fillColor: const Color(0xFFF9FAFB),
            ),
            onSubmitted: (_) {
              final name = _controller.text.trim();
              if (name.isEmpty) return;
              Navigator.of(context).pop(name);
            },
          ),
        ],
      ),
      actions: [
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _controller,
          builder: (context, value, _) {
            final canSave = value.text.trim().isNotEmpty;
            return Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.grey.shade300, width: 1),
                      ),
                      backgroundColor: Colors.white,
                    ),
                    child: Text(
                      l10n.cancel,
                      style: _kDialogButtonStyle.copyWith(color: const Color(0xFF6B7280)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: !canSave
                        ? null
                        : () => Navigator.of(context).pop(value.text.trim()),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      backgroundColor: AppColors.pointColor,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      disabledBackgroundColor: const Color(0xFFE5E7EB),
                    ),
                    child: Text(l10n.save, style: _kDialogButtonStyle),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

