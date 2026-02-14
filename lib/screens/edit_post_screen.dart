import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';

import '../l10n/app_localizations.dart';
import '../models/post.dart';
import '../services/post_service.dart';

class EditPostScreen extends StatefulWidget {
  final Post post;

  const EditPostScreen({super.key, required this.post});

  @override
  State<EditPostScreen> createState() => _EditPostScreenState();
}

class _EditPostScreenState extends State<EditPostScreen> {
  final _contentController = TextEditingController();
  final _contentFocusNode = FocusNode();

  final PostService _postService = PostService();

  // 기존 이미지(URL) / 새로 추가할 이미지(Asset/File)
  late final List<String> _keptImageUrls;
  final List<AssetEntity> _selectedAssets = [];
  final List<File> _selectedImages = [];

  bool _isSubmitting = false;
  bool _isResolvingSelectedImages = false;
  bool _canSubmit = false;

  bool get _isPollLocked =>
      widget.post.type == 'poll' && (widget.post.pollTotalVotes > 0);

  @override
  void initState() {
    super.initState();
    _keptImageUrls = List<String>.from(widget.post.imageUrls);
    _contentController.text = widget.post.content;
    _contentController.addListener(_checkCanSubmit);
    _checkCanSubmit();
  }

  @override
  void dispose() {
    _contentController.dispose();
    _contentFocusNode.dispose();
    super.dispose();
  }

  void _checkCanSubmit() {
    final contentNotEmpty = _contentController.text.trim().isNotEmpty;
    final hasAnyImage = _keptImageUrls.isNotEmpty || _selectedAssets.isNotEmpty;

    final can =
        !_isSubmitting && !_isResolvingSelectedImages && !_isPollLocked && (contentNotEmpty || hasAnyImage);
    if (can != _canSubmit && mounted) {
      setState(() => _canSubmit = can);
    } else {
      _canSubmit = can;
    }
  }

  Future<List<File>> _resolveSelectedAssetFiles() async {
    if (_selectedAssets.isEmpty) return const <File>[];
    final futures = _selectedAssets.map((asset) async {
      try {
        final origin = await asset.originFile;
        if (origin != null) return origin;
        return await asset.file;
      } catch (_) {
        return null;
      }
    }).toList(growable: false);
    final resolved = await Future.wait(futures);
    return resolved.whereType<File>().toList(growable: false);
  }

  Future<void> _syncSelectedImagesFromAssets() async {
    if (!mounted) return;
    if (_selectedAssets.isEmpty) {
      setState(() {
        _selectedImages.clear();
        _isResolvingSelectedImages = false;
      });
      return;
    }

    setState(() => _isResolvingSelectedImages = true);
    final files = await _resolveSelectedAssetFiles();
    if (!mounted) return;
    setState(() {
      _selectedImages
        ..clear()
        ..addAll(files);
      _isResolvingSelectedImages = false;
    });
    _checkCanSubmit();
  }

  Future<void> _selectImages() async {
    final remaining = (10 - _keptImageUrls.length).clamp(0, 10);
    if (remaining <= 0) return;

    final pickedAssets = await AssetPicker.pickAssets(
      context,
      pickerConfig: AssetPickerConfig(
        requestType: RequestType.image,
        selectedAssets: _selectedAssets,
        maxAssets: remaining,
        dragToSelect: false,
      ),
    );

    if (!mounted) return;
    if (pickedAssets == null) return;

    setState(() {
      _selectedAssets
        ..clear()
        ..addAll(pickedAssets.take(remaining));
    });
    await _syncSelectedImagesFromAssets();
  }

  Future<void> _removeExistingUrl(int index) async {
    if (index < 0 || index >= _keptImageUrls.length) return;
    setState(() {
      _keptImageUrls.removeAt(index);
    });
    _checkCanSubmit();
  }

  Future<void> _removeNewAsset(int index) async {
    if (index < 0 || index >= _selectedAssets.length) return;
    setState(() {
      _selectedAssets.removeAt(index);
    });
    await _syncSelectedImagesFromAssets();
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    if (_isSubmitting) return;
    if (_isResolvingSelectedImages) return;

    setState(() => _isSubmitting = true);
    _checkCanSubmit();

    try {
      // 업로드 직전 파일 리스트 동기화(안전)
      if (_selectedAssets.isNotEmpty && _selectedImages.length != _selectedAssets.length) {
        await _syncSelectedImagesFromAssets();
      }
      if (!mounted) return;

      final updated = await _postService.updatePost(
        post: widget.post,
        content: _contentController.text.trim(),
        keptImageUrls: List<String>.from(_keptImageUrls),
        newImageFiles: _selectedImages.isNotEmpty ? List<File>.from(_selectedImages) : null,
      );

      if (!mounted) return;
      if (updated != null) {
        Navigator.of(context).pop<Post>(updated);
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.postUpdateFailed),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.postUpdateFailed),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 2),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
        _checkCanSubmit();
      }
    }
  }

  Widget _buildExistingImages() {
    if (_keptImageUrls.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 10),
        SizedBox(
          height: 112,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _keptImageUrls.length,
            itemBuilder: (context, index) {
              final url = _keptImageUrls[index];
              return Container(
                margin: const EdgeInsets.only(right: 8),
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: CachedNetworkImage(
                        imageUrl: url,
                        width: 96,
                        height: 96,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(color: const Color(0xFFF3F4F6)),
                        errorWidget: (_, __, ___) => Container(
                          color: const Color(0xFFF3F4F6),
                          child: const Center(child: Icon(Icons.broken_image_outlined)),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 6,
                      right: 6,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _isSubmitting ? null : () => _removeExistingUrl(index),
                        child: Container(
                          padding: const EdgeInsets.all(5),
                          decoration: const BoxDecoration(
                            color: Color(0xCC111827),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close_rounded,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildNewImages() {
    if (_selectedAssets.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 10),
        SizedBox(
          height: 112,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _selectedAssets.length,
            itemBuilder: (context, index) {
              final asset = _selectedAssets[index];
              return Container(
                margin: const EdgeInsets.only(right: 8),
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image(
                        image: AssetEntityImageProvider(
                          asset,
                          isOriginal: false,
                          thumbnailSize: const ThumbnailSize.square(256),
                        ),
                        width: 96,
                        height: 96,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      top: 6,
                      right: 6,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _isSubmitting ? null : () => _removeNewAsset(index),
                        child: Container(
                          padding: const EdgeInsets.all(5),
                          decoration: const BoxDecoration(
                            color: Color(0xCC111827),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close_rounded,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF111827)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          l10n.editPost,
          style: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Color(0xFF111827),
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: _canSubmit ? _submit : null,
            icon: _isSubmitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check_rounded),
            label: Text(
              l10n.update,
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_isPollLocked)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFDE68A)),
                  ),
                  child: Text(
                    Localizations.localeOf(context).languageCode == 'ko'
                        ? '투표가 진행된 게시글은 수정할 수 없어요.'
                        : 'Poll posts cannot be edited after votes.',
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF92400E),
                      height: 1.25,
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              Container(
                height: 220,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _contentFocusNode.hasFocus
                        ? const Color(0xFF2563EB)
                        : const Color(0xFFE5E7EB),
                    width: _contentFocusNode.hasFocus ? 2 : 1,
                  ),
                  color: Colors.white,
                ),
                child: TextField(
                  controller: _contentController,
                  focusNode: _contentFocusNode,
                  enabled: !_isSubmitting && !_isPollLocked,
                  decoration: InputDecoration(
                    hintText: l10n.enterContent,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.all(16),
                  ),
                  maxLines: null,
                  textAlignVertical: TextAlignVertical.top,
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF111827),
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: (_isSubmitting || _isPollLocked) ? null : _selectImages,
                      icon: const Icon(Icons.image_outlined),
                      label: Text(
                        l10n.imageAttachment,
                        style: const TextStyle(
                          fontFamily: 'Pretendard',
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF111827),
                        side: const BorderSide(color: Color(0xFFE5E7EB)),
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: Text(
                      '${(_keptImageUrls.length + _selectedAssets.length).clamp(0, 10)}/10',
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF111827),
                      ),
                    ),
                  ),
                ],
              ),
              _buildExistingImages(),
              _buildNewImages(),
            ],
          ),
        ),
      ),
    );
  }
}

