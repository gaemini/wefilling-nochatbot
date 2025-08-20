import 'package:flutter/material.dart';

/// 앱 전체의 디자인 상수를 관리하는 클래스
class ChatbotDesignConstants {
  // 생성자를 private으로 만들어 인스턴스 생성 방지
  ChatbotDesignConstants._();
  
  // 색상 팔레트
  /// 기본 색상: 신뢰감을 주는 부드러운 파란색
  static const Color primaryColor = Color.fromRGBO(107, 174, 214, 1.0); // hsl(203, 69%, 75%)
  
  /// 배경 색상: 깔끔한 인터페이스를 위한 밝은 회색
  static const Color backgroundColor = Color.fromRGBO(241, 243, 245, 1.0); // hsl(210, 23%, 95%)
  
  /// 강조 색상: 성공 또는 하이라이트를 위한 밝은 녹색
  static const Color accentColor = Color.fromRGBO(144, 238, 144, 1.0); // hsl(120, 73%, 85%)
  
  /// 사용자 메시지 버블 색상
  static const Color userMessageColor = Color.fromRGBO(107, 174, 214, 1.0);
  
  /// 봇 메시지 버블 색상
  static const Color botMessageColor = Colors.white;
  
  /// 텍스트 색상
  static const Color primaryTextColor = Color.fromRGBO(33, 37, 41, 1.0);
  static const Color secondaryTextColor = Color.fromRGBO(108, 117, 125, 1.0);
  
  /// 에러 색상
  static const Color errorColor = Color.fromRGBO(220, 53, 69, 1.0);
  
  /// 성공 색상
  static const Color successColor = Color.fromRGBO(40, 167, 69, 1.0);
  
  // 크기 및 여백
  /// 기본 테두리 반지름 (둥근 모서리)
  static const double borderRadius = 16.0;
  
  /// 작은 테두리 반지름
  static const double smallBorderRadius = 8.0;
  
  /// 큰 테두리 반지름
  static const double largeBorderRadius = 24.0;
  
  /// 기본 패딩
  static const double defaultPadding = 16.0;
  
  /// 작은 패딩
  static const double smallPadding = 8.0;
  
  /// 큰 패딩
  static const double largePadding = 24.0;
  
  /// 메시지 버블 최대 너비 비율
  static const double messageBubbleMaxWidthRatio = 0.75;
  
  // 그림자 효과
  /// 기본 그림자 (부드러운 효과)
  static const List<BoxShadow> softShadow = [
    BoxShadow(
      color: Color.fromRGBO(0, 0, 0, 0.1),
      blurRadius: 8.0,
      offset: Offset(0, 2),
      spreadRadius: 0,
    ),
  ];
  
  /// 강한 그림자 (카드나 중요한 요소용)
  static const List<BoxShadow> strongShadow = [
    BoxShadow(
      color: Color.fromRGBO(0, 0, 0, 0.15),
      blurRadius: 12.0,
      offset: Offset(0, 4),
      spreadRadius: 0,
    ),
  ];
  
  // 애니메이션 Duration
  /// 기본 애니메이션 시간
  static const Duration defaultAnimationDuration = Duration(milliseconds: 300);
  
  /// 빠른 애니메이션 시간
  static const Duration fastAnimationDuration = Duration(milliseconds: 150);
  
  /// 느린 애니메이션 시간
  static const Duration slowAnimationDuration = Duration(milliseconds: 500);
  
  // 아이콘 크기
  /// 작은 아이콘 크기
  static const double smallIconSize = 16.0;
  
  /// 기본 아이콘 크기
  static const double defaultIconSize = 24.0;
  
  /// 큰 아이콘 크기
  static const double largeIconSize = 32.0;
  
  // 폰트 크기
  /// 작은 텍스트 크기
  static const double smallFontSize = 12.0;
  
  /// 기본 텍스트 크기
  static const double defaultFontSize = 16.0;
  
  /// 제목 텍스트 크기
  static const double titleFontSize = 20.0;
  
  /// 큰 제목 텍스트 크기
  static const double largeTitleFontSize = 24.0;
}
