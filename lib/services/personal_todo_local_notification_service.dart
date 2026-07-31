import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../models/semester_todo.dart';
import 'language_service.dart';
import 'navigation_service.dart';

/// 개인 할 일 알림은 Firebase/FCM과 분리된 기기 로컬 알림이다.
class PersonalTodoLocalNotificationService {
  PersonalTodoLocalNotificationService._();

  static final PersonalTodoLocalNotificationService instance =
      PersonalTodoLocalNotificationService._();

  static const _channelId = 'personal_todo_reminders';
  static const _channelName = 'Personal to-do reminders';

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  final LanguageService _languageService = LanguageService();

  Future<void>? _initializing;
  bool _exactAlarmAllowed = false;

  Future<void> initialize() => _initializing ??= _initialize();

  Future<void> _initialize() async {
    tz_data.initializeTimeZones();
    // 학기 일정은 한국 달력을 기준으로 제공되므로 알림도 동일한 기준을 쓴다.
    tz.setLocalLocation(tz.getLocation('Asia/Seoul'));

    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/launcher_icon'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );
    await _notifications.initialize(
      settings,
      onDidReceiveNotificationResponse: (response) async {
        final payload = response.payload;
        if (payload == null || payload.isEmpty) return;
        try {
          final data = jsonDecode(payload);
          if (data is Map<String, dynamic>) {
            await NavigationService.handlePushNavigation(data);
          }
        } catch (_) {
          // 잘못된 payload가 앱 탐색을 중단시키지 않게 한다.
        }
      },
    );

    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: 'Daily reminders for personal semester tasks.',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    );
    final android = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(channel);
    _exactAlarmAllowed =
        await android?.canScheduleExactNotifications() ?? false;
  }

  Future<bool> requestPermission() async {
    if (kIsWeb) return false;
    await initialize();
    if (defaultTargetPlatform == TargetPlatform.android) {
      final android = _notifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final notificationsAllowed =
          await android?.requestNotificationsPermission() ?? true;
      if (!notificationsAllowed) return false;
      // 정확한 알람 권한이 거부되어도 inexact 예약으로 기능을 유지한다.
      _exactAlarmAllowed =
          await android?.canScheduleExactNotifications() ?? false;
      if (!_exactAlarmAllowed) {
        _exactAlarmAllowed =
            await android?.requestExactAlarmsPermission() ?? false;
      }
      return true;
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return await _notifications
              .resolvePlatformSpecificImplementation<
                  IOSFlutterLocalNotificationsPlugin>()
              ?.requestPermissions(alert: true, badge: false, sound: true) ??
          false;
    }
    return true;
  }

  Future<void> schedule({
    required String userId,
    required PersonalTodo todo,
    required bool globalEnabled,
    required int hour,
    required int minute,
  }) async {
    await initialize();
    final id = notificationId(userId, todo.id);
    await _notifications.cancel(id);
    if (!globalEnabled ||
        !todo.reminderEnabled ||
        todo.completed ||
        todo.archived) {
      return;
    }

    final now = tz.TZDateTime.now(tz.local);
    final source = todo.reminderStartAt ?? DateTime.now();
    var scheduled = tz.TZDateTime(
      tz.local,
      source.year,
      source.month,
      source.day,
      hour,
      minute,
    );
    while (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    // 앱 안에서 선택한 언어를 기준으로 예약한다. 시스템 언어를 사용하면
    // 한국어 OS에서 영어 UI를 선택했을 때도 한국어 알림이 예약될 수 있다.
    final language = await _languageService.getLanguage();
    final title = language == 'ko' ? '오늘의 할 일' : 'Today’s task';
    final body = todo.title.trim().isEmpty
        ? (language == 'ko' ? '할 일을 확인해 주세요.' : 'Check your to-do list.')
        : todo.title.trim();
    final payload = jsonEncode(<String, dynamic>{
      'type': 'personalTodoReminder',
      'todoId': todo.id,
      'semesterId': todo.semesterId,
    });

    await _notifications.zonedSchedule(
      id,
      title,
      body,
      scheduled,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: 'Daily reminders for personal semester tasks.',
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
        ),
      ),
      androidScheduleMode: _exactAlarmAllowed
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: payload,
      // 미래의 시작일을 첫 실행일로 유지하면서 이후에는 매일 반복한다.
      // null로 예약하면 첫 알림 후 반복이 끊기므로 항상 시간 반복을 지정한다.
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  Future<void> cancel(String userId, String todoId) async {
    await initialize();
    await _notifications.cancel(notificationId(userId, todoId));
  }

  Future<void> syncAll({
    required String userId,
    required Iterable<PersonalTodo> todos,
    required bool enabled,
    required int hour,
    required int minute,
  }) async {
    await initialize();
    for (final todo in todos) {
      await schedule(
        userId: userId,
        todo: todo,
        globalEnabled: enabled,
        hour: hour,
        minute: minute,
      );
    }
  }

  int notificationId(String userId, String todoId) {
    // Dart hashCode는 실행마다 달라질 수 있으므로 안정적인 FNV-1a를 쓴다.
    var hash = 0x811c9dc5;
    for (final unit in '$userId:$todoId'.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }
}
