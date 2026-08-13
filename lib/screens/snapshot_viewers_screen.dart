import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/snapshot.dart';
import '../services/snapshot_service.dart';
import '../snapshot/snapshot_strings.dart';
import '../ui/widgets/user_avatar.dart';
import '../utils/country_flag_helper.dart';
import '../utils/responsive_helper.dart';
import 'friend_profile_screen.dart';

class SnapshotViewersScreen extends StatefulWidget {
  const SnapshotViewersScreen({
    super.key,
    required this.snapshotId,
    this.viewersStream,
  });

  final String snapshotId;
  final Stream<List<SnapshotViewer>>? viewersStream;

  @override
  State<SnapshotViewersScreen> createState() => _SnapshotViewersScreenState();
}

class _SnapshotViewersScreenState extends State<SnapshotViewersScreen> {
  late Stream<List<SnapshotViewer>> _viewersStream;

  Stream<List<SnapshotViewer>> _createViewersStream() {
    return widget.viewersStream ??
        SnapshotService.instance.watchViewers(widget.snapshotId);
  }

  @override
  void initState() {
    super.initState();
    _viewersStream = _createViewersStream();
  }

  @override
  void didUpdateWidget(covariant SnapshotViewersScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.snapshotId != widget.snapshotId ||
        oldWidget.viewersStream != widget.viewersStream) {
      _viewersStream = _createViewersStream();
    }
  }

  void _retry() {
    setState(() {
      _viewersStream = _createViewersStream();
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = SnapshotStrings.of(context);
    final toolbarHeight = context.rh(56, min: 54, max: 60);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: true,
          toolbarHeight: toolbarHeight,
          leadingWidth: 48,
          leading: IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            icon: Icon(
              Icons.arrow_back_rounded,
              size: context.ri(22).clamp(21, 24).toDouble(),
              color: const Color(0xFF111827),
            ),
          ),
          title: Text(
            strings.viewers,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Pretendard',
              fontSize: context.rf(18).clamp(16, 19).toDouble(),
              fontWeight: FontWeight.w700,
              color: const Color(0xFF111827),
            ),
          ),
        ),
        body: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: StreamBuilder<List<SnapshotViewer>>(
                stream: _viewersStream,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return _ViewerStatus(
                      icon: Icons.sync_problem_outlined,
                      title: strings.viewersLoadFailed,
                      actionLabel: strings.retry,
                      onAction: _retry,
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Center(
                      child: SizedBox.square(
                        dimension: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF475467),
                        ),
                      ),
                    );
                  }

                  final viewers = snapshot.data!;
                  if (viewers.isEmpty) {
                    return _ViewerStatus(
                      icon: Icons.visibility_outlined,
                      title: strings.noViewers,
                      description: strings.noViewersDescription,
                    );
                  }
                  return _ViewerList(viewers: viewers, strings: strings);
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ViewerList extends StatelessWidget {
  const _ViewerList({
    required this.viewers,
    required this.strings,
  });

  final List<SnapshotViewer> viewers;
  final SnapshotStrings strings;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final horizontalPadding = width < 360 ? 14.0 : (width < 430 ? 16.0 : 20.0);
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        context.rs(8).clamp(6, 10).toDouble(),
        horizontalPadding,
        context.rs(20).clamp(16, 24).toDouble(),
      ),
      itemCount: viewers.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: context.rs(10).clamp(8, 12).toDouble(),
            ),
            child: Text(
              strings.viewersCount(viewers.length),
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: context.rf(13).clamp(12, 14).toDouble(),
                fontWeight: FontWeight.w600,
                color: const Color(0xFF667085),
              ),
            ),
          );
        }
        return _ViewerRow(
          viewer: viewers[index - 1],
          strings: strings,
        );
      },
    );
  }
}

class _ViewerRow extends StatelessWidget {
  const _ViewerRow({
    required this.viewer,
    required this.strings,
  });

  final SnapshotViewer viewer;
  final SnapshotStrings strings;

  @override
  Widget build(BuildContext context) {
    final avatarSize = context.rh(46, min: 42, max: 50);
    final languageCode = Localizations.localeOf(context).languageCode;
    final localizedNationality = CountryFlagHelper.getLocalizedCountryName(
      viewer.nationality,
      languageCode,
    );
    final metadata = <String>[
      localizedNationality,
      viewer.university,
    ].where((value) => value.isNotEmpty).join(' · ');
    final viewedAt = _viewedAtLabel(strings, viewer.viewedAt);
    final canOpenProfile = viewer.userId.trim().isNotEmpty &&
        viewer.userId.trim().toLowerCase() != 'deleted';

    void openProfile() {
      if (!canOpenProfile) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => FriendProfileScreen(
            userId: viewer.userId,
            nickname: viewer.displayName,
            photoURL: viewer.photoUrl,
            university: viewer.university,
            allowNonFriendsPreview: true,
          ),
        ),
      );
    }

    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: Semantics(
        label: '${viewer.displayName}, $viewedAt',
        button: canOpenProfile,
        enabled: canOpenProfile,
        excludeSemantics: true,
        child: InkWell(
          onTap: canOpenProfile ? openProfile : null,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: EdgeInsets.symmetric(
              vertical: context.rs(9).clamp(7, 11).toDouble(),
            ),
            child: Row(
              children: [
                UserAvatar(
                  uid: viewer.userId,
                  photoUrl: viewer.photoUrl,
                  photoVersion: viewer.photoVersion,
                  isAnonymous: false,
                  size: avatarSize,
                  placeholderColor: const Color(0xFFF2F4F7),
                  placeholderIcon: Icons.person_outline_rounded,
                ),
                SizedBox(width: context.rs(12).clamp(10, 14).toDouble()),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        viewer.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Pretendard',
                          fontSize: context.rf(15).clamp(14, 16).toDouble(),
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF111827),
                          height: 1.2,
                        ),
                      ),
                      if (metadata.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          metadata,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: context.rf(12).clamp(11, 13).toDouble(),
                            fontWeight: FontWeight.w500,
                            color: const Color(0xFF667085),
                            height: 1.2,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                SizedBox(width: context.rs(10).clamp(8, 12).toDouble()),
                Text(
                  viewedAt,
                  maxLines: 1,
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: context.rf(12).clamp(11, 13).toDouble(),
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF98A2B3),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ViewerStatus extends StatelessWidget {
  const _ViewerStatus({
    required this.icon,
    required this.title,
    this.description,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? description;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          context.rs(24),
          context.rs(24),
          context.rs(24),
          context.rs(24),
        ),
        child: MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.3,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: context.ri(28).clamp(26, 32).toDouble(),
                color: const Color(0xFF667085),
              ),
              SizedBox(height: context.rs(12).clamp(10, 14).toDouble()),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: context.rf(16).clamp(15, 17).toDouble(),
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF111827),
                ),
              ),
              if (description != null) ...[
                const SizedBox(height: 6),
                Text(
                  description!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: context.rf(13).clamp(12, 14).toDouble(),
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF667085),
                    height: 1.4,
                  ),
                ),
              ],
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 10),
                TextButton(
                  onPressed: onAction,
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF344054),
                    minimumSize: const Size(48, 44),
                  ),
                  child: Text(
                    actionLabel!,
                    style: TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: context.rf(13).clamp(12, 14).toDouble(),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

String _viewedAtLabel(SnapshotStrings strings, DateTime viewedAt) {
  final difference = DateTime.now().difference(viewedAt.toLocal());
  if (difference.isNegative || difference.inMinutes < 1) {
    return strings.viewedJustNow;
  }
  if (difference.inHours < 1) {
    return strings.viewedMinutesAgo(difference.inMinutes);
  }
  return strings.viewedHoursAgo(difference.inHours.clamp(1, 24));
}
