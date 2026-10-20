import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../models/social_profile_data.dart';
import '../providers/auth_provider.dart';
import 'interest_tag_service.dart';

class TagLimitException implements Exception {
  const TagLimitException();
}

/// 내 프로필 #태그의 낙관적 상태. 저장하는 동안 바뀐 목록을 먼저 보여 주고,
/// 실패하면 서버 값(users.interestTagIds)으로 되돌린다.
/// 마이페이지 블록·태그 둘러보기·태그 시트가 같은 값을 본다.
class MyTagsStore extends ChangeNotifier {
  MyTagsStore._();
  static final instance = MyTagsStore._();

  List<String>? _pending;
  int _version = 0;

  /// 앞선 저장이 끝난 뒤에 다음 저장을 보낸다(순서 보장). 비어 있으면 null.
  Future<void>? _tail;

  /// 서버 목록에 저장 중인 변경을 얹은 값.
  List<String> resolve(List<String> server) => _pending ?? server;

  static List<String> serverTags(AuthProvider auth) =>
      SocialProfileData.fromMap(auth.userData).interestTagIds;

  /// 저장 중인 변경을 버린다(테스트·로그아웃).
  @visibleForTesting
  void debugReset() {
    _pending = null;
    _version++;
    _tail = null;
  }

  /// [change]로 만든 목록을 바로 보여 주고 저장한다. 새로 단 태그마다 gain을 돌려준다.
  /// 8개를 넘으면 [TagLimitException], 저장 실패면 되돌리고 다시 던진다.
  Future<Map<String, int>> save(
    AuthProvider auth,
    List<String> Function(List<String> current) change, {
    bool withGain = false,
  }) async {
    final next = change(resolve(serverTags(auth)));
    if (next.length > InterestTagService.maxProfileTags) {
      throw const TagLimitException();
    }
    final version = ++_version;
    _pending = next;
    notifyListeners();
    final previous = _tail;
    final op = previous == null
        ? InterestTagService.instance.saveProfileTags(next, withGain: withGain)
        : previous.then((_) => InterestTagService.instance
            .saveProfileTags(next, withGain: withGain));
    final tail = op.then<void>((_) {}, onError: (_) {});
    _tail = tail;
    tail.whenComplete(() {
      if (identical(_tail, tail)) _tail = null;
    });
    try {
      final result = await op;
      await auth.refreshUser();
      if (version == _version) {
        _pending = null;
        notifyListeners();
      }
      return result.gain;
    } catch (_) {
      if (version == _version) {
        _pending = null;
        notifyListeners();
      }
      rethrow;
    }
  }

  Future<int> add(AuthProvider auth, String tagId) async {
    final gain = await save(auth,
        (current) => current.contains(tagId) ? current : [...current, tagId],
        withGain: true);
    return gain[tagId] ?? 0;
  }

  Future<void> remove(AuthProvider auth, String tagId) => save(
      auth,
      (current) => [
            for (final id in current)
              if (id != tagId) id
          ]);

  /// 지운 태그를 원래 자리로 되돌린다(되돌리기).
  Future<void> restore(AuthProvider auth, String tagId, int index) =>
      save(auth, (current) {
        if (current.contains(tagId)) return current;
        final next = [...current];
        next.insert(index.clamp(0, next.length), tagId);
        return next;
      });
}

/// 내 #태그(낙관적 상태 포함)가 바뀔 때 다시 그린다.
class MyTagsBuilder extends StatelessWidget {
  const MyTagsBuilder({super.key, required this.builder});

  final Widget Function(BuildContext context, List<String> tags) builder;

  @override
  Widget build(BuildContext context) {
    final server = context.select<AuthProvider, List<String>>(
        (auth) => MyTagsStore.serverTags(auth));
    return ListenableBuilder(
      listenable: MyTagsStore.instance,
      builder: (context, _) =>
          builder(context, MyTagsStore.instance.resolve(server)),
    );
  }
}
