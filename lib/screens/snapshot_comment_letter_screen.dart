import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/app_constants.dart';
import '../models/snapshot.dart';
import '../models/snapshot_comment_letter.dart';
import '../services/snapshot_service.dart';
import '../snapshot/snapshot_storage_image.dart';
import '../utils/responsive_helper.dart';
import 'friend_profile_screen.dart';

typedef SnapshotLetterLoader = Future<SnapshotCommentLetter> Function(
  String notificationId,
);
typedef SnapshotLetterReplySender = Future<bool> Function(
  String notificationId,
  String message,
);

class SnapshotCommentLetterScreen extends StatefulWidget {
  const SnapshotCommentLetterScreen({
    super.key,
    required this.notificationId,
    this.letterLoader,
    this.replySender,
  });

  final String notificationId;
  final SnapshotLetterLoader? letterLoader;
  final SnapshotLetterReplySender? replySender;

  @override
  State<SnapshotCommentLetterScreen> createState() =>
      _SnapshotCommentLetterScreenState();
}

class _SnapshotCommentLetterScreenState
    extends State<SnapshotCommentLetterScreen> {
  final TextEditingController _replyController = TextEditingController();
  final FocusNode _replyFocusNode = FocusNode();
  SnapshotCommentLetter? _letter;
  Object? _loadError;
  bool _isLoading = true;
  bool _isSending = false;

  bool get _isKorean =>
      Localizations.localeOf(context).languageCode.toLowerCase() == 'ko';

  @override
  void initState() {
    super.initState();
    _loadLetter();
  }

  @override
  void dispose() {
    _replyController.dispose();
    _replyFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadLetter() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }
    try {
      final loader =
          widget.letterLoader ?? SnapshotService.instance.getCommentLetter;
      final letter = await loader(widget.notificationId);
      if (!mounted) return;
      setState(() {
        _letter = letter;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error;
        _isLoading = false;
      });
    }
  }

  Future<void> _sendReply() async {
    final letter = _letter;
    final message = _replyController.text.trim();
    if (letter == null ||
        !letter.canReply ||
        letter.hasReply ||
        message.isEmpty ||
        _isSending) {
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _isSending = true);
    try {
      final sender =
          widget.replySender ?? SnapshotService.instance.replyToCommentLetter;
      await sender(letter.originalNotificationId, message);
      _replyController.clear();
      await _loadLetter();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isKorean ? '답장을 보냈어요.' : 'Your reply was sent.',
            style: const TextStyle(
              fontFamily: 'Inter',
              fontFamilyFallback: const ['NotoSansKR'],
              fontWeight: FontWeight.w600,
            ),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isKorean
                ? '답장을 보내지 못했어요. 잠시 후 다시 시도해 주세요.'
                : 'Could not send the reply. Please try again.',
            style: const TextStyle(
              fontFamily: 'Inter',
              fontFamilyFallback: const ['NotoSansKR'],
              fontWeight: FontWeight.w600,
            ),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  String _relativeTime(DateTime? value) {
    if (value == null) return '';
    final difference = DateTime.now().difference(value);
    if (difference.isNegative || difference.inMinutes < 1) {
      return _isKorean ? '방금' : 'Just now';
    }
    if (difference.inDays > 0) {
      return _isKorean
          ? '${difference.inDays}일 전'
          : '${difference.inDays}d ago';
    }
    if (difference.inHours > 0) {
      return _isKorean
          ? '${difference.inHours}시간 전'
          : '${difference.inHours}h ago';
    }
    return _isKorean
        ? '${difference.inMinutes}분 전'
        : '${difference.inMinutes}m ago';
  }

  VoidCallback? _profileAction({
    required String userId,
    required String name,
    required String photoUrl,
  }) {
    final normalizedUserId = userId.trim();
    if (normalizedUserId.isEmpty ||
        normalizedUserId.toLowerCase() == 'deleted') {
      return null;
    }
    return () {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => FriendProfileScreen(
            userId: normalizedUserId,
            nickname: name,
            photoURL: photoUrl,
            allowNonFriendsPreview: true,
          ),
        ),
      );
    };
  }

  @override
  Widget build(BuildContext context) {
    final letter = _letter;
    final showComposer = !_isLoading &&
        _loadError == null &&
        letter != null &&
        letter.canReply &&
        !letter.hasReply;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          elevation: 0,
          centerTitle: true,
          toolbarHeight: context.rh(54, min: 52, max: 58),
          leadingWidth: 52,
          leading: IconButton(
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            padding: const EdgeInsets.all(12),
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            onPressed: () => Navigator.maybePop(context),
            icon: Icon(
              Icons.arrow_back_rounded,
              size: context.ri(23).clamp(22, 25).toDouble(),
            ),
          ),
          title: Text(
            _isKorean ? '스낵 편지' : 'Snack letter',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Inter',
              fontFamilyFallback: const ['NotoSansKR'],
              fontSize: context.rf(18).clamp(17, 20).toDouble(),
              fontWeight: FontWeight.w700,
              color: const Color(0xFF111827),
            ),
          ),
        ),
        body: MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.3,
          child: Column(
            children: [
              Expanded(child: _buildBody()),
              if (showComposer) _buildReplyComposer(letter),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2.4),
        ),
      );
    }
    if (_loadError != null || _letter == null) return _buildError();
    final letter = _letter!;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final horizontal = screenWidth < 360
        ? 16.0
        : screenWidth < 600
            ? 20.0
            : 24.0;
    return SafeArea(
      top: false,
      bottom: !letter.canReply || letter.hasReply,
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            horizontal,
            context.rs(14).clamp(12, 18).toDouble(),
            horizontal,
            28 + MediaQuery.paddingOf(context).bottom,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Icon(
                      Icons.mark_email_read_outlined,
                      size: context.ri(25).clamp(23, 27).toDouble(),
                      color: const Color(0xFF475467),
                    ),
                  ),
                  SizedBox(height: context.rs(14).clamp(12, 17).toDouble()),
                  _SourceContext(
                    authorName: letter.resolvedSourceAuthorName,
                    authorPhotoUrl: letter.resolvedSourceAuthorPhotoUrl,
                    sourceText: letter.sourceText,
                    time: _relativeTime(letter.sourceCreatedAt),
                    isKorean: _isKorean,
                    snapshot: _sourceSnapshot(letter),
                    onProfileTap: _profileAction(
                      userId: letter.ownerId,
                      name: letter.resolvedSourceAuthorName,
                      photoUrl: letter.resolvedSourceAuthorPhotoUrl,
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(
                      vertical: context.rs(20).clamp(17, 23).toDouble(),
                    ),
                    child: const Divider(
                      height: 1,
                      color: Color(0xFFE5E7EB),
                    ),
                  ),
                  Text(
                    letter.viewerIsOwner
                        ? (_isKorean
                            ? '${letter.commenterName}님의 코멘트'
                            : 'A comment from ${letter.commenterName}')
                        : (_isKorean ? '내가 보낸 코멘트' : 'Your comment'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontFamilyFallback: const ['NotoSansKR'],
                      fontSize: context.rf(18).clamp(17, 20).toDouble(),
                      height: 1.35,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF111827),
                    ),
                  ),
                  SizedBox(height: context.rs(16).clamp(14, 18).toDouble()),
                  _PersonLine(
                    name: letter.commenterName,
                    photoUrl: letter.commenterPhotoUrl,
                    time: _relativeTime(letter.commentCreatedAt),
                    onTap: _profileAction(
                      userId: letter.commenterId,
                      name: letter.commenterName,
                      photoUrl: letter.commenterPhotoUrl,
                    ),
                  ),
                  SizedBox(height: context.rs(14).clamp(12, 16).toDouble()),
                  Text(
                    letter.comment,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontFamilyFallback: const ['NotoSansKR'],
                      fontSize: context.rf(16).clamp(15, 17).toDouble(),
                      height: 1.5,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF1F2937),
                    ),
                  ),
                  if (letter.hasReply) ...[
                    Padding(
                      padding: EdgeInsets.symmetric(
                        vertical: context.rs(24).clamp(20, 28).toDouble(),
                      ),
                      child: const Divider(
                        height: 1,
                        color: Color(0xFFE5E7EB),
                      ),
                    ),
                    Text(
                      letter.viewerIsOwner
                          ? (_isKorean ? '나의 답장' : 'Your reply')
                          : (_isKorean
                              ? '${letter.ownerName}님의 답장'
                              : '${letter.ownerName}\'s reply'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontFamilyFallback: const ['NotoSansKR'],
                        fontSize: context.rf(16).clamp(15, 18).toDouble(),
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF111827),
                      ),
                    ),
                    SizedBox(
                      height: context.rs(14).clamp(12, 16).toDouble(),
                    ),
                    _PersonLine(
                      name: letter.ownerName,
                      photoUrl: letter.ownerPhotoUrl,
                      time: _relativeTime(letter.repliedAt),
                      onTap: _profileAction(
                        userId: letter.ownerId,
                        name: letter.ownerName,
                        photoUrl: letter.ownerPhotoUrl,
                      ),
                    ),
                    SizedBox(
                      height: context.rs(14).clamp(12, 16).toDouble(),
                    ),
                    Text(
                      letter.reply,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontFamilyFallback: const ['NotoSansKR'],
                        fontSize: context.rf(16).clamp(15, 17).toDouble(),
                        height: 1.5,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF1F2937),
                      ),
                    ),
                  ],
                  SizedBox(height: context.rs(34).clamp(28, 40).toDouble()),
                  Center(
                    child: Text(
                      _isKorean
                          ? '이 편지는 알림에서만 다시 열 수 있어요.'
                          : 'This letter can only be reopened from notifications.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontFamilyFallback: const ['NotoSansKR'],
                        fontSize: context.rf(12).clamp(11.5, 13).toDouble(),
                        height: 1.45,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF9CA3AF),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  SnapshotItem? _sourceSnapshot(SnapshotCommentLetter letter) {
    final storagePath = letter.sourceImageStoragePath.trim();
    final imageUrl = letter.sourceImageUrl.trim();
    final expiresAt = letter.sourceExpiresAt;
    if ((storagePath.isEmpty && imageUrl.isEmpty) ||
        expiresAt == null ||
        !DateTime.now().isBefore(expiresAt)) {
      return null;
    }
    return SnapshotItem(
      id: letter.snapshotId,
      authorId: letter.ownerId,
      authorName: letter.resolvedSourceAuthorName,
      authorPhotoUrl: letter.resolvedSourceAuthorPhotoUrl,
      authorNationality: '',
      university: '',
      storagePath: storagePath,
      imageUrl: imageUrl,
      visibility: SnapshotVisibility.friends,
      createdAt: letter.sourceCreatedAt ?? DateTime.now(),
      expiresAt: expiresAt,
      aspectRatio: letter.sourceAspectRatio,
      overlay: const SnapshotOverlay(
        text: '',
        x: .5,
        y: .5,
        lightText: true,
      ),
    );
  }

  Widget _buildReplyComposer(SnapshotCommentLetter letter) {
    return Material(
      color: Colors.white,
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Divider(height: 1, color: Color(0xFFE5E7EB)),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    context.rs(18).clamp(16, 20).toDouble(),
                    7,
                    context.rs(10).clamp(8, 12).toDouble(),
                    0,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _replyController,
                          focusNode: _replyFocusNode,
                          enabled: !_isSending,
                          maxLength: 120,
                          maxLines: 1,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _sendReply(),
                          onChanged: (_) => setState(() {}),
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontFamilyFallback: const ['NotoSansKR'],
                            fontSize: context.rf(15).clamp(14, 16).toDouble(),
                            fontWeight: FontWeight.w500,
                            color: const Color(0xFF111827),
                          ),
                          decoration: InputDecoration(
                            hintText: _isKorean
                                ? '한 번뿐인 답장을 작성해 주세요'
                                : 'Write your one-time reply',
                            hintStyle: TextStyle(
                              fontFamily: 'Inter',
                              fontFamilyFallback: const ['NotoSansKR'],
                              fontSize: context.rf(14).clamp(13, 15).toDouble(),
                              color: const Color(0xFF9CA3AF),
                              fontWeight: FontWeight.w500,
                            ),
                            border: InputBorder.none,
                            counterText: '',
                            isDense: true,
                            contentPadding:
                                const EdgeInsets.symmetric(vertical: 13),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        tooltip: _isKorean ? '답장 보내기' : 'Send reply',
                        constraints:
                            const BoxConstraints(minWidth: 48, minHeight: 48),
                        onPressed: !_isSending &&
                                _replyController.text.trim().isNotEmpty
                            ? _sendReply
                            : null,
                        icon: _isSending
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                ),
                              )
                            : Icon(
                                Icons.send_rounded,
                                size: context.ri(23).clamp(22, 25).toDouble(),
                              ),
                        color: AppColors.pointColor,
                        disabledColor: const Color(0xFFD1D5DB),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return SafeArea(
      top: false,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.mail_outline_rounded,
                size: 38,
                color: Color(0xFF9CA3AF),
              ),
              const SizedBox(height: 16),
              Text(
                _isKorean ? '이 편지를 열 수 없어요.' : 'This letter is unavailable.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontFamilyFallback: const ['NotoSansKR'],
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF111827),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _isKorean
                    ? '알림이 삭제되었거나 더 이상 확인할 수 없는 편지예요.'
                    : 'The notification was deleted or is no longer available.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontFamilyFallback: const ['NotoSansKR'],
                  fontSize: 14,
                  height: 1.5,
                  color: Color(0xFF6B7280),
                ),
              ),
              const SizedBox(height: 22),
              TextButton.icon(
                onPressed: _loadLetter,
                icon: const Icon(Icons.refresh_rounded, size: 20),
                label: Text(_isKorean ? '다시 시도' : 'Try again'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SourceContext extends StatelessWidget {
  const _SourceContext({
    required this.authorName,
    required this.authorPhotoUrl,
    required this.sourceText,
    required this.time,
    required this.isKorean,
    required this.snapshot,
    required this.onProfileTap,
  });

  final String authorName;
  final String authorPhotoUrl;
  final String sourceText;
  final String time;
  final bool isKorean;
  final SnapshotItem? snapshot;
  final VoidCallback? onProfileTap;

  @override
  Widget build(BuildContext context) {
    final trimmedText = sourceText.trim();
    return Semantics(
      container: true,
      label: isKorean
          ? '$authorName님이 올린 스낵에서 시작된 편지'
          : 'Letter started from a Snack by $authorName',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            button: onProfileTap != null,
            label: isKorean ? '$authorName 프로필' : '$authorName profile',
            child: InkWell(
              onTap: onProfileTap,
              borderRadius: BorderRadius.circular(8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _LetterAvatar(
                      photoUrl: authorPhotoUrl,
                      size: context.ri(38).clamp(36, 42).toDouble(),
                      iconSize: context.ri(20).clamp(19, 22).toDouble(),
                    ),
                    SizedBox(width: context.rs(10).clamp(8, 12).toDouble()),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isKorean
                                ? '$authorName님이 올린 스낵'
                                : 'A Snack by $authorName',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontFamilyFallback: const ['NotoSansKR'],
                              fontSize: context.rf(14).clamp(13, 15).toDouble(),
                              height: 1.35,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF111827),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            trimmedText.isNotEmpty
                                ? '“$trimmedText”'
                                : (isKorean ? '사진으로 공유한 스낵' : 'A photo Snack'),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontFamilyFallback: const ['NotoSansKR'],
                              fontSize:
                                  context.rf(12.5).clamp(12, 14).toDouble(),
                              height: 1.4,
                              fontWeight: FontWeight.w500,
                              color: const Color(0xFF6B7280),
                            ),
                          ),
                          if (time.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(
                              time,
                              maxLines: 1,
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontFamilyFallback: const ['NotoSansKR'],
                                fontSize:
                                    context.rf(11.5).clamp(11, 12.5).toDouble(),
                                fontWeight: FontWeight.w500,
                                color: const Color(0xFF9CA3AF),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(height: context.rs(13).clamp(11, 15).toDouble()),
          _SourceSnapshotMedia(
            snapshot: snapshot,
            isKorean: isKorean,
          ),
        ],
      ),
    );
  }
}

class _SourceSnapshotMedia extends StatelessWidget {
  const _SourceSnapshotMedia({
    required this.snapshot,
    required this.isKorean,
  });

  final SnapshotItem? snapshot;
  final bool isKorean;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportHeight = MediaQuery.sizeOf(context).height;
        final sourceAspectRatio = snapshot?.aspectRatio ?? (4 / 3);
        final maximumHeight = (viewportHeight * .44).clamp(220.0, 420.0);
        final desiredHeight = constraints.maxWidth / sourceAspectRatio;
        final mediaHeight = desiredHeight.clamp(210.0, maximumHeight);

        return Semantics(
          image: true,
          label: isKorean ? '편지가 시작된 스낵 사진' : 'Photo from this Snack',
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              key: const ValueKey<String>('snack-letter-source-image'),
              width: double.infinity,
              height: mediaHeight,
              child: snapshot == null
                  ? const ColoredBox(
                      color: Color(0xFFF3F4F6),
                      child: Icon(
                        Icons.image_not_supported_outlined,
                        size: 30,
                        color: Color(0xFF9CA3AF),
                      ),
                    )
                  : ColoredBox(
                      color: Colors.black,
                      child: SnapshotStorageImage(
                        snapshot: snapshot!,
                        fit: BoxFit.contain,
                        showLoadingIndicator: false,
                        placeholderColor: Colors.black,
                        errorBackgroundColor: const Color(0xFFF3F4F6),
                        fadeInDuration: const Duration(milliseconds: 160),
                      ),
                    ),
            ),
          ),
        );
      },
    );
  }
}

class _LetterAvatar extends StatelessWidget {
  const _LetterAvatar({
    required this.photoUrl,
    required this.size,
    required this.iconSize,
    this.fallbackIcon = Icons.photo_outlined,
  });

  final String photoUrl;
  final double size;
  final double iconSize;
  final IconData fallbackIcon;

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: SizedBox.square(
        dimension: size,
        child: photoUrl.isEmpty
            ? ColoredBox(
                color: const Color(0xFFF3F4F6),
                child: Icon(
                  fallbackIcon,
                  size: iconSize,
                  color: const Color(0xFF9CA3AF),
                ),
              )
            : Image.network(
                photoUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => ColoredBox(
                  color: const Color(0xFFF3F4F6),
                  child: Icon(
                    fallbackIcon,
                    size: iconSize,
                    color: const Color(0xFF9CA3AF),
                  ),
                ),
              ),
      ),
    );
  }
}

class _PersonLine extends StatelessWidget {
  const _PersonLine({
    required this.name,
    required this.photoUrl,
    required this.time,
    required this.onTap,
  });

  final String name;
  final String photoUrl;
  final String time;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: onTap != null,
      label: name,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Row(
            children: [
              _LetterAvatar(
                photoUrl: photoUrl,
                size: context.ri(38).clamp(36, 41).toDouble(),
                iconSize: context.ri(20).clamp(19, 22).toDouble(),
                fallbackIcon: Icons.person_outline_rounded,
              ),
              SizedBox(width: context.rs(10).clamp(8, 12).toDouble()),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontFamilyFallback: const ['NotoSansKR'],
                    fontSize: context.rf(15).clamp(14, 16).toDouble(),
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF111827),
                  ),
                ),
              ),
              if (time.isNotEmpty) ...[
                SizedBox(width: context.rs(8).clamp(6, 10).toDouble()),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 104),
                  child: Text(
                    time,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontFamilyFallback: const ['NotoSansKR'],
                      fontSize: context.rf(12).clamp(11.5, 13).toDouble(),
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF9CA3AF),
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
