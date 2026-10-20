import 'package:flutter/foundation.dart';

import '../utils/logger.dart';
import 'interest_tag_service.dart';

/// '새로 알게 될 사람'에서 숨긴 사람. 관심 탭 레일과 '모두 보기'가 같이 본다.
/// 서버 저장(setSuggestionHidden)은 기다리지 않고, 실패하면 로그만 남긴다
/// (다음 새로고침에서 서버 목록으로 맞춰진다).
class OverlapHiddenStore extends ChangeNotifier {
  OverlapHiddenStore._();
  static final instance = OverlapHiddenStore._();

  final Set<String> _hidden = <String>{};

  bool isHidden(String uid) => _hidden.contains(uid);

  void hide(String uid) {
    if (!_hidden.add(uid)) return;
    notifyListeners();
    _save(uid, hidden: true);
  }

  void restore(String uid) {
    if (!_hidden.remove(uid)) return;
    notifyListeners();
    _save(uid, hidden: false);
  }

  void _save(String uid, {required bool hidden}) {
    InterestTagService.instance
        .setSuggestionHidden(uid, hidden: hidden)
        .catchError((Object error) {
      Logger.warning('setSuggestionHidden 실패($hidden): $error');
    });
  }

  @visibleForTesting
  void debugReset() => _hidden.clear();
}
