import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';

/// Opt-in profile instrumentation. Never logs message content or alters the
/// application's global verbose logging policy. Durations use Stopwatches;
/// device wall clocks must not be subtracted to claim one-way latency.
class ChatTiming {
  static const enabled =
      !kReleaseMode && bool.fromEnvironment('CHAT_TIMING', defaultValue: false);

  static void record(String event) {
    if (!enabled) return;
    developer.log(event, name: 'ChatTiming');
    developer.Timeline.instantSync('ChatTiming', arguments: {'event': event});
  }
}
