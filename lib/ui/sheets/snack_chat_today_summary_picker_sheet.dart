import 'package:flutter/material.dart';

import '../../l10n/ui_locale.dart';
import '../../utils/responsive_helper.dart';

enum SnackChatTodaySummaryCategory {
  highlights,
  schedule,
  tasks,
  decisions,
  questions,
  information,
  people,
  casual,
}

enum SnackChatTodaySummaryScope { today, unread, relatedToMe }

class SnackChatTodaySummaryRequest {
  const SnackChatTodaySummaryRequest({
    required this.categories,
    required this.scope,
    this.question = '',
  });

  final Set<SnackChatTodaySummaryCategory> categories;
  final SnackChatTodaySummaryScope scope;
  final String question;

  bool get isDirectSearch => question.trim().isNotEmpty;
}

Future<SnackChatTodaySummaryRequest?> showSnackChatTodaySummaryPickerSheet(
  BuildContext context, {
  required bool hasUnreadMessages,
}) {
  final rootBottomInset = MediaQuery.viewPaddingOf(context).bottom;
  return showModalBottomSheet<SnackChatTodaySummaryRequest>(
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
    builder: (sheetContext) => _TodaySummaryPickerSheet(
      hasUnreadMessages: hasUnreadMessages,
      rootBottomInset: rootBottomInset,
    ),
  );
}

class _TodaySummaryPickerSheet extends StatefulWidget {
  const _TodaySummaryPickerSheet({
    required this.hasUnreadMessages,
    required this.rootBottomInset,
  });

  final bool hasUnreadMessages;
  final double rootBottomInset;

  @override
  State<_TodaySummaryPickerSheet> createState() =>
      _TodaySummaryPickerSheetState();
}

class _TodaySummaryPickerSheetState extends State<_TodaySummaryPickerSheet> {
  final TextEditingController _questionController = TextEditingController();
  final Set<SnackChatTodaySummaryCategory> _categories = {
    SnackChatTodaySummaryCategory.highlights,
  };
  SnackChatTodaySummaryScope _scope = SnackChatTodaySummaryScope.today;

  bool get _isKo => Localizations.localeOf(context).languageCode == 'ko';
  bool get _isZh => isChineseUi(context);

  @override
  void dispose() {
    _questionController.dispose();
    super.dispose();
  }

  String _categoryLabel(SnackChatTodaySummaryCategory value) {
    switch (value) {
      case SnackChatTodaySummaryCategory.highlights:
        return _isZh
            ? '核心内容'
            : _isKo
                ? '핵심 내용'
                : 'Highlights';
      case SnackChatTodaySummaryCategory.schedule:
        return _isZh
            ? '日程·约定'
            : _isKo
                ? '일정·약속'
                : 'Plans';
      case SnackChatTodaySummaryCategory.tasks:
        return _isZh
            ? '待办事项'
            : _isKo
                ? '해야 할 일'
                : 'Tasks';
      case SnackChatTodaySummaryCategory.decisions:
        return _isZh
            ? '决定·通知'
            : _isKo
                ? '결정·공지'
                : 'Decisions';
      case SnackChatTodaySummaryCategory.questions:
        return _isZh
            ? '问答'
            : _isKo
                ? '질문·답변'
                : 'Q&A';
      case SnackChatTodaySummaryCategory.information:
        return _isZh
            ? '资料·信息'
            : _isKo
                ? '자료·정보'
                : 'Resources';
      case SnackChatTodaySummaryCategory.people:
        return _isZh
            ? '人员·参与'
            : _isKo
                ? '사람·참여'
                : 'People';
      case SnackChatTodaySummaryCategory.casual:
        return _isZh
            ? '有趣的话题'
            : _isKo
                ? '재밌었던 이야기'
                : 'Fun chat';
    }
  }

  String _scopeLabel(SnackChatTodaySummaryScope value) {
    switch (value) {
      case SnackChatTodaySummaryScope.today:
        return _isZh
            ? '今天全部'
            : _isKo
                ? '오늘 전체'
                : 'All today';
      case SnackChatTodaySummaryScope.unread:
        return _isZh
            ? '未读对话'
            : _isKo
                ? '안 읽은 대화'
                : 'Unread';
      case SnackChatTodaySummaryScope.relatedToMe:
        return _isZh
            ? '与我相关'
            : _isKo
                ? '나와 관련된 내용'
                : 'Related to me';
    }
  }

  void _submit() {
    final question = _questionController.text.trim();
    if (question.isEmpty && _categories.isEmpty) return;
    Navigator.pop(
      context,
      SnackChatTodaySummaryRequest(
        categories: Set.unmodifiable(_categories),
        scope: _scope,
        question: question,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final sheetInset = MediaQuery.viewPaddingOf(context).bottom;
    final safeBottom = widget.rootBottomInset > sheetInset
        ? widget.rootBottomInset
        : sheetInset;
    final isSearching = _questionController.text.trim().isNotEmpty;
    final horizontal = context.rs(20).clamp(18, 24).toDouble();

    return SafeArea(
      top: false,
      bottom: false,
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        padding: EdgeInsets.only(bottom: keyboardInset),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.86,
          ),
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding:
                EdgeInsets.fromLTRB(horizontal, 2, horizontal, safeBottom + 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _isZh
                            ? '查找今日对话'
                            : _isKo
                                ? '오늘 대화에서 찾기'
                                : 'Find in today’s chat',
                        style: TextStyle(
                          fontFamily: uiFontFamily(context, 'Inter'),
                          fontFamilyFallback: const ['NotoSansKR'],
                          fontSize: context.rf(20).clamp(18, 21).toDouble(),
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF111827),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: _isZh
                          ? '关闭'
                          : _isKo
                              ? '닫기'
                              : 'Close',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  _isZh
                      ? '想整理哪些内容？'
                      : _isKo
                          ? '어떤 내용을 정리할까요?'
                          : 'What should be organized?',
                  style: _sectionStyle(context),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children:
                      SnackChatTodaySummaryCategory.values.map((category) {
                    final selected = _categories.contains(category);
                    return FilterChip(
                      selected: selected,
                      showCheckmark: false,
                      label: Text(_categoryLabel(category), maxLines: 1),
                      labelStyle: TextStyle(
                        fontFamily: uiFontFamily(context, 'Inter'),
                        fontFamilyFallback: const ['NotoSansKR'],
                        fontSize: 13,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w600,
                        color: selected
                            ? const Color(0xFF087BB5)
                            : const Color(0xFF475467),
                      ),
                      backgroundColor: Colors.white,
                      selectedColor: const Color(0xFFEAF7FC),
                      side: BorderSide(
                        color: selected
                            ? const Color(0xFF87CBE8)
                            : const Color(0xFFD0D5DD),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      visualDensity: VisualDensity.compact,
                      onSelected: (value) => setState(() {
                        value
                            ? _categories.add(category)
                            : _categories.remove(category);
                      }),
                    );
                  }).toList(growable: false),
                ),
                const SizedBox(height: 22),
                Text(
                  _isZh
                      ? '查看范围'
                      : _isKo
                          ? '조회 범위'
                          : 'Range',
                  style: _sectionStyle(context),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: SnackChatTodaySummaryScope.values.map((scope) {
                    final disabled =
                        scope == SnackChatTodaySummaryScope.unread &&
                            !widget.hasUnreadMessages;
                    return ChoiceChip(
                      selected: _scope == scope,
                      showCheckmark: false,
                      label: Text(_scopeLabel(scope), maxLines: 1),
                      onSelected: disabled
                          ? null
                          : (_) => setState(() => _scope = scope),
                      backgroundColor: Colors.white,
                      selectedColor: const Color(0xFFEAF7FC),
                      disabledColor: Colors.white,
                      side: BorderSide(
                        color: _scope == scope
                            ? const Color(0xFF87CBE8)
                            : const Color(0xFFD0D5DD),
                      ),
                      labelStyle: TextStyle(
                        fontFamily: uiFontFamily(context, 'Inter'),
                        fontFamilyFallback: const ['NotoSansKR'],
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: disabled
                            ? const Color(0xFFB8C0CC)
                            : _scope == scope
                                ? const Color(0xFF087BB5)
                                : const Color(0xFF475467),
                      ),
                    );
                  }).toList(growable: false),
                ),
                const SizedBox(height: 22),
                Text(
                  _isZh
                      ? '直接查找'
                      : _isKo
                          ? '직접 찾기'
                          : 'Ask directly',
                  style: _sectionStyle(context),
                ),
                const SizedBox(height: 5),
                Text(
                  _isZh
                      ? '仅从当前聊天室今天的对话中查找。'
                      : _isKo
                          ? '현재 방의 오늘 대화에서만 답을 찾아요.'
                          : 'Answers use only today’s messages in this room.',
                  style: TextStyle(
                    fontFamily: uiFontFamily(context, 'Inter'),
                    fontFamilyFallback: const ['NotoSansKR'],
                    fontSize: 13,
                    height: 1.4,
                    color: const Color(0xFF667085),
                  ),
                ),
                const SizedBox(height: 9),
                TextField(
                  controller: _questionController,
                  minLines: 1,
                  maxLines: 3,
                  maxLength: 200,
                  textInputAction: TextInputAction.done,
                  onChanged: (value) => setState(() {
                    if (value.trim().isNotEmpty) {
                      _scope = SnackChatTodaySummaryScope.today;
                    }
                  }),
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    hintText: _isZh
                        ? '例：今晚约在几点？'
                        : _isKo
                            ? '예: 오늘 저녁 약속 몇 시였지?'
                            : 'e.g. What time was dinner?',
                    counterText: '',
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton(
                    onPressed:
                        isSearching || _categories.isNotEmpty ? _submit : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF087BB5),
                      shape: const StadiumBorder(),
                    ),
                    child: Text(
                      isSearching
                          ? (_isZh
                              ? '查找'
                              : _isKo
                                  ? '찾기'
                                  : 'Find')
                          : (_isZh
                              ? '查看总结'
                              : _isKo
                                  ? '정리 보기'
                                  : 'View recap'),
                      style: TextStyle(
                        fontFamily: uiFontFamily(context, 'Inter'),
                        fontFamilyFallback: const ['NotoSansKR'],
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  TextStyle _sectionStyle(BuildContext context) => TextStyle(
        fontFamily: uiFontFamily(context, 'Inter'),
        fontFamilyFallback: const ['NotoSansKR'],
        fontSize: 15,
        fontWeight: FontWeight.w800,
        color: const Color(0xFF1D2939),
      );
}
