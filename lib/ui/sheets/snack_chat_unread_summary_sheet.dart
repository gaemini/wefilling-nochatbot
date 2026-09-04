import 'package:flutter/material.dart';

import '../../services/snack_chat_service.dart';
import '../../utils/responsive_helper.dart';

Future<void> showSnackChatUnreadSummarySheet(
  BuildContext context, {
  required List<SnackChatUnreadSummaryItem> items,
  required int messageCount,
  List<SnackChatUnreadSummarySection> sections =
      const <SnackChatUnreadSummarySection>[],
  DateTime? sourceStartedAt,
  DateTime? sourceEndedAt,
  String overview = '',
  String otherConversationSummary = '',
  SnackChatSummaryRangeType rangeType = SnackChatSummaryRangeType.unread,
}) async {
  if (items.isEmpty &&
      sections.isEmpty &&
      overview.isEmpty &&
      otherConversationSummary.isEmpty) {
    return;
  }
  final rootBottomInset = MediaQuery.viewPaddingOf(context).bottom;
  await showModalBottomSheet<void>(
    context: context,
    useSafeArea: false,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    barrierColor: Colors.black.withValues(alpha: 0.42),
    elevation: 0,
    constraints: const BoxConstraints(maxWidth: 600),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) => _SnackChatUnreadSummarySheet(
      items: items,
      sections: sections,
      messageCount: messageCount,
      sourceStartedAt: sourceStartedAt,
      sourceEndedAt: sourceEndedAt,
      overview: overview,
      otherConversationSummary: otherConversationSummary,
      rangeType: rangeType,
      rootBottomInset: rootBottomInset,
    ),
  );
}

class _SnackChatUnreadSummarySheet extends StatelessWidget {
  const _SnackChatUnreadSummarySheet({
    required this.items,
    required this.sections,
    required this.messageCount,
    required this.sourceStartedAt,
    required this.sourceEndedAt,
    required this.overview,
    required this.otherConversationSummary,
    required this.rangeType,
    required this.rootBottomInset,
  });

  final List<SnackChatUnreadSummaryItem> items;
  final List<SnackChatUnreadSummarySection> sections;
  final int messageCount;
  final DateTime? sourceStartedAt;
  final DateTime? sourceEndedAt;
  final String overview;
  final String otherConversationSummary;
  final SnackChatSummaryRangeType rangeType;
  final double rootBottomInset;

  List<SnackChatUnreadSummarySection> _displaySections(bool isKo) {
    if (sections.isNotEmpty) {
      return sections
          .where((section) =>
              section.type != SnackChatSummarySectionType.otherConversation)
          .take(5)
          .toList(growable: false);
    }
    if (overview.isNotEmpty) {
      return const <SnackChatUnreadSummarySection>[];
    }
    return <SnackChatUnreadSummarySection>[
      SnackChatUnreadSummarySection(
        type: SnackChatSummarySectionType.mustKnow,
        title: isKo ? '꼭 확인하세요' : 'Must know',
        items: items,
      ),
    ];
  }

  String _defaultSectionTitle(
    SnackChatUnreadSummarySection section,
    bool isKo,
  ) {
    switch (section.type) {
      case SnackChatSummarySectionType.mustKnow:
        return isKo ? '해야 할 일' : 'Your next steps';
      case SnackChatSummarySectionType.responseRequired:
        return isKo ? '답장이 필요한 내용' : 'Needs your reply';
      case SnackChatSummarySectionType.scheduleAndPlace:
        return isKo ? '일정' : 'Schedule';
      case SnackChatSummarySectionType.decisionsAndChanges:
        final statuses = section.items.map((item) => item.status).toSet();
        if (statuses.length == 1) {
          switch (statuses.single) {
            case SnackChatSummaryStatus.changed:
              return isKo ? '변경된 내용' : 'Changed';
            case SnackChatSummaryStatus.cancelled:
              return isKo ? '취소된 내용' : 'Cancelled';
            case SnackChatSummaryStatus.confirmed:
              return isKo ? '확정된 내용' : 'Confirmed';
            case SnackChatSummaryStatus.proposed:
            case SnackChatSummaryStatus.unresolved:
            case SnackChatSummaryStatus.responseRequired:
            case SnackChatSummaryStatus.information:
              break;
          }
        }
        return isKo ? '결정 및 변경' : 'Decisions and changes';
      case SnackChatSummarySectionType.unresolved:
        return isKo ? '아직 정해지지 않은 내용' : 'Still undecided';
      case SnackChatSummarySectionType.sharedInformation:
        return isKo ? '공유된 내용' : 'Shared';
      case SnackChatSummarySectionType.otherConversation:
        return isKo ? '그 외 이야기' : 'Other conversation';
    }
  }

  String _statusLabel(SnackChatSummaryStatus status, bool isKo) {
    switch (status) {
      case SnackChatSummaryStatus.confirmed:
        return '';
      case SnackChatSummaryStatus.proposed:
        return '';
      case SnackChatSummaryStatus.changed:
        return isKo ? '변경' : 'Changed';
      case SnackChatSummaryStatus.cancelled:
        return isKo ? '취소' : 'Cancelled';
      case SnackChatSummaryStatus.unresolved:
        return '';
      case SnackChatSummaryStatus.responseRequired:
        return '';
      case SnackChatSummaryStatus.information:
        return '';
    }
  }

  String _timeRange(BuildContext context) {
    final start = sourceStartedAt?.toLocal();
    final end = sourceEndedAt?.toLocal();
    if (start == null && end == null) return '';
    final localizations = MaterialLocalizations.of(context);
    final use24Hour = MediaQuery.alwaysUse24HourFormatOf(context);
    String format(DateTime value) => localizations.formatTimeOfDay(
          TimeOfDay.fromDateTime(value),
          alwaysUse24HourFormat: use24Hour,
        );
    if (start == null) return format(end!);
    if (end == null || start.isAtSameMomentAs(end)) return format(start);
    return '${format(start)}~${format(end)}';
  }

  @override
  Widget build(BuildContext context) {
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    final sheetBottomInset = MediaQuery.viewPaddingOf(context).bottom;
    final safeBottom =
        rootBottomInset > sheetBottomInset ? rootBottomInset : sheetBottomInset;
    final displaySections = _displaySections(isKo);
    final count = messageCount > 0
        ? messageCount
        : displaySections.fold<int>(
            0,
            (total, section) => total + section.items.length,
          );
    final range = _timeRange(context);
    final isToday = rangeType == SnackChatSummaryRangeType.today;

    return SafeArea(
      top: false,
      bottom: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.78,
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            context.rs(20).clamp(18, 24).toDouble(),
            2,
            context.rs(20).clamp(18, 24).toDouble(),
            safeBottom + context.rs(20).clamp(18, 24).toDouble(),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isToday
                                ? (isKo ? '오늘 대화 정리' : "Today's recap")
                                : (isKo ? '놓친 대화 정리' : 'What you missed'),
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontFamilyFallback: const ['NotoSansKR'],
                              fontSize: context.rf(20).clamp(18, 21).toDouble(),
                              fontWeight: FontWeight.w800,
                              height: 1.25,
                              color: const Color(0xFF111827),
                            ),
                          ),
                          SizedBox(
                            height: context.rs(5).clamp(4, 7).toDouble(),
                          ),
                          Text(
                            isToday
                                ? (range.isEmpty
                                    ? (isKo
                                        ? '오늘 메시지 $count개'
                                        : '$count messages today')
                                    : (isKo
                                        ? '오늘 메시지 $count개 · $range'
                                        : '$count messages today · $range'))
                                : (range.isEmpty
                                    ? (isKo
                                        ? '새 메시지 $count개'
                                        : '$count new messages')
                                    : (isKo
                                        ? '새 메시지 $count개 · $range'
                                        : '$count new messages · $range')),
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontFamilyFallback: const ['NotoSansKR'],
                              fontSize: context.rf(13).clamp(12, 14).toDouble(),
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF667085),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: isKo ? '닫기' : 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                    color: const Color(0xFF475467),
                    iconSize: context.ri(21).clamp(20, 23).toDouble(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 44,
                      height: 44,
                    ),
                  ),
                ],
              ),
              SizedBox(height: context.rs(22).clamp(18, 26).toDouble()),
              if (overview.isNotEmpty) ...[
                _SummaryTextBlock(
                  title: isKo ? '한눈에 보기' : 'Quick recap',
                  content: overview,
                ),
                if (displaySections.isNotEmpty ||
                    otherConversationSummary.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.symmetric(
                      vertical: context.rs(18).clamp(15, 22).toDouble(),
                    ),
                    child: const Divider(
                      height: 1,
                      color: Color(0xFFEAECF0),
                    ),
                  ),
              ],
              for (var index = 0; index < displaySections.length; index++) ...[
                _SummarySectionView(
                  section: displaySections[index],
                  title: _defaultSectionTitle(displaySections[index], isKo),
                  isKo: isKo,
                  statusLabel: _statusLabel,
                ),
                if (index != displaySections.length - 1 ||
                    otherConversationSummary.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.symmetric(
                      vertical: context.rs(18).clamp(15, 22).toDouble(),
                    ),
                    child: const Divider(height: 1, color: Color(0xFFEAECF0)),
                  ),
              ],
              if (otherConversationSummary.isNotEmpty)
                _SummaryTextBlock(
                  title: isKo ? '그 외 이야기' : 'Other conversation',
                  content: otherConversationSummary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryTextBlock extends StatelessWidget {
  const _SummaryTextBlock({required this.title, required this.content});

  final String title;
  final String content;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontFamily: 'Inter',
            fontFamilyFallback: const ['NotoSansKR'],
            fontSize: context.rf(16).clamp(15, 17).toDouble(),
            fontWeight: FontWeight.w800,
            height: 1.35,
            color: const Color(0xFF111827),
          ),
        ),
        SizedBox(height: context.rs(9).clamp(8, 11).toDouble()),
        Text(
          content,
          softWrap: true,
          textWidthBasis: TextWidthBasis.parent,
          style: TextStyle(
            fontFamily: 'Inter',
            fontFamilyFallback: const ['NotoSansKR'],
            fontSize: context.rf(15).clamp(14, 16).toDouble(),
            fontWeight: FontWeight.w500,
            height: 1.5,
            color: const Color(0xFF1D2939),
          ),
        ),
      ],
    );
  }
}

class _SummarySectionView extends StatelessWidget {
  const _SummarySectionView({
    required this.section,
    required this.title,
    required this.isKo,
    required this.statusLabel,
  });

  final SnackChatUnreadSummarySection section;
  final String title;
  final bool isKo;
  final String Function(SnackChatSummaryStatus status, bool isKo) statusLabel;

  @override
  Widget build(BuildContext context) {
    final isOther =
        section.type == SnackChatSummarySectionType.otherConversation;
    final sectionStatuses = section.items.map((item) => item.status).toSet();
    final hideRepeatedDecisionStatus =
        section.type == SnackChatSummarySectionType.decisionsAndChanges &&
            sectionStatuses.length == 1 &&
            const <SnackChatSummaryStatus>{
              SnackChatSummaryStatus.confirmed,
              SnackChatSummaryStatus.changed,
              SnackChatSummaryStatus.cancelled,
            }.contains(sectionStatuses.single);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontFamily: 'Inter',
            fontFamilyFallback: const ['NotoSansKR'],
            fontSize: context.rf(16).clamp(15, 17).toDouble(),
            fontWeight: FontWeight.w800,
            height: 1.35,
            color: const Color(0xFF111827),
          ),
        ),
        SizedBox(height: context.rs(12).clamp(10, 14).toDouble()),
        for (var index = 0; index < section.items.length; index++) ...[
          _SummaryItemView(
            item: section.items[index],
            isOtherConversation: isOther,
            statusText: hideRepeatedDecisionStatus
                ? ''
                : statusLabel(section.items[index].status, isKo),
          ),
          if (index != section.items.length - 1)
            SizedBox(height: context.rs(14).clamp(12, 17).toDouble()),
        ],
      ],
    );
  }
}

class _SummaryItemView extends StatelessWidget {
  const _SummaryItemView({
    required this.item,
    required this.isOtherConversation,
    required this.statusText,
  });

  final SnackChatUnreadSummaryItem item;
  final bool isOtherConversation;
  final String statusText;

  Widget _label(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (item.label.isNotEmpty)
          Text(
            item.label,
            style: TextStyle(
              fontFamily: 'Inter',
              fontFamilyFallback: const ['NotoSansKR'],
              fontSize: context.rf(13).clamp(12, 14).toDouble(),
              fontWeight: FontWeight.w700,
              height: 1.35,
              color: const Color(0xFF087BB5),
            ),
          ),
        if (statusText.isNotEmpty)
          Text(
            statusText,
            style: TextStyle(
              fontFamily: 'Inter',
              fontFamilyFallback: const ['NotoSansKR'],
              fontSize: context.rf(12).clamp(11, 13).toDouble(),
              fontWeight: FontWeight.w700,
              height: 1.35,
              color: const Color(0xFF087BB5),
            ),
          ),
      ],
    );
  }

  Widget _content(BuildContext context) {
    return Text(
      item.content,
      softWrap: true,
      textWidthBasis: TextWidthBasis.parent,
      style: TextStyle(
        fontFamily: 'Inter',
        fontFamilyFallback: const ['NotoSansKR'],
        fontSize: context.rf(15).clamp(14, 16).toDouble(),
        fontWeight: FontWeight.w500,
        height: 1.5,
        color: const Color(0xFF1D2939),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isOtherConversation || (item.label.isEmpty && statusText.isEmpty)) {
      return _content(context);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        final useWideLayout = constraints.maxWidth >= 460 && textScale <= 1.3;
        if (useWideLayout) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 116, child: _label(context)),
              const SizedBox(width: 14),
              Expanded(child: _content(context)),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label(context),
            SizedBox(height: context.rs(5).clamp(4, 7).toDouble()),
            _content(context),
          ],
        );
      },
    );
  }
}
