import 'content_tag_row.dart';
import 'package:flutter/material.dart';
import 'motion_press.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../models/content_translation.dart';
import '../../models/meetup.dart';
import '../../services/user_info_cache_service.dart';
import 'audience_ring.dart';
import 'meetup_public_countdown.dart';
import 'hanyang_verification_gate.dart';
import 'translatable_content.dart';
import '../../l10n/ui_locale.dart';

/// 포스트 피드용 밋업 요약.
/// 날짜를 고정된 레일로 분리하고 관련 정보를 한 덩어리로 묶어 빠르게 훑을 수 있게 한다.
class BoardMeetupCard extends StatelessWidget {
  final Meetup meetup;
  final int? currentParticipants;
  final VoidCallback onTap;
  final VoidCallback? onLocationTap;
  final Widget? trailingAction;

  const BoardMeetupCard({
    super.key,
    required this.meetup,
    required this.onTap,
    this.currentParticipants,
    this.onLocationTap,
    this.trailingAction,
  });

  bool _isKorean(BuildContext context) =>
      Localizations.localeOf(context).languageCode == 'ko';


  /// 날짜는 언어와 상관없이 '월/일'로 짧게 쓴다. 예: 10월 7일 → 10/7
  String _dateLabel() {
    final localDate = meetup.date.toLocal();
    return '${localDate.month}/${localDate.day}';
  }

  String _weekdayLabel(BuildContext context) {
    final localDate = meetup.date.toLocal();
    if (isChineseUi(context)) {
      return const [
        '周一',
        '周二',
        '周三',
        '周四',
        '周五',
        '周六',
        '周日'
      ][localDate.weekday - 1];
    }
    if (_isKorean(context)) {
      const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
      return weekdays[localDate.weekday - 1];
    }
    return DateFormat('EEE', 'en_US').format(localDate).toUpperCase();
  }

  String _timeLabel(BuildContext context) {
    final raw = meetup.time.trim();
    if (raw.isEmpty || raw == '미정' || raw == 'Undecided' || raw == 'TBD') {
      return AppLocalizations.of(context)?.undecided ?? 'TBD';
    }
    // 피드에서는 시작 시각만 보여주고 전체 시간 범위는 상세 화면에 유지한다.
    return raw.split('~').first.trim();
  }

  @override
  Widget build(BuildContext context) {
    final participants = currentParticipants ?? meetup.currentParticipants;
    // 글자·여백은 고정값(화면 비례 없음). 확대는 1.2배까지만 따른다.
    const horizontal = 16.0;
    final dateRailSize = meetup.hasPublicTimeLimit ? 76.0 : 66.0;
    final metaStyle = TextStyle(
      fontFamily: uiFontFamily(context, 'Inter'),
      fontFamilyFallback: const ['NotoSansKR'],
      fontSize: 12.5,
      fontWeight: FontWeight.w500,
      height: isChineseUi(context) ? 1.3 : 1.18,
      color: const Color(0xFF667085),
    );
    final isHanyangLocked = HanyangVerificationGate.isLockedForCurrentUser(
      context,
      meetup.requiresHanyangVerification,
    );

    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.2,
      child: Material(
        color: Colors.white,
        child: InkWell(
          onTap: isHanyangLocked ? null : onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: isHanyangLocked ? horizontal : 0,
            ),
            child: HanyangVerificationGate(
              locked: isHanyangLocked,
              compact: true,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(horizontal, 10, horizontal, 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    AudienceRing(
                      restricted: meetup.visibility != 'public',
                      size: dateRailSize,
                      innerGap: 1.5,
                      borderRadius: BorderRadius.circular(14),
                      semanticLabel: (isChineseUi(context)
                          ? '部分人可见的聚会'
                          : _isKorean(context)
                              ? '공개 범위가 제한된 모임'
                              : 'Limited audience meetup'),
                      child: ColoredBox(
                        color: Colors.white,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _weekdayLabel(context),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: uiFontFamily(context, 'Inter'),
                                fontFamilyFallback: const ['NotoSansKR'],
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                height: 1,
                                letterSpacing: 0.2,
                                color: const Color(0xFF667085),
                              ),
                            ),
                            const SizedBox(height: 2),
                            // '12/31'처럼 긴 날짜도 칸을 넘지 않도록 칸 너비에
                            // 맞춰 줄인다(짧은 날짜는 원래 크기 그대로).
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 4),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  _dateLabel(),
                                  maxLines: 1,
                                  softWrap: false,
                                  style: TextStyle(
                                    fontFamily: uiFontFamily(context, 'Inter'),
                                    fontFamilyFallback: const ['NotoSansKR'],
                                    fontSize: 19,
                                    fontWeight: FontWeight.w700,
                                    height: 1,
                                    letterSpacing: -0.6,
                                    color: const Color(0xFF101828),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _timeLabel(context),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: uiFontFamily(context, 'Inter'),
                                fontFamilyFallback: const ['NotoSansKR'],
                                fontSize: 10.5,
                                fontWeight: FontWeight.w500,
                                height: isChineseUi(context) ? 1.3 : 1.05,
                                color: const Color(0xFF667085),
                              ),
                            ),
                            if (meetup.hasPublicTimeLimit) ...[
                              const SizedBox(height: 4),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 3),
                                child: MeetupPublicCountdown(
                                  meetup: meetup,
                                  compact: true,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  meetup.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontFamily: uiFontFamily(context, 'Inter'),
                                    fontFamilyFallback: const ['NotoSansKR'],
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    height: isChineseUi(context) ? 1.3 : 20 / 15,
                                    letterSpacing: -0.2,
                                    color: const Color(0xFF101828),
                                  ),
                                ),
                              ),
                              if (meetup.requiresHanyangVerification) ...[
                                const SizedBox(width: 6),
                                const HanyangContentBadge(compact: true),
                              ],
                              const SizedBox(width: 5),
                              const Icon(
                                Icons.chevron_right_rounded,
                                size: 18,
                                color: Color(0xFFB0B0B0),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          TranslatableContent(
                            request: ContentTranslationRequest(
                              contentType: 'meetup',
                              contentId: meetup.id,
                              sourceFields: <String, String>{
                                'description': meetup.description,
                                'location': meetup.location,
                              },
                            ),
                            scope: 'meetup:${meetup.id}',
                            showToggle: false,
                            builder: (context, fields) => _InlineMeta(
                              icon: Icons.location_on_outlined,
                              text: fields['location'] ?? meetup.location,
                              style: metaStyle,
                              onTap: onLocationTap,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                  child:
                                      _buildHostIdentity(context, metaStyle)),
                              const SizedBox(width: 10),
                              const Icon(
                                Icons.people_outline_rounded,
                                size: 15,
                                color: Color(0xFF667085),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '$participants / ${meetup.maxParticipants}',
                                maxLines: 1,
                                style: metaStyle.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF475467),
                                ),
                              ),
                              if (trailingAction != null) ...[
                                const SizedBox(width: 8),
                                trailingAction!,
                              ],
                            ],
                          ),
                          if (meetup.isTagAudience) ...[
                            const SizedBox(height: 6),
                            TagAudienceBadge(tagIds: meetup.audienceTagIds),
                          ],
                          if (meetup.tagIds.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            ContentTagRow(tagIds: meetup.tagIds),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHostIdentity(BuildContext context, TextStyle metaStyle) {
    final userId = meetup.userId?.trim() ?? '';
    if (userId.isEmpty || userId == 'deleted') {
      return _hostIdentityContent(
        context,
        metaStyle,
        name: AppLocalizations.of(context)!.deletedAccount,
        photoURL: '',
      );
    }
    final cache = UserInfoCacheService();
    return StreamBuilder<DMUserInfo?>(
      key: ValueKey<String>('meetup_host_$userId'),
      stream: cache.watchUserInfo(userId),
      initialData: cache.getCachedUserInfo(userId),
      builder: (context, snapshot) {
        // A StreamBuilder element can be reused while a filtered/reordered
        // list swaps rows. Never paint a response belonging to the previous
        // meetup host while the new UID's stream is attaching.
        final candidate = snapshot.data;
        final latest = candidate?.uid == userId ? candidate : null;
        final isDeleted = latest?.isDeletedAccount == true;
        return _hostIdentityContent(
          context,
          metaStyle,
          name: isDeleted
              ? AppLocalizations.of(context)!.deletedAccount
              : ((latest?.nickname ?? '').trim().isNotEmpty
                  ? latest!.nickname
                  : (meetup.hostNickname ??
                      AppLocalizations.of(context)!.anonymous)),
          photoURL: isDeleted
              ? ''
              : ((latest?.photoURL ?? '').trim().isNotEmpty
                  ? latest!.photoURL
                  : meetup.hostPhotoURL),
        );
      },
    );
  }

  Widget _hostIdentityContent(
    BuildContext context,
    TextStyle metaStyle, {
    required String name,
    required String photoURL,
  }) {
    return Row(
      children: [
        CircleAvatar(
          radius: 10,
          backgroundColor: const Color(0xFFF2F4F7),
          backgroundImage: photoURL.isNotEmpty ? NetworkImage(photoURL) : null,
          child: photoURL.isEmpty
              ? const Icon(
                  Icons.person_outline,
                  size: 11,
                  color: Color(0xFF667085),
                )
              : null,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: metaStyle.copyWith(
              fontWeight: FontWeight.w600,
              color: const Color(0xFF344054),
            ),
          ),
        ),
      ],
    );
  }
}

class _InlineMeta extends StatelessWidget {
  final IconData icon;
  final String text;
  final TextStyle style;
  final VoidCallback? onTap;

  const _InlineMeta({
    required this.icon,
    required this.text,
    required this.style,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final content = Row(
      children: [
        Icon(
          icon,
          size: 14,
          color: const Color(0xFF667085),
        ),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style.copyWith(
              decoration: onTap == null ? null : TextDecoration.underline,
            ),
          ),
        ),
      ],
    );
    if (onTap == null) return content;
    return MotionPress(
      pressedScale: .99,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: content,
      ),
    );
  }
}
