// lib/screens/notification_settings_screen.dart
// 알림 설정 화면
// 알림 유형별 ON/OFF 설정 기능 제공

import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../design/tokens.dart';
import '../l10n/app_localizations.dart';
import '../l10n/ui_locale.dart';
import '../services/notification_settings_service.dart';
import '../utils/responsive_helper.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  // 글쓰기 화면과 동일한 중립 팔레트
  static const Color _ink = Color(0xFF111827);
  static const Color _iconNeutral = Color(0xFF667085);
  static const Color _textMuted = Color(0xFF6B7280);
  static const Color _disabledText = Color(0xFF9CA3AF);
  static const Color _dividerColor = Color(0xFFE5E7EB);
  static const Color _switchActiveTrack = Color(0xFF344054);

  final _notificationSettingsService = NotificationSettingsService();
  bool _isLoading = true;
  Map<String, bool> _settings = {};

  bool get _allNotificationsOn =>
      _settings[NotificationSettingKeys.allNotifications] ?? true;

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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)!.loadSettingsError(e.toString()),
            ),
          ),
        );
      }
    }
  }

  Future<void> _updateSetting(String key, bool value) async {
    try {
      // 즉시 UI 업데이트 (낙관적 업데이트)
      setState(() {
        _settings[key] = value;
      });

      // 설정 저장. 서비스는 Firestore 실패를 삼키고 false를 돌려주므로
      // 실패도 예외와 같은 경로로 되돌린다.
      final saved = await _notificationSettingsService.updateNotificationSetting(
        key,
        value,
      );
      if (!saved) {
        throw StateError('notification-setting-not-saved');
      }
    } catch (e) {
      if (!mounted) return;
      // 에러 발생시 원래 값으로 되돌림
      setState(() {
        _settings[key] = !value;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.saveSettingsError(e.toString()),
          ),
        ),
      );
    }
  }

  // 스위치/행 탭 공통 처리: 전체 알림을 끌 때만 확인 다이얼로그를 거친다.
  Future<void> _handleToggle(String key, bool value) async {
    if (key == NotificationSettingKeys.allNotifications && !value) {
      final confirmed = await _showDisableAllConfirmDialog();
      if (!confirmed || !mounted) return;
    }
    await _updateSetting(key, value);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _buildAppBar(l10n),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: _switchActiveTrack,
              ),
            )
          : _buildBody(l10n),
    );
  }

  PreferredSizeWidget _buildAppBar(AppLocalizations l10n) {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      surfaceTintColor: Colors.white,
      toolbarHeight: _toolbarHeight,
      automaticallyImplyLeading: false,
      leadingWidth: 48,
      leading: IconButton(
        icon: Icon(
          Icons.arrow_back_rounded,
          color: _ink,
          size: context.ri(22).clamp(21, 24).toDouble(),
        ),
        onPressed: () => Navigator.of(context).pop(),
        tooltip: MaterialLocalizations.of(context).backButtonTooltip,
      ),
      flexibleSpace: _buildCenteredTitle(l10n.notificationSettings),
    );
  }

  double get _toolbarHeight {
    final base = context.rh(56, min: 54, max: 60);
    final scaledTitle = MediaQuery.textScalerOf(context).scale(
      context.rf(18).clamp(16, 19).toDouble(),
    );
    final accessible = scaledTitle * 1.2 + DesignTokens.s24;
    return accessible > base ? accessible.clamp(base, 96).toDouble() : base;
  }

  Widget _buildCenteredTitle(String title) {
    final horizontalClearance =
        MediaQuery.sizeOf(context).width < 360 ? 88.0 : 104.0;
    return SafeArea(
      bottom: false,
      child: IgnorePointer(
        child: Center(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: horizontalClearance),
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: uiFontFamily(context, 'Inter'),
                fontFamilyFallback: const ['NotoSansKR'],
                fontSize: context.rf(18).clamp(16, 19).toDouble(),
                fontWeight: FontWeight.w700,
                color: _ink,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(AppLocalizations l10n) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final systemBottomInset = MediaQuery.viewPaddingOf(context).bottom;
    final horizontalPadding = screenWidth < 360
        ? 14.0
        : screenWidth < 430
            ? 16.0
            : 20.0;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        context.rs(8).clamp(6, 10).toDouble(),
        horizontalPadding,
        DesignTokens.s24 + systemBottomInset,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 전체 알림 토글 (최상단, 마스터 스위치)
              _buildMasterRow(l10n),
              SizedBox(height: context.rs(6).clamp(4, 8).toDouble()),
              _buildDivider(),

              // 주요 알림
              _buildSectionLabel(l10n.meetupNotifications),
              _buildSettingRow(
                icon: Icons.groups_outlined,
                title: l10n.meetupAlertsTitle,
                description: l10n.meetupAlertsSubtitle,
                settingKey: NotificationSettingKeys.meetupAlerts,
              ),
              _buildSettingRow(
                icon: Icons.person_add_alt_outlined,
                title: l10n.friendAlertsTitle,
                description: l10n.friendAlertsSubtitle,
                settingKey: NotificationSettingKeys.friendAlerts,
              ),
              _buildSettingRow(
                icon: Icons.article_outlined,
                title: l10n.postInteractionsTitle,
                description: l10n.postInteractionsSubtitle,
                settingKey: NotificationSettingKeys.postInteractions,
              ),
              SizedBox(height: context.rs(8).clamp(6, 10).toDouble()),
              _buildDivider(),

              // 메시지 & 기타
              _buildSectionLabel(l10n.generalSettings),
              _buildSettingRow(
                icon: Icons.chat_bubble_outline_rounded,
                title: l10n.dmMessagesTitle,
                description: l10n.dmMessagesSubtitle,
                settingKey: NotificationSettingKeys.dmMessages,
              ),
              _buildSettingRow(
                icon: Icons.campaign_outlined,
                title: l10n.marketingTitle,
                description: l10n.marketingSubtitle,
                settingKey: NotificationSettingKeys.marketing,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return const Divider(height: 1, thickness: 1, color: _dividerColor);
  }

  Widget _buildSectionLabel(String text) {
    return Padding(
      padding: EdgeInsets.only(
        top: context.rs(18).clamp(14, 20).toDouble(),
        bottom: context.rs(4).clamp(2, 6).toDouble(),
      ),
      child: Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontFamily: uiFontFamily(context, 'Inter'),
          fontFamilyFallback: const ['NotoSansKR'],
          fontSize: context.rf(15).clamp(14, 16).toDouble(),
          fontWeight: FontWeight.w800,
          color: _ink,
        ),
      ),
    );
  }

  // 전체 알림 토글 (살짝 강조된 행)
  Widget _buildMasterRow(AppLocalizations l10n) {
    final isOn = _allNotificationsOn;
    return _buildToggleRow(
      icon: isOn
          ? Icons.notifications_active_outlined
          : Icons.notifications_off_outlined,
      title: l10n.allNotifications,
      description: l10n.allNotificationsSubtitle,
      value: isOn,
      enabled: true,
      titleFontSize: context.rf(16).clamp(15, 17).toDouble(),
      verticalPadding: context.rs(12).clamp(10, 14).toDouble(),
      onChanged: (value) =>
          _handleToggle(NotificationSettingKeys.allNotifications, value),
    );
  }

  Widget _buildSettingRow({
    required IconData icon,
    required String title,
    required String description,
    required String settingKey,
  }) {
    // 모든 알림이 꺼져 있으면 다른 토글은 비활성화
    final enabled = _allNotificationsOn;
    return _buildToggleRow(
      icon: icon,
      title: title,
      description: description,
      value: enabled && (_settings[settingKey] ?? true),
      enabled: enabled,
      titleFontSize: context.rf(15).clamp(14, 16).toDouble(),
      verticalPadding: context.rs(11).clamp(9, 13).toDouble(),
      onChanged: (value) => _handleToggle(settingKey, value),
    );
  }

  Widget _buildToggleRow({
    required IconData icon,
    required String title,
    required String description,
    required bool value,
    required bool enabled,
    required double titleFontSize,
    required double verticalPadding,
    required ValueChanged<bool> onChanged,
  }) {
    final titleColor = enabled ? _ink : _disabledText;
    final descriptionColor = enabled ? _textMuted : _disabledText;
    final iconColor = enabled ? _iconNeutral : _disabledText;

    return MergeSemantics(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? () => onChanged(!value) : null,
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: verticalPadding),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox.square(
                  dimension: 30,
                  child: Icon(
                    icon,
                    color: iconColor,
                    size: context.ri(20).clamp(19, 22).toDouble(),
                  ),
                ),
                SizedBox(width: context.rs(10)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: uiFontFamily(context, 'Inter'),
                          fontFamilyFallback: const ['NotoSansKR'],
                          fontSize: titleFontSize,
                          fontWeight: FontWeight.w800,
                          color: titleColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: uiFontFamily(context, 'Inter'),
                          fontFamilyFallback: const ['NotoSansKR'],
                          fontSize: context.rf(12).clamp(11, 13).toDouble(),
                          fontWeight: FontWeight.w500,
                          color: descriptionColor,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                _buildSwitch(
                  value: value,
                  onChanged: enabled ? onChanged : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSwitch({
    required bool value,
    required ValueChanged<bool>? onChanged,
  }) {
    final toggle = Switch.adaptive(
      value: value,
      onChanged: onChanged,
      activeTrackColor: _switchActiveTrack,
      activeThumbColor: Colors.white,
      inactiveTrackColor: _dividerColor,
      inactiveThumbColor: Colors.white,
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    if (onChanged != null) return toggle;
    // 비활성 상태: 꺼진 채로 잠그고 살짝 흐리게 표시
    return Opacity(opacity: 0.5, child: toggle);
  }

  // 전체 알림 끄기 확인 다이얼로그 (글쓰기 화면의 확인 다이얼로그와 동일한 스타일)
  Future<bool> _showDisableAllConfirmDialog() async {
    final l10n = AppLocalizations.of(context)!;

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          elevation: 8,
          contentPadding: const EdgeInsets.fromLTRB(24, 26, 24, 8),
          actionsPadding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.disableAllNotificationsTitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: uiFontFamily(context, 'Inter'),
                  fontFamilyFallback: const ['NotoSansKR'],
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: _ink,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: DesignTokens.s8),
              Text(
                l10n.disableAllNotificationsMessage,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: uiFontFamily(context, 'Inter'),
                  fontFamilyFallback: const ['NotoSansKR'],
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _textMuted,
                  height: 1.45,
                ),
              ),
            ],
          ),
          actions: [
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.grey.shade300),
                      ),
                      foregroundColor: _textMuted,
                    ),
                    child: Text(
                      l10n.cancel,
                      style: TextStyle(
                        fontFamily: uiFontFamily(context, 'Inter'),
                        fontFamilyFallback: const ['NotoSansKR'],
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      backgroundColor: AppColors.pointColor,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      l10n.turnOff,
                      style: TextStyle(
                        fontFamily: uiFontFamily(context, 'Inter'),
                        fontFamilyFallback: const ['NotoSansKR'],
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
    return result ?? false;
  }
}
