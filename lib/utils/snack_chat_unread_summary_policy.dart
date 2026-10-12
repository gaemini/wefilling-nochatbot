import '../models/snack_chat_message.dart';

const int minimumUnreadMessagesForSummary = 3;
const int maximumLocalSummaryMessages = 2;
const int maximumUnreadSummaryItems = 5;
const int maximumLocalSummaryCharacters = 180;

class SnackChatUnreadSummaryPlan {
  const SnackChatUnreadSummaryPlan({
    required this.messages,
    required this.declaredUnreadCount,
    required this.shouldShowButton,
    required this.useLocalSummary,
  });

  final List<SnackChatMessage> messages;
  final int declaredUnreadCount;
  final bool shouldShowButton;
  final bool useLocalSummary;
}

SnackChatUnreadSummaryPlan buildSnackChatUnreadSummaryPlan({
  required Iterable<SnackChatMessage> messages,
  required String currentUserId,
  required int firstUnreadSequence,
  required int latestSequence,
  required int declaredUnreadCount,
}) {
  if (currentUserId.isEmpty ||
      firstUnreadSequence <= 0 ||
      latestSequence < firstUnreadSequence ||
      declaredUnreadCount <= 0) {
    return const SnackChatUnreadSummaryPlan(
      messages: <SnackChatMessage>[],
      declaredUnreadCount: 0,
      shouldShowButton: false,
      useLocalSummary: false,
    );
  }

  final byId = <String, SnackChatMessage>{};
  for (final message in messages) {
    final sequence = message.sequence;
    if (sequence == null ||
        sequence < firstUnreadSequence ||
        sequence > latestSequence ||
        message.senderId == currentUserId ||
        message.isDeleted ||
        message.type == SnackChatMessageType.system ||
        message.isPending ||
        message.hasFailed) {
      continue;
    }
    final delivered = message.deliveryRecipientIds;
    if (delivered != null &&
        delivered.isNotEmpty &&
        !delivered.contains(currentUserId)) {
      continue;
    }
    if (_summarySourceText(message).isEmpty && !_hasAttachment(message)) {
      continue;
    }
    byId[message.id] = message;
  }
  final candidates = byId.values.toList(growable: false)
    ..sort((a, b) => (a.sequence ?? 0).compareTo(b.sequence ?? 0));
  if (candidates.isEmpty) {
    return SnackChatUnreadSummaryPlan(
      messages: candidates,
      declaredUnreadCount: declaredUnreadCount,
      shouldShowButton: false,
      useLocalSummary: false,
    );
  }

  final effectiveUnreadCount = declaredUnreadCount > candidates.length
      ? declaredUnreadCount
      : candidates.length;
  if (effectiveUnreadCount < minimumUnreadMessagesForSummary) {
    return SnackChatUnreadSummaryPlan(
      messages: candidates,
      declaredUnreadCount: effectiveUnreadCount,
      shouldShowButton: false,
      useLocalSummary: false,
    );
  }

  return SnackChatUnreadSummaryPlan(
    messages: candidates,
    declaredUnreadCount: effectiveUnreadCount,
    shouldShowButton: true,
    useLocalSummary: false,
  );
}

/// Picks a small, useful extractive fallback when the server/provider is
/// temporarily unavailable. High-signal scheduling/questions/attachments are
/// preferred, duplicate and reaction-only messages are removed, and the final
/// items retain conversation order.
List<SnackChatMessage> selectSnackChatLocalFallbackMessages(
  Iterable<SnackChatMessage> messages, {
  int maximumItems = maximumUnreadSummaryItems,
}) {
  if (maximumItems <= 0) return const <SnackChatMessage>[];
  final unique = <String, SnackChatMessage>{};
  for (final message in messages) {
    final normalized = _normalizedSource(message);
    if (normalized.isEmpty || _isLowValueReaction(message)) continue;
    unique.putIfAbsent(normalized, () => message);
  }
  final ranked = unique.values.toList(growable: true)
    ..sort((first, second) {
      final byScore = _fallbackScore(second).compareTo(_fallbackScore(first));
      if (byScore != 0) return byScore;
      return (first.sequence ?? 0).compareTo(second.sequence ?? 0);
    });
  final selected = ranked.take(maximumItems).toList(growable: true)
    ..sort((first, second) =>
        (first.sequence ?? 0).compareTo(second.sequence ?? 0));
  return selected;
}

int _fallbackScore(SnackChatMessage message) {
  final source = _singleLine(_summarySourceText(message));
  var score = _containsImportantInformation(message) ? 1000 : 0;
  if (_hasAttachment(message)) score += 200;
  if (source.contains('?') || source.contains('？')) score += 100;
  score += _meaningfulCharacterCount(source).clamp(0, 160);
  return score;
}

String snackChatLocalSummaryText(
  SnackChatMessage message, {
  required bool isKorean,
}) {
  final text = message.text.trim();
  if (text.isNotEmpty) return snackChatLocalSummaryPreview(text);
  switch (message.type) {
    case SnackChatMessageType.image:
      return isKorean ? '이미지를 공유했어요.' : 'Shared an image.';
    case SnackChatMessageType.file:
      final fileName = message.originalFileName?.trim() ?? '';
      if (fileName.isNotEmpty) {
        return isKorean ? '$fileName 파일을 공유했어요.' : 'Shared the file $fileName.';
      }
      return isKorean ? '파일을 공유했어요.' : 'Shared a file.';
    case SnackChatMessageType.poll:
      final question = message.poll?.question.trim() ?? '';
      return question.isNotEmpty
          ? snackChatLocalSummaryPreview(question)
          : (isKorean ? '투표를 공유했어요.' : 'Shared a poll.');
    case SnackChatMessageType.text:
    case SnackChatMessageType.system:
    case SnackChatMessageType.unknown:
      return isKorean ? '새 메시지가 있어요.' : 'There is a new message.';
  }
}

String snackChatLocalSummaryPreview(String value) {
  final normalized = _singleLine(value);
  if (normalized.runes.length <= maximumLocalSummaryCharacters) {
    return normalized;
  }
  final sentenceEnd = RegExp(r'[.!?。！？]').firstMatch(normalized)?.end;
  if (sentenceEnd != null &&
      sentenceEnd >= 20 &&
      normalized.substring(0, sentenceEnd).runes.length <=
          maximumLocalSummaryCharacters) {
    return normalized.substring(0, sentenceEnd).trim();
  }
  return '${String.fromCharCodes(
    normalized.runes.take(maximumLocalSummaryCharacters),
  ).trimRight()}…';
}

bool _hasAttachment(SnackChatMessage message) {
  return message.type == SnackChatMessageType.image ||
      message.type == SnackChatMessageType.file ||
      message.type == SnackChatMessageType.poll;
}

String _summarySourceText(SnackChatMessage message) {
  final parts = <String>[message.text.trim()];
  final poll = message.poll;
  if (poll != null) {
    parts.add(poll.question.trim());
    parts.addAll(poll.options.map((option) => option.text.trim()));
  }
  if (message.type == SnackChatMessageType.file) {
    parts.add(message.originalFileName?.trim() ?? '');
  }
  final preview = message.linkPreview;
  if (preview != null) {
    parts.add(preview.url.trim());
    parts.add(preview.title.trim());
  }
  return parts.where((part) => part.isNotEmpty).join(' ');
}

String _normalizedSource(SnackChatMessage message) {
  final source = _singleLine(_summarySourceText(message)).toLowerCase();
  if (source.isNotEmpty) return source;
  return _hasAttachment(message) ? '${message.type.name}:${message.id}' : '';
}

String _singleLine(String value) =>
    value.replaceAll(RegExp(r'\s+'), ' ').trim();

int _meaningfulCharacterCount(String value) {
  return RegExp(
    r'[A-Za-z0-9가-힣ㄱ-ㆎ぀-ヿ㐀-鿿Ѐ-ӿ؀-ۿ]',
  ).allMatches(value).length;
}

bool _containsImportantInformation(SnackChatMessage message) {
  if (_hasAttachment(message)) return true;
  final text = _singleLine(_summarySourceText(message));
  if (text.length >= 80 || text.contains('?') || text.contains('？')) {
    return true;
  }
  return RegExp(
    r'(https?://|www\.|\b\d{1,2}[:시]\s*\d{0,2}\b|\b\d{1,2}[./-]\d{1,2}\b|'
    r'오늘|내일|모레|매주|다음\s*주|요일|시간|일정|장소|미팅|회의|온라인|오프라인|어디|언제|변경|취소|결정|준비|공유|요청|부탁|해줘|해주세요|할까|가능|'
    r'\b(today|tomorrow|tonight|monday|tuesday|wednesday|thursday|friday|saturday|sunday|when|where|please|could you|can you|change|cancel|schedule|meeting|meet|location|address)\b)',
    caseSensitive: false,
  ).hasMatch(text);
}

bool _isLowValueReaction(SnackChatMessage message) {
  final text = _singleLine(_summarySourceText(message)).toLowerCase();
  final compact = text.replaceAll(RegExp(r'[^a-z0-9가-힣ㄱ-ㆎ]+'), '');
  if (RegExp(
    r'^(안녕(하세요)?|반가워(요)?|제이름은.+(이에요|입니다)|오늘같이.+반가워(요)?)$',
  ).hasMatch(compact)) {
    return true;
  }
  if (_containsImportantInformation(message)) return false;
  final meaningful = _meaningfulCharacterCount(text);
  if (meaningful == 0) return true;
  if (meaningful <= 3) return true;
  return const <String>{
    'ㅋ',
    'ㅋㅋ',
    'ㅋㅋㅋ',
    'ㅎㅎ',
    'ㅇㅇ',
    'ㅇㅋ',
    '네',
    '넥',
    '응',
    '어',
    '오케이',
    '안녕',
    '안녕하세요',
    '반가워',
    '반가워요',
    '고마워',
    '감사',
    'hi',
    'hey',
    'hello',
    'ok',
    'okay',
    'yes',
    'no',
    'thanks',
    'thankyou',
    'lol',
  }.contains(compact);
}
