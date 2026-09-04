// lib/screens/review_approval_screen.dart
// 후기 수락/거절 화면
// 모임장이 작성한 후기를 확인하고 수락 또는 거절

import 'package:flutter/material.dart';
import '../services/meetup_service.dart';
import '../l10n/app_localizations.dart';
import '../utils/logger.dart';
import '../ui/widgets/fullscreen_image_viewer.dart';
import '../utils/responsive_helper.dart';

class ReviewApprovalScreen extends StatefulWidget {
  final String requestId;
  final String reviewId;
  final String meetupTitle;
  final String imageUrl; // 단일 이미지 (하위 호환성)
  final List<String>? imageUrls; // 여러 이미지 지원
  final String content;
  final String authorName;

  const ReviewApprovalScreen({
    Key? key,
    required this.requestId,
    required this.reviewId,
    required this.meetupTitle,
    required this.imageUrl,
    this.imageUrls,
    required this.content,
    required this.authorName,
  }) : super(key: key);

  @override
  State<ReviewApprovalScreen> createState() => _ReviewApprovalScreenState();
}

class _ReviewApprovalScreenState extends State<ReviewApprovalScreen> {
  final MeetupService _meetupService = MeetupService();
  bool _isProcessing = false;
  bool _isLoading = true;
  String? _currentStatus; // 'pending', 'accepted', 'rejected'
  late PageController _pageController;
  int _currentImageIndex = 0;
  late List<String> _imageUrls;

  @override
  void initState() {
    super.initState();
    // 이미지 URL 목록 초기화 (여러 이미지 또는 단일 이미지)
    _imageUrls = widget.imageUrls ?? [widget.imageUrl];
    _pageController = PageController();
    _checkRequestStatus();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// 요청의 현재 상태 확인
  Future<void> _checkRequestStatus() async {
    try {
      final requestDoc =
          await _meetupService.getReviewRequestStatus(widget.requestId);

      if (mounted) {
        setState(() {
          _currentStatus = requestDoc?['status'] as String?;
          _isLoading = false;
        });
      }
    } catch (e) {
      Logger.error('❌ 요청 상태 확인 오류: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleResponse(bool accept) async {
    setState(() {
      _isProcessing = true;
    });

    try {
      final success = await _meetupService.respondToReviewRequest(
        requestId: widget.requestId,
        accept: accept,
      );

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(accept
                  ? (AppLocalizations.of(context)!.reviewAccepted ?? "")
                  : AppLocalizations.of(context)!.reviewRejected),
            ),
          );
          Navigator.of(context).pop(true);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(
                    AppLocalizations.of(context)!.reviewProcessError ?? "")),
          );
        }
      }
    } catch (e) {
      Logger.error('❌ 후기 수락/거절 처리 오류: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.error ?? "")),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: _buildAppBar(l10n?.reviewApprovalRequest ?? ''),
        body: const SafeArea(
          top: false,
          child: Center(
            child: CircularProgressIndicator(color: Color(0xFF2E90FA)),
          ),
        ),
      );
    }

    final alreadyResponded =
        _currentStatus != null && _currentStatus != 'pending';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _buildAppBar(l10n?.reviewApprovalRequest ?? ''),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.only(bottom: alreadyResponded ? 28 : 16),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: EdgeInsets.fromLTRB(
                            _horizontalPadding,
                            14,
                            _horizontalPadding,
                            16,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.meetupTitle,
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontFamilyFallback: const ['NotoSansKR'],
                                  fontSize:
                                      context.rf(18).clamp(16, 19).toDouble(),
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF111827),
                                  height: 1.35,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                l10n!.reviewByAuthor(widget.authorName),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontFamily: 'Inter',
                                  fontFamilyFallback: ['NotoSansKR'],
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF667085),
                                ),
                              ),
                            ],
                          ),
                        ),
                        _buildImageGallery(),
                        Padding(
                          padding: EdgeInsets.fromLTRB(
                            _horizontalPadding,
                            22,
                            _horizontalPadding,
                            0,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.reviewContent,
                                style: const TextStyle(
                                  fontFamily: 'Inter',
                                  fontFamilyFallback: ['NotoSansKR'],
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF667085),
                                ),
                              ),
                              const SizedBox(height: 9),
                              Text(
                                widget.content,
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontFamilyFallback: const ['NotoSansKR'],
                                  fontSize:
                                      context.rf(15).clamp(14, 16).toDouble(),
                                  fontWeight: FontWeight.w400,
                                  height: 1.6,
                                  color: const Color(0xFF111827),
                                ),
                              ),
                              const SizedBox(height: 24),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Padding(
                                    padding: EdgeInsets.only(top: 1),
                                    child: Icon(
                                      Icons.info_outline_rounded,
                                      color: Color(0xFF667085),
                                      size: 18,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      l10n.reviewApprovalInfo,
                                      style: const TextStyle(
                                        fontFamily: 'Inter',
                                        fontFamilyFallback: ['NotoSansKR'],
                                        color: Color(0xFF667085),
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w500,
                                        height: 1.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (alreadyResponded) ...[
                                const SizedBox(height: 22),
                                _buildResponseStatus(l10n),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (!alreadyResponded) _buildBottomActions(l10n),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(String title) {
    return AppBar(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      toolbarHeight: context.rh(56, min: 54, max: 60),
      leadingWidth: 48,
      leading: IconButton(
        onPressed: () => Navigator.of(context).maybePop(),
        icon: Icon(
          Icons.arrow_back_rounded,
          color: const Color(0xFF111827),
          size: context.ri(22).clamp(21, 24).toDouble(),
        ),
        tooltip: MaterialLocalizations.of(context).backButtonTooltip,
      ),
      title: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.2,
        child: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: 'Inter',
            fontFamilyFallback: const ['NotoSansKR'],
            fontSize: context.rf(18).clamp(16, 19).toDouble(),
            fontWeight: FontWeight.w700,
            color: const Color(0xFF111827),
          ),
        ),
      ),
    );
  }

  double get _horizontalPadding {
    final width = MediaQuery.sizeOf(context).width;
    return width < 360 ? 14 : (width < 430 ? 16 : 20);
  }

  Widget _buildImageGallery() {
    final isWide = MediaQuery.sizeOf(context).width >= 600;
    return Stack(
      children: [
        AspectRatio(
          aspectRatio: isWide ? 4 / 3 : 1,
          child: PageView.builder(
            controller: _pageController,
            itemCount: _imageUrls.length,
            onPageChanged: (index) => setState(() {
              _currentImageIndex = index;
            }),
            itemBuilder: (context, index) {
              return GestureDetector(
                onTap: () => showFullscreenImageViewer(
                  context,
                  imageUrls: _imageUrls,
                  initialIndex: index,
                  heroTag: 'review_approval_image_$index',
                ),
                child: Hero(
                  tag: 'review_approval_image_$index',
                  child: Image.network(
                    _imageUrls[index],
                    fit: BoxFit.cover,
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return const ColoredBox(
                        color: Color(0xFFF2F4F7),
                        child: Center(
                          child: CircularProgressIndicator(
                            color: Color(0xFF2E90FA),
                            strokeWidth: 2,
                          ),
                        ),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) {
                      return const ColoredBox(
                        color: Color(0xFFF2F4F7),
                        child: Center(
                          child: Icon(
                            Icons.broken_image_outlined,
                            size: 42,
                            color: Color(0xFF98A2B3),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              );
            },
          ),
        ),
        if (_imageUrls.length > 1)
          Positioned(
            right: _horizontalPadding,
            bottom: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xB3111827),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                '${_currentImageIndex + 1}/${_imageUrls.length}',
                style: const TextStyle(
                  fontFamily: 'Inter',
                  color: Colors.white,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildResponseStatus(AppLocalizations l10n) {
    final accepted = _currentStatus == 'accepted';
    return Row(
      children: [
        Icon(
          accepted ? Icons.check_circle_outline_rounded : Icons.cancel_outlined,
          color: accepted ? const Color(0xFF12B76A) : const Color(0xFFF04438),
          size: 20,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            accepted
                ? l10n.reviewAlreadyAccepted ?? ''
                : l10n.reviewAlreadyRejected ?? '',
            style: const TextStyle(
              fontFamily: 'Inter',
              fontFamilyFallback: ['NotoSansKR'],
              color: Color(0xFF475467),
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomActions(AppLocalizations? l10n) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        _horizontalPadding,
        10,
        _horizontalPadding,
        12,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: context.rh(50, min: 48, max: 54),
                  child: TextButton(
                    onPressed:
                        _isProcessing ? null : () => _handleResponse(false),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF667085),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      l10n?.reject ?? '',
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontFamilyFallback: ['NotoSansKR'],
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: context.rh(50, min: 48, max: 54),
                  child: FilledButton(
                    onPressed:
                        _isProcessing ? null : () => _handleResponse(true),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF2E90FA),
                      disabledBackgroundColor: const Color(0xFFE4E7EC),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isProcessing
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            l10n?.accept ?? '',
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              fontFamilyFallback: ['NotoSansKR'],
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
