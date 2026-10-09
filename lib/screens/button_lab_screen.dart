import 'package:flutter/material.dart';

import '../design/tokens.dart';
import '../l10n/ui_locale.dart';
import '../ui/widgets/app_icon_button.dart';
import '../ui/widgets/motion_press.dart';
import '../ui/widgets/motion_processing_button.dart';
import '../ui/widgets/motion_selectable.dart';
import '../ui/widgets/motion_selection_pulse.dart';
import '../ui/widgets/motion_state_icon.dart';
import '../utils/motion_haptics.dart';

/// 개발용 버튼 인터랙션 시험 화면(kDebugMode 전용).
///
/// 대표 버튼 5개를 "현재 구현 복제(Current)"와 "공통 인터랙션 적용(New)"으로
/// 나란히 비교한다. 실제 가입·업로드·참여 요청은 보내지 않는다.
class ButtonLabScreen extends StatefulWidget {
  const ButtonLabScreen({super.key});

  static const Key disabledSwitchKey = ValueKey('lab_disabled');
  static const Key busySwitchKey = ValueKey('lab_busy');
  static const Key failureSwitchKey = ValueKey('lab_failure');
  static const Key longLabelSwitchKey = ValueKey('lab_long_label');
  static const Key reducedMotionSwitchKey = ValueKey('lab_reduced_motion');
  static const Key hapticCounterKey = ValueKey('lab_haptic_counter');
  static const Key currentSendKey = ValueKey('lab_current_send');
  static const Key newSendKey = ValueKey('lab_new_send');
  static const Key currentSendCounterKey = ValueKey('lab_current_send_counter');
  static const Key newSendCounterKey = ValueKey('lab_new_send_counter');
  static const Key currentProcessingKey = ValueKey('lab_current_processing');
  static const Key newProcessingKey = ValueKey('lab_new_processing');
  static const Key newLikeKey = ValueKey('lab_new_like');
  static const Key currentLikeKey = ValueKey('lab_current_like');
  static Key newChipKey(String id) => ValueKey('lab_new_chip_$id');
  static Key currentChipKey(String id) => ValueKey('lab_current_chip_$id');

  @override
  State<ButtonLabScreen> createState() => _ButtonLabScreenState();
}

class _ButtonLabScreenState extends State<ButtonLabScreen> {
  static const _chipOptions = <String, String>{
    'sports': '운동',
    'music': '음악',
    'travel': '여행',
  };
  static const _maxChips = 2;

  bool _disabled = false;
  bool _busyOverride = false;
  bool _forceFailure = false;
  bool _longLabel = false;
  bool _reducedMotion = false;
  int _haptics = 0;

  int _sentCurrent = 0;
  int _sentNew = 0;
  final Set<String> _currentChips = <String>{};
  final Set<String> _newChips = <String>{};
  bool _likedCurrent = false;
  bool _likedNew = false;
  int _likesCurrent = 12;
  int _likesNew = 12;
  bool _processingCurrent = false;
  bool _processingNew = false;
  final ProcessingFeedback _feedback = ProcessingFeedback();

  @override
  void initState() {
    super.initState();
    MotionHaptics.debugObserver = (_) {
      if (mounted) setState(() => _haptics++);
    };
  }

  @override
  void dispose() {
    MotionHaptics.debugObserver = null;
    _feedback.dispose();
    super.dispose();
  }

  String _t(String ko, String en, String zh) => isChineseUi(context)
      ? zh
      : Localizations.localeOf(context).languageCode == 'ko'
          ? ko
          : en;

  String get _processingLabel => _longLabel
      ? _t('참여 신청하고 알림 받기', 'Join and get notified about updates',
          '参加聚会并接收通知')
      : _t('참여하기', 'Join', '参加');

  bool get _busy => _busyOverride;

  Future<void> _runCurrent() async {
    if (_processingCurrent || _busy) return;
    setState(() => _processingCurrent = true);
    await Future<void>.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;
    setState(() => _processingCurrent = false);
  }

  Future<void> _runNew() async {
    if (_processingNew || _busy) return;
    setState(() => _processingNew = true);
    await Future<void>.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;
    setState(() => _processingNew = false);
    // The result is shown only after the simulated request finished.
    if (_forceFailure) {
      _feedback.failure();
    } else {
      _feedback.success();
      MotionHaptics.fire(context, MotionHapticEvent.processingSuccess);
    }
  }

  void _toggleChip(Set<String> chips, String id) {
    setState(() {
      if (chips.contains(id)) {
        chips.remove(id);
      } else if (chips.length >= _maxChips) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: Text(_t('최대 $_maxChips개까지 선택할 수 있어요.',
                'You can select up to $_maxChips.', '最多可选$_maxChips项。')),
          ));
      } else {
        chips.add(id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[
      _row(
        '1 · ${_t('기본 아이콘', 'Basic icon', '基本图标')}',
        current: IconButton(
          onPressed: _disabled ? null : () {},
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        next: AppIconButton(
          icon: Icons.arrow_back_rounded,
          onPressed: _disabled ? null : () {},
          semanticLabel: 'Back',
        ),
      ),
      _row(
        '2 · ${_t('관심사 칩 (최대 $_maxChips)', 'Interest chips (max $_maxChips)', '兴趣标签 (最多$_maxChips)')}',
        current: _chips(_currentChips, animated: false),
        next: _chips(_newChips, animated: true),
      ),
      _row(
        '3 · ${_t('스냅 좋아요', 'Snap like', '快照点赞')}',
        current: _currentLike(),
        next: _newLike(),
      ),
      _row(
        '4 · ${_t('저장 / 참여 처리', 'Save / join processing', '保存 / 参加处理')}',
        current: _currentProcessing(),
        next: _newProcessing(),
      ),
      _row(
        '5 · ${_t('메시지 전송', 'Message send', '发送消息')}',
        current: _send(
          key: ButtonLabScreen.currentSendKey,
          counterKey: ButtonLabScreen.currentSendCounterKey,
          count: _sentCurrent,
          onTap: () => setState(() => _sentCurrent++),
          animated: false,
        ),
        next: _send(
          key: ButtonLabScreen.newSendKey,
          counterKey: ButtonLabScreen.newSendCounterKey,
          count: _sentNew,
          onTap: () => setState(() => _sentNew++),
          animated: true,
        ),
      ),
    ];

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Button lab'),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _controls(),
            const SizedBox(height: 8),
            MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(disableAnimations: _reducedMotion),
              child: Column(children: rows),
            ),
            const SizedBox(height: 16),
            const SelectableText(
              'tokens · press 90 / release 160 / state 200 / hold 600\n'
              '1 basic: MotionPress only, no selected/success state\n'
              '2 select: MotionSelectable + AnimatedContainer + MotionStateIcon\n'
              '3 toggle: MotionPress(.88, resetToken) + pulse + MotionStateIcon\n'
              '4 processing: busy from caller flag, success only after result\n'
              '5 send: MotionPress(.90), never blocks the next tap\n'
              '6 cautious: MotionPress(.99), no success phase',
              style: TextStyle(fontSize: 12, color: Color(0xFF475467)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _controls() {
    Widget chip(String label, Key key, bool value, ValueChanged<bool> onChanged) =>
        Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: const TextStyle(fontSize: 13)),
          Switch(key: key, value: value, onChanged: onChanged),
        ]);
    return Wrap(
      spacing: 4,
      runSpacing: 0,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        chip('disabled', ButtonLabScreen.disabledSwitchKey, _disabled,
            (v) => setState(() => _disabled = v)),
        chip('busy', ButtonLabScreen.busySwitchKey, _busyOverride,
            (v) => setState(() => _busyOverride = v)),
        chip('failure', ButtonLabScreen.failureSwitchKey, _forceFailure,
            (v) => setState(() => _forceFailure = v)),
        chip('long label', ButtonLabScreen.longLabelSwitchKey, _longLabel,
            (v) => setState(() => _longLabel = v)),
        chip('reduced motion', ButtonLabScreen.reducedMotionSwitchKey,
            _reducedMotion, (v) => setState(() => _reducedMotion = v)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text('haptics: $_haptics',
              key: ButtonLabScreen.hapticCounterKey,
              style: const TextStyle(fontSize: 13)),
        ),
      ],
    );
  }

  Widget _row(String title, {required Widget current, required Widget next}) {
    Widget column(String heading, Widget child) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(heading,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 11, color: Color(0xFF98A2B3))),
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Center(child: child),
              ),
            ],
          ),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Row(children: [
            column('Current', current),
            const SizedBox(width: 12),
            column('New', next),
          ]),
          const Divider(height: 20),
        ],
      ),
    );
  }

  Widget _chips(Set<String> chips, {required bool animated}) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      alignment: WrapAlignment.center,
      children: _chipOptions.entries.map((entry) {
        final selected = chips.contains(entry.key);
        final foreground =
            selected ? const Color(0xFF157DB8) : const Color(0xFF475467);
        final background =
            selected ? const Color(0xFFEAF6FC) : const Color(0xFFF5F6F8);
        final content = Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            animated
                ? MotionStateIcon(
                    selected: selected,
                    inactiveIcon: Icons.tag_rounded,
                    activeIcon: Icons.check_circle_rounded,
                    color: foreground,
                    size: 17,
                  )
                : Icon(
                    selected ? Icons.check_circle_rounded : Icons.tag_rounded,
                    size: 17,
                    color: foreground),
            const SizedBox(width: 6),
            animated
                ? AnimatedDefaultTextStyle(
                    duration: MotionTokens.of(context, MotionTokens.state),
                    curve: MotionTokens.curve,
                    style: TextStyle(
                        fontSize: 13,
                        color: foreground,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500),
                    child: Text(entry.value),
                  )
                : Text(entry.value,
                    style: TextStyle(
                        fontSize: 13,
                        color: foreground,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500)),
          ]),
        );
        final onTap = _disabled ? null : () => _toggleChip(chips, entry.key);
        if (!animated) {
          return Material(
            key: ButtonLabScreen.currentChipKey(entry.key),
            color: background,
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: onTap,
              child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 40),
                  child: content),
            ),
          );
        }
        return MotionSelectable(
          key: ButtonLabScreen.newChipKey(entry.key),
          selected: selected,
          enabled: !_disabled,
          pressedScale: MotionSelectable.chipScale,
          pulse: true,
          child: AnimatedContainer(
            duration: MotionTokens.of(context, MotionTokens.state),
            curve: MotionTokens.curve,
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(18),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: onTap,
                child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 40),
                    child: content),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _likeLabel(bool liked, int count) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(width: 6),
          Text('$count',
              style: const TextStyle(fontSize: 14, color: Color(0xFF475467))),
        ],
      );

  Widget _currentLike() {
    final color = _likedCurrent ? const Color(0xFFEC4899) : const Color(0xFF475467);
    return InkResponse(
      key: ButtonLabScreen.currentLikeKey,
      onTap: _disabled
          ? null
          : () => setState(() {
                _likedCurrent = !_likedCurrent;
                _likesCurrent += _likedCurrent ? 1 : -1;
              }),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(_likedCurrent ? Icons.favorite : Icons.favorite_border,
              color: color, size: 26),
          _likeLabel(_likedCurrent, _likesCurrent),
        ]),
      ),
    );
  }

  Widget _newLike() {
    final color = _likedNew ? const Color(0xFFEC4899) : const Color(0xFF475467);
    return MotionPress(
      key: ButtonLabScreen.newLikeKey,
      enabled: !_disabled,
      pressedScale: .88,
      resetToken: _likedNew,
      child: InkResponse(
        onTap: _disabled
            ? null
            : () {
                setState(() {
                  _likedNew = !_likedNew;
                  _likesNew += _likedNew ? 1 : -1;
                });
                if (_likedNew) {
                  MotionHaptics.fire(context, MotionHapticEvent.likeSelected);
                }
              },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            MotionSelectionPulse(
              selected: _likedNew,
              activePeak: 1.2,
              activeDip: .96,
              inactiveDip: .9,
              child: MotionStateIcon(
                selected: _likedNew,
                inactiveIcon: Icons.favorite_border,
                activeIcon: Icons.favorite,
                color: color,
                size: 26,
              ),
            ),
            _likeLabel(_likedNew, _likesNew),
          ]),
        ),
      ),
    );
  }

  ButtonStyle get _processingStyle => FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        backgroundColor: BrandColors.primary,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      );

  Widget _currentProcessing() {
    final busy = _processingCurrent || _busy;
    return FilledButton(
      key: ButtonLabScreen.currentProcessingKey,
      style: _processingStyle,
      onPressed: busy || _disabled ? null : _runCurrent,
      child: busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white))
          : Text(_processingLabel, textAlign: TextAlign.center, maxLines: 2),
    );
  }

  Widget _newProcessing() {
    return MotionProcessingButton(
      key: ButtonLabScreen.newProcessingKey,
      busy: _processingNew || _busy,
      onPressed: _disabled ? null : _runNew,
      feedback: _feedback,
      foreground: Colors.white,
      label: Text(_processingLabel, textAlign: TextAlign.center, maxLines: 2),
      builder: (context, onPressed, child) => FilledButton(
        style: _processingStyle,
        onPressed: onPressed,
        child: child,
      ),
    );
  }

  Widget _send({
    required Key key,
    required Key counterKey,
    required int count,
    required VoidCallback onTap,
    required bool animated,
  }) {
    final button = Material(
      color: _disabled ? const Color(0xFFD0D5DD) : BrandColors.primary,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: _disabled ? null : onTap,
        child: const SizedBox(
          width: 44,
          height: 44,
          child: Icon(Icons.arrow_upward_rounded, color: Colors.white),
        ),
      ),
    );
    return Column(mainAxisSize: MainAxisSize.min, children: [
      animated
          ? MotionPress(
              key: key,
              enabled: !_disabled,
              pressedScale: .90,
              child: button,
            )
          : KeyedSubtree(key: key, child: button),
      const SizedBox(height: 4),
      Text('sent: $count',
          key: counterKey,
          style: const TextStyle(fontSize: 12, color: Color(0xFF475467))),
    ]);
  }
}
