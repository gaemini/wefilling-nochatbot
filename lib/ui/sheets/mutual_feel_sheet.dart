// lib/ui/sheets/mutual_feel_sheet.dart
// 서로 필링 순간: 두 사람이 서로의 스낵에 필링했을 때 올라오는 흰 시트.
// 표현 위젯(MutualFeelSheet)과 서비스에 연결하는 열기 함수를 함께 둔다.

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/ui_locale.dart';
import '../../models/relationship_status.dart';
import '../../models/snapshot.dart';
import '../../models/snapshot_mutual_feel.dart';
import '../../providers/relationship_provider.dart';
import '../../screens/dm_chat_screen.dart';
import '../../services/dm_service.dart';
import '../../services/snapshot_service.dart';
import '../../services/user_info_cache_service.dart';
import '../../snapshot/mutual_feel_shown_store.dart';
import '../../snapshot/snapshot_storage_image.dart';
import '../../snapshot/snapshot_strings.dart';
import '../widgets/user_avatar.dart';

const Color _accent = Color(0xFF2C6BC0);

/// 순수 표현 위젯. 버튼 상태는 [status]로 정한다.
class MutualFeelSheet extends StatelessWidget {
  const MutualFeelSheet({
    super.key,
    required this.otherName,
    required this.myAvatar,
    required this.otherAvatar,
    required this.status,
    required this.onMessage,
    required this.onAddFriend,
    this.myThumbnail,
    this.theirThumbnail,
  });

  final String otherName;
  final Widget myAvatar;
  final Widget otherAvatar;

  /// null이면 관계를 아직 모르는 상태(친구 추가를 보여 준다).
  final RelationshipStatus? status;
  final VoidCallback onMessage;
  final VoidCallback onAddFriend;
  final Widget? myThumbnail;
  final Widget? theirThumbnail;

  TextStyle _style(
    BuildContext context,
    double size,
    FontWeight weight,
    Color color, {
    double? line,
  }) =>
      TextStyle(
        fontFamily: uiFontFamily(context, 'Inter'),
        fontFamilyFallback: const ['NotoSansKR'],
        fontSize: size,
        height: (line ?? size * 1.3) / size,
        fontWeight: weight,
        letterSpacing: -0.2,
        color: color,
      );

  @override
  Widget build(BuildContext context) {
    final strings = SnapshotStrings.of(context);
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final isFriend = status == RelationshipStatus.friends;
    final pending = status == RelationshipStatus.pendingOut;
    Widget avatar(Widget child, double fromX) => TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: reduce ? 0 : fromX, end: 0),
          duration: reduce ? Duration.zero : const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic,
          builder: (context, dx, child) =>
              Transform.translate(offset: Offset(dx, 0), child: child),
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
            ),
            child: ClipOval(child: child),
          ),
        );
    Widget thumb(Widget? child) => ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 48,
            height: 64,
            child: child ?? const ColoredBox(color: Color(0xFFEEEEEE)),
          ),
        );
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.25,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(
          20,
          28,
          20,
          MediaQuery.paddingOf(context).bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                avatar(myAvatar, -48),
                Transform.translate(
                  offset: const Offset(-16, 0),
                  child: avatar(otherAvatar, 48),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              strings.mutualFeel,
              key: const ValueKey('mutual_feel_title'),
              style: _style(context, 18, FontWeight.w700, Colors.black,
                  line: 24),
            ),
            const SizedBox(height: 8),
            Text(
              '${strings.mutualFeelTheyToo(otherName)}\n${strings.mutualFeelPrompt}',
              textAlign: TextAlign.center,
              style: _style(
                context,
                13,
                FontWeight.w400,
                const Color(0xFF5F5F5F),
                line: 19,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                thumb(myThumbnail),
                const SizedBox(width: 8),
                thumb(theirThumbnail),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: Material(
                color: _accent,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  key: const ValueKey('mutual_feel_message'),
                  borderRadius: BorderRadius.circular(14),
                  onTap: onMessage,
                  child: Center(
                    child: Text(
                      strings.sendMessageButton,
                      style: _style(context, 15, FontWeight.w600, Colors.white,
                          line: 20),
                    ),
                  ),
                ),
              ),
            ),
            if (!isFriend) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: Material(
                  color: const Color(0xFFEEEEEE),
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    key: const ValueKey('mutual_feel_add_friend'),
                    borderRadius: BorderRadius.circular(14),
                    onTap: pending ? null : onAddFriend,
                    child: Center(
                      child: Text(
                        pending ? strings.feelRequested : strings.addFriendShort,
                        style: _style(
                          context,
                          15,
                          FontWeight.w600,
                          pending ? const Color(0xFF707070) : Colors.black,
                          line: 20,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 서비스에 연결된 열기 함수. 시트를 닫은 뒤 DM으로 이어 갈 수 있다.
Future<void> showMutualFeelSheet(
  BuildContext context, {
  required String otherUserId,
  required String otherName,
  String otherPhotoUrl = '',
  int otherPhotoVersion = 0,
  SnapshotMutualFeel? mutual,
}) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: false,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: .7),
    builder: (_) => _MutualFeelSheetHost(
      otherUserId: otherUserId,
      otherName: otherName,
      otherPhotoUrl: otherPhotoUrl,
      otherPhotoVersion: otherPhotoVersion,
      mutual: mutual,
    ),
  );
}

/// 알림에서 열 때: 쌍 키나 상대 uid로 서버 목록에서 찾아 시트를 연다.
Future<void> showMutualFeelSheetForPair(
  BuildContext context, {
  required String otherUserId,
  String otherName = '',
  String pairKey = '',
}) async {
  SnapshotMutualFeel? found;
  try {
    final list = await SnapshotService.instance.getMyMutualFeels();
    for (final item in list) {
      if ((pairKey.isNotEmpty && item.pairKey == pairKey) ||
          item.otherUserId == otherUserId) {
        found = item;
        break;
      }
    }
  } catch (_) {}
  if (!context.mounted) return;
  final cached = UserInfoCacheService().getCachedUserInfo(otherUserId);
  await showMutualFeelSheet(
    context,
    otherUserId: otherUserId,
    otherName: found?.otherName.isNotEmpty == true
        ? found!.otherName
        : (otherName.isNotEmpty ? otherName : (cached?.nickname ?? '')),
    otherPhotoUrl: found?.otherPhotoUrl ?? cached?.photoURL ?? '',
    otherPhotoVersion: found?.otherPhotoVersion ?? cached?.photoVersion ?? 0,
    mutual: found,
  );
}

/// 내가 필링한 직후, 방금 서로 필링이 열렸는지 확인하고 한 번만 띄운다.
Future<void> maybeShowMutualFeelAfterFeel(
  BuildContext context, {
  required String snapshotId,
}) async {
  try {
    final list =
        await SnapshotService.instance.getMyMutualFeels(snapshotId: snapshotId);
    unawaited(SnapshotService.instance.refreshMutualFeels());
    final recent = list.where((item) =>
        DateTime.now().difference(item.createdAt) < const Duration(minutes: 2));
    for (final item in recent) {
      final stamp = item.createdAt.millisecondsSinceEpoch;
      if (await MutualFeelShownStore.instance.wasShown(item.pairKey, stamp)) {
        continue;
      }
      await MutualFeelShownStore.instance.markShown(item.pairKey, stamp);
      if (!context.mounted) return;
      await showMutualFeelSheet(
        context,
        otherUserId: item.otherUserId,
        otherName: item.otherName,
        otherPhotoUrl: item.otherPhotoUrl,
        otherPhotoVersion: item.otherPhotoVersion,
        mutual: item,
      );
      return;
    }
  } catch (_) {
    // 서로 필링 확인 실패는 필링 자체에 영향을 주지 않는다.
  }
}

class _MutualFeelSheetHost extends StatelessWidget {
  const _MutualFeelSheetHost({
    required this.otherUserId,
    required this.otherName,
    required this.otherPhotoUrl,
    required this.otherPhotoVersion,
    required this.mutual,
  });

  final String otherUserId;
  final String otherName;
  final String otherPhotoUrl;
  final int otherPhotoVersion;
  final SnapshotMutualFeel? mutual;

  Widget? _thumb(SnapshotFeelThumbnail? feel) {
    if (feel == null || !feel.hasImage) return null;
    final item = SnapshotItem.fromMap(feel.snapshotId, <String, dynamic>{
      'mediaType': feel.isVideo ? 'video' : 'photo',
      'storagePath': feel.imageStoragePath,
      'thumbnailStoragePath': feel.imageStoragePath,
      'storageBucket': feel.storageBucket,
    });
    return SnapshotStorageImage(snapshot: item, decodeWidth: 160);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.read<RelationshipProvider>();
    unawaited(provider.ensureInitialized().catchError((Object _) {}));
    final myUid = provider.currentUserId ?? '';
    return Selector<RelationshipProvider, RelationshipStatus?>(
      selector: (_, p) => p.feedRelationshipStatus(otherUserId),
      builder: (context, status, _) => MutualFeelSheet(
        otherName: otherName,
        status: status,
        myAvatar: UserAvatar(
          uid: myUid,
          photoUrl: FirebaseAuth.instance.currentUser?.photoURL ?? '',
          photoVersion: 0,
          isAnonymous: false,
          size: 58,
        ),
        otherAvatar: UserAvatar(
          uid: otherUserId,
          photoUrl: otherPhotoUrl,
          photoVersion: otherPhotoVersion,
          isAnonymous: false,
          size: 58,
        ),
        myThumbnail: _thumb(mutual?.mine),
        theirThumbnail: _thumb(mutual?.theirs),
        onMessage: () async {
          final navigator = Navigator.of(context);
          final route = ModalRoute.of(context);
          String? room;
          try {
            room = await DMService().prepareConversationForOpen(otherUserId);
          } catch (_) {
            return;
          }
          // 연타 시 두 번째 호출은 시트가 이미 닫혀 있으므로 아래 화면을 닫지 않는다.
          if (room == null || !navigator.mounted || route?.isCurrent != true) {
            return;
          }
          final conversationId = room;
          navigator.pop();
          await navigator.push<void>(
            MaterialPageRoute(
              builder: (_) => DMChatScreen(
                  conversationId: conversationId, otherUserId: otherUserId),
            ),
          );
        },
        onAddFriend: () =>
            unawaited(provider.sendFriendRequest(otherUserId, silent: true)),
      ),
    );
  }
}
