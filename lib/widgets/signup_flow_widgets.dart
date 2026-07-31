import 'package:flutter/material.dart';

import '../constants/app_constants.dart';

class SignupPageIntro extends StatelessWidget {
  const SignupPageIntro({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, size: 38, color: const Color(0xFF0F172A)),
        const SizedBox(height: 18),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: Color(0xFF0F172A),
            height: 1.25,
            letterSpacing: -0.6,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          description,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: Color(0xFF64748B),
            height: 1.55,
            letterSpacing: -0.2,
          ),
        ),
      ],
    );
  }
}

class SignupSectionLabel extends StatelessWidget {
  const SignupSectionLabel({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontFamily: 'Pretendard',
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: Color(0xFF0F172A),
        letterSpacing: -0.2,
      ),
    );
  }
}

InputDecoration signupInputDecoration({
  required String hintText,
  required IconData icon,
  String? helperText,
  String? counterText,
  Widget? suffixIcon,
}) {
  return InputDecoration(
    hintText: hintText,
    helperText: helperText,
    counterText: counterText,
    prefixIcon: Icon(icon, color: const Color(0xFF64748B), size: 21),
    prefixIconConstraints: const BoxConstraints(minWidth: 38, minHeight: 48),
    suffixIcon: suffixIcon,
    hintStyle: const TextStyle(
      fontFamily: 'Pretendard',
      fontSize: 16,
      fontWeight: FontWeight.w400,
      color: Color(0xFF94A3B8),
      letterSpacing: -0.2,
    ),
    helperStyle: const TextStyle(
      fontFamily: 'Pretendard',
      fontSize: 12,
      fontWeight: FontWeight.w400,
      color: Color(0xFF64748B),
      height: 1.35,
    ),
    contentPadding: const EdgeInsets.symmetric(vertical: 14),
    enabledBorder: const UnderlineInputBorder(
      borderSide: BorderSide(color: Color(0xFFE2E8F0)),
    ),
    disabledBorder: const UnderlineInputBorder(
      borderSide: BorderSide(color: Color(0xFFE2E8F0)),
    ),
    focusedBorder: const UnderlineInputBorder(
      borderSide: BorderSide(color: AppColors.pointColor, width: 1.5),
    ),
    errorBorder: const UnderlineInputBorder(
      borderSide: BorderSide(color: Color(0xFFDC2626)),
    ),
    focusedErrorBorder: const UnderlineInputBorder(
      borderSide: BorderSide(color: Color(0xFFDC2626), width: 1.5),
    ),
  );
}

class SignupVerifiedEmail extends StatelessWidget {
  const SignupVerifiedEmail({
    super.key,
    required this.label,
    required this.email,
  });

  final String label;
  final String email;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 1),
          child: Icon(
            Icons.verified_rounded,
            color: AppColors.pointColor,
            size: 20,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                email,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0F172A),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class SignupPrimaryButton extends StatelessWidget {
  const SignupPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final child = isLoading
        ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 19),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
            ],
          );

    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: AppColors.pointColor,
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0xFFE2E8F0),
          disabledForegroundColor: const Color(0xFF94A3B8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: child,
      ),
    );
  }
}

class SignupInlineError extends StatelessWidget {
  const SignupInlineError({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.error_outline_rounded,
          color: Color(0xFFDC2626),
          size: 19,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Color(0xFFB91C1C),
              height: 1.45,
            ),
          ),
        ),
      ],
    );
  }
}

/// 가입 도중 뒤로 가기를 눌렀을 때 입력값과 임시 인증을 버릴지 확인합니다.
Future<bool> showSignupExitConfirmation(BuildContext context) async {
  final isKorean = Localizations.localeOf(context).languageCode == 'ko';
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
      actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      title: Text(
        isKorean ? '회원가입을 중단할까요?' : 'Leave sign up?',
        style: const TextStyle(
          fontFamily: 'Pretendard',
          fontSize: 20,
          fontWeight: FontWeight.w800,
          color: Color(0xFF0F172A),
        ),
      ),
      content: Text(
        isKorean
            ? '아직 회원으로 저장되지 않았어요. 지금까지 입력한 내용은 삭제되며 언제든 다시 가입할 수 있어요.'
            : 'Your account has not been registered yet. Your progress will be discarded, and you can sign up again anytime.',
        style: const TextStyle(
          fontFamily: 'Pretendard',
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: Color(0xFF64748B),
          height: 1.5,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(isKorean ? '계속 가입' : 'Keep signing up'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFFDC2626),
          ),
          child: Text(isKorean ? '가입 중단' : 'Leave'),
        ),
      ],
    ),
  );
  return result == true;
}
