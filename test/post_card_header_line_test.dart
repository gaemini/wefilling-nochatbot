import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/l10n/app_localizations.dart';
import 'package:wefilling/models/relationship_status.dart';
import 'package:wefilling/ui/widgets/post_card_friend_button.dart';
import 'package:wefilling/ui/widgets/post_card_header_line.dart';

void main() {
  const names = <String, String>{
    'en': 'Alexandria Montgomery-Fitzgerald the Third',
    'zh': '欧阳娜娜非常非常长的中文名字测试用户',
    'ko': '아주아주긴한국어닉네임입니다정말로길어요',
  };

  for (final width in const [320.0, 375.0, 430.0]) {
    for (final scale in const [1.0, 1.3, 2.0]) {
      testWidgets('머리줄 오버플로우 없음 $width/$scale', (tester) async {
        for (final entry in names.entries) {
          for (final status in const [
            RelationshipStatus.none,
            RelationshipStatus.pendingOut,
            RelationshipStatus.pendingIn,
          ]) {
            await tester.binding.setSurfaceSize(Size(width, 200));
            addTearDown(() => tester.binding.setSurfaceSize(null));
            await tester.pumpWidget(MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: Locale(entry.key),
              home: MediaQuery(
                data: MediaQueryData(
                  size: Size(width, 200),
                  textScaler: TextScaler.linear(scale),
                ),
                child: Scaffold(
                  body: Padding(
                    // 카드: 좌우 패딩 + 아바타 40 + 간격 4
                    padding: const EdgeInsets.only(left: 16 + 44, right: 16),
                    child: PostCardHeaderLine(
                      name: Text(entry.value,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      details: const <Widget>[
                        SizedBox(width: 4),
                        Text('·'),
                        SizedBox(width: 4),
                        Flexible(
                          child: Text('17분 전',
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                      ],
                      trailing: PostCardFriendButton(
                        status: status,
                        onSend: () async => true,
                        onCancel: () async => true,
                        onAccept: () async => true,
                      ),
                    ),
                  ),
                ),
              ),
            ));
            expect(tester.takeException(), isNull,
                reason: '${entry.key} $status');
            expect(find.byKey(const ValueKey('post-card-friend-button')),
                findsOneWidget);
          }
        }
      });
    }
  }
}
