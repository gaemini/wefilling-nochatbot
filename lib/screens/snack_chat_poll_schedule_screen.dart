import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/app_constants.dart';
import '../utils/responsive_helper.dart';

class SnackChatPollScheduleScreen extends StatefulWidget {
  const SnackChatPollScheduleScreen({
    super.key,
    required this.initialDateTime,
    required this.firstDate,
    required this.lastDate,
  });

  final DateTime initialDateTime;
  final DateTime firstDate;
  final DateTime lastDate;

  @override
  State<SnackChatPollScheduleScreen> createState() =>
      _SnackChatPollScheduleScreenState();
}

class _SnackChatPollScheduleScreenState
    extends State<SnackChatPollScheduleScreen> {
  late DateTime _selectedDay;
  late int _selectedHour;
  late int _selectedMinute;
  late final FixedExtentScrollController _hourController;
  late final FixedExtentScrollController _minuteController;

  bool get _isKo => Localizations.localeOf(context).languageCode == 'ko';

  DateTime get _selectedDateTime => DateTime(
        _selectedDay.year,
        _selectedDay.month,
        _selectedDay.day,
        _selectedHour,
        _selectedMinute,
      );

  bool get _canComplete => _selectedDateTime.isAfter(DateTime.now());

  @override
  void initState() {
    super.initState();
    final first = DateUtils.dateOnly(widget.firstDate);
    final last = DateUtils.dateOnly(widget.lastDate);
    final initialDay = DateUtils.dateOnly(widget.initialDateTime);
    _selectedDay = initialDay.isBefore(first)
        ? first
        : initialDay.isAfter(last)
            ? last
            : initialDay;
    _selectedHour = widget.initialDateTime.hour;
    _selectedMinute = widget.initialDateTime.minute;
    _hourController = FixedExtentScrollController(
      initialItem: _selectedHour,
    );
    _minuteController = FixedExtentScrollController(
      initialItem: _selectedMinute,
    );
  }

  @override
  void dispose() {
    _hourController.dispose();
    _minuteController.dispose();
    super.dispose();
  }

  void _complete() {
    if (!_canComplete) return;
    Navigator.of(context).pop(_selectedDateTime);
  }

  String _selectedDateLabel() {
    final material = MaterialLocalizations.of(context);
    return material.formatFullDate(_selectedDay);
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final horizontalPadding = width < 360 ? 14.0 : 20.0;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: _buildAppBar(),
        body: MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.3,
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
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
                      _sectionTitle(_isKo ? '날짜' : 'Date'),
                      const SizedBox(height: 6),
                      Text(
                        _selectedDateLabel(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Pretendard',
                          fontSize: context.rf(16).clamp(15, 17).toDouble(),
                          height: 1.35,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF4B5563),
                        ),
                      ),
                      SizedBox(
                        height: context.rs(8).clamp(6, 10).toDouble(),
                      ),
                      _buildCalendar(),
                      SizedBox(
                        height: context.rs(14).clamp(10, 18).toDouble(),
                      ),
                      const Divider(height: 1, color: Color(0xFFE5E7EB)),
                      SizedBox(
                        height: context.rs(20).clamp(16, 24).toDouble(),
                      ),
                      _sectionTitle(_isKo ? '시간 (24시간)' : 'Time (24-hour)'),
                      const SizedBox(height: 8),
                      Center(child: _buildTimeWheels()),
                      if (!_canComplete) ...[
                        const SizedBox(height: 12),
                        Text(
                          _isKo
                              ? '현재 시간 이후로 선택해 주세요.'
                              : 'Choose a time later than now.',
                          style: const TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: 12.5,
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
        tooltip: MaterialLocalizations.of(context).backButtonTooltip,
        icon: Icon(
          Icons.arrow_back_rounded,
          size: context.ri(22).clamp(21, 24).toDouble(),
          color: const Color(0xFF111827),
        ),
      ),
      flexibleSpace: SafeArea(
        bottom: false,
        child: IgnorePointer(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 96),
              child: Text(
                _isKo ? '종료 시간' : 'End time',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Pretendard',
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
              onPressed: _canComplete ? _complete : null,
              tooltip: _isKo ? '완료' : 'Done',
              icon: const Icon(Icons.check_rounded, size: 22),
              color: const Color(0xFF111827),
              disabledColor: const Color(0xFFD1D5DB),
            ),
          )
        else
          TextButton(
            onPressed: _canComplete ? _complete : null,
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF111827),
              disabledForegroundColor: const Color(0xFFD1D5DB),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              minimumSize: const Size(44, 44),
            ),
            child: Text(
              _isKo ? '완료' : 'Done',
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _buildCalendar() {
    final base = Theme.of(context);
    return Theme(
      data: base.copyWith(
        colorScheme: base.colorScheme.copyWith(
          primary: AppColors.pointColor,
          onPrimary: Colors.white,
          surface: Colors.white,
          onSurface: const Color(0xFF111827),
        ),
        datePickerTheme: const DatePickerThemeData(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          headerBackgroundColor: Colors.white,
          headerForegroundColor: Color(0xFF111827),
          dividerColor: Colors.transparent,
        ),
      ),
      child: CalendarDatePicker(
        initialDate: _selectedDay,
        firstDate: DateUtils.dateOnly(widget.firstDate),
        lastDate: DateUtils.dateOnly(widget.lastDate),
        onDateChanged: (value) {
          setState(() => _selectedDay = DateUtils.dateOnly(value));
        },
      ),
    );
  }

  Widget _buildTimeWheels() {
    return Semantics(
      label: _isKo
          ? '$_selectedHour시 $_selectedMinute분'
          : '$_selectedHour hours $_selectedMinute minutes',
      child: SizedBox(
        height: 132,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _TimeWheel(
              controller: _hourController,
              itemCount: 24,
              valueLabel: (value) => value.toString().padLeft(2, '0'),
              onChanged: (value) => setState(() => _selectedHour = value),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                ':',
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF374151),
                ),
              ),
            ),
            _TimeWheel(
              controller: _minuteController,
              itemCount: 60,
              valueLabel: (value) => value.toString().padLeft(2, '0'),
              onChanged: (value) => setState(() => _selectedMinute = value),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String value) {
    return Text(
      value,
      style: TextStyle(
        fontFamily: 'Pretendard',
        fontSize: context.rf(15).clamp(14, 16).toDouble(),
        fontWeight: FontWeight.w800,
        color: const Color(0xFF111827),
      ),
    );
  }
}

class _TimeWheel extends StatelessWidget {
  const _TimeWheel({
    required this.controller,
    required this.itemCount,
    required this.valueLabel,
    required this.onChanged,
  });

  final FixedExtentScrollController controller;
  final int itemCount;
  final String Function(int value) valueLabel;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      child: CupertinoPicker.builder(
        scrollController: controller,
        itemExtent: 42,
        useMagnifier: true,
        magnification: 1.08,
        squeeze: 1,
        selectionOverlay: const SizedBox.shrink(),
        onSelectedItemChanged: onChanged,
        childCount: itemCount,
        itemBuilder: (context, index) => Center(
          child: Text(
            valueLabel(index),
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 21,
              fontWeight: FontWeight.w600,
              color: Color(0xFF111827),
            ),
          ),
        ),
      ),
    );
  }
}
