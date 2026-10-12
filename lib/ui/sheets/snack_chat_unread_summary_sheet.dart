import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../services/snack_chat_service.dart';
import '../../utils/responsive_helper.dart';
import '../../l10n/ui_locale.dart';

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
  String titleOverride = '',
  Future<void> Function(String messageId)? onOpenSource,
  bool useProvidedSectionTitles = false,
  bool keepOpenOnSource = false,
  bool includeOtherConversation = false,
  String? accountOwnerUid,
}) async {
  if (items.isEmpty &&
      sections.isEmpty &&
      overview.isEmpty &&
      otherConversationSummary.isEmpty) {
    return;
  }
  final rootBottomInset = MediaQuery.viewPaddingOf(context).bottom;
  final owner = accountOwnerUid;
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
    builder: (sheetContext) {
      final sheet = _SnackChatUnreadSummarySheet(
      items: items,
      sections: sections,
      messageCount: messageCount,
      sourceStartedAt: sourceStartedAt,
      sourceEndedAt: sourceEndedAt,
      overview: overview,
      otherConversationSummary: otherConversationSummary,
      rangeType: rangeType,
      titleOverride: titleOverride,
      onOpenSource: onOpenSource,
      keepOpenOnSource: keepOpenOnSource,
      includeOtherConversation: includeOtherConversation,
      useProvidedSectionTitles: useProvidedSectionTitles,
      rootBottomInset: rootBottomInset,
      );
      if (owner == null) return sheet;
      return StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, _) => FirebaseAuth.instance.currentUser?.uid == owner
            ? sheet : const SizedBox.shrink(),
      );
    },
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
    required this.titleOverride,
    required this.onOpenSource,
    required this.keepOpenOnSource,
    required this.includeOtherConversation,
    required this.useProvidedSectionTitles,
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
  final String titleOverride;
  final Future<void> Function(String messageId)? onOpenSource;
  final bool keepOpenOnSource;
  final bool includeOtherConversation;
  final bool useProvidedSectionTitles;
  final double rootBottomInset;

  List<SnackChatUnreadSummarySection> _displaySections(
      BuildContext context, bool isKo) {
    if (sections.isNotEmpty) {
      return sections
          .where((section) =>
              includeOtherConversation || section.type != SnackChatSummarySectionType.otherConversation)
          .take(8)
          .toList(growable: false);
    }
    if (overview.isNotEmpty) {
      return const <SnackChatUnreadSummarySection>[];
    }
    return <SnackChatUnreadSummarySection>[
      SnackChatUnreadSummarySection(
        type: SnackChatSummarySectionType.mustKnow,
        title: (isChineseUi(context)
            ? '重要信息'
            : isKo
                ? '꼭 확인하세요'
                : 'Must know'),
        items: items,
      ),
    ];
  }

  String _defaultSectionTitle(
    BuildContext context,
    SnackChatUnreadSummarySection section,
    bool isKo,
  ) {
    switch (section.type) {
      case SnackChatSummarySectionType.mustKnow:
        return (isChineseUi(context)
            ? '接下来要做'
            : isKo
                ? '해야 할 일'
                : 'Your next steps');
      case SnackChatSummarySectionType.responseRequired:
        return (isChineseUi(context)
            ? '待你回复'
            : isKo
                ? '답장이 필요한 내용'
                : 'Needs your reply');
      case SnackChatSummarySectionType.scheduleAndPlace:
        return (isChineseUi(context)
            ? '日程'
            : isKo
                ? '일정'
                : 'Schedule');
      case SnackChatSummarySectionType.decisionsAndChanges:
        final statuses = section.items.map((item) => item.status).toSet();
        if (statuses.length == 1) {
          switch (statuses.single) {
            case SnackChatSummaryStatus.changed:
              return (isChineseUi(context)
                  ? '已变更'
                  : isKo
                      ? '변경된 내용'
                      : 'Changed');
            case SnackChatSummaryStatus.cancelled:
              return (isChineseUi(context)
                  ? '已取消'
                  : isKo
                      ? '취소된 내용'
                      : 'Cancelled');
            case SnackChatSummaryStatus.confirmed:
              return (isChineseUi(context)
                  ? '已确认'
                  : isKo
                      ? '확정된 내용'
                      : 'Confirmed');
            case SnackChatSummaryStatus.proposed:
            case SnackChatSummaryStatus.unresolved:
            case SnackChatSummaryStatus.responseRequired:
            case SnackChatSummaryStatus.information:
              break;
          }
        }
        return (isChineseUi(context)
            ? '决定与变更'
            : isKo
                ? '결정 및 변경'
                : 'Decisions and changes');
      case SnackChatSummarySectionType.unresolved:
        return (isChineseUi(context)
            ? '尚未确定'
            : isKo
                ? '아직 정해지지 않은 내용'
                : 'Still undecided');
      case SnackChatSummarySectionType.sharedInformation:
        return (isChineseUi(context)
            ? '分享内容'
            : isKo
                ? '공유된 내용'
                : 'Shared');
      case SnackChatSummarySectionType.otherConversation:
        return (isChineseUi(context)
            ? '其他对话'
            : isKo
                ? '그 외 이야기'
                : 'Other conversation');
    }
  }

  String _statusLabel(
      BuildContext context, SnackChatSummaryStatus status, bool isKo) {
    switch (status) {
      case SnackChatSummaryStatus.confirmed:
        return '';
      case SnackChatSummaryStatus.proposed:
        return '';
      case SnackChatSummaryStatus.changed:
        return (isChineseUi(context)
            ? '已变更'
            : isKo
                ? '변경'
                : 'Changed');
      case SnackChatSummaryStatus.cancelled:
        return (isChineseUi(context)
            ? '已取消'
            : isKo
                ? '취소'
                : 'Cancelled');
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
    final displaySections = _displaySections(context, isKo);
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
                            titleOverride.isNotEmpty
                                ? titleOverride
                                : isToday
                                    ? ((isChineseUi(context)
                                        ? '今日总结'
                                        : isKo
                                            ? '오늘 대화 정리'
                                            : "Today's recap"))
                                    : ((isChineseUi(context)
                                        ? '错过的内容'
                                        : isKo
                                            ? '놓친 대화 정리'
                                            : 'What you missed')),
                            style: TextStyle(
                              fontFamily: uiFontFamily(context, 'Inter'),
                              fontFamilyFallback: const ['NotoSansKR'],
                              fontSize: context.rf(20).clamp(18, 21).toDouble(),
                              fontWeight: FontWeight.w800,
                              height: isChineseUi(context) ? 1.3 : 1.25,
                              color: const Color(0xFF111827),
                            ),
                          ),
                          SizedBox(
                            height: context.rs(5).clamp(4, 7).toDouble(),
                          ),
                          Text(
                            isToday
                                ? (range.isEmpty
                                    ? ((isChineseUi(context)
                                        ? '今日${count}条消息'
                                        : isKo
                                            ? '오늘 메시지 $count개'
                                            : '$count messages today'))
                                    : ((isChineseUi(context)
                                        ? '今日${count}条消息 · ${range}'
                                        : isKo
                                            ? '오늘 메시지 $count개 · $range'
                                            : '$count messages today · $range')))
                                : (range.isEmpty
                                    ? ((isChineseUi(context)
                                        ? '${count}条新消息'
                                        : isKo
                                            ? '새 메시지 $count개'
                                            : '$count new messages'))
                                    : ((isChineseUi(context)
                                        ? '${count}条新消息 · ${range}'
                                        : isKo
                                            ? '새 메시지 $count개 · $range'
                                            : '$count new messages · $range'))),
                            style: TextStyle(
                              fontFamily: uiFontFamily(context, 'Inter'),
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
                    tooltip: (isChineseUi(context)
                        ? '关闭'
                        : isKo
                            ? '닫기'
                            : 'Close'),
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
                  title: (isChineseUi(context)
                      ? '快速总结'
                      : isKo
                          ? '한눈에 보기'
                          : 'Quick recap'),
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
                  title: useProvidedSectionTitles &&
                          displaySections[index].title.trim().isNotEmpty
                      ? displaySections[index].title.trim()
                      : _defaultSectionTitle(
                          context, displaySections[index], isKo),
                  isKo: isKo,
                  statusLabel: (status, korean) =>
                      _statusLabel(context, status, korean),
                  onOpenSource: onOpenSource,
      keepOpenOnSource: keepOpenOnSource,
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
                  title: (isChineseUi(context)
                      ? '其他对话'
                      : isKo
                          ? '그 외 이야기'
                          : 'Other conversation'),
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
            fontFamily: uiFontFamily(context, 'Inter'),
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
            fontFamily: uiFontFamily(context, 'Inter'),
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
    required this.onOpenSource,
    required this.keepOpenOnSource,
  });

  final SnackChatUnreadSummarySection section;
  final String title;
  final bool isKo;
  final String Function(SnackChatSummaryStatus status, bool isKo) statusLabel;
  final Future<void> Function(String messageId)? onOpenSource;
  final bool keepOpenOnSource;

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
            fontFamily: uiFontFamily(context, 'Inter'),
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
            onOpenSource: onOpenSource,
      keepOpenOnSource: keepOpenOnSource,
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
    required this.onOpenSource,
    required this.keepOpenOnSource,
  });

  final SnackChatUnreadSummaryItem item;
  final bool isOtherConversation;
  final String statusText;
  final Future<void> Function(String messageId)? onOpenSource;
  final bool keepOpenOnSource;

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
              fontFamily: uiFontFamily(context, 'Inter'),
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
              fontFamily: uiFontFamily(context, 'Inter'),
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
    final messageId = item.representativeMessageId.isNotEmpty
        ? item.representativeMessageId
        : (item.sourceMessageIds.isEmpty ? null : item.sourceMessageIds.first);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          item.content,
          softWrap: true,
          textWidthBasis: TextWidthBasis.parent,
          style: TextStyle(
            fontFamily: uiFontFamily(context, 'Inter'),
            fontFamilyFallback: const ['NotoSansKR'],
            fontSize: context.rf(15).clamp(14, 16).toDouble(),
            fontWeight: FontWeight.w500,
            height: 1.5,
            color: const Color(0xFF1D2939),
          ),
        ),
        if (messageId != null && onOpenSource != null) ...[
          const SizedBox(height: 4),
          TextButton.icon(
            onPressed: () async {
              if (!keepOpenOnSource) Navigator.of(context).pop();
              await onOpenSource!(messageId);
            },
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF087BB5),
              minimumSize: const Size(0, 34),
              padding: EdgeInsets.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
            icon: const Icon(Icons.forum_outlined, size: 16),
            label: Text(
              isChineseUi(context)
                  ? '查看原消息'
                  : Localizations.localeOf(context).languageCode == 'ko'
                      ? '원문 보기'
                      : 'View message',
              style: TextStyle(
                fontFamily: uiFontFamily(context, 'Inter'),
                fontFamilyFallback: const ['NotoSansKR'],
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ],
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
