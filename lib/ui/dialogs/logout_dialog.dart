// lib/ui/dialogs/logout_dialog.dart
// 로그아웃 확인 다이얼로그 (앱 공통 다이얼로그 스타일 적용)

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design/tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/auth_provider.dart';
import '../../screens/login_screen.dart';
import '../../utils/responsive_helper.dart';
import '../../l10n/ui_locale.dart';

Future<void> showLogoutConfirmDialog(
  BuildContext outerContext, {
  required AuthProvider authProvider,
}) {
  // 중요한 액션임을 알림
  HapticFeedback.mediumImpact();
  // The opening page may disappear when authentication notifies its listeners.
  // Keep navigation independent of that page's inherited-widget lookups.
  final outerNavigator = Navigator.of(outerContext);

  return showDialog<void>(
    context: outerContext,
    barrierDismissible: false,
    barrierColor: const Color(0x99000000),
    builder: (dialogContext) {
      return AnimatedBuilder(
        animation: authProvider,
        builder: (innerContext, _) {
          final l10n = AppLocalizations.of(innerContext)!;
          final isLoading = authProvider.isLoading;

          return Dialog(
            backgroundColor: Colors.white,
            elevation: 0,
            insetPadding: EdgeInsets.symmetric(
              horizontal: innerContext.rs(28).clamp(20, 36).toDouble(),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: MediaQuery.withClampedTextScaling(
                maxScaleFactor: 1.3,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    innerContext.rs(22).clamp(20, 24).toDouble(),
                    innerContext.rs(22).clamp(20, 24).toDouble(),
                    innerContext.rs(16).clamp(12, 18).toDouble(),
                    innerContext.rs(12).clamp(10, 14).toDouble(),
                  ),
                  child: _LogoutDialogContent(
                      child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.logout,
                        style: TextStyle(
                          fontFamily: uiFontFamily(innerContext, 'Inter'),
                          fontFamilyFallback: const ['NotoSansKR'],
                          fontSize:
                              innerContext.rf(17).clamp(16, 18).toDouble(),
                          fontWeight: FontWeight.w700,
                          height: 1.3,
                          color: const Color(0xFF111827),
                        ),
                      ),
                      SizedBox(
                        height: innerContext.rs(8).clamp(6, 10).toDouble(),
                      ),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        child: Text(
                          isLoading ? l10n.loggingOut : l10n.logoutConfirm,
                          key: ValueKey(isLoading),
                          style: TextStyle(
                            fontFamily: uiFontFamily(innerContext, 'Inter'),
                            fontFamilyFallback: const ['NotoSansKR'],
                            fontSize: innerContext
                                .rf(13.5)
                                .clamp(13, 14.5)
                                .toDouble(),
                            fontWeight: FontWeight.w400,
                            height: 1.5,
                            color: const Color(0xFF667085),
                          ),
                        ),
                      ),
                      SizedBox(
                        height: innerContext.rs(14).clamp(12, 18).toDouble(),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Wrap(
                          spacing: 2,
                          runSpacing: 2,
                          alignment: WrapAlignment.end,
                          children: [
                            TextButton(
                              onPressed: isLoading
                                  ? null
                                  : () {
                                      HapticFeedback.lightImpact();
                                      Navigator.of(dialogContext).pop();
                                    },
                              style: _dialogActionStyle(
                                const Color(0xFF667085),
                              ),
                              child: Text(
                                l10n.cancel,
                                style: TextStyle(
                                  fontFamily:
                                      uiFontFamily(innerContext, 'Inter'),
                                  fontFamilyFallback: const ['NotoSansKR'],
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: isLoading
                                  ? null
                                  : () => _performLogout(
                                        dialogContext,
                                        outerContext,
                                        authProvider,
                                        outerNavigator,
                                      ),
                              style: _dialogActionStyle(BrandColors.error),
                              child: isLoading
                                  ? const SizedBox.square(
                                      dimension: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: BrandColors.error,
                                      ),
                                    )
                                  : Text(
                                      l10n.logout,
                                      style: TextStyle(
                                        fontFamily:
                                            uiFontFamily(innerContext, 'Inter'),
                                        fontFamilyFallback: const [
                                          'NotoSansKR'
                                        ],
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )),
                ),
              ),
            ),
          );
        },
      );
    },
  );
}

class _LogoutDialogContent extends StatelessWidget {
  const _LogoutDialogContent({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      isChineseUi(context) ? SingleChildScrollView(child: child) : child;
}

ButtonStyle _dialogActionStyle(Color foregroundColor) => TextButton.styleFrom(
      foregroundColor: foregroundColor,
      disabledForegroundColor: const Color(0xFF98A2B3),
      minimumSize: const Size(64, 40),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      ),
    );

Future<void> _performLogout(
  BuildContext dialogContext,
  BuildContext outerContext,
  AuthProvider authProvider,
  NavigatorState outerNavigator,
) async {
  HapticFeedback.heavyImpact();
  final dialogNavigator = Navigator.of(dialogContext);

  try {
    await authProvider.signOut();
  } catch (_) {
    // signOut 내부에서 상태 정리됨 (best-effort)
  }

  if (!dialogContext.mounted || !dialogNavigator.mounted) return;
  dialogNavigator.pop();

  if (!outerContext.mounted || !outerNavigator.mounted) return;
  outerNavigator.pushAndRemoveUntil(
    MaterialPageRoute(
      builder: (_) => const LoginScreen(
        showLogoutSuccess: true,
      ),
    ),
    (route) => false,
  );
}
