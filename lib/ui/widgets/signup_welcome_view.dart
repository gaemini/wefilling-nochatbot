// lib/ui/widgets/signup_welcome_view.dart
// 가입 완료 순간의 환영 화면: 흰 바탕 가운데 프로필 사진 84(둥근 네모 25%)가
// 튀어나오고(MotionSelectionPulse peak 1.12), 120ms 뒤 `환영해요, {닉네임}`이
// 아래에서 올라온다(medium). 탭하면 바로 넘어간다.

import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../l10n/ui_locale.dart';
import 'motion_selection_pulse.dart';

class SignupWelcomeView extends StatefulWidget {
  const SignupWelcomeView({
    super.key,
    required this.nickname,
    required this.onTap,
    this.photo,
  });

  final String nickname;
  final ImageProvider? photo;
  final VoidCallback onTap;

  @override
  State<SignupWelcomeView> createState() => _SignupWelcomeViewState();
}

class _SignupWelcomeViewState extends State<SignupWelcomeView> {
  bool _showText = false;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 120), () {
      if (mounted) setState(() => _showText = true);
    });
  }

  String _title(BuildContext context) {
    final code = Localizations.localeOf(context).languageCode;
    if (isChineseUi(context)) return '欢迎你，${widget.nickname}';
    return code == 'ko'
        ? '환영해요, ${widget.nickname}'
        : 'Welcome, ${widget.nickname}';
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MotionTokens.reduceMotion(context);
    const size = 84.0;
    return Scaffold(
      key: const ValueKey('signup_welcome'),
      backgroundColor: Colors.white,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              MotionSelectionPulse(
                selected: true,
                pulseOnMount: true,
                activePeak: 1.12,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(size * .25),
                  child: SizedBox.square(
                    dimension: size,
                    child: widget.photo == null
                        ? const ColoredBox(
                            color: Color(0xFFE5E7EB),
                            child: Icon(
                              Icons.person,
                              size: 44,
                              color: Color(0xFF9CA3AF),
                            ),
                          )
                        : Image(image: widget.photo!, fit: BoxFit.cover),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              AnimatedOpacity(
                opacity: _showText ? 1 : 0,
                duration: reduce ? Duration.zero : MotionTokens.medium,
                curve: MotionTokens.curve,
                child: AnimatedSlide(
                  offset: _showText || reduce
                      ? Offset.zero
                      : const Offset(0, .4),
                  duration: reduce ? Duration.zero : MotionTokens.medium,
                  curve: MotionTokens.curve,
                  child: MediaQuery.withClampedTextScaling(
                    maxScaleFactor: 1.3,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        _title(context),
                        key: const ValueKey('signup_welcome_title'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: uiFontFamily(context, 'Inter'),
                          fontFamilyFallback: const ['NotoSansKR'],
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF111827),
                        ),
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
