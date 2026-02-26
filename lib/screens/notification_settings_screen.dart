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
        ).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context)!.loadSettingsError(e.toString() ?? ""))));
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
        ).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context)!.saveSettingsError(e.toString() ?? ""))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF111827)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          AppLocalizations.of(context)!.notificationSettings ?? "",
          style: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Color(0xFF111827),
          ),
        ),
        centerTitle: false,
      ),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                children: [
                  // 전체 알림 토글 (최상단, 강조)
                  _buildMainToggleSection(),
                  
                  const Divider(height: 1, thickness: 1),
                  
                  // 주요 알림
                  _buildSectionHeader(
                    title: AppLocalizations.of(context)!.meetupNotifications,
                    icon: Icons.campaign,
                  ),
                  _buildSettingItem(
                    title: AppLocalizations.of(context)!.meetupAlertsTitle,
                    subtitle: AppLocalizations.of(context)!.meetupAlertsSubtitle,
                    settingKey: NotificationSettingKeys.meetupAlerts,
                    icon: Icons.groups,
                  ),
                  _buildSettingItem(
                    title: AppLocalizations.of(context)!.friendAlertsTitle,
                    subtitle: AppLocalizations.of(context)!.friendAlertsSubtitle,
                    settingKey: NotificationSettingKeys.friendAlerts,
                    icon: Icons.person_add_alt,
                  ),
                  _buildSettingItem(
                    title: AppLocalizations.of(context)!.postInteractionsTitle,
                    subtitle: AppLocalizations.of(context)!.postInteractionsSubtitle,
                    settingKey: NotificationSettingKeys.postInteractions,
                    icon: Icons.article,
                  ),
                  
                  const Divider(height: 1, thickness: 1),
                  
                  // 메시지 & 기타
                  _buildSectionHeader(
                    title: AppLocalizations.of(context)!.generalSettings,
                    icon: Icons.more_horiz,
                  ),
                  _buildSettingItem(
                    title: AppLocalizations.of(context)!.dmMessagesTitle,
                    subtitle: AppLocalizations.of(context)!.dmMessagesSubtitle,
                    settingKey: NotificationSettingKeys.dmMessages,
                    icon: Icons.chat_bubble,
                  ),
                  _buildSettingItem(
                    title: AppLocalizations.of(context)!.marketingTitle,
                    subtitle: AppLocalizations.of(context)!.marketingSubtitle,
                    settingKey: NotificationSettingKeys.marketing,
                    icon: Icons.campaign,
                  ),
                  
                  const SizedBox(height: 24),
                ],
              ),
    );
  }

  // 전체 알림 토글 섹션 (강조 스타일)
  Widget _buildMainToggleSection() {
    final allNotificationsOn = _settings[NotificationSettingKeys.allNotifications] ?? true;
    
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: allNotificationsOn ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: allNotificationsOn ? const Color(0xFF166534) : const Color(0xFFB91C1C),
          width: 2,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: allNotificationsOn ? const Color(0xFF166534) : const Color(0xFFB91C1C),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            allNotificationsOn ? Icons.notifications_active : Icons.notifications_off,
            color: Colors.white,
            size: 28,
          ),
        ),
        title: Text(
          AppLocalizations.of(context)!.allNotifications,
          style: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: Color(0xFF111827),
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            AppLocalizations.of(context)!.allNotificationsSubtitle,
            style: TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.grey[700],
            ),
          ),
        ),
        trailing: Switch(
          value: allNotificationsOn,
          onChanged: (value) async {
            if (!value) {
              // 전체 알림 끄기 확인
              final confirmed = await _showDisableAllConfirmDialog();
              if (!confirmed) return;
            }
            _updateSetting(NotificationSettingKeys.allNotifications, value);
          },
          activeColor: const Color(0xFF166534),
        ),
      ),
    );
  }

  // 섹션 헤더
  Widget _buildSectionHeader({
    required String title,
    required IconData icon,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF6B7280), size: 20),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: Color(0xFF6B7280),
            ),
          ),
        ],
      ),
    );
  }

  // 전체 알림 끄기 확인 다이얼로그
  Future<bool> _showDisableAllConfirmDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          backgroundColor: Colors.white,
          title: Text(
            AppLocalizations.of(context)!.disableAllNotificationsTitle,
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          content: Text(
            AppLocalizations.of(context)!.disableAllNotificationsMessage,
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 15,
              fontWeight: FontWeight.w600,
              height: 1.5,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(
                AppLocalizations.of(context)!.cancel,
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFB91C1C),
                foregroundColor: Colors.white,
              ),
              child: Text(
                AppLocalizations.of(context)!.turnOff,
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        );
      },
    );
    return result ?? false;
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
    IconData? icon,
    bool isMainToggle = false,
  }) {
    // 모든 알림이 꺼져 있으면 다른 토글은 비활성화
    final bool allNotificationsOff =
        !(_settings[NotificationSettingKeys.allNotifications] ?? true);

    // 전체 알림 토글이 아니고, 전체 알림이 꺼져 있으면 비활성화
    final bool disabled = !isMainToggle && allNotificationsOff;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: icon != null
          ? Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: disabled ? Colors.grey.shade200 : const Color(0xFF6CCFF6).withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                size: 24,
                color: disabled ? Colors.grey.shade400 : const Color(0xFF6CCFF6),
              ),
            )
          : null,
      title: Text(
        title,
        style: TextStyle(
          fontFamily: 'Pretendard',
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: disabled ? Colors.grey.shade400 : const Color(0xFF111827),
        ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          subtitle,
          style: TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: disabled ? Colors.grey.shade400 : Colors.grey[600],
          ),
        ),
      ),
      trailing: Switch(
        value: disabled ? false : (_settings[settingKey] ?? true),
        onChanged:
            disabled
                ? null
                : (value) {
                  _updateSetting(settingKey, value);
                },
        activeColor: const Color(0xFF6CCFF6),
      ),
      enabled: !disabled,
    );
  }
}
