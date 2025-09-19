// lib/ui/animations/page_transitions.dart
// 2024-2025 트렌드 페이지 전환 애니메이션
// Slide, Fade, Scale, Glassmorphism 전환 효과

import 'package:flutter/material.dart';
import '../../constants/app_constants.dart';

/// 2024-2025 트렌드 페이지 전환 애니메이션 유틸리티
class PageTransitions {
  
  /// Slide Transition (기본 트렌드 스타일)
  static PageRouteBuilder slideTransition({
    required Widget page,
    SlideDirection direction = SlideDirection.fromRight,
    Duration? duration,
  }) {
    return PageRouteBuilder(
      transitionDuration: duration ?? AppTheme.pageTransition,
      reverseTransitionDuration: duration ?? AppTheme.pageTransition,
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        Offset begin;
        switch (direction) {
          case SlideDirection.fromRight:
            begin = const Offset(1.0, 0.0);
            break;
          case SlideDirection.fromLeft:
            begin = const Offset(-1.0, 0.0);
            break;
          case SlideDirection.fromTop:
            begin = const Offset(0.0, -1.0);
            break;
          case SlideDirection.fromBottom:
            begin = const Offset(0.0, 1.0);
            break;
        }

        return SlideTransition(
          position: Tween<Offset>(
            begin: begin,
            end: Offset.zero,
          ).animate(CurvedAnimation(
            parent: animation,
            curve: AppTheme.primaryCurve, // easeInOutCubic
          )),
          child: child,
        );
      },
    );
  }

  /// Fade Transition (부드러운 전환)
  static PageRouteBuilder fadeTransition({
    required Widget page,
    Duration? duration,
  }) {
    return PageRouteBuilder(
      transitionDuration: duration ?? AppTheme.pageTransition,
      reverseTransitionDuration: duration ?? AppTheme.pageTransition,
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: Tween<double>(
            begin: 0.0,
            end: 1.0,
          ).animate(CurvedAnimation(
            parent: animation,
            curve: AppTheme.primaryCurve,
          )),
          child: child,
        );
      },
    );
  }

  /// Scale Transition (확대/축소 효과)
  static PageRouteBuilder scaleTransition({
    required Widget page,
    Duration? duration,
    Alignment alignment = Alignment.center,
  }) {
    return PageRouteBuilder(
      transitionDuration: duration ?? AppTheme.pageTransition,
      reverseTransitionDuration: duration ?? AppTheme.pageTransition,
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return ScaleTransition(
          alignment: alignment,
          scale: Tween<double>(
            begin: 0.8,
            end: 1.0,
          ).animate(CurvedAnimation(
            parent: animation,
            curve: AppTheme.bounceInCurve, // elasticOut
          )),
          child: FadeTransition(
            opacity: animation,
            child: child,
          ),
        );
      },
    );
  }

  /// Mixed Transition (슬라이드 + 페이드)
  static PageRouteBuilder mixedTransition({
    required Widget page,
    SlideDirection direction = SlideDirection.fromRight,
    Duration? duration,
  }) {
    return PageRouteBuilder(
      transitionDuration: duration ?? AppTheme.pageTransition,
      reverseTransitionDuration: duration ?? AppTheme.pageTransition,
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        Offset begin;
        switch (direction) {
          case SlideDirection.fromRight:
            begin = const Offset(0.3, 0.0);
            break;
          case SlideDirection.fromLeft:
            begin = const Offset(-0.3, 0.0);
            break;
          case SlideDirection.fromTop:
            begin = const Offset(0.0, -0.3);
            break;
          case SlideDirection.fromBottom:
            begin = const Offset(0.0, 0.3);
            break;
        }

        return SlideTransition(
          position: Tween<Offset>(
            begin: begin,
            end: Offset.zero,
          ).animate(CurvedAnimation(
            parent: animation,
            curve: AppTheme.slideInCurve, // fastOutSlowIn
          )),
          child: FadeTransition(
            opacity: Tween<double>(
              begin: 0.0,
              end: 1.0,
            ).animate(CurvedAnimation(
              parent: animation,
              curve: const Interval(0.0, 0.8, curve: Curves.easeOut),
            )),
            child: child,
          ),
        );
      },
    );
  }

  /// 회전 전환 효과 (특별한 액션용)
  static PageRouteBuilder rotationTransition({
    required Widget page,
    Duration? duration,
  }) {
    return PageRouteBuilder(
      transitionDuration: duration ?? AppTheme.pageTransition,
      reverseTransitionDuration: duration ?? AppTheme.pageTransition,
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return RotationTransition(
          turns: Tween<double>(
            begin: 0.1,
            end: 0.0,
          ).animate(CurvedAnimation(
            parent: animation,
            curve: AppTheme.bounceInCurve,
          )),
          child: ScaleTransition(
            scale: Tween<double>(
              begin: 0.8,
              end: 1.0,
            ).animate(CurvedAnimation(
              parent: animation,
              curve: AppTheme.bounceInCurve,
            )),
            child: FadeTransition(
              opacity: animation,
              child: child,
            ),
          ),
        );
      },
    );
  }

  /// 커스텀 그라디언트 배경과 함께하는 전환
  static PageRouteBuilder gradientTransition({
    required Widget page,
    LinearGradient? gradient,
    Duration? duration,
  }) {
    return PageRouteBuilder(
      opaque: false,
      transitionDuration: duration ?? AppTheme.pageTransition,
      reverseTransitionDuration: duration ?? AppTheme.pageTransition,
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return Container(
          decoration: BoxDecoration(
            gradient: gradient ?? AppTheme.backgroundGradient,
          ),
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(1.0, 0.0),
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: animation,
              curve: AppTheme.primaryCurve,
            )),
            child: FadeTransition(
              opacity: animation,
              child: child,
            ),
          ),
        );
      },
    );
  }
}

/// 슬라이드 방향 열거형
enum SlideDirection {
  fromRight,
  fromLeft,
  fromTop,
  fromBottom,
}

/// 편리한 Navigator 확장
extension NavigatorTransitions on NavigatorState {
  
  /// Slide push
  Future<T?> pushSlide<T extends Object?>(
    Widget page, {
    SlideDirection direction = SlideDirection.fromRight,
  }) {
    return push<T>(PageTransitions.slideTransition(
      page: page,
      direction: direction,
    ));
  }

  /// Fade push
  Future<T?> pushFade<T extends Object?>(Widget page) {
    return push<T>(PageTransitions.fadeTransition(page: page));
  }

  /// Scale push
  Future<T?> pushScale<T extends Object?>(
    Widget page, {
    Alignment alignment = Alignment.center,
  }) {
    return push<T>(PageTransitions.scaleTransition(
      page: page,
      alignment: alignment,
    ));
  }

  /// Mixed push
  Future<T?> pushMixed<T extends Object?>(
    Widget page, {
    SlideDirection direction = SlideDirection.fromRight,
  }) {
    return push<T>(PageTransitions.mixedTransition(
      page: page,
      direction: direction,
    ));
  }

  /// Replace with slide
  Future<T?> pushReplacementSlide<T extends Object?, TO extends Object?>(
    Widget page, {
    SlideDirection direction = SlideDirection.fromRight,
    TO? result,
  }) {
    return pushReplacement<T, TO>(
      PageTransitions.slideTransition(
        page: page,
        direction: direction,
      ),
      result: result,
    );
  }
}

/// Widget 확장 (편리한 사용법)
extension WidgetTransitions on Widget {
  
  /// 이 위젯을 슬라이드 전환으로 열기
  Future<T?> openWithSlide<T extends Object?>(
    BuildContext context, {
    SlideDirection direction = SlideDirection.fromRight,
  }) {
    return Navigator.of(context).pushSlide<T>(this, direction: direction);
  }

  /// 이 위젯을 페이드 전환으로 열기
  Future<T?> openWithFade<T extends Object?>(BuildContext context) {
    return Navigator.of(context).pushFade<T>(this);
  }

  /// 이 위젯을 스케일 전환으로 열기
  Future<T?> openWithScale<T extends Object?>(
    BuildContext context, {
    Alignment alignment = Alignment.center,
  }) {
    return Navigator.of(context).pushScale<T>(this, alignment: alignment);
  }

  /// 이 위젯을 믹스 전환으로 열기
  Future<T?> openWithMixed<T extends Object?>(
    BuildContext context, {
    SlideDirection direction = SlideDirection.fromRight,
  }) {
    return Navigator.of(context).pushMixed<T>(this, direction: direction);
  }
}

