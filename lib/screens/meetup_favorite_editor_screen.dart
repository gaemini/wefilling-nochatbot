import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../l10n/app_localizations.dart';
import '../constants/meetup_limits.dart';
import '../models/friend_category.dart';
import '../models/meetup_favorite_template.dart';
import '../services/friend_category_service.dart';
import '../ui/sheets/participant_count_sheet.dart';
import '../ui/snackbar/app_snackbar.dart';
import '../utils/responsive_helper.dart';
import 'meetup_category_select_screen.dart';
import 'meetup_visibility_group_select_screen.dart';

class MeetupFavoriteEditorScreen extends StatefulWidget {
  final MeetupFavoriteTemplate? template;

  const MeetupFavoriteEditorScreen({
    super.key,
    this.template,
  });

  @override
  State<MeetupFavoriteEditorScreen> createState() =>
      _MeetupFavoriteEditorScreenState();
}

class _MeetupFavoriteEditorScreenState
    extends State<MeetupFavoriteEditorScreen> {
  final _titleController = TextEditingController();
  final _locationController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _friendCategoryService = FriendCategoryService();
  final _imagePicker = ImagePicker();

  List<FriendCategory> _friendCategories = const <FriendCategory>[];
  List<String> _selectedCategoryIds = <String>[];
  String _visibility = 'public';
  String? _categoryKey;
  bool _isUndecidedTime = true;
  String? _time;
  int _maxParticipants = 3;
  String? _thumbnailImagePath;
  String? _thumbnailImageUrl;
  bool _isSaving = false;

  bool get _isEditing => widget.template != null;

  @override
  void initState() {
    super.initState();
    final template = widget.template;
    if (template != null) {
      _titleController.text = template.title;
      _locationController.text = template.location;
      _descriptionController.text = template.description;
      _visibility =
          const {'public', 'friends', 'category'}.contains(template.visibility)
              ? template.visibility
              : 'public';
      _selectedCategoryIds = List<String>.from(template.visibleToCategoryIds);
      final rawCategoryKey = template.categoryKey.trim().toLowerCase();
      _categoryKey = switch (rawCategoryKey) {
        '' => null,
        'drink' || 'drinks' || '술' || '행아웃' => 'hangout',
        _ => rawCategoryKey,
      };
      _isUndecidedTime = template.isUndecidedTime;
      _time = template.time;
      _maxParticipants =
          meetupParticipantOptions.contains(template.maxParticipants)
              ? template.maxParticipants
              : 3;
      _thumbnailImagePath = template.thumbnailImagePath;
      _thumbnailImageUrl = template.thumbnailImageUrl;
    }
    _loadFriendCategories();
  }

  Future<void> _loadFriendCategories() async {
    final categories = await _friendCategoryService
        .getCategoriesStream()
        .first
        .catchError((_) => <FriendCategory>[]);
    if (!mounted) return;
    setState(() => _friendCategories = categories);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _locationController.dispose();
    _descriptionController.dispose();
    _friendCategoryService.dispose();
    super.dispose();
  }

  double _horizontalPadding(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < 360) return 14;
    if (width < 600) return 18;
    return 24;
  }

  String _categoryLabel(AppLocalizations l10n, String? key) {
    switch (key) {
      case 'study':
        return l10n.study;
      case 'meal':
        return l10n.meal;
      case 'cafe':
        return l10n.cafe;
      case 'hangout':
        return l10n.hangout;
      case 'culture':
        return l10n.culture;
      case 'etc':
        return l10n.other;
      default:
        return l10n.pleaseSelectCategory;
    }
  }

  String _timeLabel(AppLocalizations l10n) {
    if (_isUndecidedTime || _time == null || _time!.isEmpty) {
      return l10n.undecided;
    }
    return _time!;
  }

  Future<void> _selectGroups() async {
    if (_friendCategories.isEmpty) {
      final isKo = Localizations.localeOf(context).languageCode == 'ko';
      AppSnackBar.show(
        context,
        message: isKo ? '그룹 목록을 불러오는 중입니다.' : 'Groups are still loading.',
        type: AppSnackBarType.info,
      );
      return;
    }

    final result = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(
        builder: (_) => MeetupVisibilityGroupSelectScreen(
          categories: _friendCategories,
          initialSelectedCategoryIds: _selectedCategoryIds,
        ),
      ),
    );
    if (!mounted || result == null) return;
    setState(() {
      _visibility = 'category';
      _selectedCategoryIds = result;
    });
  }

  Future<void> _selectCategory() async {
    final result =
        await Navigator.of(context).push<MeetupCategorySelectionResult>(
      MaterialPageRoute(
        builder: (_) => MeetupCategorySelectScreen(
          initialSelectedCategoryKey: _categoryKey,
        ),
      ),
    );
    if (!mounted || result == null) return;
    setState(() {
      _categoryKey = result.categoryKey;
      if (result.placeUrl?.trim().isNotEmpty == true) {
        _locationController.text = result.placeUrl!.trim();
      }
      if (result.placeMainImageUrl?.trim().isNotEmpty == true) {
        _thumbnailImagePath = null;
        _thumbnailImageUrl = result.placeMainImageUrl!.trim();
      }
    });
  }

  Future<void> _selectTime() async {
    final l10n = AppLocalizations.of(context)!;
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.schedule_outlined, size: 21),
                title: Text(
                  l10n.undecided,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontFamilyFallback: const ['NotoSansKR'],
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onTap: () => Navigator.of(sheetContext).pop('undecided'),
              ),
              ListTile(
                leading: const Icon(Icons.access_time_rounded, size: 21),
                title: Text(
                  isKo ? '시간 선택' : 'Choose a time',
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontFamilyFallback: const ['NotoSansKR'],
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onTap: () => Navigator.of(sheetContext).pop('pick'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'undecided') {
      setState(() {
        _isUndecidedTime = true;
        _time = null;
      });
      return;
    }

    final parts = _time?.split(':');
    final initial = parts != null && parts.length == 2
        ? TimeOfDay(
            hour: int.tryParse(parts[0]) ?? TimeOfDay.now().hour,
            minute: int.tryParse(parts[1]) ?? TimeOfDay.now().minute,
          )
        : TimeOfDay.now();
    final selected =
        await showTimePicker(context: context, initialTime: initial);
    if (!mounted || selected == null) return;
    setState(() {
      _isUndecidedTime = false;
      _time = '${selected.hour.toString().padLeft(2, '0')}:'
          '${selected.minute.toString().padLeft(2, '0')}';
    });
  }

  Future<void> _selectMaxParticipants() async {
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    final selected = await showParticipantCountSheet(
      context: context,
      selectedValue: _maxParticipants,
      options: meetupParticipantOptions,
      title: isKo ? '최대 인원' : 'Max participants',
      itemLabel: (count) => isKo ? '$count명' : '$count people',
    );
    if (!mounted || selected == null || selected == _maxParticipants) return;
    setState(() => _maxParticipants = selected);
  }

  Future<void> _pickThumbnail() async {
    final image = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 88,
      maxWidth: 1600,
    );
    if (!mounted || image == null) return;
    setState(() {
      _thumbnailImagePath = image.path;
      _thumbnailImageUrl = null;
    });
  }

  Future<String?> _persistThumbnailPath() async {
    final path = _thumbnailImagePath?.trim();
    if (path == null || path.isEmpty) return null;
    try {
      final source = File(path);
      if (!source.existsSync()) return null;
      final supportDirectory = await getApplicationSupportDirectory();
      final imageDirectory = Directory(
        '${supportDirectory.path}${Platform.pathSeparator}'
        'meetup_favorite_images',
      );
      if (source.path.startsWith(imageDirectory.path)) return source.path;
      await imageDirectory.create(recursive: true);
      final fileName = source.uri.pathSegments.isEmpty
          ? 'favorite_image.jpg'
          : source.uri.pathSegments.last;
      final dotIndex = fileName.lastIndexOf('.');
      final extension = dotIndex >= 0 ? fileName.substring(dotIndex) : '.jpg';
      final destination = File(
        '${imageDirectory.path}${Platform.pathSeparator}'
        'favorite_${DateTime.now().microsecondsSinceEpoch}$extension',
      );
      return (await source.copy(destination.path)).path;
    } catch (_) {
      return path;
    }
  }

  Future<void> _save() async {
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    final title = _titleController.text.trim();
    final location = _locationController.text.trim();
    if (title.isEmpty || location.isEmpty || _categoryKey == null) {
      AppSnackBar.show(
        context,
        message: isKo
            ? '제목, 카테고리, 장소를 모두 입력해주세요.'
            : 'Enter a title, category, and location.',
        type: AppSnackBarType.warning,
      );
      return;
    }
    if (_visibility == 'category' && _selectedCategoryIds.isEmpty) {
      AppSnackBar.show(
        context,
        message: isKo ? '공개할 그룹을 선택해주세요.' : 'Select at least one group.',
        type: AppSnackBarType.warning,
      );
      return;
    }

    setState(() => _isSaving = true);
    final persistedThumbnailPath = await _persistThumbnailPath();
    if (!mounted) return;
    final old = widget.template;
    Navigator.of(context).pop(
      MeetupFavoriteTemplate(
        id: old?.id ?? 'tmpl_${DateTime.now().microsecondsSinceEpoch}',
        name: title,
        title: title,
        description: _descriptionController.text.trim(),
        location: location,
        categoryKey: _categoryKey!,
        visibility: _visibility,
        visibleToCategoryIds: _visibility == 'category'
            ? List<String>.from(_selectedCategoryIds)
            : const <String>[],
        isUndecidedTime: _isUndecidedTime,
        time: _isUndecidedTime ? null : _time,
        maxParticipants: _maxParticipants,
        thumbnailImagePath: persistedThumbnailPath,
        thumbnailImageUrl: _thumbnailImageUrl,
        updatedAt: DateTime.now(),
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: TextStyle(
        fontFamily: 'Inter',
        fontFamilyFallback: const ['NotoSansKR'],
        fontSize: context.rf(15).clamp(14, 16).toDouble(),
        fontWeight: FontWeight.w700,
        color: const Color(0xFF111827),
      ),
    );
  }

  InputDecoration _underlineDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(
        fontFamily: 'Inter',
        fontFamilyFallback: const ['NotoSansKR'],
        fontSize: 14,
        color: Color(0xFF98A2B3),
      ),
      enabledBorder: const UnderlineInputBorder(
        borderSide: BorderSide(color: Color(0xFFEAECF0)),
      ),
      focusedBorder: const UnderlineInputBorder(
        borderSide: BorderSide(color: Color(0xFF667085), width: 1.3),
      ),
      contentPadding: const EdgeInsets.symmetric(vertical: 11),
    );
  }

  Widget _visibilityOption({
    required String value,
    required String label,
    required VoidCallback onTap,
  }) {
    final selected = _visibility == value;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 46),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected
                    ? const Color(0xFF344054)
                    : const Color(0xFFEAECF0),
                width: selected ? 2 : 1,
              ),
            ),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Inter',
              fontFamilyFallback: const ['NotoSansKR'],
              fontSize: context.rf(13).clamp(12, 14).toDouble(),
              fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              color:
                  selected ? const Color(0xFF111827) : const Color(0xFF667085),
            ),
          ),
        ),
      ),
    );
  }

  Widget _selectionRow({
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 50),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFFEAECF0))),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontFamilyFallback: const ['NotoSansKR'],
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF667085),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
            const Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: Color(0xFF98A2B3),
            ),
          ],
        ),
      ),
    );
  }

  Widget _thumbnailPreview() {
    final path = _thumbnailImagePath?.trim();
    final file = path == null || path.isEmpty ? null : File(path);
    final url = _thumbnailImageUrl?.trim();
    Widget child = const Icon(
      Icons.image_outlined,
      size: 22,
      color: Color(0xFF98A2B3),
    );
    if (file != null && file.existsSync()) {
      child = Image.file(file, fit: BoxFit.cover);
    } else if (url != null && url.isNotEmpty) {
      child = Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const Icon(
          Icons.image_not_supported_outlined,
          size: 22,
          color: Color(0xFF98A2B3),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: ColoredBox(
        color: const Color(0xFFF2F4F7),
        child: SizedBox(width: 46, height: 46, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    final horizontalPadding = _horizontalPadding(context);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        toolbarHeight: context.rh(56, min: 54, max: 60),
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back_rounded),
          color: const Color(0xFF111827),
          iconSize: 22,
        ),
        title: Text(
          _isEditing
              ? (isKo ? '즐겨찾기 수정' : 'Edit Favorite')
              : (isKo ? '새 즐겨찾기' : 'New Favorite'),
          style: TextStyle(
            fontFamily: 'Inter',
            fontFamilyFallback: const ['NotoSansKR'],
            fontSize: context.rf(18).clamp(16, 19).toDouble(),
            fontWeight: FontWeight.w700,
            color: const Color(0xFF111827),
          ),
        ),
      ),
      body: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(
          horizontalPadding,
          12,
          horizontalPadding,
          32,
        ),
        children: [
          _sectionTitle(isKo ? '공개 범위' : 'Visibility'),
          const SizedBox(height: 4),
          Row(
            children: [
              _visibilityOption(
                value: 'public',
                label: isKo ? '전체' : 'All',
                onTap: () => setState(() {
                  _visibility = 'public';
                  _selectedCategoryIds.clear();
                }),
              ),
              _visibilityOption(
                value: 'friends',
                label: isKo ? '모든 친구' : 'Friends',
                onTap: () => setState(() {
                  _visibility = 'friends';
                  _selectedCategoryIds.clear();
                }),
              ),
              _visibilityOption(
                value: 'category',
                label: _selectedCategoryIds.isEmpty
                    ? (isKo ? '그룹' : 'Groups')
                    : (isKo
                        ? '그룹 ${_selectedCategoryIds.length}'
                        : 'Groups ${_selectedCategoryIds.length}'),
                onTap: _selectGroups,
              ),
            ],
          ),
          SizedBox(height: context.rs(22).clamp(18, 26).toDouble()),
          _sectionTitle(isKo ? '제목' : 'Title'),
          TextField(
            controller: _titleController,
            maxLength: 60,
            textInputAction: TextInputAction.next,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontFamilyFallback: const ['NotoSansKR'],
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
            decoration: _underlineDecoration(
              isKo ? '반복해서 사용할 밋업 제목' : 'Meetup title',
            ).copyWith(counterText: ''),
          ),
          SizedBox(height: context.rs(20).clamp(18, 24).toDouble()),
          _selectionRow(
            label: isKo ? '카테고리' : 'Category',
            value: _categoryLabel(l10n, _categoryKey),
            onTap: _selectCategory,
          ),
          SizedBox(height: context.rs(20).clamp(18, 24).toDouble()),
          _sectionTitle(isKo ? '장소' : 'Location'),
          TextField(
            controller: _locationController,
            textInputAction: TextInputAction.next,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontFamilyFallback: const ['NotoSansKR'],
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
            decoration: _underlineDecoration(
              isKo ? '밋업 장소' : 'Meetup location',
            ),
          ),
          SizedBox(height: context.rs(20).clamp(18, 24).toDouble()),
          _selectionRow(
            label: isKo ? '시간' : 'Time',
            value: _timeLabel(l10n),
            onTap: _selectTime,
          ),
          SizedBox(height: context.rs(20).clamp(18, 24).toDouble()),
          _selectionRow(
            label: isKo ? '최대 인원' : 'Max participants',
            value: isKo ? '$_maxParticipants명' : '$_maxParticipants people',
            onTap: _selectMaxParticipants,
          ),
          SizedBox(height: context.rs(20).clamp(18, 24).toDouble()),
          _sectionTitle(isKo ? '설명 (선택)' : 'Description (optional)'),
          TextField(
            controller: _descriptionController,
            minLines: 3,
            maxLines: 5,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontFamilyFallback: const ['NotoSansKR'],
              fontSize: 14,
              height: 1.45,
            ),
            decoration: _underlineDecoration(
              isKo ? '밋업 설명' : 'Meetup description',
            ),
          ),
          SizedBox(height: context.rs(20).clamp(18, 24).toDouble()),
          InkWell(
            onTap: _pickThumbnail,
            child: Container(
              constraints: const BoxConstraints(minHeight: 58),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFFEAECF0))),
              ),
              child: Row(
                children: [
                  _thumbnailPreview(),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isKo ? '썸네일 이미지' : 'Thumbnail image',
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontFamilyFallback: const ['NotoSansKR'],
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF111827),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isKo ? '눌러서 이미지 선택' : 'Tap to choose an image',
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontFamilyFallback: const ['NotoSansKR'],
                            fontSize: 12,
                            color: Color(0xFF667085),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: Color(0xFF98A2B3),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            8,
            horizontalPadding,
            12,
          ),
          child: SizedBox(
            height: context.rh(48, min: 46, max: 50),
            child: ElevatedButton(
              onPressed: _isSaving ? null : _save,
              style: ElevatedButton.styleFrom(
                elevation: 0,
                backgroundColor: const Color(0xFF344054),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      l10n.save,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontFamilyFallback: const ['NotoSansKR'],
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
