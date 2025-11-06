// lib/screens/notification_settings_screen.dart
// 알림 설정 화면
// 알림 유형별 ON/OFF 설정 기능 제공

import 'package:flutter/material.dart';
import '../services/notification_settings_service.dart';
import '../l10n/app_localizations.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({Key? key}) : super(key: key);

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  final _notificationSettingsService = NotificationSettingsService();
  bool _isLoading = true;
  Map<String, bool> _settings = {};

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final settings =
          await _notificationSettingsService.getNotificationSettings();
      if (mounted) {
        setState(() {
          _settings = settings;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context)?.loadSettingsError(e.toString()))));
      }
    }
  }

  Future<void> _updateSetting(String key, bool value) async {
    try {
      // 즉시 UI 업데이트 (낙관적 업데이트)
      setState(() {
        _settings[key] = value;
      });

      // 설정 저장
      await _notificationSettingsService.updateNotificationSetting(key, value);
    } catch (e) {
      // 에러 발생시 원래 값으로 되돌림
      setState(() {
        _settings[key] = !value;
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context)?.saveSettingsError(e.toString()))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context)?.notificationSettings)),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                children: [
                  // 설정 카테고리 - 모임 알림
                  _buildSettingCategory(
                    title: AppLocalizations.of(context)?.meetupNotifications,
                    icon: Icons.group,
                    color: Colors.blue,
                    children: [
                      // 비공개 게시글 알림
                      _buildSettingItem(
                        title: AppLocalizations.of(context)?.postNotifications,
                        subtitle: 'Private posts only',
                        settingKey: NotificationSettingKeys.postPrivate,
                      ),
                      _buildSettingItem(
                        title: AppLocalizations.of(context)?.meetupFullAlertTitle,
                        subtitle: AppLocalizations.of(context)?.meetupFullAlertSubtitle,
                        settingKey: NotificationSettingKeys.meetupFull,
                      ),
                      _buildSettingItem(
                        title: AppLocalizations.of(context)?.meetupCancelledAlertTitle,
                        subtitle: AppLocalizations.of(context)?.meetupCancelledAlertSubtitle,
                        settingKey: NotificationSettingKeys.meetupCancelled,
                      ),
                    ],
                  ),

                  // 설정 카테고리 - 게시글 알림 (비공개 전용)
                  _buildSettingCategory(
                    title: AppLocalizations.of(context)?.postNotifications,
                    icon: Icons.article,
                    color: Colors.green,
                    children: [
                      _buildSettingItem(
                        title: AppLocalizations.of(context)?.privatePostAlertTitle,
                        subtitle: AppLocalizations.of(context)?.privatePostAlertSubtitle,
                        settingKey: NotificationSettingKeys.postPrivate,
                      ),
                    ],
                  ),
                  // 설정 카테고리 - 친구 알림
                  _buildSettingCategory(
                    title: AppLocalizations.of(context)?.friendNotifications,
                    icon: Icons.person_add_alt,
                    color: Colors.purple,
                    children: [
                      _buildSettingItem(
                        title: AppLocalizations.of(context)?.friendRequestAlertTitle,
                        subtitle: AppLocalizations.of(context)?.friendRequestAlertSubtitle,
                        settingKey: NotificationSettingKeys.friendRequest,
                      ),
                    ],
                  ),

                  // 추가 설정 - 알림 전체 ON/OFF
                  _buildSettingCategory(
                    title: AppLocalizations.of(context)?.generalSettings,
                    icon: Icons.settings,
                    color: Colors.orange,
                    children: [
                      _buildSettingItem(
                        title: AppLocalizations.of(context)?.allNotifications,
                        subtitle: AppLocalizations.of(context)?.allNotificationsSubtitle,
                        settingKey: NotificationSettingKeys.allNotifications,
                        isMainToggle: true,
                      ),
                      // 광고 업데이트
                      _buildSettingItem(
                        title: AppLocalizations.of(context)?.adUpdatesTitle,
                        subtitle: AppLocalizations.of(context)?.adUpdatesSubtitle,
                        settingKey: NotificationSettingKeys.adUpdates,
                      ),
                    ],
                  ),
                ],
              ),
    );
  }

  Widget _buildSettingCategory({
    required String title,
    required IconData icon,
    required Color color,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        ...children,
        const Divider(height: 32),
      ],
    );
  }

  Widget _buildSettingItem({
    required String title,
    required String subtitle,
    required String settingKey,
    bool isMainToggle = false,
  }) {
    // 모든 알림이 꺼져 있으면 다른 토글은 비활성화
    final bool allNotificationsOff =
        !(_settings[NotificationSettingKeys.allNotifications] ?? true);

    // 전체 알림 토글이 아니고, 전체 알림이 꺼져 있으면 비활성화
    final bool disabled = !isMainToggle && allNotificationsOff;

    return ListTile(
      title: Text(title),
      subtitle: Text(
        subtitle,
        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
      ),
      trailing: Switch(
        value: disabled ? false : (_settings[settingKey] ?? true),
        onChanged:
            disabled
                ? null
                : (value) {
                  _updateSetting(settingKey, value);
                },
        activeColor: isMainToggle ? Colors.orange : Colors.blue,
      ),
      enabled: !disabled,
    );
  }
}
