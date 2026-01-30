// lib/ui/dialogs/logout_dialog.dart
// 로그아웃 확인 다이얼로그 (앱 공통 다이얼로그 스타일 적용)

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design/tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/auth_provider.dart';
import '../../screens/login_screen.dart';

Future<void> showLogoutConfirmDialog(
  BuildContext outerContext, {
  required AuthProvider authProvider,
}) {
  // 중요한 액션임을 알림
  HapticFeedback.mediumImpact();

  return showDialog<void>(
    context: outerContext,
    barrierDismissible: false,
    builder: (dialogContext) {
      return AnimatedBuilder(
        animation: authProvider,
        builder: (innerContext, _) {
          final l10n = AppLocalizations.of(innerContext)!;
          final isLoading = authProvider.isLoading;

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
                    // withOpacity는 정밀도 이슈로 deprecate됨 → withAlpha 사용
                    color: BrandColors.error.withAlpha(26), // 0.1 * 255 ≈ 26
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.logout_rounded,
                    color: BrandColors.error,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  l10n.logout,
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF111827),
                  ),
                ),
              ],
            ),
            content: isLoading
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          l10n.loggingOut,
                          style: const TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF6B7280),
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  )
                : Text(
                    l10n.logoutConfirm,
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF374151),
                      height: 1.5,
                    ),
                  ),
            actions: [
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: isLoading
                          ? null
                          : () {
                              HapticFeedback.lightImpact();
                              Navigator.of(dialogContext).pop();
                            },
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
                        style: const TextStyle(
                          fontFamily: 'Pretendard',
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: isLoading
                          ? null
                          : () async {
                              // 중요한 액션 실행
                              HapticFeedback.heavyImpact();

                              try {
                                await authProvider.signOut();
                              } catch (_) {
                                // signOut 내부에서 상태 정리됨 (best-effort)
                              }

                              if (!dialogContext.mounted) return;
                              Navigator.of(dialogContext).pop();

                              if (!outerContext.mounted) return;
                              Navigator.of(outerContext).pushAndRemoveUntil(
                                MaterialPageRoute(
                                  builder: (_) => const LoginScreen(
                                    showLogoutSuccess: true,
                                  ),
                                ),
                                (route) => false,
                              );
                            },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        backgroundColor: BrandColors.error,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        disabledBackgroundColor: const Color(0xFFE5E7EB),
                      ),
                      child: isLoading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : Text(
                              l10n.logout,
                              style: const TextStyle(
                                fontFamily: 'Pretendard',
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      );
    },
  );
}

