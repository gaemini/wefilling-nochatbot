// lib/ui/widgets/profile_share_sheet.dart
// 내 프로필 공유 시트: QR + 링크 복사 + 시스템 공유.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../l10n/profile_share_strings.dart';
import '../../l10n/ui_locale.dart';
import '../../services/profile_link.dart';

Future<void> showProfileShareSheet(
  BuildContext context, {
  required String uid,
  required String nickname,
}) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: false,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => ProfileShareSheet(uid: uid, nickname: nickname),
  );
}

class ProfileShareSheet extends StatelessWidget {
  const ProfileShareSheet({
    super.key,
    required this.uid,
    required this.nickname,
  });

  final String uid;
  final String nickname;

  /// 시스템 공유 시트를 연다. 열지 못하면(플러그인 미적용 등) 링크를 복사해
  /// 아무 반응이 없는 상태로 두지 않는다.
  static Future<void> _shareSystem(
    BuildContext context, {
    required String text,
    required String link,
    required String copiedMessage,
  }) async {
    final box = context.findRenderObject() as RenderBox?;
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await SharePlus.instance.share(
        ShareParams(
          text: text,
          // iPad 팝오버 기준 위치(시트 영역).
          sharePositionOrigin: box == null || !box.hasSize
              ? null
              : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: link));
      messenger?.showSnackBar(SnackBar(content: Text(copiedMessage)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = ProfileShareStrings.of(context);
    final link = ProfileLink.build(uid);
    // 안드로이드 제스처/3버튼 바가 시트를 가리지 않도록 아래쪽 여백을 직접 더한다.
    final view = View.of(context);
    final mq = MediaQuery.of(context);
    final bottomInset = [
      mq.padding.bottom,
      mq.viewPadding.bottom,
      view.viewPadding.bottom / view.devicePixelRatio,
      mq.systemGestureInsets.bottom,
    ].reduce((a, b) => a > b ? a : b);
    TextStyle style(double size, FontWeight weight, Color color) => TextStyle(
          fontFamily: uiFontFamily(context, 'Inter'),
          fontFamilyFallback: const ['NotoSansKR'],
          fontSize: size,
          fontWeight: weight,
          color: color,
        );
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE0E0E0),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text(strings.title,
                style: style(17, FontWeight.w700, const Color(0xFF111827))),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: QrImageView(
                key: const ValueKey('profile_share_qr'),
                data: link,
                size: (mq.size.height * 0.26).clamp(130.0, 190.0),
                backgroundColor: Colors.white,
                semanticsLabel: link,
              ),
            ),
            const SizedBox(height: 12),
            Text(nickname,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style(15, FontWeight.w600, const Color(0xFF111827))),
            const SizedBox(height: 4),
            Text(strings.qrCaption,
                style: style(12, FontWeight.w400, const Color(0xFF707070))),
            const SizedBox(height: 4),
            Text(link,
                key: const ValueKey('profile_share_link'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style(12, FontWeight.w400, const Color(0xFF9A9A9A))),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: OutlinedButton(
                      key: const ValueKey('profile_share_copy'),
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: link));
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(strings.copied)),
                        );
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF111827),
                        side: const BorderSide(color: Color(0xFFD9D9D9)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Text(strings.copy,
                          style: style(14, FontWeight.w600,
                              const Color(0xFF111827))),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: FilledButton(
                      key: const ValueKey('profile_share_system'),
                      onPressed: () => _shareSystem(
                        context,
                        text: strings.shareText(nickname, link),
                        link: link,
                        copiedMessage: strings.copied,
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF2C6BC0),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Text(strings.share,
                          style: style(14, FontWeight.w600, Colors.white)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
