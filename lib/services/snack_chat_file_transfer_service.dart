import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../config/snack_chat_file_policy.dart';
import '../models/snack_chat.dart';
import '../models/snack_chat_message.dart';
import '../utils/logger.dart';
import 'snack_chat_local_cache_service.dart';
import 'snack_chat_service.dart';

class SnackChatFileTransferEvent {
  const SnackChatFileTransferEvent({
    required this.roomId,
    required this.message,
    this.removed = false,
  });

  final String roomId;
  final SnackChatMessage message;
  final bool removed;
}

/// Central Firebase Storage selector for Snack Chat files.
///
/// Keeping bucket/reference creation here makes a future temporary-file bucket
/// split possible without changing the upload queue or message UI.
class SnackChatFileStorageGateway {
  SnackChatFileStorageGateway._();

  static final SnackChatFileStorageGateway instance =
      SnackChatFileStorageGateway._();

  FirebaseStorage get _storage => FirebaseStorage.instance;

  Reference reference(String storagePath) => _storage.ref(storagePath);
}

class SnackChatFileTransferService {
  SnackChatFileTransferService._() {
    _auth.userChanges().listen(_onAuthChanged);
  }

  static final SnackChatFileTransferService instance =
      SnackChatFileTransferService._();

  static const String _queueKeyPrefix = 'snack_chat_file_queue_v1';
  static const String _cacheIndexKeyPrefix = 'snack_chat_file_cache_v1';

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;
  final SnackChatService _chatService = SnackChatService();
  final SnackChatLocalCacheService _localChatCache =
      SnackChatLocalCacheService();
  final SnackChatFileStorageGateway _storage =
      SnackChatFileStorageGateway.instance;
  final Uuid _uuid = const Uuid();
  final StreamController<SnackChatFileTransferEvent> _events =
      StreamController<SnackChatFileTransferEvent>.broadcast(sync: true);
  final Map<String, _UploadRecord> _records = <String, _UploadRecord>{};
  final Map<String, UploadTask> _activeUploadTasks = <String, UploadTask>{};
  final Set<String> _activeRecordIds = <String>{};
  final Map<String, DownloadTask> _activeDownloadTasks =
      <String, DownloadTask>{};
  final Set<String> _activeFileOpenIds = <String>{};

  String? _loadedUid;
  String? _lastAuthUid;
  Future<void>? _loading;
  Future<void> _persisting = Future<void>.value();
  bool _pumpScheduled = false;

  Stream<SnackChatFileTransferEvent> watchRoom(String roomId) =>
      _events.stream.where((event) => event.roomId == roomId);

  Future<List<SnackChatMessage>> restoreRoom(String roomId) async {
    await _ensureLoaded();
    final uid = _auth.currentUser?.uid;
    if (uid == null) return const <SnackChatMessage>[];
    var changed = false;
    final messages = <SnackChatMessage>[];
    for (final record in _records.values.where(
      (value) => value.ownerUid == uid && value.roomId == roomId,
    )) {
      if (!await File(record.localPath).exists()) {
        record
          ..status = SnackChatFileTransferStatus.failed
          ..errorMessage = '원본 파일에 접근할 수 없습니다.';
        changed = true;
      } else if (record.status == SnackChatFileTransferStatus.uploading) {
        record.status = SnackChatFileTransferStatus.queued;
        changed = true;
      } else if (record.status == SnackChatFileTransferStatus.finalizing) {
        record.status = SnackChatFileTransferStatus.queued;
        changed = true;
      }
      messages.add(record.toMessage());
    }
    if (changed) await _persistQueue();
    _schedulePump();
    return messages;
  }

  Future<List<SnackChatMessage>> enqueueFiles({
    required SnackChat room,
    required List<SnackChatSelectedFile> files,
    ReplyMessagePreview? replyPreview,
  }) async {
    if (files.isEmpty || files.length > SnackChatFilePolicy.maxSelectionCount) {
      throw StateError('파일은 한 번에 최대 5개까지 선택할 수 있습니다.');
    }
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('로그인이 필요합니다.');
    await _ensureLoaded();
    final retentionMode =
        room.activeDurationHours == 0 ? 'permanent' : 'temporary24h';
    final now = DateTime.now();
    final messages = <SnackChatMessage>[];
    final stagedPaths = <String>[];
    try {
      for (var index = 0; index < files.length; index++) {
        if (_auth.currentUser?.uid != uid) {
          throw StateError('로그인 상태가 변경되었습니다.');
        }
        final selected = files[index];
        final messageId = _chatService.createMessageId(room.id);
        final staged = await _stageSelectedFile(
          uid: uid,
          messageId: messageId,
          selected: selected,
        );
        stagedPaths.add(staged.path);
        final record = _UploadRecord(
          ownerUid: uid,
          roomId: room.id,
          messageId: messageId,
          uploadId: _uuid.v4(),
          fileId: _uuid.v4(),
          originalFileName: selected.originalFileName,
          fileExtension: selected.fileExtension,
          mimeType: selected.mimeType,
          fileSize: selected.fileSize,
          localPath: staged.path,
          retentionMode: retentionMode,
          createdAt: now.add(Duration(microseconds: index)),
          replyPreview: replyPreview,
        );
        _records[messageId] = record;
        messages.add(record.toMessage());
      }
    } catch (_) {
      for (final message in messages) {
        _records.remove(message.id);
      }
      for (final path in stagedPaths) {
        await File(path).delete().catchError((_) => File(''));
      }
      rethrow;
    }
    await _persistQueue();
    for (final message in messages) {
      _emit(_records[message.id]!);
    }
    _schedulePump();
    return messages;
  }

  Future<void> retry(String messageId) async {
    await _ensureLoaded();
    final record = _records[messageId];
    if (record == null || record.ownerUid != _auth.currentUser?.uid) return;
    if (!await File(record.localPath).exists()) {
      record
        ..status = SnackChatFileTransferStatus.failed
        ..errorMessage = '원본 파일에 접근할 수 없습니다.';
      await _persistQueue();
      _emit(record);
      return;
    }
    record
      ..status = SnackChatFileTransferStatus.queued
      ..errorMessage = null;
    await _persistQueue();
    _emit(record);
    _schedulePump();
  }

  Future<void> retryRoom(String roomId) async {
    await _ensureLoaded();
    var changed = false;
    for (final record in _records.values) {
      if (record.roomId != roomId ||
          record.ownerUid != _auth.currentUser?.uid ||
          record.status != SnackChatFileTransferStatus.failed) {
        continue;
      }
      if (await File(record.localPath).exists()) {
        record
          ..status = SnackChatFileTransferStatus.queued
          ..errorMessage = null;
        changed = true;
        _emit(record);
      }
    }
    if (changed) await _persistQueue();
    _schedulePump();
  }

  Future<void> cancelAndRemove(String messageId) async {
    await _ensureLoaded();
    final record = _records[messageId];
    if (record == null || record.ownerUid != _auth.currentUser?.uid) return;
    await _activeUploadTasks.remove(messageId)?.cancel();
    try {
      await _functions.httpsCallable('cancelSnackChatFileUpload').call(
        <String, dynamic>{
          'snackChatId': record.roomId,
          'uploadId': record.uploadId,
        },
      ).timeout(const Duration(seconds: 20));
    } catch (error) {
      // A missing job/object is already the desired idempotent end state.
      Logger.warning('Snack Chat 파일 취소 서버 정리 지연: $error');
    }
    record.status = SnackChatFileTransferStatus.canceled;
    _emit(record, removed: true);
    _records.remove(messageId);
    _activeRecordIds.remove(messageId);
    await File(record.localPath).delete().catchError((_) => File(''));
    await _persistQueue();
    _schedulePump();
  }

  Future<void> openFile(
    SnackChatMessage message, {
    required String roomId,
  }) async {
    if (!_activeFileOpenIds.add(message.id)) return;
    try {
      await _openFileOnce(message, roomId: roomId);
    } finally {
      _activeFileOpenIds.remove(message.id);
    }
  }

  Future<void> _openFileOnce(
    SnackChatMessage message, {
    required String roomId,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('로그인이 필요합니다.');
    if (message.isFileExpired) {
      await _removeCachedMessageFile(uid, message);
      throw StateError('만료된 파일입니다.');
    }
    final storagePath = message.storagePath;
    if (storagePath == null || storagePath.isEmpty) {
      throw StateError('파일 정보를 확인할 수 없습니다.');
    }
    final room = await _chatService.getSnackChatFromServer(roomId);
    if (room == null || !room.participantIds.contains(uid)) {
      throw StateError('이 파일에 접근할 수 없습니다.');
    }
    if (message.isFileExpired) throw StateError('만료된 파일입니다.');

    final localSourcePath = message.localFilePath;
    if (localSourcePath != null && localSourcePath.isNotEmpty) {
      final localSource = File(localSourcePath);
      if (await localSource.exists()) {
        final result = await OpenFilex.open(localSource.path);
        if (result.type != ResultType.done) throw StateError(result.message);
        return;
      }
    }

    final cached = await _cachedFile(uid, message);
    if (cached != null) {
      await _touchCache(uid, message, cached);
      final result = await OpenFilex.open(cached.path);
      if (result.type != ResultType.done) throw StateError(result.message);
      return;
    }

    final destination = await _cacheDestination(uid, message);
    await destination.parent.create(recursive: true);
    final download = _storage.reference(storagePath).writeToFile(destination);
    _activeDownloadTasks[message.id] = download;
    _events.add(SnackChatFileTransferEvent(
      roomId: roomId,
      message: message.copyWith(
        fileTransferStatus: SnackChatFileTransferStatus.downloading,
        transferProgress: 0,
      ),
    ));
    var lastProgress = -1;
    final subscription = download.snapshotEvents.listen((snapshot) {
      final total = snapshot.totalBytes;
      if (total <= 0) return;
      final percent = ((snapshot.bytesTransferred / total) * 100).floor();
      if (percent < 100 && percent - lastProgress < 4) return;
      lastProgress = percent;
      _events.add(SnackChatFileTransferEvent(
        roomId: roomId,
        message: message.copyWith(
          fileTransferStatus: SnackChatFileTransferStatus.downloading,
          transferProgress: percent / 100,
        ),
      ));
    });
    try {
      await download;
      if (message.isFileExpired) {
        await destination.delete().catchError((_) => destination);
        throw StateError('만료된 파일입니다.');
      }
      await _touchCache(uid, message, destination);
      await _trimCache(uid);
      _events.add(SnackChatFileTransferEvent(
        roomId: roomId,
        message: message.copyWith(
          fileTransferStatus: SnackChatFileTransferStatus.downloaded,
          transferProgress: 1,
        ),
      ));
      final result = await OpenFilex.open(destination.path);
      if (result.type != ResultType.done) throw StateError(result.message);
    } catch (error) {
      if (await destination.exists()) await destination.delete();
      _events.add(SnackChatFileTransferEvent(
        roomId: roomId,
        message: message.copyWith(
          fileTransferStatus: SnackChatFileTransferStatus.failed,
          clearTransferProgress: true,
          errorMessage: '다운로드하지 못했습니다.',
        ),
      ));
      rethrow;
    } finally {
      await subscription.cancel();
      _activeDownloadTasks.remove(message.id);
    }
  }

  Future<void> purgeExpiredCache() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    final prefs = await SharedPreferences.getInstance();
    final index = _decodeCacheIndex(prefs.getString(_cacheIndexKey(uid)));
    final now = DateTime.now().millisecondsSinceEpoch;
    var changed = false;
    for (final entry in Map<String, _CacheRecord>.from(index).entries) {
      final expiresAt = entry.value.expiresAtMs;
      if (expiresAt == null || now < expiresAt) continue;
      await File(entry.value.path).delete().catchError((_) => File(''));
      index.remove(entry.key);
      changed = true;
    }
    if (changed) await _saveCacheIndex(prefs, uid, index);
  }

  void _schedulePump() {
    if (_pumpScheduled) return;
    _pumpScheduled = true;
    scheduleMicrotask(() {
      _pumpScheduled = false;
      unawaited(_pump());
    });
  }

  Future<void> _pump() async {
    await _ensureLoaded();
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    while (_activeRecordIds.length < SnackChatFilePolicy.maxConcurrentUploads) {
      _UploadRecord? next;
      for (final record in _records.values) {
        if (record.ownerUid == uid &&
            record.status == SnackChatFileTransferStatus.queued &&
            !_activeRecordIds.contains(record.messageId)) {
          next = record;
          break;
        }
      }
      if (next == null) return;
      _activeRecordIds.add(next.messageId);
      unawaited(_runRecord(next));
    }
  }

  Future<void> _runRecord(_UploadRecord record) async {
    try {
      if (!await File(record.localPath).exists()) {
        throw StateError('원본 파일에 접근할 수 없습니다.');
      }
      final prepared = await _prepare(record);
      record
        ..storagePath = prepared.storagePath
        ..retentionMode = prepared.retentionMode;
      if (prepared.committed) {
        await _finishCommitted(record);
        return;
      }
      await _persistQueue();

      if (record.uploadStarted) {
        try {
          record.status = SnackChatFileTransferStatus.finalizing;
          _emit(record);
          await _waitForFinalizeTurn(record);
          await _commit(record);
          await _finishCommitted(record);
          return;
        } on FirebaseFunctionsException catch (error) {
          if (error.code != 'not-found') rethrow;
        }
      }

      record
        ..status = SnackChatFileTransferStatus.uploading
        ..uploadStarted = true
        ..errorMessage = null;
      await _persistQueue();
      _emit(record);
      final upload = _storage.reference(record.storagePath!).putFile(
            File(record.localPath),
            SettableMetadata(
              contentType: record.mimeType,
              customMetadata: <String, String>{
                'senderId': record.ownerUid,
                'chatRoomId': record.roomId,
                'messageId': record.messageId,
                'uploadId': record.uploadId,
                'fileId': record.fileId,
                'fileExtension': record.fileExtension,
                'retentionMode': record.retentionMode,
              },
            ),
          );
      _activeUploadTasks[record.messageId] = upload;
      var lastPercent = -1;
      var lastEmittedAt = DateTime.fromMillisecondsSinceEpoch(0);
      final progress = upload.snapshotEvents.listen((snapshot) {
        final total = snapshot.totalBytes;
        if (total <= 0) return;
        final percent = ((snapshot.bytesTransferred / total) * 100).floor();
        final now = DateTime.now();
        if (percent < 100 &&
            percent - lastPercent < 3 &&
            now.difference(lastEmittedAt) < const Duration(milliseconds: 180)) {
          return;
        }
        lastPercent = percent;
        lastEmittedAt = now;
        record.progress = percent / 100;
        _emit(record);
      });
      try {
        await upload;
      } finally {
        await progress.cancel();
        _activeUploadTasks.remove(record.messageId);
      }
      record
        ..progress = 1
        ..status = SnackChatFileTransferStatus.finalizing;
      await _persistQueue();
      _emit(record);
      await _waitForFinalizeTurn(record);
      await _commit(record);
      await _finishCommitted(record);
    } catch (error, stackTrace) {
      Logger.error('Snack Chat 파일 전송 실패', error, stackTrace);
      if (_records.containsKey(record.messageId)) {
        record
          ..status = SnackChatFileTransferStatus.failed
          ..errorMessage = _friendlyTransferError(error);
        await _persistQueue();
        _emit(record);
      }
    } finally {
      _activeRecordIds.remove(record.messageId);
      _schedulePump();
    }
  }

  Future<_PreparedUpload> _prepare(_UploadRecord record) async {
    final result = await _functions
        .httpsCallable('prepareSnackChatFileUpload')
        .call<Map<String, dynamic>>(record.callableData)
        .timeout(const Duration(seconds: 20));
    final data = result.data;
    final storagePath = (data['storagePath'] ?? '').toString();
    final retentionMode = (data['retentionMode'] ?? '').toString();
    if (storagePath.isEmpty ||
        !<String>{'temporary24h', 'permanent'}.contains(retentionMode)) {
      throw StateError('서버 파일 경로를 확인할 수 없습니다.');
    }
    return _PreparedUpload(
      storagePath: storagePath,
      retentionMode: retentionMode,
      committed: data['committed'] == true,
    );
  }

  Future<void> _commit(_UploadRecord record) async {
    final result = await _functions
        .httpsCallable('commitSnackChatFileUpload')
        .call<Map<String, dynamic>>(record.callableData)
        .timeout(const Duration(seconds: 30));
    if (result.data['success'] != true) {
      throw StateError('파일 메시지를 전송하지 못했습니다.');
    }
  }

  Future<void> _waitForFinalizeTurn(_UploadRecord record) async {
    while (_records.containsKey(record.messageId) &&
        _auth.currentUser?.uid == record.ownerUid) {
      final earlierStillActive = _records.values.any((candidate) {
        if (candidate.messageId == record.messageId ||
            candidate.ownerUid != record.ownerUid ||
            candidate.roomId != record.roomId ||
            !candidate.createdAt.isBefore(record.createdAt)) {
          return false;
        }
        return candidate.status != SnackChatFileTransferStatus.failed &&
            candidate.status != SnackChatFileTransferStatus.canceled;
      });
      if (!earlierStillActive) return;
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
  }

  Future<void> _finishCommitted(_UploadRecord record) async {
    SnackChatMessage? server;
    for (var attempt = 0; attempt < 3 && server == null; attempt++) {
      try {
        server = await _chatService.getMessageFromServer(
          record.roomId,
          record.messageId,
        );
      } catch (_) {
        // The callable already committed atomically. A transient confirmation
        // read must not turn a successfully-sent file back into a failed one.
      }
      if (server == null) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    }
    final fallbackExpiry = record.retentionMode == 'temporary24h'
        ? DateTime.now().add(const Duration(hours: 24))
        : null;
    var message = server ??
        record.toMessage().copyWith(
              sendStatus: MessageSendStatus.sent,
              fileTransferStatus: SnackChatFileTransferStatus.ready,
              transferProgress: 1,
              expiresAt: fallbackExpiry,
              deleteAt: fallbackExpiry,
              clearErrorMessage: true,
            );
    message = await _promoteUploadToCache(record, message);
    _events.add(SnackChatFileTransferEvent(
      roomId: record.roomId,
      message: message,
    ));
    _records.remove(record.messageId);
    await _persistQueue();
  }

  void _emit(_UploadRecord record, {bool removed = false}) {
    if (_events.isClosed) return;
    _events.add(SnackChatFileTransferEvent(
      roomId: record.roomId,
      message: record.toMessage(),
      removed: removed,
    ));
  }

  Future<void> _ensureLoaded() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    if (_loadedUid == uid) return;
    final pending = _loading;
    if (pending != null) return pending;
    final operation = _load(uid);
    _loading = operation;
    try {
      await operation;
    } finally {
      if (identical(_loading, operation)) _loading = null;
    }
  }

  Future<void> _load(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_queueKeyPrefix::$uid');
    _records.clear();
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw);
        if (list is List) {
          for (final item in list) {
            final record = _UploadRecord.fromJson(item);
            if (record != null && record.ownerUid == uid) {
              _records[record.messageId] = record;
            }
          }
        }
      } catch (error) {
        Logger.warning('Snack Chat 파일 대기열 복원 실패: $error');
      }
    }
    _loadedUid = uid;
  }

  Future<void> _persistQueue() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null || _loadedUid != uid) return;
    final previous = _persisting;
    final operation = previous.catchError((_) {}).then((_) async {
      if (_auth.currentUser?.uid != uid || _loadedUid != uid) return;
      final prefs = await SharedPreferences.getInstance();
      final values = _records.values
          .where((record) => record.ownerUid == uid)
          .map((record) => record.toJson())
          .toList(growable: false);
      await prefs.setString('$_queueKeyPrefix::$uid', jsonEncode(values));
    });
    _persisting = operation;
    await operation;
  }

  void _onAuthChanged(User? user) {
    final nextUid = user?.uid;
    final previousUid = _lastAuthUid;
    _lastAuthUid = nextUid;
    if (previousUid != null && previousUid != nextUid) {
      for (final task in _activeUploadTasks.values) {
        unawaited(task.cancel());
      }
      for (final task in _activeDownloadTasks.values) {
        unawaited(task.cancel());
      }
      _activeUploadTasks.clear();
      _activeDownloadTasks.clear();
      _activeRecordIds.clear();
      unawaited(_clearPrivateLocalState(previousUid));
    }
    if (_loadedUid != nextUid) {
      _loadedUid = null;
      _records.clear();
    }
  }

  String _friendlyTransferError(Object error) {
    if (error is FirebaseFunctionsException) {
      if (error.code == 'permission-denied') return '파일 전송 권한이 없습니다.';
      if (error.code == 'unauthenticated') return '로그인 상태를 확인해 주세요.';
    }
    if (error is FirebaseException && error.code == 'canceled') {
      return '파일 전송이 취소되었습니다.';
    }
    return '전송하지 못했습니다. 눌러서 다시 시도해 주세요.';
  }

  String _cacheIndexKey(String uid) => '$_cacheIndexKeyPrefix::$uid';

  String _cacheRecordKey(SnackChatMessage message) =>
      message.storagePath ?? message.id;

  Future<Directory> _cacheDirectory(String uid) async {
    final support = await getApplicationSupportDirectory();
    return Directory(p.join(support.path, 'private_snack_chat_files', uid));
  }

  Future<Directory> _stagingDirectory(String uid) async {
    final support = await getApplicationSupportDirectory();
    return Directory(p.join(support.path, 'private_snack_chat_uploads', uid));
  }

  Future<File> _stageSelectedFile({
    required String uid,
    required String messageId,
    required SnackChatSelectedFile selected,
  }) async {
    final directory = await _stagingDirectory(uid);
    await directory.create(recursive: true);
    final destination = File(
      p.join(directory.path, '$messageId.${selected.fileExtension}'),
    );
    if (await destination.exists()) await destination.delete();
    try {
      await File(selected.path).openRead().pipe(destination.openWrite());
      if (await destination.length() != selected.fileSize) {
        throw StateError('선택한 파일을 전송 대기열에 보관하지 못했습니다.');
      }
      return destination;
    } catch (_) {
      await destination.delete().catchError((_) => destination);
      rethrow;
    }
  }

  Future<SnackChatMessage> _promoteUploadToCache(
    _UploadRecord record,
    SnackChatMessage message,
  ) async {
    final source = File(record.localPath);
    if (!await source.exists()) return message;
    final destination = await _cacheDestination(record.ownerUid, message);
    await destination.parent.create(recursive: true);
    try {
      if (source.path != destination.path) {
        if (await destination.exists()) await destination.delete();
        try {
          await source.rename(destination.path);
        } on FileSystemException {
          await source.openRead().pipe(destination.openWrite());
          await source.delete().catchError((_) => source);
        }
      }
      await _touchCache(record.ownerUid, message, destination);
      await _trimCache(record.ownerUid);
      return message.copyWith(localFilePath: destination.path);
    } catch (error) {
      if (await destination.exists()) {
        await destination.delete().catchError((_) => destination);
      }
      Logger.warning('Snack Chat 전송 파일 캐시 승격 실패: $error');
      return message.copyWith(localFilePath: source.path);
    }
  }

  Future<File> _cacheDestination(
    String uid,
    SnackChatMessage message,
  ) async {
    final directory = await _cacheDirectory(uid);
    final extension =
        message.fileExtension?.replaceAll(RegExp(r'[^a-z0-9]'), '') ?? '';
    final fileName = extension.isEmpty
        ? '${message.id}_${message.uploadId ?? 'file'}'
        : '${message.id}_${message.uploadId ?? 'file'}.$extension';
    return File(p.join(directory.path, fileName));
  }

  Future<File?> _cachedFile(String uid, SnackChatMessage message) async {
    final prefs = await SharedPreferences.getInstance();
    final index = _decodeCacheIndex(prefs.getString(_cacheIndexKey(uid)));
    final record = index[_cacheRecordKey(message)];
    if (record == null) return null;
    if (record.expiresAtMs != null &&
        DateTime.now().millisecondsSinceEpoch >= record.expiresAtMs!) {
      await File(record.path).delete().catchError((_) => File(''));
      index.remove(_cacheRecordKey(message));
      await _saveCacheIndex(prefs, uid, index);
      return null;
    }
    final file = File(record.path);
    if (!await file.exists()) {
      index.remove(_cacheRecordKey(message));
      await _saveCacheIndex(prefs, uid, index);
      return null;
    }
    return file;
  }

  Future<void> _touchCache(
    String uid,
    SnackChatMessage message,
    File file,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final index = _decodeCacheIndex(prefs.getString(_cacheIndexKey(uid)));
    index[_cacheRecordKey(message)] = _CacheRecord(
      path: file.path,
      size: await file.length(),
      lastAccessMs: DateTime.now().millisecondsSinceEpoch,
      expiresAtMs: message.expiresAt?.millisecondsSinceEpoch,
    );
    await _saveCacheIndex(prefs, uid, index);
  }

  Future<void> _removeCachedMessageFile(
    String uid,
    SnackChatMessage message,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final index = _decodeCacheIndex(prefs.getString(_cacheIndexKey(uid)));
    final removed = index.remove(_cacheRecordKey(message));
    if (removed == null) return;
    await File(removed.path).delete().catchError((_) => File(''));
    await _saveCacheIndex(prefs, uid, index);
  }

  Future<void> _trimCache(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final index = _decodeCacheIndex(prefs.getString(_cacheIndexKey(uid)));
    final ordered = index.entries.toList()
      ..sort((a, b) => a.value.lastAccessMs.compareTo(b.value.lastAccessMs));
    var total = ordered.fold<int>(0, (sum, entry) => sum + entry.value.size);
    for (final entry in ordered) {
      if (total <= SnackChatFilePolicy.maxLocalCacheBytes) break;
      await File(entry.value.path).delete().catchError((_) => File(''));
      total -= entry.value.size;
      index.remove(entry.key);
    }
    await _saveCacheIndex(prefs, uid, index);
  }

  Map<String, _CacheRecord> _decodeCacheIndex(String? raw) {
    if (raw == null || raw.isEmpty) return <String, _CacheRecord>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, _CacheRecord>{};
      final result = <String, _CacheRecord>{};
      for (final entry in decoded.entries) {
        final value = _CacheRecord.fromJson(entry.value);
        if (value != null) result[entry.key.toString()] = value;
      }
      return result;
    } catch (_) {
      return <String, _CacheRecord>{};
    }
  }

  Future<void> _saveCacheIndex(
    SharedPreferences prefs,
    String uid,
    Map<String, _CacheRecord> index,
  ) =>
      prefs.setString(
        _cacheIndexKey(uid),
        jsonEncode(index.map((key, value) => MapEntry(key, value.toJson()))),
      );

  Future<void> _clearPrivateLocalState(String uid) async {
    final directory = await _cacheDirectory(uid);
    if (await directory.exists()) await directory.delete(recursive: true);
    final staging = await _stagingDirectory(uid);
    if (await staging.exists()) await staging.delete(recursive: true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cacheIndexKey(uid));
    await prefs.remove('$_queueKeyPrefix::$uid');
    await _localChatCache.clearPrivateFileStateForAccount(uid);
  }
}

class _PreparedUpload {
  const _PreparedUpload({
    required this.storagePath,
    required this.retentionMode,
    required this.committed,
  });

  final String storagePath;
  final String retentionMode;
  final bool committed;
}

class _UploadRecord {
  _UploadRecord({
    required this.ownerUid,
    required this.roomId,
    required this.messageId,
    required this.uploadId,
    required this.fileId,
    required this.originalFileName,
    required this.fileExtension,
    required this.mimeType,
    required this.fileSize,
    required this.localPath,
    required this.retentionMode,
    required this.createdAt,
    this.replyPreview,
    this.storagePath,
    this.status = SnackChatFileTransferStatus.queued,
    this.progress = 0,
    this.uploadStarted = false,
    this.errorMessage,
  });

  final String ownerUid;
  final String roomId;
  final String messageId;
  final String uploadId;
  final String fileId;
  final String originalFileName;
  final String fileExtension;
  final String mimeType;
  final int fileSize;
  final String localPath;
  String retentionMode;
  final DateTime createdAt;
  final ReplyMessagePreview? replyPreview;
  String? storagePath;
  SnackChatFileTransferStatus status;
  double progress;
  bool uploadStarted;
  String? errorMessage;

  Map<String, dynamic> get callableData => <String, dynamic>{
        'snackChatId': roomId,
        'messageId': messageId,
        'uploadId': uploadId,
        'fileId': fileId,
        'originalFileName': originalFileName,
        'fileExtension': fileExtension,
        'mimeType': mimeType,
        'fileSize': fileSize,
        if (replyPreview != null) 'replyToMessageId': replyPreview!.messageId,
      };

  SnackChatMessage toMessage() => SnackChatMessage(
        id: messageId,
        senderId: ownerUid,
        type: SnackChatMessageType.file,
        text: '',
        originalFileName: originalFileName,
        fileExtension: fileExtension,
        mimeType: mimeType,
        fileSize: fileSize,
        storagePath: storagePath,
        retentionMode: retentionMode,
        uploadId: uploadId,
        createdAt: createdAt,
        replyToMessageId: replyPreview?.messageId,
        replyPreview: replyPreview,
        readBy: <String>[ownerUid],
        sendStatus: status == SnackChatFileTransferStatus.failed ||
                status == SnackChatFileTransferStatus.canceled
            ? MessageSendStatus.failed
            : status == SnackChatFileTransferStatus.ready
                ? MessageSendStatus.sent
                : MessageSendStatus.sending,
        localFilePath: localPath,
        fileTransferStatus: status,
        transferProgress: progress,
        errorMessage: errorMessage,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'ownerUid': ownerUid,
        'roomId': roomId,
        'messageId': messageId,
        'uploadId': uploadId,
        'fileId': fileId,
        'originalFileName': originalFileName,
        'fileExtension': fileExtension,
        'mimeType': mimeType,
        'fileSize': fileSize,
        'localPath': localPath,
        'retentionMode': retentionMode,
        'createdAtUs': createdAt.microsecondsSinceEpoch,
        if (replyPreview != null) 'replyPreview': _replyJson(replyPreview!),
        if (storagePath != null) 'storagePath': storagePath,
        'status': status.name,
        'progress': progress,
        'uploadStarted': uploadStarted,
        if (errorMessage != null) 'errorMessage': errorMessage,
      };

  static Map<String, dynamic> _replyJson(ReplyMessagePreview reply) {
    final map = Map<String, dynamic>.from(reply.toMap());
    map.remove('fileExpiresAt');
    if (reply.fileExpiresAt != null) {
      map['fileExpiresAtMs'] = reply.fileExpiresAt!.millisecondsSinceEpoch;
    }
    return map;
  }

  static _UploadRecord? fromJson(Object? raw) {
    try {
      if (raw is! Map) return null;
      final map = Map<String, dynamic>.from(raw);
      final statusName = (map['status'] ?? '').toString();
      var status = SnackChatFileTransferStatus.queued;
      for (final candidate in SnackChatFileTransferStatus.values) {
        if (candidate.name == statusName) status = candidate;
      }
      final replyMap = map['replyPreview'] is Map
          ? Map<String, dynamic>.from(map['replyPreview'] as Map)
          : null;
      if (replyMap?['fileExpiresAtMs'] is num) {
        replyMap!['fileExpiresAt'] = DateTime.fromMillisecondsSinceEpoch(
          (replyMap.remove('fileExpiresAtMs') as num).toInt(),
        );
      }
      return _UploadRecord(
        ownerUid: map['ownerUid'].toString(),
        roomId: map['roomId'].toString(),
        messageId: map['messageId'].toString(),
        uploadId: map['uploadId'].toString(),
        fileId: map['fileId'].toString(),
        originalFileName: map['originalFileName'].toString(),
        fileExtension: map['fileExtension'].toString(),
        mimeType: map['mimeType'].toString(),
        fileSize: (map['fileSize'] as num).toInt(),
        localPath: map['localPath'].toString(),
        retentionMode: map['retentionMode'].toString(),
        createdAt: DateTime.fromMicrosecondsSinceEpoch(
          (map['createdAtUs'] as num).toInt(),
        ),
        replyPreview:
            replyMap == null ? null : ReplyMessagePreview.fromMap(replyMap),
        storagePath: (map['storagePath'] ?? '').toString().isEmpty
            ? null
            : map['storagePath'].toString(),
        status: status,
        progress:
            map['progress'] is num ? (map['progress'] as num).toDouble() : 0,
        uploadStarted: map['uploadStarted'] == true,
        errorMessage: (map['errorMessage'] ?? '').toString().isEmpty
            ? null
            : map['errorMessage'].toString(),
      );
    } catch (_) {
      return null;
    }
  }
}

class _CacheRecord {
  const _CacheRecord({
    required this.path,
    required this.size,
    required this.lastAccessMs,
    required this.expiresAtMs,
  });

  final String path;
  final int size;
  final int lastAccessMs;
  final int? expiresAtMs;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'path': path,
        'size': size,
        'lastAccessMs': lastAccessMs,
        if (expiresAtMs != null) 'expiresAtMs': expiresAtMs,
      };

  static _CacheRecord? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    if (map['size'] is! num || map['lastAccessMs'] is! num) return null;
    return _CacheRecord(
      path: (map['path'] ?? '').toString(),
      size: (map['size'] as num).toInt(),
      lastAccessMs: (map['lastAccessMs'] as num).toInt(),
      expiresAtMs: map['expiresAtMs'] is num
          ? (map['expiresAtMs'] as num).toInt()
          : null,
    );
  }
}
