import 'package:flutter/material.dart';

class DateSelector extends StatelessWidget {
  final List<DateTime> weekDates;
  final int selectedDayIndex;
  final Function(int) onDateSelected;
  final List<String> weekdayNames;

  const DateSelector({
    super.key,
    required this.weekDates,
    required this.selectedDayIndex,
    required this.onDateSelected,
    required this.weekdayNames,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(weekDates.length, (index) {
        final bool isSelected = index == selectedDayIndex;
        final DateTime date = weekDates[index];
        // 로케일에 따라 요일 이름 선택
        final locale = Localizations.localeOf(context).languageCode;
        final String weekday = locale == 'ko'
            ? ['월', '화', '수', '목', '금', '토', '일'][date.weekday - 1]
            : weekdayNames[date.weekday - 1];

        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: InkWell(
              onTap: () => onDateSelected(index),
              borderRadius: BorderRadius.circular(12),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                height: 64,
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFF4A90E2) // 프라이머리 컬러
                      : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected 
                        ? const Color(0xFF4A90E2)
                        : const Color(0xFFE1E6EE),
                    width: 1,
                  ),
                  boxShadow: isSelected ? [
                    BoxShadow(
                      color: const Color(0xFF4A90E2).withOpacity(0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ] : null,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      weekday,
                      style: TextStyle(
                        color: isSelected
                            ? Colors.white
                            : (date.weekday == 7 // 일요일 체크
                                ? Colors.red
                                : date.weekday == 6 // 토요일 체크
                                    ? Colors.blue
                                    : const Color(0xFF666666)),
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${date.day}',
                      style: TextStyle(
                        color: isSelected
                            ? Colors.white
                            : (date.weekday == 7 // 일요일 체크
                                ? Colors.red
                                : date.weekday == 6 // 토요일 체크
                                    ? Colors.blue
                                    : const Color(0xFF1A1A1A)),
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}
