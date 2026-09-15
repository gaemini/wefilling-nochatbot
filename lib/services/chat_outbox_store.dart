import 'dart:io';

import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';

import '../utils/chat_work_queue.dart';

/// Durable packets are never keyed by the *current* Firebase account after an
/// await. The caller supplies the captured owner and revalidates it at send.
class ChatOutboxStore {
  static final ChatOutboxStore instance = ChatOutboxStore._();
  ChatOutboxStore._();
  Future<Box<dynamic>>? _opening;
  final ChatWorkQueue _writes = ChatWorkQueue();
  Future<Box<dynamic>> _box() => _opening ??=
          Hive.openBox<dynamic>('chat_outbox_v1').catchError((Object e) {
        _opening = null;
        throw e;
      });

  String _key(String owner, String room) => 'dm::$owner::$room';

  Future<List<Map<String, dynamic>>> load(String owner, String room) async {
    final box = await _box();
    final raw = box.get(_key(owner, room));
    if (raw is! Map) return [];
    return raw.values
        .whereType<Map>()
        .map((value) => Map<String, dynamic>.from(value))
        .toList();
  }

  Future<void> put(
          String owner, String room, String id, Map<String, dynamic> packet) =>
      _change(owner, room, (packets) {
        packets[id] = packet;
      });

  Future<void> remove(String owner, String room, String id) =>
      _change(owner, room, (packets) => packets.remove(id));

  Future<void> _change(
      String owner, String room, void Function(Map<String, dynamic>) change) {
    final key = _key(owner, room);
    return _writes.run(key, () async {
      final box = await _box();
      final raw = box.get(key);
      final packets =
          raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
      change(packets);
      await box.put(key, packets);
    });
  }

  /// Image-picker files can disappear on restart. Keep an app-private copy;
  /// remote images are never deleted in response to an uncertain send result.
  Future<String> retainImage(String owner, String id, String path) async {
    final root = await getApplicationSupportDirectory();
    final directory =
        Directory('${root.path}/chat_outbox/${Uri.encodeComponent(owner)}');
    await directory.create(recursive: true);
    final target = '${directory.path}/${Uri.encodeComponent(id)}.jpg';
    if (path != target) await File(path).copy(target);
    return target;
  }

  /// Document-picker URIs can also become unavailable after process death.
  /// Preserve the validated bytes under the account-scoped outbox so the same
  /// message ID can resume without asking the user to select the file again.
  Future<String> retainFile(
    String owner,
    String id,
    String path,
    String extension,
  ) async {
    final root = await getApplicationSupportDirectory();
    final directory =
        Directory('${root.path}/chat_outbox/${Uri.encodeComponent(owner)}');
    await directory.create(recursive: true);
    final normalizedExtension =
        extension.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final safeExtension = normalizedExtension.length > 12
        ? normalizedExtension.substring(0, 12)
        : normalizedExtension;
    final suffix = safeExtension.isEmpty ? 'bin' : safeExtension;
    final target = '${directory.path}/${Uri.encodeComponent(id)}.$suffix';
    if (path != target) await File(path).copy(target);
    return target;
  }
}
