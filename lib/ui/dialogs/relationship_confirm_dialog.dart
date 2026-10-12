// lib/ui/dialogs/relationship_confirm_dialog.dart
// 친구 관계 액션(요청 취소·친구 삭제·차단 해제 등) 확인 다이얼로그.
// 프로필 화면과 포스트 카드 친구 버튼이 같은 확인 흐름을 쓴다.

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

Future<bool> showRelationshipConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String? confirmLabel,
  String? cancelLabel,
}) async {
  final loc = AppLocalizations.of(context)!;
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(cancelLabel ?? loc.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel ?? loc.confirm),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// 보낸 친구 요청 취소 확인(프로필 화면과 같은 문구).
Future<bool> confirmCancelFriendRequest(BuildContext context) {
  final loc = AppLocalizations.of(context)!;
  return showRelationshipConfirmDialog(
    context,
    title: loc.cancelFriendRequest,
    message: loc.confirmCancelFriendRequest,
    confirmLabel: loc.cancelFriendRequest,
  );
}
