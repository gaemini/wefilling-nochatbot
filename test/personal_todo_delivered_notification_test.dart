import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wefilling/models/semester_todo.dart';
import 'package:wefilling/services/personal_todo_local_notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('startup rescheduling preserves delivered cards and recurring identity',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    SharedPreferences.setMockInitialValues({});
    const channel = MethodChannel('dexterous.com/flutter/local_notifications');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'initialize') return true;
      if (call.method == 'canScheduleExactNotifications') return false;
      return null;
    });
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    const todo = PersonalTodo(
        id: 'todo-a',
        semesterId: 'semester',
        title: 'Task',
        weekNumber: 1,
        completed: false,
        carryOver: false,
        reminderEnabled: true,
        archived: false);
    final service = PersonalTodoLocalNotificationService.instance;
    for (var i = 0; i < 2; i++) {
      await service.schedule(
          userId: 'alice', todo: todo, globalEnabled: true, hour: 9, minute: 0);
    }
    expect(calls.where((call) => call.method == 'cancel'), isEmpty);
    final scheduled =
        calls.where((call) => call.method == 'zonedSchedule').toList();
    expect(scheduled, hasLength(2));
    final first = scheduled.first.arguments as Map;
    final second = scheduled.last.arguments as Map;
    expect(first['id'], second['id']);
    expect(first['matchDateTimeComponents'], isNotNull);
    final payload = jsonDecode(first['payload'] as String) as Map;
    expect(payload['recipientUserId'], 'alice');
    expect(payload['todoId'], 'todo-a');
    await service.schedule(
        userId: 'alice', todo: todo, globalEnabled: false, hour: 9, minute: 0);
    expect(calls.where((call) => call.method == 'cancel'), hasLength(1));
  });
}
