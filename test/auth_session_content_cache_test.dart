import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/providers/auth_provider.dart';
import 'package:wefilling/services/content_filter_service.dart';
import 'package:wefilling/services/content_hide_service.dart';

void main() {
  test('account switch clears block and reported-content caches', () {
    ContentFilterService.setBlockedUserIds(<String>{'old-blocked'});
    ContentFilterService.setBlockedByUserIds(<String>{'old-blocker'});
    ContentFilterService.setBlockedAnonymousPostIds(<String>{'old-anon'});
    ContentHideService.hideReportedTarget(
      targetType: 'post',
      targetId: 'old-post',
      reportedUserId: 'old-reported-user',
    );
    ContentHideService.hideReportedTarget(
      targetType: 'meetup',
      targetId: 'old-meetup',
    );

    clearAccountScopedContentCaches();

    expect(ContentFilterService.getBlockedUserIdsCached(), isEmpty);
    expect(ContentFilterService.getBlockedByUserIdsCached(), isEmpty);
    expect(ContentFilterService.getBlockedAnonymousPostIdsCached(), isEmpty);
    expect(ContentHideService.isHiddenPost('old-post'), isFalse);
    expect(ContentHideService.isHiddenMeetup('old-meetup'), isFalse);
    expect(ContentHideService.isHiddenUser('old-reported-user'), isFalse);
  });
}
