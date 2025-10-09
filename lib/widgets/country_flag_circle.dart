// lib/widgets/country_flag_circle.dart
// 국기 이모티콘을 표시하는 위젯

import 'package:flutter/material.dart';
import '../utils/country_flag_helper.dart';

/// 국기 이모티콘을 표시하는 위젯 (동그라미 없이 이모티콘만)
class CountryFlagCircle extends StatelessWidget {
  final String nationality; // 한글 국가명
  final double size;

  const CountryFlagCircle({
    Key? key,
    required this.nationality,
    this.size = 24.0,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // 한글 국가명으로 국기 이모티콘 가져오기
    final flagEmoji = CountryFlagHelper.getFlagEmoji(nationality);

    return Text(
      flagEmoji,
      style: TextStyle(
        fontSize: size * 1.2, // 이모티콘 크기를 기존보다 크게 (24 → 28.8)
        height: 1.0,
      ),
      textAlign: TextAlign.center,
    );
  }
}
