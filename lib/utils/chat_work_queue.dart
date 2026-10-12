import 'dart:async';

/// One running job and one replaceable pending job per account/room. Callers
/// merge deltas before submitting; a slow disk write cannot replace newer data.
class ChatLatestWriter {
  final Map<String, Future<void> Function()> _pending = {};
  final Map<String, Future<void>> _running = {};

  Future<void> schedule(String key, Future<void> Function() write) {
    _pending[key] = write;
    return _running.putIfAbsent(key, () async {
      // Install the running future before invoking any user code.
      await Future<void>.value();
      try {
        while (_pending.containsKey(key)) {
          await _pending.remove(key)!();
        }
      } finally {
        _running.remove(key);
      }
    });
  }
}

/// Ordered commits; failures do not poison later sends. Upload preparation
/// deliberately uses a separate queue, so text can overtake a slow image.
class ChatWorkQueue {
  final Map<String, Future<void>> _tails = {};

  Future<T> run<T>(String key, Future<T> Function() job) {
    final previous = _tails[key] ?? Future<void>.value();
    final result = previous.then((_) => job());
    final tail =
        result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    _tails[key] = tail;
    unawaited(tail.then((_) {
      if (identical(_tails[key], tail)) _tails.remove(key);
    }));
    return result;
  }
}
