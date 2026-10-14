// lib/ui/widgets/login_chat_scene.dart
// 로그인 화면 위쪽의 작은 단체 대화 장면(연출).
//
// 외국어 메시지 3개가 도착해 지금 화면 언어로 번역되고, 마지막에 내가 답한다.
// 실제 번역 API는 부르지 않는다. 문구는 이 파일의 고정 문자열이다(콘텐츠).
//
// 시간은 Ticker 하나가 움직이는 자체 시계(ms)로 정해진다. 각 줄의 상태는
// 계획표(_Plan)와 지금 시각만으로 계산하므로, 같은 시각이면 항상 같은 모습이다.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../design/tokens.dart';
import '../../l10n/app_localizations.dart';
import 'wefilling_mark.dart' show WefillingAmbientMotion;

/// 장면 한 줄(상대 메시지).
class LoginChatLine {
  const LoginChatLine(this.original, this.sourceLanguage, this.translations);

  final String original;

  /// 원문 언어 코드(ja/es/fr/vi/de/pt).
  final String sourceLanguage;

  /// 화면 언어(ko/en/zh) → 번역문.
  final Map<String, String> translations;
}

class LoginChatScript {
  const LoginChatScript({
    required this.lines,
    required this.reply,
    required this.reaction,
  });

  final List<LoginChatLine> lines;
  final Map<String, String> reply;
  final String reaction;
}

/// 장면 문구(고정 문자열). 원문은 KOR/ENG/中文 어느 화면에서도 번역되는 언어다.
const List<LoginChatScript> kLoginChatScripts = [
  LoginChatScript(
    lines: [
      LoginChatLine('週末あそぼう！', 'ja', {
        'ko': '주말에 놀자!',
        'en': "Let's hang out this weekend!",
        'zh': '周末一起玩吧！',
      }),
      LoginChatLine('¡Yo me apunto!', 'es', {
        'ko': '나도 낄래!',
        'en': 'Count me in!',
        'zh': '算我一个！',
      }),
      LoginChatLine('On se voit où ?', 'fr', {
        'ko': '어디서 만날까?',
        'en': 'Where should we meet?',
        'zh': '在哪儿见？',
      }),
    ],
    reply: {'ko': '정문 앞 어때? 🙌', 'en': 'Main gate? 🙌', 'zh': '正门见？🙌'},
    reaction: '❤️',
  ),
  LoginChatScript(
    lines: [
      LoginChatLine('Thư viện lúc 3 giờ nhé?', 'vi', {
        'ko': '3시에 도서관 어때?',
        'en': 'Library at 3?',
        'zh': '三点去图书馆？',
      }),
      LoginChatLine('Ich bringe Snacks mit!', 'de', {
        'ko': '간식은 내가 챙길게!',
        'en': "I'll bring snacks!",
        'zh': '我带零食！',
      }),
      LoginChatLine('Fechado! 📚', 'pt', {
        'ko': '좋아! 📚',
        'en': 'Deal! 📚',
        'zh': '就这么定了！📚',
      }),
    ],
    reply: {'ko': '나도 갈게!', 'en': "I'm coming too!", 'zh': '我也去！'},
    reaction: '👍',
  ),
];

/// 원문 언어 이름(표시 언어별).
const Map<String, Map<String, String>> kLoginChatLanguageNames = {
  'ja': {'ko': '일본어', 'en': 'Japanese', 'zh': '日语'},
  'es': {'ko': '스페인어', 'en': 'Spanish', 'zh': '西班牙语'},
  'fr': {'ko': '프랑스어', 'en': 'French', 'zh': '法语'},
  'vi': {'ko': '베트남어', 'en': 'Vietnamese', 'zh': '越南语'},
  'de': {'ko': '독일어', 'en': 'German', 'zh': '德语'},
  'pt': {'ko': '포르투갈어', 'en': 'Portuguese', 'zh': '葡萄牙语'},
};

/// 아래 줄 '원문 언어 {언어}'(표시 중인 글의 언어로).
String loginChatOriginalLabel(String displayLanguage, String sourceLanguage) {
  final strings = lookupAppLocalizations(Locale(displayLanguage));
  final name = kLoginChatLanguageNames[sourceLanguage]?[displayLanguage] ??
      sourceLanguage;
  return strings.translationOriginalLanguage(name);
}

String _uiCode(String languageCode) => switch (languageCode) {
      'ko' => 'ko',
      'zh' => 'zh',
      _ => 'en',
    };

/// 계획표의 사건: [lang]이 null이면 '번역 중' 시작, 아니면 그 언어로 번역됨.
class _Event {
  const _Event(this.at, this.lang);
  final double at;
  final String? lang;
}

class _Plan {
  _Plan(this.script, String lang)
      : avatarAt = [0, 800, 1600, LoginChatScene.replyTypingAt],
        bubbleAt = [600, 1400, 2200, LoginChatScene.replyAt],
        events = [
          for (var i = 0; i < 3; i++)
            [
              _Event(2800 + 400.0 * i, null),
              _Event(3600 + 400.0 * i, lang),
            ],
          [_Event(LoginChatScene.replyAt, lang)],
        ],
        reactionAt = LoginChatScene.reactionAt,
        endAt = LoginChatScene.sceneEnd;

  final int script;

  /// 줄 0–2: 아바타·입력 중 시작 / 원문 말풍선. 줄 3(나): 입력 중 / 답장.
  final List<double> avatarAt;
  final List<double> bubbleAt;
  final List<List<_Event>> events;
  double reactionAt;
  double endAt;
}

/// 한 줄의 지금 모습.
class _RowView {
  const _RowView({
    required this.avatar,
    required this.typing,
    required this.bubble,
    this.displayLang,
    this.translatingSince,
    this.sweep,
    this.typingSince = 0,
  });

  static const _RowView hidden =
      _RowView(avatar: -1, typing: false, bubble: -1);

  /// 0..1 튀어나옴 진행(-1이면 없음).
  final double avatar;
  final bool typing;
  final double typingSince;
  final double bubble;
  final String? displayLang;
  final double? translatingSince;
  final double? sweep;

  bool get visible => avatar >= 0;
}

class LoginChatScene extends StatefulWidget {
  const LoginChatScene({
    super.key,
    required this.languageCode,
    this.frozen = false,
    this.collapseTarget,
    this.compact = false,
    this.advanceSignal = 0,
  });

  /// 화면 언어(ko/en/zh…). 바뀌면 이미 나온 줄을 다시 번역한다.
  final String languageCode;

  /// 로그인 중: 시간을 멈추고 지금 모습을 유지한다(입력 중은 원문으로 확정).
  final bool frozen;

  /// 성공: 장면 안 좌표의 이 점(로고)으로 말풍선이 빨려 들어간다.
  final Offset? collapseTarget;

  /// 작은 화면: 줄 0–1 + 내 답장 3줄.
  final bool compact;

  /// 값이 바뀌면 4초 뒤 다음 장면으로 넘어간다(로그인 실패 뒤).
  final int advanceSignal;

  static const double rowGap = 48;
  static const List<double> rowTops = [0, 48, 96, 146];
  static const List<double> compactRowTops = [0, 48, -1, 98];
  static const double fullHeight = 200;
  static const double compactHeight = 150;

  static const List<Color> avatarColors = [
    Color(0xFFE8B4A0),
    Color(0xFF7FAF8E),
    Color(0xFFB79CC9),
    Color(0xFF2C6BC0),
  ];

  // 시간(ms, 장면 시작 기준).
  static const double replyTypingAt = 4900;
  static const double replyAt = 5500;
  static const double reactionAt = 6100;
  static const double sceneEnd = 10000;
  static const double fadeOut = 400;
  static const double nextAfter = 450;
  static const double avatarPop = 350;
  static const double bubblePop = 320;
  static const double sweepDuration = 700;
  static const List<double> retranslateDelays = [200, 580, 960];
  static const double retranslateTranslating = 750;
  static const double replyRetranslate = 2000;
  static const double afterLanguageChangeEnd = 7000;
  static const double advanceAfterFailure = 4000;
  static const double collapseDuration = 550;
  static const double collapseStagger = 45;

  static const Cubic popCurve = Cubic(.34, 1.56, .64, 1);
  static const Cubic bubbleCurve = Cubic(.34, 1.4, .64, 1);
  static const Cubic collapseCurve = Cubic(.55, 0, .35, 1);
  static const Duration crossfade = Duration(milliseconds: 180);

  @override
  State<LoginChatScene> createState() => LoginChatSceneState();
}

class LoginChatSceneState extends State<LoginChatScene>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final Ticker _ticker = createTicker(_onTick);
  Duration _lastElapsed = Duration.zero;

  /// 장면 시계(ms).
  double _t = 0;
  late _Plan _plan;
  bool _foreground = true;
  bool _reduce = false;

  /// 성공 연출 시계(ms). null이면 연출 전.
  double? _collapseT;
  List<Offset> _rowCenters = const [];
  final LayerLink _reactionLink = LayerLink();
  final List<GlobalKey> _rowKeys =
      List<GlobalKey>.generate(4, (_) => GlobalKey());

  /// 지금 장면(테스트용): 0 = A, 1 = B.
  @visibleForTesting
  int get debugScript => _plan.script;

  @visibleForTesting
  double get debugTime => _t;

  String get _lang => _uiCode(widget.languageCode);

  bool get _static => !WefillingAmbientMotion.enabled;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _plan = _Plan(0, _lang);
    // 테스트(끝없는 움직임 끔): 모두 번역 + 답장 + 반응이 끝난 모습으로 고정.
    if (_static) _t = 7200;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduce = MotionTokens.reduceMotion(context);
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant LoginChatScene oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_uiCode(oldWidget.languageCode) != _lang) _replanForLanguage(_lang);
    if (widget.frozen && !oldWidget.frozen) _settleForFreeze();
    if (widget.advanceSignal != oldWidget.advanceSignal) {
      _plan.endAt =
          math.min(_plan.endAt, _t + LoginChatScene.advanceAfterFailure);
      _plan.endAt = math.max(_plan.endAt, _t);
    }
    if (widget.collapseTarget != null && oldWidget.collapseTarget == null) {
      _settleForFreeze();
      _rowCenters = _measureRows();
      _collapseT = 0;
    } else if (widget.collapseTarget == null) {
      _collapseT = null;
    }
    _syncTicker();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _syncTicker();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    super.dispose();
  }

  bool get _collapsing =>
      _collapseT != null && _collapseT! < _collapseEnd && !_reduce;

  static const double _collapseEnd =
      LoginChatScene.collapseDuration + LoginChatScene.collapseStagger * 3;

  void _syncTicker() {
    final run = !_static &&
        _foreground &&
        (_collapseT == null ? !widget.frozen : _collapsing);
    if (run && !_ticker.isActive) {
      _lastElapsed = Duration.zero;
      _ticker.start();
    } else if (!run && _ticker.isActive) {
      _ticker.stop();
    }
  }

  void _onTick(Duration elapsed) {
    var dt = (elapsed - _lastElapsed).inMicroseconds / 1000;
    _lastElapsed = elapsed;
    // 가려졌던 동안(TickerMode)·백그라운드에서 돌아오면 한 프레임만 진행.
    if (dt > 250 || dt < 0) dt = 16;
    setState(() {
      if (_collapseT != null) {
        _collapseT = _collapseT! + dt;
      } else {
        _advance(dt);
      }
    });
    if (_collapseT != null && !_collapsing) _syncTicker();
  }

  void _advance(double dt) {
    _t += dt;
    final next = _plan.endAt + (_reduce ? 0 : LoginChatScene.nextAfter);
    if (_t >= next) {
      _plan = _Plan((_plan.script + 1) % kLoginChatScripts.length, _lang);
      _t = 0;
    }
  }

  /// 언어 바꿈: 이미 나온 줄 0–2는 200/580/960ms에 다시 번역 중 → +750ms에
  /// 새 언어로, 내 답장은 2000ms에 새 언어로. 7000ms 뒤 다음 장면.
  void _replanForLanguage(String lang) {
    final now = _t;
    final plan = _plan;
    for (var i = 0; i < 3; i++) {
      final kept = plan.events[i].where((e) => e.at <= now).toList();
      if (plan.bubbleAt[i] <= now) {
        final at = now + LoginChatScene.retranslateDelays[i];
        kept
          ..add(_Event(at, null))
          ..add(_Event(at + LoginChatScene.retranslateTranslating, lang));
      } else {
        kept.addAll(plan.events[i]
            .where((e) => e.at > now)
            .map((e) => _Event(e.at, e.lang == null ? null : lang)));
      }
      plan.events[i] = kept;
    }
    if (plan.bubbleAt[3] <= now) {
      plan.events[3] = [
        ...plan.events[3].where((e) => e.at <= now),
        _Event(now + LoginChatScene.replyRetranslate, lang),
      ];
    } else {
      final shown =
          math.max(plan.bubbleAt[3], now + LoginChatScene.replyRetranslate);
      if (plan.avatarAt[3] > now) {
        plan.avatarAt[3] =
            shown - (LoginChatScene.replyAt - LoginChatScene.replyTypingAt);
      }
      plan.bubbleAt[3] = shown;
      plan.events[3] = [_Event(shown, lang)];
    }
    if (plan.reactionAt > now) {
      plan.reactionAt = math.max(plan.reactionAt, plan.bubbleAt[3] + 600);
    }
    if (now < plan.endAt) {
      plan.endAt = math.max(
          now + LoginChatScene.afterLanguageChangeEnd, plan.reactionAt + 1000);
    }
  }

  /// 멈추기 직전: 튀어나오는 중인 것은 끝난 모습으로, 입력 중은 원문으로.
  void _settleForFreeze() {
    final now = _t;
    final plan = _plan;
    for (var i = 0; i < 4; i++) {
      if (plan.avatarAt[i] <= now &&
          now < plan.avatarAt[i] + LoginChatScene.avatarPop) {
        plan.avatarAt[i] = now - LoginChatScene.avatarPop;
      }
      if (plan.avatarAt[i] <= now && now < plan.bubbleAt[i]) {
        // 입력 중 → 원문(내 줄은 답장)으로 확정.
        final shift = plan.bubbleAt[i] - (now - LoginChatScene.bubblePop);
        plan.bubbleAt[i] = now - LoginChatScene.bubblePop;
        if (i == 3) {
          plan.events[3] = [
            for (final e in plan.events[3]) _Event(e.at - shift, e.lang)
          ];
        }
      } else if (plan.bubbleAt[i] <= now &&
          now < plan.bubbleAt[i] + LoginChatScene.bubblePop) {
        plan.bubbleAt[i] = now - LoginChatScene.bubblePop;
      }
      // 빛 지나가는 중이면 끝난 것으로.
      plan.events[i] = [
        for (final e in plan.events[i])
          e.lang != null &&
                  e.at <= now &&
                  now < e.at + LoginChatScene.sweepDuration
              ? _Event(now - LoginChatScene.sweepDuration, e.lang)
              : e
      ];
    }
    if (plan.reactionAt <= now &&
        now < plan.reactionAt + LoginChatScene.avatarPop) {
      plan.reactionAt = now - LoginChatScene.avatarPop;
    }
  }

  List<Offset> _measureRows() {
    final scene = context.findRenderObject();
    if (scene is! RenderBox || !scene.hasSize) return const [];
    return [
      for (final key in _rowKeys)
        () {
          final box = key.currentContext?.findRenderObject();
          if (box is! RenderBox || !box.hasSize) return Offset.zero;
          return scene
              .globalToLocal(box.localToGlobal(box.size.center(Offset.zero)));
        }(),
    ];
  }

  _RowView _view(int row) {
    final plan = _plan;
    final t = _t;
    final avatarAt = plan.avatarAt[row];
    final bubbleAt = plan.bubbleAt[row];
    if (_reduce) {
      // 입력 중 표시·튀어나옴·빛 없음: 말풍선 시각에 바로 나온다.
      if (t < bubbleAt) return _RowView.hidden;
    } else if (t < avatarAt) {
      return _RowView.hidden;
    }
    final avatar = _reduce
        ? 1.0
        : ((t - avatarAt) / LoginChatScene.avatarPop).clamp(0.0, 1.0);
    if (t < bubbleAt) {
      return _RowView(
          avatar: avatar, typing: true, bubble: -1, typingSince: avatarAt);
    }
    final bubble = _reduce
        ? 1.0
        : ((t - bubbleAt) / LoginChatScene.bubblePop).clamp(0.0, 1.0);
    String? displayLang;
    double? translatingSince;
    double? lastTranslatedAt;
    for (final e in plan.events[row]) {
      if (e.at > t) break;
      if (e.lang == null) {
        translatingSince = e.at;
      } else {
        displayLang = e.lang;
        translatingSince = null;
        lastTranslatedAt = e.at;
      }
    }
    double? sweep;
    if (!_reduce && row < 3 && lastTranslatedAt != null) {
      final p = (t - lastTranslatedAt) / LoginChatScene.sweepDuration;
      if (p >= 0 && p < 1) sweep = p;
    }
    return _RowView(
      avatar: avatar,
      typing: false,
      bubble: bubble,
      displayLang: displayLang,
      translatingSince: translatingSince,
      sweep: sweep,
    );
  }

  double get _sceneOpacity {
    if (_t < _plan.endAt) return 1;
    // 동작 줄이기: 장면 전환은 즉시.
    if (_reduce) return 0;
    return 1 - ((_t - _plan.endAt) / LoginChatScene.fadeOut).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final tops =
        widget.compact ? LoginChatScene.compactRowTops : LoginChatScene.rowTops;
    final height = widget.compact
        ? LoginChatScene.compactHeight
        : LoginChatScene.fullHeight;
    final script = kLoginChatScripts[_plan.script];
    return ExcludeSemantics(
      child: RepaintBoundary(
        // 줄 위치가 고정이라 글자 확대는 따르지 않는다(장식).
        child: MediaQuery.withNoTextScaling(
          child: LayoutBuilder(builder: (context, constraints) {
            final width = constraints.maxWidth;
            return SizedBox(
              key: const ValueKey('login_chat_scene'),
              height: height,
              width: width,
              child: Opacity(
                opacity: _sceneOpacity,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    for (var row = 0; row < 4; row++)
                      if (tops[row] >= 0)
                        Positioned(
                          top: tops[row],
                          left: 0,
                          right: 0,
                          child: _collapse(
                            row,
                            KeyedSubtree(
                              key: _rowKeys[row],
                              child: _buildRow(row, script, width),
                            ),
                          ),
                        ),
                    _buildReaction(script),
                  ],
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  /// 줄 0 말풍선 오른쪽 아래의 반응 이모지 칩(20 높이, 흰색, 350ms 튀어나옴).
  Widget _buildReaction(LoginChatScript script) {
    final at = _plan.reactionAt;
    final row0 = _view(0);
    if (_t < at || !row0.visible || row0.typing) {
      return const SizedBox.shrink();
    }
    final p =
        _reduce ? 1.0 : ((_t - at) / LoginChatScene.avatarPop).clamp(0.0, 1.0);
    final chip = Transform.scale(
      scale: LoginChatScene.popCurve.transform(p),
      child: Container(
        key: const ValueKey('login_chat_reaction'),
        height: 20,
        padding: const EdgeInsets.symmetric(horizontal: 5),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          boxShadow: const [
            BoxShadow(
              color: Color(0x2408214A),
              offset: Offset(0, 2),
              blurRadius: 6,
            ),
          ],
        ),
        child: Text(script.reaction,
            style: const TextStyle(fontSize: 11, height: 1)),
      ),
    );
    return Positioned(
      left: 0,
      top: 0,
      child: CompositedTransformFollower(
        link: _reactionLink,
        showWhenUnlinked: false,
        targetAnchor: Alignment.bottomRight,
        followerAnchor: Alignment.topRight,
        offset: const Offset(6, -8),
        // 성공 연출: 줄 0과 함께 사라진다.
        child: _collapse(0, chip, translate: false),
      ),
    );
  }

  Widget _collapse(int row, Widget child, {bool translate = true}) {
    final collapseT = _collapseT;
    final target = widget.collapseTarget;
    if (collapseT == null || target == null) return child;
    if (_reduce) return const SizedBox.shrink();
    final p = LoginChatScene.collapseCurve.transform(
        ((collapseT - row * LoginChatScene.collapseStagger) /
                LoginChatScene.collapseDuration)
            .clamp(0.0, 1.0));
    final center = row < _rowCenters.length ? _rowCenters[row] : target;
    if (!translate) return Opacity(opacity: 1 - p, child: child);
    final delta = (target - center) * p;
    return Opacity(
      opacity: 1 - p,
      child: Transform.translate(
        offset: delta,
        child: Transform.scale(scale: 1 - .85 * p, child: child),
      ),
    );
  }

  Widget _buildRow(int row, LoginChatScript script, double width) {
    final view = _view(row);
    if (!view.visible) return const SizedBox(height: 40);
    final mine = row == 3;
    final right = row == 1 || row == 3;
    final maxBubble = math.max(80.0, math.min(220.0, width - 26 - 8 - 28));
    Widget bubble;
    if (view.typing) {
      bubble = _TypingBubble(
        key: ValueKey('login_chat_typing_$row'),
        since: view.typingSince,
        now: _t,
        mine: mine,
        right: right,
      );
    } else {
      final String text;
      final String? footer;
      if (mine) {
        text = script.reply[view.displayLang ?? _lang]!;
        footer = null;
      } else {
        final line = script.lines[row];
        text = view.displayLang == null
            ? line.original
            : line.translations[view.displayLang]!;
        footer = view.translatingSince != null
            ? null
            : view.displayLang == null
                ? null
                : loginChatOriginalLabel(
                    view.displayLang!, line.sourceLanguage);
      }
      bubble = _MessageBubble(
        key: ValueKey('login_chat_bubble_$row'),
        row: row,
        text: text,
        footer: footer,
        translatingSince: view.translatingSince,
        translatingLabel:
            AppLocalizations.of(context)?.chatTranslationTranslating ??
                'Translating',
        now: _t,
        frozen: widget.frozen || _collapseT != null,
        sweep: view.sweep,
        mine: mine,
        right: right,
        reduce: _reduce,
        reactionLink: row == 0 ? _reactionLink : null,
      );
      if (view.bubble < 1) {
        final c = LoginChatScene.bubbleCurve.transform(view.bubble);
        bubble = Opacity(
          opacity: view.bubble.clamp(0.0, 1.0),
          child: Transform.scale(
            scale: .6 + .4 * c,
            alignment: right ? Alignment.bottomRight : Alignment.bottomLeft,
            child: bubble,
          ),
        );
      }
    }
    final avatar = Transform.scale(
      scale: LoginChatScene.popCurve.transform(view.avatar),
      child: _Avatar(color: LoginChatScene.avatarColors[row]),
    );
    final children = <Widget>[
      avatar,
      const SizedBox(width: 8),
      Flexible(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxBubble),
          child: bubble,
        ),
      ),
    ];
    return Row(
      mainAxisAlignment:
          right ? MainAxisAlignment.end : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: right ? children.reversed.toList() : children,
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.white.withValues(alpha: .7),
          width: 1.5,
        ),
      ),
    );
  }
}

const List<BoxShadow> _bubbleShadow = [
  BoxShadow(color: Color(0x2E08214A), offset: Offset(0, 4), blurRadius: 14),
];

Color _bubbleColor({required bool mine, required bool right}) => mine
    ? const Color(0xFF0F3F80)
    : right
        ? const Color(0xFFE3F0FF)
        : Colors.white;

class _TypingBubble extends StatelessWidget {
  const _TypingBubble({
    super.key,
    required this.since,
    required this.now,
    required this.mine,
    required this.right,
  });

  final double since;
  final double now;
  final bool mine;
  final bool right;

  @override
  Widget build(BuildContext context) {
    final dot =
        mine ? Colors.white.withValues(alpha: .67) : const Color(0xFF9AA4B2);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 13, 12, 12),
      decoration: BoxDecoration(
        color: _bubbleColor(mine: mine, right: right),
        borderRadius: BorderRadius.circular(18),
        boxShadow: _bubbleShadow,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            Transform.translate(
              offset: Offset(0, _bounce(now - since - i * 150)),
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 1초 주기로 위로 4px 튄다(주기의 앞 40% 동안).
  static double _bounce(double t) {
    if (t < 0) return 0;
    final phase = (t % 1000) / 1000;
    if (phase >= .4) return 0;
    return -4 * math.sin(math.pi * phase / .4);
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    super.key,
    required this.row,
    required this.text,
    required this.footer,
    required this.translatingSince,
    required this.translatingLabel,
    required this.now,
    required this.frozen,
    required this.sweep,
    required this.mine,
    required this.right,
    required this.reduce,
    this.reactionLink,
  });

  final int row;
  final String text;
  final String? footer;
  final double? translatingSince;
  final String translatingLabel;
  final double now;
  final bool frozen;
  final double? sweep;
  final bool mine;
  final bool right;
  final bool reduce;
  final LayerLink? reactionLink;

  @override
  Widget build(BuildContext context) {
    final zh = Localizations.maybeLocaleOf(context)?.languageCode == 'zh';
    final base = TextStyle(
      fontFamily: 'Inter',
      fontFamilyFallback: zh
          ? const ['NotoSansSC', 'NotoSansKR']
          : const ['NotoSansKR', 'NotoSansSC'],
      decoration: TextDecoration.none,
    );
    final bodyStyle = base.copyWith(
      fontSize: 14,
      height: 19 / 14,
      fontWeight: FontWeight.w400,
      color: mine ? Colors.white : const Color(0xFF111111),
    );
    final metaStyle = base.copyWith(
      fontSize: 11,
      height: 15 / 11,
      fontWeight: FontWeight.w400,
      color: const Color(0xFF5F5F5F),
    );
    final duration = reduce ? Duration.zero : LoginChatScene.crossfade;

    // 번역 중: 원문 글자 투명도 1 ↔ .55(1.2초 주기, SnackChatTranslatedText와 같은 값).
    var bodyOpacity = 1.0;
    final translating = translatingSince;
    if (translating != null && !reduce && !frozen) {
      final half = (now - translating) / 600;
      final tri = half.floor().isEven ? half % 1 : 1 - half % 1;
      bodyOpacity = 1 - .45 * Curves.easeInOut.transform(tri);
    }

    Widget body = AnimatedSwitcher(
      duration: duration,
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeOut,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topLeft,
        children: [...previous, if (current != null) current],
      ),
      child: FittedBox(
        key: ValueKey<String>(text),
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(text, maxLines: 1, softWrap: false, style: bodyStyle),
      ),
    );
    body = Opacity(opacity: bodyOpacity, child: body);

    Widget? footerRow;
    if (translating != null) {
      final dots = reduce || frozen
          ? 3
          : (((now - translating) % 1200) / 1200 * 4).floor().clamp(0, 3);
      footerRow = Row(
        key: const ValueKey('translating'),
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.translate_rounded,
              size: 12, color: Color(0xFF5F5F5F)),
          const SizedBox(width: 3),
          Text(translatingLabel, style: metaStyle),
          // 폭이 흔들리지 않게 항상 세 칸.
          Text.rich(
            TextSpan(children: [
              TextSpan(text: '.' * dots),
              TextSpan(
                text: '.' * (3 - dots),
                style: const TextStyle(color: Colors.transparent),
              ),
            ]),
            style: metaStyle,
          ),
        ],
      );
    } else if (footer != null) {
      footerRow = Row(
        key: ValueKey<String>('footer:$footer'),
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.translate_rounded,
              size: 12, color: Color(0xFF5F5F5F)),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              footer!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: metaStyle,
            ),
          ),
        ],
      );
    }

    Widget content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        body,
        if (footerRow != null)
          AnimatedSwitcher(
            duration: duration,
            layoutBuilder: (current, previous) => Stack(
              alignment: Alignment.topLeft,
              children: [...previous, if (current != null) current],
            ),
            child: footerRow,
          ),
      ],
    );
    if (!reduce) {
      content = AnimatedSize(
        duration: LoginChatScene.crossfade,
        curve: Curves.easeOut,
        alignment: right ? Alignment.topRight : Alignment.topLeft,
        child: content,
      );
    }

    Widget bubble = Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 7),
      decoration: BoxDecoration(
        color: _bubbleColor(mine: mine, right: right),
        borderRadius: BorderRadius.circular(18),
        boxShadow: _bubbleShadow,
      ),
      child: content,
    );
    final sweepP = sweep;
    if (sweepP != null) {
      bubble = Stack(
        children: [
          bubble,
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: CustomPaint(
                painter: _SweepPainter(Curves.easeOut.transform(sweepP)),
              ),
            ),
          ),
        ],
      );
    }
    final link = reactionLink;
    if (link != null) {
      // 반응 칩은 장면 맨 위 층에서 이 말풍선을 따라간다(옆 줄에 가리지 않게).
      bubble = CompositedTransformTarget(link: link, child: bubble);
    }
    return bubble;
  }
}

/// 왼쪽에서 오른쪽으로 지나가는 연한 빛(#9CC8FF 40%, 폭 40%).
class _SweepPainter extends CustomPainter {
  const _SweepPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final bandWidth = size.width * .4;
    final left = -bandWidth + (size.width + bandWidth) * progress;
    final rect = Rect.fromLTWH(left, 0, bandWidth, size.height);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(colors: [
          Color(0x009CC8FF),
          Color(0x669CC8FF),
          Color(0x009CC8FF),
        ]).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_SweepPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
