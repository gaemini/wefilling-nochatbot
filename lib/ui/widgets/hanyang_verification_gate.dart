import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../constants/app_constants.dart';
import '../../providers/auth_provider.dart';
import '../../screens/hanyang_email_verification_screen.dart';
import '../../utils/responsive_helper.dart';

/// 한양메일 인증 사용자에게만 공개되는 콘텐츠를 나타내는 작은 공통 표식입니다.
/// 정해진 콘텐츠 크기만 사용해 Row/Wrap 안에서 가로로 늘어나지 않습니다.
class HanyangContentBadge extends StatelessWidget {
  const HanyangContentBadge({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    return Semantics(
      label: isKo ? '한양메일 인증 전용' : 'Hanyang verified only',
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF63B5FF),
              AppColors.pointColor,
              Color(0xFF5577F2),
            ],
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 5 : 6,
            vertical: compact ? 2.5 : 3,
          ),
          child: Text(
            'HY',
            maxLines: 1,
            style: TextStyle(
              fontFamily: 'Inter',
              fontFamilyFallback: const ['NotoSansKR'],
              fontSize: compact ? 8.5 : 9,
              fontWeight: FontWeight.w600,
              color: Colors.white,
              height: 1,
              letterSpacing: 0.1,
            ),
          ),
        ),
      ),
    );
  }
}

/// 한양메일 전용 콘텐츠의 공통 잠금 UI입니다.
///
/// 공개 목록에서는 카드의 존재를 유지하면서 본문/미디어만 흐리게 표시하고,
/// 인증을 완료하면 AuthProvider의 최신 사용자 상태로 즉시 다시 렌더링합니다.
class HanyangVerificationGate extends StatelessWidget {
  const HanyangVerificationGate({
    super.key,
    required this.locked,
    required this.child,
    this.compact = false,
  });

  final bool locked;
  final Widget child;
  final bool compact;

  static bool isLockedForCurrentUser(BuildContext context, bool required) {
    if (!required) return false;
    return !context.watch<AuthProvider>().isHanyangEmailVerified;
  }

  static Future<void> openVerification(BuildContext context) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => const HanyangEmailVerificationScreen.profile(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!locked) return child;

    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    final buttonHorizontal = compact
        ? context.rs(12).clamp(10.0, 14.0).toDouble()
        : context.rs(18).clamp(16.0, 22.0).toDouble();
    final overlayRadius = compact
        ? context.rs(17).clamp(14.0, 18.0).toDouble()
        : context.rs(22).clamp(18.0, 24.0).toDouble();

    final gatedContent = Stack(
      alignment: Alignment.center,
      children: [
        ExcludeSemantics(
          child: AbsorbPointer(
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: double.infinity,
                  minHeight: compact ? 112 : 260,
                ),
                child: child,
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF1D2939).withValues(alpha: 0.58),
                  const Color(0xFF101828).withValues(alpha: 0.68),
                ],
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: Center(
            child: MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.2,
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 14 : 22,
                  vertical: compact ? 8 : 20,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: compact ? 300 : 360,
                  ),
                  child: compact
                      ? _CompactVerificationPrompt(
                          isKorean: isKo,
                          buttonHorizontal: buttonHorizontal,
                          onPressed: () => openVerification(context),
                        )
                      : _ExpandedVerificationPrompt(
                          isKorean: isKo,
                          buttonHorizontal: buttonHorizontal,
                          onPressed: () => openVerification(context),
                        ),
                ),
              ),
            ),
          ),
        ),
      ],
    );

    if (!compact) return ClipRect(child: gatedContent);
    return _SoftEdgeMask(
      feather: context.rs(7).clamp(5.0, 8.0).toDouble(),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(overlayRadius),
        child: gatedContent,
      ),
    );
  }
}

/// 잠긴 피드 카드의 바깥쪽만 짧게 투명해지도록 처리합니다.
/// 중앙 콘텐츠와 인증 버튼은 완전히 불투명하게 유지합니다.
class _SoftEdgeMask extends StatelessWidget {
  const _SoftEdgeMask({required this.feather, required this.child});

  final double feather;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (bounds) {
        final stop = (feather / bounds.width).clamp(0.0, 0.12).toDouble();
        return LinearGradient(
          colors: const [
            Colors.transparent,
            Colors.black,
            Colors.black,
            Colors.transparent,
          ],
          stops: [0, stop, 1 - stop, 1],
        ).createShader(bounds);
      },
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (bounds) {
          final stop = (feather / bounds.height).clamp(0.0, 0.12).toDouble();
          return LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: const [
              Colors.transparent,
              Colors.black,
              Colors.black,
              Colors.transparent,
            ],
            stops: [0, stop, 1 - stop, 1],
          ).createShader(bounds);
        },
        child: child,
      ),
    );
  }
}

class _CompactVerificationPrompt extends StatelessWidget {
  const _CompactVerificationPrompt({
    required this.isKorean,
    required this.buttonHorizontal,
    required this.onPressed,
  });

  final bool isKorean;
  final double buttonHorizontal;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.school_outlined,
          size: 19,
          color: Colors.white,
        ),
        const SizedBox(height: 5),
        Text(
          isKorean ? '한양메일 인증을 해주세요.' : 'Hanyang email verification required',
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontFamily: 'Inter',
            fontFamilyFallback: ['NotoSansKR'],
            fontSize: 12.25,
            fontWeight: FontWeight.w700,
            color: Colors.white,
            height: 1.2,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 8),
        _VerificationButton(
          label: isKorean ? '인증하러 가기' : 'Verify email',
          horizontalPadding: buttonHorizontal,
          compact: true,
          onPressed: onPressed,
        ),
      ],
    );
  }
}

class _ExpandedVerificationPrompt extends StatelessWidget {
  const _ExpandedVerificationPrompt({
    required this.isKorean,
    required this.buttonHorizontal,
    required this.onPressed,
  });

  final bool isKorean;
  final double buttonHorizontal;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.school_outlined,
            size: 27,
            color: Colors.white,
          ),
          const SizedBox(height: 9),
          Text(
            isKorean ? '한양메일 인증을 해주세요.' : 'Hanyang email verification required',
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontFamilyFallback: ['NotoSansKR'],
              fontSize: 15.5,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              height: 1.24,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isKorean
                ? '인증하면 이 내용을 전체 확인할 수 있어요.'
                : 'Verify your school email to view this content.',
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Inter',
              fontFamilyFallback: const ['NotoSansKR'],
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: Colors.white.withValues(alpha: 0.82),
              height: 1.3,
            ),
          ),
          const SizedBox(height: 14),
          _VerificationButton(
            label: isKorean ? '인증하러 가기' : 'Verify Hanyang email',
            horizontalPadding: buttonHorizontal,
            compact: false,
            onPressed: onPressed,
          ),
        ],
      ),
    );
  }
}

class _VerificationButton extends StatelessWidget {
  const _VerificationButton({
    required this.label,
    required this.horizontalPadding,
    required this.compact,
    required this.onPressed,
  });

  final String label;
  final double horizontalPadding;
  final bool compact;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: Colors.white,
        backgroundColor: AppColors.pointColor,
        minimumSize: Size(0, compact ? 30 : 38),
        padding: EdgeInsets.symmetric(
          horizontal: horizontalPadding,
          vertical: 0,
        ),
        shape: const StadiumBorder(),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontFamily: 'Inter',
          fontFamilyFallback: const ['NotoSansKR'],
          fontSize: compact ? 11.5 : 13,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    );
  }
}
