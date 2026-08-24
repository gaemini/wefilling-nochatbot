import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/snack_chat_message.dart';
import '../../screens/snack_chat_poll_schedule_screen.dart';
import '../../utils/responsive_helper.dart';

Future<SnackChatPoll?> showSnackChatPollDialog(BuildContext context) {
  return Navigator.of(context).push<SnackChatPoll>(
    MaterialPageRoute<SnackChatPoll>(
      fullscreenDialog: true,
      builder: (_) => const SnackChatPollDialog(),
    ),
  );
}

class SnackChatPollDialog extends StatefulWidget {
  const SnackChatPollDialog({
    super.key,
    this.rootBottomInset = 0,
  });

  // 이전 바텀시트 호출부와의 소스 호환을 위한 값이다. 전체 화면에서는
  // Scaffold와 SafeArea가 시스템 하단 여백을 직접 처리한다.
  final double rootBottomInset;

  @override
  State<SnackChatPollDialog> createState() => _SnackChatPollDialogState();
}

class _SnackChatPollDialogState extends State<SnackChatPollDialog> {
  static const int _maxOptions = 10;
  static const int _maxQuestionLength = 120;
  static const int _maxOptionLength = 60;

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _questionController = TextEditingController();
  final List<_PollOptionDraft> _options = <_PollOptionDraft>[];

  bool _initializedOptions = false;
  bool _allowMultiple = false;
  bool _isAnonymous = false;
  int _nextOptionId = 0;
  DateTime? _closesAt;
  String? _formError;

  bool get _isKo => Localizations.localeOf(context).languageCode == 'ko';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initializedOptions) return;
    _initializedOptions = true;
    _options.addAll(<_PollOptionDraft>[
      _newOption(_isKo ? '참석' : 'Attending'),
      _newOption(_isKo ? '불참' : 'Not attending'),
      _newOption(_isKo ? '미정' : 'Maybe'),
    ]);
  }

  @override
  void dispose() {
    _questionController.dispose();
    for (final option in _options) {
      option.dispose();
    }
    super.dispose();
  }

  _PollOptionDraft _newOption([String text = '']) {
    return _PollOptionDraft(
      id: _nextOptionId++,
      controller: TextEditingController(text: text),
      focusNode: FocusNode(),
    );
  }

  void _addOption() {
    if (_options.length >= _maxOptions) return;
    final option = _newOption();
    setState(() {
      _options.add(option);
      _formError = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_options.contains(option)) return;
      option.focusNode.requestFocus();
    });
  }

  void _removeOption(_PollOptionDraft option) {
    if (_options.length <= 2 || !_options.contains(option)) return;
    option.focusNode.unfocus();
    setState(() {
      _options.remove(option);
      _formError = null;
    });
    // Keep the controller/focus node alive until the removed EditableText has
    // actually unmounted at the end of this frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => option.dispose());
  }

  Future<void> _selectClosingTime() async {
    final now = DateTime.now();
    final initial = _closesAt != null && _closesAt!.isAfter(now)
        ? _closesAt!
        : now.add(const Duration(hours: 1));
    final selected = await Navigator.of(context).push<DateTime>(
      MaterialPageRoute<DateTime>(
        builder: (_) => SnackChatPollScheduleScreen(
          initialDateTime: initial,
          firstDate: DateUtils.dateOnly(now),
          lastDate: DateUtils.dateOnly(now.add(const Duration(days: 365))),
        ),
      ),
    );
    if (selected == null || !mounted) return;
    if (!selected.isAfter(DateTime.now())) {
      setState(() {
        _formError = _isKo
            ? '종료 시간은 현재 시간 이후로 선택해주세요.'
            : 'Choose an end time later than now.';
      });
      return;
    }

    setState(() {
      _closesAt = selected;
      _formError = null;
    });
  }

  void _submit() {
    FocusScope.of(context).unfocus();
    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) return;

    final normalizedOptions = _options
        .map((option) => option.controller.text.trim())
        .toList(growable: false);
    final uniqueOptions =
        normalizedOptions.map((option) => option.toLowerCase()).toSet();
    if (uniqueOptions.length != normalizedOptions.length) {
      setState(() {
        _formError =
            _isKo ? '같은 선택지를 두 번 사용할 수 없어요.' : 'Each option must be unique.';
      });
      return;
    }
    if (_closesAt != null && !_closesAt!.isAfter(DateTime.now())) {
      setState(() {
        _formError = _isKo
            ? '종료 시간은 현재 시간 이후여야 해요.'
            : 'The end time must be later than now.';
      });
      return;
    }

    final poll = SnackChatPoll(
      question: _questionController.text.trim(),
      options: <SnackChatPollOption>[
        for (var index = 0; index < _options.length; index++)
          SnackChatPollOption(
            id: 'option_${_options[index].id}',
            text: normalizedOptions[index],
          ),
      ],
      allowMultiple: _allowMultiple,
      isAnonymous: _isAnonymous,
      closesAt: _closesAt,
    );
    Navigator.of(context).pop(poll);
  }

  String _formatClosingTime(DateTime value) {
    final material = MaterialLocalizations.of(context);
    final date = material.formatMediumDate(value);
    final time = TimeOfDay.fromDateTime(value).format(context);
    return '$date · $time';
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final horizontalPadding = screenWidth < 360 ? 14.0 : 20.0;
    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: true,
      appBar: _buildAppBar(),
      body: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.3,
        child: SafeArea(
          top: false,
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                context.rs(12).clamp(8, 16).toDouble(),
                horizontalPadding,
                context.rs(28).clamp(24, 36).toDouble(),
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSectionLabel(
                        _isKo ? '투표 제목' : 'Poll question',
                      ),
                      TextFormField(
                        controller: _questionController,
                        maxLength: _maxQuestionLength,
                        maxLengthEnforcement:
                            MaxLengthEnforcement.truncateAfterCompositionEnds,
                        textInputAction: TextInputAction.next,
                        onChanged: (_) {
                          if (_formError != null) {
                            setState(() => _formError = null);
                          }
                        },
                        validator: (value) {
                          if ((value ?? '').trim().isEmpty) {
                            return _isKo
                                ? '투표 제목을 입력해주세요.'
                                : 'Enter a poll question.';
                          }
                          return null;
                        },
                        style: _inputTextStyle(context),
                        decoration: _inputDecoration(
                          hintText: _isKo
                              ? '무엇을 정할까요?'
                              : 'What would you like to decide?',
                        ),
                      ),
                      SizedBox(
                        height: context.rs(24).clamp(20, 28).toDouble(),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: _buildSectionLabel(
                              _isKo ? '선택지' : 'Options',
                            ),
                          ),
                          Text(
                            '${_options.length}/$_maxOptions',
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              fontFamilyFallback: const ['NotoSansKR'],
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF6B7280),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      for (var index = 0; index < _options.length; index++)
                        _buildOptionField(_options[index], index),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed:
                              _options.length < _maxOptions ? _addOption : null,
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFF475467),
                            disabledForegroundColor: const Color(0xFFB8C0CC),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            minimumSize: const Size(44, 44),
                          ),
                          icon: const Icon(Icons.add_rounded, size: 19),
                          label: Text(
                            _isKo ? '선택지 추가' : 'Add option',
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              fontFamilyFallback: const ['NotoSansKR'],
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        height: context.rs(18).clamp(14, 22).toDouble(),
                      ),
                      const Divider(height: 1, color: Color(0xFFE5E7EB)),
                      SizedBox(
                        height: context.rs(10).clamp(8, 12).toDouble(),
                      ),
                      _buildSettingRow(
                        title: _isKo ? '복수 선택' : 'Multiple choices',
                        description: _isKo
                            ? '끄면 한 가지 선택지만 고를 수 있어요.'
                            : 'When off, participants can choose one option.',
                        value: _allowMultiple,
                        onChanged: (value) {
                          setState(() => _allowMultiple = value);
                        },
                      ),
                      _buildSettingRow(
                        title: _isKo ? '익명 투표' : 'Anonymous voting',
                        description: _isKo
                            ? '참여자에게 누가 선택했는지 표시하지 않아요.'
                            : 'Participant choices will not show names.',
                        value: _isAnonymous,
                        onChanged: (value) {
                          setState(() => _isAnonymous = value);
                        },
                      ),
                      SizedBox(
                        height: context.rs(8).clamp(6, 10).toDouble(),
                      ),
                      _buildClosingTimeRow(),
                      if (_formError != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          _formError!,
                          key: const ValueKey('snack_chat_poll_form_error'),
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontFamilyFallback: const ['NotoSansKR'],
                            fontSize: 12.5,
                            height: 1.35,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFB42318),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    final compactAction = MediaQuery.sizeOf(context).width < 340 ||
        MediaQuery.textScalerOf(context).scale(14) > 24;
    return AppBar(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      elevation: 0,
      toolbarHeight: context.rh(56, min: 54, max: 60),
      automaticallyImplyLeading: false,
      leadingWidth: 48,
      leading: IconButton(
        onPressed: () => Navigator.of(context).pop(),
        tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
        icon: Icon(
          Icons.close_rounded,
          size: context.ri(22).clamp(21, 24).toDouble(),
          color: const Color(0xFF111827),
        ),
      ),
      flexibleSpace: SafeArea(
        bottom: false,
        child: IgnorePointer(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 104),
              child: Text(
                _isKo ? '참석 투표 만들기' : 'Create attendance poll',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontFamilyFallback: const ['NotoSansKR'],
                  fontSize: context.rf(18).clamp(16, 19).toDouble(),
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF111827),
                ),
              ),
            ),
          ),
        ),
      ),
      actions: [
        if (compactAction)
          SizedBox.square(
            dimension: 48,
            child: IconButton(
              onPressed: _submit,
              tooltip: _isKo ? '만들기' : 'Create',
              icon: const Icon(Icons.check_rounded, size: 22),
              color: const Color(0xFF111827),
            ),
          )
        else
          TextButton.icon(
            onPressed: _submit,
            icon: const Icon(Icons.check_rounded, size: 19),
            label: Text(
              _isKo ? '만들기' : 'Create',
              style: const TextStyle(
                fontFamily: 'Inter',
                fontFamilyFallback: const ['NotoSansKR'],
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF111827),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(44, 44),
            ),
          ),
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _buildSectionLabel(String text) {
    return Text(
      text,
      style: TextStyle(
        fontFamily: 'Inter',
        fontFamilyFallback: const ['NotoSansKR'],
        fontSize: context.rf(14).clamp(13, 15).toDouble(),
        fontWeight: FontWeight.w800,
        color: const Color(0xFF344054),
      ),
    );
  }

  Widget _buildOptionField(_PollOptionDraft option, int index) {
    return Row(
      key: ValueKey<int>(option.id),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 14),
          child: SizedBox(
            width: 24,
            child: Text(
              '${index + 1}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontFamilyFallback: const ['NotoSansKR'],
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF667085),
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: TextFormField(
            controller: option.controller,
            focusNode: option.focusNode,
            maxLength: _maxOptionLength,
            maxLengthEnforcement:
                MaxLengthEnforcement.truncateAfterCompositionEnds,
            textInputAction: index == _options.length - 1
                ? TextInputAction.done
                : TextInputAction.next,
            onFieldSubmitted: (_) {
              if (index < _options.length - 1) {
                _options[index + 1].focusNode.requestFocus();
              }
            },
            onChanged: (_) {
              if (_formError != null) {
                setState(() => _formError = null);
              }
            },
            validator: (value) {
              if ((value ?? '').trim().isEmpty) {
                return _isKo ? '선택지를 입력해주세요.' : 'Enter an option.';
              }
              return null;
            },
            style: _inputTextStyle(context),
            decoration: _inputDecoration(
              hintText: _isKo ? '선택지 ${index + 1}' : 'Option ${index + 1}',
            ),
          ),
        ),
        IconButton(
          onPressed: _options.length > 2 ? () => _removeOption(option) : null,
          tooltip: _isKo ? '선택지 삭제' : 'Remove option',
          icon: const Icon(Icons.remove_circle_outline_rounded),
          iconSize: 20,
          color: const Color(0xFF667085),
          disabledColor: const Color(0xFFD0D5DD),
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          padding: EdgeInsets.zero,
        ),
      ],
    );
  }

  Widget _buildSettingRow({
    required String title,
    required String description,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Semantics(
      toggled: value,
      label: title,
      child: InkWell(
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontFamilyFallback: const ['NotoSansKR'],
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontFamilyFallback: const ['NotoSansKR'],
                        fontSize: 12,
                        height: 1.35,
                        fontWeight: FontWeight.w400,
                        color: Color(0xFF667085),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Switch.adaptive(
                value: value,
                onChanged: onChanged,
                activeTrackColor: const Color(0xFF475467),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildClosingTimeRow() {
    final value = _closesAt;
    return Semantics(
      button: true,
      label: _isKo ? '투표 종료 시간 선택' : 'Choose poll end time',
      child: InkWell(
        onTap: _selectClosingTime,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              const Icon(
                Icons.schedule_rounded,
                size: 21,
                color: Color(0xFF667085),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isKo ? '종료 시간' : 'End time',
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontFamilyFallback: const ['NotoSansKR'],
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value == null
                          ? (_isKo ? '종료 시간 없음' : 'No end time')
                          : _formatClosingTime(value),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontFamilyFallback: const ['NotoSansKR'],
                        fontSize: 12.5,
                        height: 1.35,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF667085),
                      ),
                    ),
                  ],
                ),
              ),
              if (value != null)
                IconButton(
                  onPressed: () {
                    setState(() {
                      _closesAt = null;
                      _formError = null;
                    });
                  },
                  tooltip: _isKo ? '종료 시간 삭제' : 'Remove end time',
                  icon: const Icon(Icons.close_rounded),
                  iconSize: 19,
                  color: const Color(0xFF667085),
                  constraints:
                      const BoxConstraints(minWidth: 44, minHeight: 44),
                  padding: EdgeInsets.zero,
                )
              else
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 22,
                  color: Color(0xFF98A2B3),
                ),
            ],
          ),
        ),
      ),
    );
  }

  TextStyle _inputTextStyle(BuildContext context) {
    return TextStyle(
      fontFamily: 'Inter',
      fontFamilyFallback: const ['NotoSansKR'],
      fontSize: context.rf(15).clamp(14, 16).toDouble(),
      height: 1.35,
      fontWeight: FontWeight.w500,
      color: const Color(0xFF111827),
    );
  }

  InputDecoration _inputDecoration({required String hintText}) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: const TextStyle(
        fontFamily: 'Inter',
        fontFamilyFallback: const ['NotoSansKR'],
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: Color(0xFF98A2B3),
      ),
      counterText: '',
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(vertical: 12),
      border: const UnderlineInputBorder(
        borderSide: BorderSide(color: Color(0xFFEAECF0)),
      ),
      enabledBorder: const UnderlineInputBorder(
        borderSide: BorderSide(color: Color(0xFFEAECF0)),
      ),
      focusedBorder: const UnderlineInputBorder(
        borderSide: BorderSide(color: Color(0xFF667085), width: 1.4),
      ),
      errorBorder: const UnderlineInputBorder(
        borderSide: BorderSide(color: Color(0xFFD92D20)),
      ),
      focusedErrorBorder: const UnderlineInputBorder(
        borderSide: BorderSide(color: Color(0xFFD92D20), width: 1.4),
      ),
      errorStyle: const TextStyle(
        fontFamily: 'Inter',
        fontFamilyFallback: const ['NotoSansKR'],
        fontSize: 11.5,
        height: 1.2,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

class _PollOptionDraft {
  const _PollOptionDraft({
    required this.id,
    required this.controller,
    required this.focusNode,
  });

  final int id;
  final TextEditingController controller;
  final FocusNode focusNode;

  void dispose() {
    controller.dispose();
    focusNode.dispose();
  }
}
