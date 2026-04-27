// 나눔 전용 글 작성 화면

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';

import '../constants/app_constants.dart';
import '../providers/auth_provider.dart' as app_auth;
import '../services/post_service.dart';
import '../utils/category_label_utils.dart';
import '../utils/sharing_category.dart';
import 'hanyang_email_verification_screen.dart';

class CreateSharingPostScreen extends StatefulWidget {
  final VoidCallback onPostCreated;

  const CreateSharingPostScreen({
    super.key,
    required this.onPostCreated,
  });

  @override
  State<CreateSharingPostScreen> createState() =>
      _CreateSharingPostScreenState();
}

class _CreateSharingPostScreenState extends State<CreateSharingPostScreen> {
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  final _locationController = TextEditingController();
  final _postService = PostService();
  final List<AssetEntity> _selectedAssets = [];
  final List<File> _selectedImages = [];

  String _selectedCategory = kSharingCategoryOptions.first;
  bool _schoolOnly = false;
  bool _isSubmitting = false;
  bool _isResolvingImages = false;

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _selectImages() async {
    final pickedAssets = await AssetPicker.pickAssets(
      context,
      pickerConfig: AssetPickerConfig(
        requestType: RequestType.image,
        selectedAssets: _selectedAssets,
        maxAssets: 10,
        dragToSelect: false,
      ),
    );
    if (!mounted || pickedAssets == null) return;
    setState(() {
      _selectedAssets
        ..clear()
        ..addAll(pickedAssets.take(10));
    });
    await _syncSelectedImages();
  }

  Future<void> _syncSelectedImages() async {
    if (_selectedAssets.isEmpty) {
      if (mounted) setState(_selectedImages.clear);
      return;
    }
    setState(() => _isResolvingImages = true);
    final files = await Future.wait(_selectedAssets.map((asset) async {
      try {
        return await asset.originFile ?? await asset.file;
      } catch (_) {
        return null;
      }
    }));
    if (!mounted) return;
    setState(() {
      _selectedImages
        ..clear()
        ..addAll(files.whereType<File>());
      _isResolvingImages = false;
    });
  }

  Future<void> _removeImage(int index) async {
    setState(() => _selectedAssets.removeAt(index));
    await _syncSelectedImages();
  }

  Future<void> _toggleSchoolOnly(bool value) async {
    if (!value) {
      setState(() => _schoolOnly = false);
      return;
    }

    final auth = context.read<app_auth.AuthProvider>();
    if (!auth.isHanyangUser) {
      final verified = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => const HanyangEmailVerificationScreen(
            returnOnSuccess: true,
          ),
        ),
      );
      if (!mounted) return;
      if (verified != true &&
          !context.read<app_auth.AuthProvider>().isHanyangUser) {
        return;
      }
    }
    if (mounted) setState(() => _schoolOnly = true);
  }

  Future<void> _submit() async {
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();
    final location = _locationController.text.trim();
    if (title.isEmpty) {
      _showSnack(
        Localizations.localeOf(context).languageCode == 'ko'
            ? '제목을 입력해주세요.'
            : 'Please enter a title.',
      );
      return;
    }
    if (location.isEmpty) {
      _showSnack(
        Localizations.localeOf(context).languageCode == 'ko'
            ? '위치를 입력해주세요.'
            : 'Please enter a location.',
      );
      return;
    }
    if (_selectedAssets.isEmpty) {
      _showSnack('사진을 1장 이상 첨부해주세요.');
      return;
    }
    if (_isResolvingImages) {
      _showSnack('선택한 사진을 준비 중이에요.');
      return;
    }
    if (_selectedImages.length != _selectedAssets.length) {
      await _syncSelectedImages();
    }
    if (!mounted) return;

    setState(() => _isSubmitting = true);
    final success = await _postService.addSharingPost(
      title: title,
      content: content,
      sharingLocation: location,
      category: _selectedCategory,
      imageFiles: _selectedImages,
      schoolOnly: _schoolOnly,
    );
    if (!mounted) return;
    setState(() => _isSubmitting = false);
    if (!success) {
      _showSnack('나눔 글을 등록하지 못했어요.', isError: true);
      return;
    }
    widget.onPostCreated();
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('나눔 글이 등록되었습니다.')),
    );
  }

  void _showSnack(String message, {bool isError = false}) {
    HapticFeedback.selectionClick();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.orange,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom + 32;
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.black, size: 30),
          onPressed: () => Navigator.of(context).pop(),
        ),
        centerTitle: true,
        title: Text(
          isKo ? '나눔 작성하기' : 'Create Sharing Post',
          style: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: Colors.black,
          ),
        ),
        actions: [
          TextButton(
            onPressed: _isSubmitting ? null : _submit,
            child: _isSubmitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    isKo ? '등록' : 'Post',
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(22, 12, 22, bottomPadding),
        children: [
          _buildLabel(isKo ? '사진 첨부(1장 이상 필수)' : 'Photos (required)'),
          const SizedBox(height: 10),
          _buildImagePicker(),
          const SizedBox(height: 24),
          _buildLabel(isKo ? '카테고리' : 'Category'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: kSharingCategoryOptions.map((category) {
              final selected = category == _selectedCategory;
              return ChoiceChip(
                label: Text(localizedCategoryLabel(context, category)),
                selected: selected,
                onSelected: (_) => setState(() => _selectedCategory = category),
                selectedColor: AppColors.pointColor.withValues(alpha: 0.14),
                labelStyle: TextStyle(
                  fontFamily: 'Pretendard',
                  fontWeight: FontWeight.w700,
                  color: selected ? AppColors.pointColor : Colors.black87,
                ),
                shape: StadiumBorder(
                  side: BorderSide(
                    color: selected
                        ? AppColors.pointColor
                        : const Color(0xFFE5E7EB),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
          _buildLabel(isKo ? '제목' : 'Title'),
          const SizedBox(height: 10),
          _buildTextField(
            controller: _titleController,
            hintText: isKo ? '예: 안 쓰는 대나무 의자' : 'e.g. Study desk',
            maxLines: 1,
          ),
          const SizedBox(height: 20),
          _buildLabel(isKo ? '위치' : 'Location'),
          const SizedBox(height: 10),
          _buildTextField(
            controller: _locationController,
            hintText: isKo ? '예: 학생회관 앞' : 'e.g. Student Center lobby',
            maxLines: 1,
          ),
          const SizedBox(height: 20),
          _buildLabel(isKo ? '설명 (선택)' : 'Description (optional)'),
          const SizedBox(height: 10),
          _buildTextField(
            controller: _contentController,
            hintText: isKo
                ? '상태와 나눔 방법을 적어주세요.'
                : 'Describe condition and pickup details.',
            maxLines: 8,
          ),
          const SizedBox(height: 24),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _schoolOnly,
            onChanged: _toggleSchoolOnly,
            activeThumbColor: AppColors.pointColor,
            title: Text(
              isKo ? 'Univ. 인증자에게만 공개' : 'Only for verified Univ. users',
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            subtitle: Text(
              isKo
                  ? '한양메일 인증을 완료한 사용자만 열람할 수 있어요.'
                  : 'Only users verified with Hanyang email can view this.',
              style: const TextStyle(fontFamily: 'Pretendard'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontFamily: 'Pretendard',
        fontSize: 16,
        fontWeight: FontWeight.w800,
        color: Colors.black,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hintText,
    required int maxLines,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(
        hintText: hintText,
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.pointColor, width: 1.4),
        ),
      ),
      style: const TextStyle(
        fontFamily: 'Pretendard',
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _buildImagePicker() {
    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _selectedAssets.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          if (index == 0) {
            return InkWell(
              onTap: _selectImages,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                width: 92,
                height: 92,
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.add_photo_alternate_outlined, size: 28),
                    const SizedBox(height: 6),
                    Text('${_selectedAssets.length}/10'),
                  ],
                ),
              ),
            );
          }

          final assetIndex = index - 1;
          return Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image(
                  image: AssetEntityImageProvider(
                    _selectedAssets[assetIndex],
                    isOriginal: false,
                  ),
                  width: 92,
                  height: 92,
                  fit: BoxFit.cover,
                ),
              ),
              Positioned(
                top: 4,
                right: 4,
                child: GestureDetector(
                  onTap: () => _removeImage(assetIndex),
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
