// lib/ui/widgets/social_interactions.dart
// 2024-2025 트렌드 소셜 미디어 스타일 인터랙션
// 좋아요, 공유, 댓글 등 Instagram/TikTok 영감 상호작용

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../constants/app_constants.dart';
import '../../utils/ui_utils.dart';

/// 소셜 미디어 스타일 액션 버튼
class SocialActionButton extends StatefulWidget {
  /// 버튼 아이콘
  final IconData icon;
  
  /// 활성화된 상태의 아이콘
  final IconData? activeIcon;
  
  /// 라벨 텍스트
  final String? label;
  
  /// 숫자 카운트
  final int? count;
  
  /// 활성화 상태
  final bool isActive;
  
  /// 클릭 콜백
  final VoidCallback? onTap;
  
  /// 색상 테마
  final SocialActionTheme theme;
  
  /// 크기
  final SocialActionSize size;
  
  /// 애니메이션 활성화
  final bool enableAnimation;

  const SocialActionButton({
    super.key,
    required this.icon,
    this.activeIcon,
    this.label,
    this.count,
    this.isActive = false,
    this.onTap,
    this.theme = SocialActionTheme.neutral,
    this.size = SocialActionSize.medium,
    this.enableAnimation = true,
  });

  /// 좋아요 버튼
  factory SocialActionButton.like({
    Key? key,
    int? count,
    bool isActive = false,
    VoidCallback? onTap,
    SocialActionSize size = SocialActionSize.medium,
  }) {
    return SocialActionButton(
      key: key,
      icon: Icons.favorite_border_rounded,
      activeIcon: Icons.favorite_rounded,
      count: count,
      isActive: isActive,
      onTap: onTap,
      theme: SocialActionTheme.like,
      size: size,
    );
  }

  /// 댓글 버튼
  factory SocialActionButton.comment({
    Key? key,
    int? count,
    VoidCallback? onTap,
    SocialActionSize size = SocialActionSize.medium,
  }) {
    return SocialActionButton(
      key: key,
      icon: Icons.chat_bubble_outline_rounded,
      count: count,
      onTap: onTap,
      theme: SocialActionTheme.comment,
      size: size,
    );
  }

  /// 공유 버튼
  factory SocialActionButton.share({
    Key? key,
    int? count,
    VoidCallback? onTap,
    SocialActionSize size = SocialActionSize.medium,
  }) {
    return SocialActionButton(
      key: key,
      icon: Icons.share_rounded,
      count: count,
      onTap: onTap,
      theme: SocialActionTheme.share,
      size: size,
    );
  }

  /// 북마크 버튼
  factory SocialActionButton.bookmark({
    Key? key,
    bool isActive = false,
    VoidCallback? onTap,
    SocialActionSize size = SocialActionSize.medium,
  }) {
    return SocialActionButton(
      key: key,
      icon: Icons.bookmark_border_rounded,
      activeIcon: Icons.bookmark_rounded,
      isActive: isActive,
      onTap: onTap,
      theme: SocialActionTheme.bookmark,
      size: size,
    );
  }

  @override
  State<SocialActionButton> createState() => _SocialActionButtonState();
}

class _SocialActionButtonState extends State<SocialActionButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _rotateAnimation;
  
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    
    _animationController = AnimationController(
      duration: AppTheme.microFast, // 120ms
      vsync: this,
    );

    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 1.2,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: AppTheme.bounceInCurve,
    ));

    _rotateAnimation = Tween<double>(
      begin: 0.0,
      end: 0.1,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.elasticOut,
    ));
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _handleTap() {
    if (widget.enableAnimation) {
      _animationController.forward().then((_) {
        _animationController.reverse();
      });
    }
    
    HapticFeedback.lightImpact();
    widget.onTap?.call();
  }

  Color _getColor() {
    if (widget.isActive) {
      switch (widget.theme) {
        case SocialActionTheme.like:
          return const Color(0xFFEF4444); // Red
        case SocialActionTheme.comment:
          return AppTheme.primary;
        case SocialActionTheme.share:
          return AppTheme.accentEmerald;
        case SocialActionTheme.bookmark:
          return AppTheme.secondary;
        case SocialActionTheme.neutral:
          return AppTheme.textPrimary;
      }
    }
    return AppTheme.textSecondary;
  }

  double _getIconSize() {
    switch (widget.size) {
      case SocialActionSize.small:
        return 16.0;
      case SocialActionSize.medium:
        return 20.0;
      case SocialActionSize.large:
        return 24.0;
    }
  }

  double _getFontSize() {
    switch (widget.size) {
      case SocialActionSize.small:
        return 11.0;
      case SocialActionSize.medium:
        return 12.0;
      case SocialActionSize.large:
        return 14.0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _getColor();
    final iconSize = _getIconSize();
    final fontSize = _getFontSize();
    
    final currentIcon = widget.isActive && widget.activeIcon != null
        ? widget.activeIcon!
        : widget.icon;

    return GestureDetector(
      onTap: _handleTap,
      child: AnimatedBuilder(
        animation: _animationController,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: Transform.rotate(
              angle: _rotateAnimation.value,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    currentIcon,
                    color: color,
                    size: iconSize,
                  ),
                  if (widget.label != null || widget.count != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      widget.label ?? widget.count?.toString() ?? '',
                      style: TextStyle(
                        color: color,
                        fontSize: fontSize,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 소셜 미디어 스타일 액션 바
class SocialActionBar extends StatelessWidget {
  /// 좋아요 정보
  final SocialActionData? likeData;
  
  /// 댓글 정보
  final SocialActionData? commentData;
  
  /// 공유 정보
  final SocialActionData? shareData;
  
  /// 북마크 정보
  final SocialActionData? bookmarkData;
  
  /// 액션 간 간격
  final double spacing;
  
  /// 크기
  final SocialActionSize size;
  
  /// 메인 축 정렬
  final MainAxisAlignment mainAxisAlignment;

  const SocialActionBar({
    super.key,
    this.likeData,
    this.commentData,
    this.shareData,
    this.bookmarkData,
    this.spacing = 24.0,
    this.size = SocialActionSize.medium,
    this.mainAxisAlignment = MainAxisAlignment.spaceEvenly,
  });

  @override
  Widget build(BuildContext context) {
    final actions = <Widget>[];

    if (likeData != null) {
      actions.add(
        SocialActionButton.like(
          count: likeData!.count,
          isActive: likeData!.isActive,
          onTap: likeData!.onTap,
          size: size,
        ),
      );
    }

    if (commentData != null) {
      actions.add(
        SocialActionButton.comment(
          count: commentData!.count,
          onTap: commentData!.onTap,
          size: size,
        ),
      );
    }

    if (shareData != null) {
      actions.add(
        SocialActionButton.share(
          count: shareData!.count,
          onTap: shareData!.onTap,
          size: size,
        ),
      );
    }

    if (bookmarkData != null) {
      actions.add(
        SocialActionButton.bookmark(
          isActive: bookmarkData!.isActive,
          onTap: bookmarkData!.onTap,
          size: size,
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Row(
        mainAxisAlignment: mainAxisAlignment,
        children: actions,
      ),
    );
  }
}

/// 소셜 액션 데이터 클래스
class SocialActionData {
  final int? count;
  final bool isActive;
  final VoidCallback? onTap;

  const SocialActionData({
    this.count,
    this.isActive = false,
    this.onTap,
  });
}

/// 소셜 액션 테마
enum SocialActionTheme {
  like,
  comment,
  share,
  bookmark,
  neutral,
}

/// 소셜 액션 크기
enum SocialActionSize {
  small,
  medium,
  large,
}

/// 하트 폭발 애니메이션 (좋아요 효과)
class HeartExplosionWidget extends StatefulWidget {
  /// 트리거 여부
  final bool trigger;
  
  /// 완료 콜백
  final VoidCallback? onComplete;

  const HeartExplosionWidget({
    super.key,
    required this.trigger,
    this.onComplete,
  });

  @override
  State<HeartExplosionWidget> createState() => _HeartExplosionWidgetState();
}

class _HeartExplosionWidgetState extends State<HeartExplosionWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(
      begin: 0.0,
      end: 2.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.elasticOut,
    ));

    _opacityAnimation = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: const Interval(0.5, 1.0, curve: Curves.easeOut),
    ));

    _animationController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onComplete?.call();
        _animationController.reset();
      }
    });
  }

  @override
  void didUpdateWidget(HeartExplosionWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    if (widget.trigger && !oldWidget.trigger) {
      _animationController.forward();
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: Opacity(
            opacity: UIUtils.safeOpacity(_opacityAnimation.value),
            child: Icon(
              Icons.favorite_rounded,
              color: const Color(0xFFEF4444),
              size: 40,
            ),
          ),
        );
      },
    );
  }
}

/// 소셜 미디어 스타일 댓글 입력창
class SocialCommentInput extends StatefulWidget {
  /// 힌트 텍스트
  final String hintText;
  
  /// 전송 콜백
  final ValueChanged<String>? onSend;
  
  /// 컨트롤러
  final TextEditingController? controller;
  
  /// 최대 줄 수
  final int maxLines;

  const SocialCommentInput({
    super.key,
    this.hintText = '댓글을 입력하세요...',
    this.onSend,
    this.controller,
    this.maxLines = 3,
  });

  @override
  State<SocialCommentInput> createState() => _SocialCommentInputState();
}

class _SocialCommentInputState extends State<SocialCommentInput> {
  late TextEditingController _controller;
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    
    _controller = widget.controller ?? TextEditingController();
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    if (widget.controller == null) {
      _controller.dispose();
    } else {
      _controller.removeListener(_onTextChanged);
    }
    super.dispose();
  }

  void _onTextChanged() {
    final hasText = _controller.text.trim().isNotEmpty;
    if (_hasText != hasText) {
      setState(() => _hasText = hasText);
    }
  }

  void _handleSend() {
    final text = _controller.text.trim();
    if (text.isNotEmpty) {
      widget.onSend?.call(text);
      _controller.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.backgroundSecondary,
        border: Border(
          top: BorderSide(
            color: AppTheme.borderLight,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // 프로필 아바타
          CircleAvatar(
            radius: 16,
            backgroundColor: AppTheme.primarySubtle,
            child: Icon(
              Icons.person_rounded,
              color: AppTheme.primary,
              size: 20,
            ),
          ),
          
          const SizedBox(width: 12),
          
          // 입력 필드
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: AppTheme.backgroundPrimary,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AppTheme.borderLight,
                  width: 1,
                ),
              ),
              child: TextField(
                controller: _controller,
                maxLines: widget.maxLines,
                minLines: 1,
                decoration: InputDecoration(
                  hintText: widget.hintText,
                  hintStyle: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 14,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
                style: AppTheme.bodyMedium,
              ),
            ),
          ),
          
          const SizedBox(width: 8),
          
          // 전송 버튼
          AnimatedScale(
            duration: AppTheme.microMedium,
            scale: _hasText ? 1.0 : 0.8,
            child: AnimatedOpacity(
              duration: AppTheme.microMedium,
              opacity: _hasText ? 1.0 : 0.5,
              child: GestureDetector(
                onTap: _hasText ? _handleSend : null,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    gradient: _hasText 
                        ? AppTheme.primaryGradient 
                        : LinearGradient(
                            colors: [Colors.grey.shade300, Colors.grey.shade400],
                          ),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(
                    Icons.send_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

