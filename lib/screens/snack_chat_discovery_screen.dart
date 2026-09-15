import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../constants/app_constants.dart';
import '../l10n/ui_locale.dart';
import '../models/snack_chat_message.dart';
import '../services/snack_chat_discovery_cache_service.dart';
import '../services/snack_chat_discovery_service.dart';
import '../services/snack_chat_file_transfer_service.dart';
import '../services/snack_chat_local_cache_service.dart';
import '../ui/widgets/fullscreen_image_viewer.dart';
import '../ui/widgets/snack_chat_message_extras.dart';

String snackDiscoveryText(
        BuildContext context, String ko, String en, String zh) =>
    switch (Localizations.localeOf(context).languageCode) {
      'ko' => ko,
      'zh' => zh,
      _ => en
    };

TextStyle _discoveryTextStyle(
  BuildContext context, {
  double size = 14,
  FontWeight weight = FontWeight.w400,
  Color color = const Color(0xFF0F172A),
  double height = 1.45,
}) =>
    TextStyle(
      fontFamily: uiFontFamily(context, 'Inter'),
      fontFamilyFallback: const ['NotoSansKR', 'NotoSansSC'],
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
    );

class SnackChatDiscoveryScreen extends StatefulWidget {
  const SnackChatDiscoveryScreen(
      {super.key, required this.roomId, this.initialKind = 'image'});
  final String roomId, initialKind;
  @override
  State<SnackChatDiscoveryScreen> createState() =>
      _SnackChatDiscoveryScreenState();
}

class _SnackChatDiscoveryScreenState extends State<SnackChatDiscoveryScreen> {
  final _service = SnackChatDiscoveryService();
  final _cache = SnackChatDiscoveryCacheService.instance;
  final _scroll = ScrollController();
  final _rows = <Map<String, dynamic>>[];
  late String _kind;
  String? _cursor, _error;
  final DateTime _from = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _to = DateTime.now();
  bool _loading = false, _hasMore = false;
  int _generation = 0;
  String? _owner;
  Timer? _refreshTimer;
  bool _historyComplete = false;
  bool _refreshing = false;
  int _knownSequence = 0;
  StreamSubscription? _auth;
  String t(String ko, String en, String zh) =>
      snackDiscoveryText(context, ko, en, zh);

  @override
  void initState() {
    super.initState();
    _kind = const {'image', 'file', 'link'}.contains(widget.initialKind)
        ? widget.initialKind
        : 'image';
    _scroll.addListener(_loadNextPageNearEnd);
    _owner = FirebaseAuth.instance.currentUser?.uid;
    _auth = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user?.uid != _owner && mounted) {
        _generation++;
        setState(() {
          _rows.clear();
          _hasMore = false;
          _error = 'session';
        });
      }
    });
    _bootstrap();
    _refreshTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _syncNewMessages(),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _auth?.cancel();
    _scroll.removeListener(_loadNextPageNearEnd);
    _scroll.dispose();
    super.dispose();
  }

  void _loadNextPageNearEnd() {
    if (!_scroll.hasClients || _loading || !_hasMore || _error != null) return;
    if (_scroll.position.extentAfter < 420) _load();
  }

  Future<void> _bootstrap() async {
    final snapshot = await _cache.read(widget.roomId, _kind);
    if (!mounted || FirebaseAuth.instance.currentUser?.uid != _owner) return;
    if (snapshot != null) {
      setState(() {
        _rows
          ..clear()
          ..addAll(snapshot.rows);
        _cursor = snapshot.cursor;
        _historyComplete = snapshot.historyComplete;
        _knownSequence = snapshot.latestSequence;
        if (!snapshot.historyComplete && snapshot.queryToMillis > 0) {
          _to = DateTime.fromMillisecondsSinceEpoch(snapshot.queryToMillis);
        }
      });
    }
    await _hydrateCachedRows();
    if (!mounted || FirebaseAuth.instance.currentUser?.uid != _owner) return;
    if (_historyComplete) {
      unawaited(_persistIndex());
      unawaited(_syncNewMessages());
      return;
    }
    await _load(
      reset: _cursor == null,
      preserveVisibleRows: true,
    );
  }

  Future<void> _hydrateCachedRows() async {
    final messages = await SnackChatLocalCacheService().getMessages(
      widget.roomId,
      limit: 400,
    );
    if (!mounted || FirebaseAuth.instance.currentUser?.uid != _owner) return;
    final cached =
        messages.where(_matchesKind).map(_cachedRow).toList(growable: false);
    if (cached.isEmpty) return;
    setState(() {
      final ids = _rows.map((row) => row['id']).toSet();
      _rows.addAll(cached.where((row) => ids.add(row['id'])));
      _sortRows();
    });
  }

  bool _matchesKind(SnackChatMessage message) {
    if (message.isDeleted || message.sendStatus != MessageSendStatus.sent) {
      return false;
    }
    return switch (_kind) {
      'file' => message.type == SnackChatMessageType.file,
      'link' => message.linkPreview != null ||
          RegExp(r'https?://[^\s<>]+', caseSensitive: false)
              .hasMatch(message.text),
      _ => message.imagePath?.isNotEmpty == true ||
          message.imageUrl?.isNotEmpty == true,
    };
  }

  Map<String, dynamic> _cachedRow(SnackChatMessage message) =>
      <String, dynamic>{
        'id': message.id,
        'senderId': message.senderId,
        if (message.senderName?.isNotEmpty == true)
          'senderName': message.senderName,
        'type': snackChatMessageTypeWireName(message.type),
        'text': message.text,
        if (message.imagePath?.isNotEmpty == true)
          'imagePath': message.imagePath,
        if (message.imageUrl?.isNotEmpty == true) 'imageUrl': message.imageUrl,
        if (message.originalFileName?.isNotEmpty == true)
          'originalFileName': message.originalFileName,
        if (message.fileExtension?.isNotEmpty == true)
          'fileExtension': message.fileExtension,
        if (message.mimeType?.isNotEmpty == true) 'mimeType': message.mimeType,
        if (message.fileSize != null) 'fileSize': message.fileSize,
        if (message.storagePath?.isNotEmpty == true)
          'storagePath': message.storagePath,
        if (message.expiresAt != null)
          'expiresAt': message.expiresAt!.millisecondsSinceEpoch,
        if (message.linkPreview != null)
          'linkPreview': message.linkPreview!.toMap(),
        'fileExpired': message.isFileExpired,
        'createdAt': message.createdAt.millisecondsSinceEpoch,
      };

  Future<void> _load({
    bool reset = false,
    bool preserveVisibleRows = false,
  }) async {
    if (_loading && !reset) return;
    if (FirebaseAuth.instance.currentUser?.uid != _owner) return;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
      if (reset) {
        if (!preserveVisibleRows) _rows.clear();
        _cursor = null;
        _hasMore = false;
        _historyComplete = false;
        _to = DateTime.now();
      }
    });
    try {
      final page = await _service.query(widget.roomId, {
        'fromMillis': _from.millisecondsSinceEpoch,
        'toMillis': _to.millisecondsSinceEpoch,
        'kind': _kind,
        if (_cursor != null) 'cursor': _cursor,
      });
      if (!mounted || generation != _generation) return;
      setState(() {
        if (reset) {
          _knownSequence = (page['latestSequence'] as num? ?? 0).toInt();
        }
        final ids = _rows.map((row) => row['id']).toSet();
        _rows.addAll(SnackChatDiscoveryService.rows(page)
            .where((row) => ids.add(row['id'])));
        _sortRows();
        _cursor = page['cursor'] as String?;
        _hasMore = page['hasMore'] == true;
        _historyComplete = !_hasMore;
      });
      unawaited(_persistIndex());
    } catch (error) {
      if (mounted && generation == _generation) {
        final code = error is FirebaseFunctionsException ? error.code : 'query';
        if (code == 'permission-denied') {
          setState(() {
            _rows.clear();
            _historyComplete = false;
            _error = code;
          });
          unawaited(_cache.clearRoom(widget.roomId));
        } else if (_rows.isEmpty) {
          setState(() => _error = code);
        }
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || generation != _generation || _loading || !_hasMore) {
            return;
          }
          // Sparse media can require more than one bounded server scan before
          // the first visible result. Fill a short viewport automatically;
          // longer histories continue loading as the user scrolls.
          if (!_scroll.hasClients || _scroll.position.extentAfter < 420) {
            _load();
          }
        });
      }
    }
  }

  void _sortRows() {
    _rows.sort((a, b) => ((b['createdAt'] as num?)?.toInt() ?? 0)
        .compareTo((a['createdAt'] as num?)?.toInt() ?? 0));
  }

  Future<void> _persistIndex() => _cache.write(
        widget.roomId,
        _kind,
        SnackChatDiscoveryCacheSnapshot(
          rows: List<Map<String, dynamic>>.of(_rows),
          historyComplete: _historyComplete,
          latestSequence: _knownSequence,
          queryToMillis: _to.millisecondsSinceEpoch,
          updatedAt: DateTime.now(),
          cursor: _historyComplete ? null : _cursor,
        ),
      );

  Future<void> _syncNewMessages() async {
    if (_refreshing ||
        _loading ||
        !mounted ||
        !_historyComplete ||
        ModalRoute.of(context)?.isCurrent != true ||
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed ||
        FirebaseAuth.instance.currentUser?.uid != _owner) {
      return;
    }
    _refreshing = true;
    final generation = _generation;
    try {
      var scannedThrough = _knownSequence;
      for (var pageNumber = 0; pageNumber < 8; pageNumber++) {
        final page = await _service.query(widget.roomId, {
          'kind': _kind,
          'afterSequence': scannedThrough,
        });
        if (!mounted ||
            generation != _generation ||
            FirebaseAuth.instance.currentUser?.uid != _owner) {
          return;
        }
        // An older Functions deployment ignores afterSequence. Preserve the
        // local index and wait for the compatible server instead of repeatedly
        // rescanning the complete conversation.
        if (page['scannedThroughSequence'] == null) return;
        final incoming = SnackChatDiscoveryService.rows(page);
        final nextScanned =
            (page['scannedThroughSequence'] as num? ?? scannedThrough).toInt();
        setState(() {
          final byId = <String, Map<String, dynamic>>{
            for (final row in _rows) row['id'].toString(): row,
          };
          for (final row in incoming) {
            byId[row['id'].toString()] = row;
          }
          _rows
            ..clear()
            ..addAll(byId.values);
          _sortRows();
          _knownSequence = nextScanned;
        });
        if (nextScanned <= scannedThrough || page['hasMore'] != true) break;
        scannedThrough = nextScanned;
      }
      unawaited(_persistIndex());
    } catch (_) {
      // Persistent content stays readable offline. A failed background sync
      // must not turn cached data into an error or an empty list.
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _openPhoto(Map<String, dynamic> row) async {
    final photos = _rows.where(_hasPhotoSource).toList(growable: false);
    final index = photos.indexWhere((item) => item['id'] == row['id']);
    if (index < 0 || !mounted) return;
    await showFullscreenImageViewer(
      context,
      imageUrls: photos
          .map((item) => (item['imageUrl'] ?? '').toString())
          .toList(growable: false),
      storagePaths: photos
          .map((item) => item['imagePath']?.toString())
          .toList(growable: false),
      initialIndex: index,
    );
  }

  bool _hasPhotoSource(Map<String, dynamic> row) =>
      (row['imagePath']?.toString().trim().isNotEmpty ?? false) ||
      (row['imageUrl']?.toString().trim().isNotEmpty ?? false);

  Future<void> _openFile(Map<String, dynamic> row) async {
    try {
      await SnackChatFileTransferService.instance.openFile(
        SnackChatDiscoveryService.message(row),
        roomId: widget.roomId,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(t('파일을 열 수 없어요.', 'File unavailable.', '无法打开文件。')),
        ),
      );
    }
  }

  List<String> _links(Map<String, dynamic> row) {
    final values = <String>{};
    final preview = row['linkPreview'];
    if (preview is Map) {
      final previewUrl = (preview['url'] ?? '').toString().trim();
      if (_isWebUrl(previewUrl)) values.add(previewUrl);
    }
    final text = (row['text'] ?? '').toString();
    for (final match in RegExp(r'https?://[^\s<>]+', caseSensitive: false)
        .allMatches(text)) {
      final value = (match.group(0) ?? '').replaceFirst(
        RegExp(r'[),.!?]+$'),
        '',
      );
      if (_isWebUrl(value)) values.add(value);
    }
    return values.toList(growable: false);
  }

  bool _isWebUrl(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host.isNotEmpty;
  }

  Future<void> _openLink(String value) async {
    try {
      final opened = await launchUrl(
        Uri.parse(value),
        mode: LaunchMode.externalApplication,
      );
      if (!opened) throw StateError('launch failed');
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(t('링크를 열 수 없어요.', 'Link unavailable.', '无法打开链接。')),
        ),
      );
    }
  }

  Widget _photoResult(Map<String, dynamic> row) {
    final sender = row['senderName']?.toString().trim().isNotEmpty == true
        ? row['senderName'].toString().trim()
        : t('참여자', 'Participant', '成员');
    final millis = (row['createdAt'] as num? ?? 0).toInt();
    final date = DateTime.fromMillisecondsSinceEpoch(millis);
    return Semantics(
      button: true,
      label: '$sender · ${DateFormat('yyyy.MM.dd HH:mm').format(date)}',
      child: Material(
        color: const Color(0xFFF2F4F7),
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _openPhoto(row),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _CachedPhotoThumbnail(
                storagePath: row['imagePath'] as String?,
                imageUrl: row['imageUrl'] as String?,
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Color(0xB3000000)],
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 18, 8, 7),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          sender,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _discoveryTextStyle(
                            context,
                            size: 11.5,
                            weight: FontWeight.w600,
                            color: Colors.white,
                            height: 1.25,
                          ),
                        ),
                        Text(
                          DateFormat('MM.dd HH:mm').format(date),
                          maxLines: 1,
                          style: _discoveryTextStyle(
                            context,
                            size: 10.5,
                            color: const Color(0xFFE5E7EB),
                            height: 1.25,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Map<DateTime, List<Map<String, dynamic>>> _rowsByDay() {
    final grouped = <DateTime, List<Map<String, dynamic>>>{};
    for (final row in _rows) {
      if (_kind == 'image' && !_hasPhotoSource(row)) continue;
      if (_kind == 'link' && _links(row).isEmpty) continue;
      final millis = (row['createdAt'] as num? ?? 0).toInt();
      final value = DateTime.fromMillisecondsSinceEpoch(millis);
      final day = DateTime(value.year, value.month, value.day);
      grouped.putIfAbsent(day, () => <Map<String, dynamic>>[]).add(row);
    }
    return grouped;
  }

  String _dayLabel(DateTime day) {
    final language = Localizations.localeOf(context).languageCode;
    if (language == 'ko') return '${day.year}년 ${day.month}월 ${day.day}일';
    if (language == 'zh') return '${day.year}年${day.month}月${day.day}日';
    return DateFormat('MMM d, yyyy').format(day);
  }

  String _kindLabel() => switch (_kind) {
        'file' => t('파일', 'Files', '文件'),
        'link' => t('링크', 'Links', '链接'),
        _ => t('사진', 'Photos', '照片'),
      };

  Widget _dayHeader(DateTime day, int count) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 9),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _dayLabel(day),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _discoveryTextStyle(
                  context,
                  size: 14,
                  weight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$count',
              style: _discoveryTextStyle(
                context,
                size: 12,
                color: const Color(0xFF667085),
              ),
            ),
          ],
        ),
      );

  Widget _resultFooter() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      child: Column(
        children: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(color: AppColors.pointColor),
            ),
          if (_error != null)
            Text(
              _error == 'permission-denied'
                  ? t(
                      '현재 이 방의 대화를 조회할 수 없어요. 참여 상태를 확인해 주세요.',
                      'This conversation is not currently accessible. Check your membership.',
                      '当前无法查看此群聊，请确认成员状态。')
                  : _error == 'unauthenticated' || _error == 'session'
                      ? t('로그인 상태를 확인해 주세요.',
                          'Please check your sign-in status.', '请确认登录状态。')
                      : _error == 'not-found'
                          ? t(
                              '자료를 불러올 수 없어요. 잠시 후 다시 시도해 주세요.',
                              'Media is unavailable. Please try again shortly.',
                              '暂时无法加载资料，请稍后重试。')
                          : t(
                              '자료를 불러오지 못했어요. 다시 시도해 주세요.',
                              'Could not load media. Please try again.',
                              '无法加载资料，请重试。'),
              textAlign: TextAlign.center,
              style: _discoveryTextStyle(
                context,
                size: 13,
                color: const Color(0xFF475569),
              ),
            ),
          if (_error != null)
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: AppColors.pointColor,
              ),
              onPressed: () => _load(reset: _rows.isEmpty),
              child: Text(t('다시 시도', 'Retry', '重试')),
            ),
          if (!_loading && _error == null && _rows.isEmpty && !_hasMore)
            Text(
              t(
                  '이 대화방에 표시할 ${_kindLabel()}이 없어요.',
                  'No ${_kindLabel().toLowerCase()} in this chat.',
                  '此群聊中没有可显示的${_kindLabel()}。'),
              textAlign: TextAlign.center,
              style: _discoveryTextStyle(
                context,
                size: 12,
                color: const Color(0xFF667085),
              ),
            ),
          if (_hasMore && !_loading)
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: AppColors.pointColor,
              ),
              onPressed: _load,
              child: Text(t('더 보기', 'Load more', '加载更多')),
            ),
        ],
      ),
    );
  }

  Widget _results() {
    final photoGrid = _kind == 'image';
    final groups = _rowsByDay();
    return RefreshIndicator(
      color: AppColors.pointColor,
      onRefresh: () async {
        if (_historyComplete) {
          await _syncNewMessages();
        } else {
          await _load(
            reset: _cursor == null,
            preserveVisibleRows: true,
          );
        }
      },
      child: CustomScrollView(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          for (final group in groups.entries) ...[
            SliverToBoxAdapter(
              child: _dayHeader(group.key, group.value.length),
            ),
            if (photoGrid)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 180,
                    mainAxisSpacing: 4,
                    crossAxisSpacing: 4,
                    childAspectRatio: 1,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => _photoResult(group.value[index]),
                    childCount: group.value.length,
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final row = group.value[index];
                      return _kind == 'file'
                          ? _FileLibraryRow(
                              row: row,
                              onTap: () => _openFile(row),
                            )
                          : _LinkLibraryRow(
                              row: row,
                              links: _links(row),
                              onOpen: _openLink,
                            );
                    },
                    childCount: group.value.length,
                  ),
                ),
              ),
          ],
          SliverToBoxAdapter(child: _resultFooter()),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.white,
            title: Text(_kindLabel(),
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700))),
        body: SafeArea(top: false, child: _results()),
      );
}

/// Uses the same authenticated Storage loader and account-scoped cache as the
/// chat bubble, while retaining URL-only legacy image compatibility.
class _CachedPhotoThumbnail extends StatelessWidget {
  const _CachedPhotoThumbnail({this.storagePath, this.imageUrl});
  final String? storagePath;
  final String? imageUrl;

  Widget _placeholder() => const ColoredBox(
        color: Color(0xFFF2F4F7),
        child: Center(
          child: Icon(Icons.photo_outlined, size: 30, color: Color(0xFF667085)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final path = storagePath?.trim() ?? '';
    if (path.isNotEmpty) {
      return SnackChatStorageImage(
        storagePath: path,
        fit: BoxFit.cover,
        imageBuilder: (context, provider) => Image(
          image: ResizeImage(provider, width: 480),
          fit: BoxFit.cover,
          gaplessPlayback: true,
        ),
        loading: _placeholder(),
        error: _placeholder(),
      );
    }
    return _networkOrPlaceholder();
  }

  Widget _networkOrPlaceholder() {
    final rawUrl = imageUrl?.trim() ?? '';
    final uri = Uri.tryParse(rawUrl);
    if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
      return _placeholder();
    }
    return Image.network(
      rawUrl,
      fit: BoxFit.cover,
      cacheWidth: 480,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) =>
          wasSynchronouslyLoaded || frame != null ? child : _placeholder(),
      errorBuilder: (_, __, ___) => _placeholder(),
    );
  }
}

class _FileLibraryRow extends StatelessWidget {
  const _FileLibraryRow({required this.row, required this.onTap});
  final Map<String, dynamic> row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final expiresAt = (row['expiresAt'] as num? ?? 0).toInt();
    final expired = row['fileExpired'] == true ||
        (expiresAt > 0 && expiresAt <= DateTime.now().millisecondsSinceEpoch);
    final name = (row['originalFileName'] ?? '').toString().trim();
    final extension = (row['fileExtension'] ?? '').toString().trim();
    final size = (row['fileSize'] as num?)?.toInt();
    final sender = row['senderName']?.toString().isNotEmpty == true
        ? row['senderName'].toString()
        : snackDiscoveryText(context, '참여자', 'Participant', '成员');
    final details = <String>[
      if (extension.isNotEmpty) extension.toUpperCase(),
      if (size != null) _fileSize(size),
      sender,
    ].join(' · ');
    return InkWell(
      onTap: expired ? null : onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.insert_drive_file_outlined,
                size: 24, color: Color(0xFF64748B)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name.isEmpty
                        ? snackDiscoveryText(
                            context, '첨부 파일', 'Attachment', '附件')
                        : name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: _discoveryTextStyle(context,
                        size: 14, weight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    expired
                        ? snackDiscoveryText(
                            context, '보관 기간 만료', 'Expired', '已过期')
                        : details,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _discoveryTextStyle(context,
                        size: 12, color: const Color(0xFF64748B)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(expired ? Icons.block_outlined : Icons.open_in_new_rounded,
                size: 18, color: const Color(0xFF98A2B3)),
          ],
        ),
      ),
    );
  }

  static String _fileSize(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '$bytes B';
  }
}

class _LinkLibraryRow extends StatelessWidget {
  const _LinkLibraryRow({
    required this.row,
    required this.links,
    required this.onOpen,
  });

  final Map<String, dynamic> row;
  final List<String> links;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final preview = row['linkPreview'] is Map
        ? Map<String, dynamic>.from(row['linkPreview'] as Map)
        : const <String, dynamic>{};
    final title = (preview['title'] ?? '').toString().trim();
    if (links.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        for (final link in links)
          InkWell(
            onTap: () => onOpen(link),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 1),
                    child: Icon(Icons.link_rounded,
                        size: 22, color: Color(0xFF64748B)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (title.isNotEmpty) ...[
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _discoveryTextStyle(context,
                                size: 14, weight: FontWeight.w600),
                          ),
                          const SizedBox(height: 2),
                        ],
                        Text(
                          link,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: _discoveryTextStyle(context,
                              size: 12.5, color: AppColors.pointColor),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(Icons.open_in_new_rounded,
                        size: 17, color: Color(0xFF98A2B3)),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
