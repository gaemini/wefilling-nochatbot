import 'dart:developer' as developer;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'logger.dart';

/// Opt-in chat latency instrumentation. Never logs message content or alters
/// the application's global verbose logging policy. Durations use Stopwatches;
/// device wall clocks must not be subtracted to claim one-way latency.
///
/// * Profile builds: `--dart-define=CHAT_TIMING=true` (unchanged).
/// * Release/internal measurement builds: additionally
///   `--dart-define=CHAT_TIMING_RELEASE=true`. Events are sampled per
///   message/room key with [sampleRate] (default 1.0) and emitted through
///   [Logger] so they appear in `adb logcat` / Xcode console for the baseline
///   report script (`functions/scripts/report_chat_timing.js`).
///
/// Store builds leave both defines unset, so this class is a no-op there.
class ChatTiming {
  static const bool _profileEnabled =
      !kReleaseMode && bool.fromEnvironment('CHAT_TIMING', defaultValue: false);
  static const bool _releaseEnabled =
      bool.fromEnvironment('CHAT_TIMING_RELEASE', defaultValue: false);
  static const enabled = _profileEnabled || _releaseEnabled;

  /// Fraction of sampled keys that are recorded (0.0–1.0). Read from
  /// `CHAT_TIMING_SAMPLE_RATE` as a percentage integer to keep it a const.
  static const int _sampleRatePercent =
      int.fromEnvironment('CHAT_TIMING_SAMPLE_RATE', defaultValue: 100);
  static double get sampleRate =>
      (_sampleRatePercent.clamp(0, 100)) / 100.0;

  /// Stable per-key sampling so every stage of one message/room entry is kept
  /// or dropped together. Keys are ids only, never text.
  static bool sampled(String key) {
    if (!enabled) return false;
    if (_sampleRatePercent >= 100) return true;
    if (_sampleRatePercent <= 0) return false;
    return (key.hashCode & 0x7fffffff) % 100 < _sampleRatePercent;
  }

  static void record(String event, {String? sampleKey}) {
    if (!enabled) return;
    if (sampleKey != null && !sampled(sampleKey)) return;
    developer.log(event, name: 'ChatTiming');
    developer.Timeline.instantSync('ChatTiming', arguments: {'event': event});
    if (_releaseEnabled) Logger.log('[ChatTiming] $event');
  }

  /// Records one measured stage. [durationMs] must come from a Stopwatch on
  /// the same device; [kind] is `snack`/`dm`; [key] is a message or room id.
  static void stage(
    String kind,
    String stage,
    int durationMs, {
    required String key,
    Map<String, Object?> extra = const {},
  }) {
    if (!enabled || !sampled(key)) return;
    final buffer = StringBuffer('[${kind}ChatTiming] $stage key=$key '
        'ms=${math.max(0, durationMs)}');
    for (final entry in extra.entries) {
      buffer.write(' ${entry.key}=${entry.value}');
    }
    record(buffer.toString());
  }
}
