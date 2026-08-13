import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/config/snack_chat_file_policy.dart';

void main() {
  test('PDF signature inspection waits for each read before closing', () async {
    final directory = await Directory.systemTemp.createTemp(
      'snack-chat-file-policy-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/lecture.pdf');
    await file.writeAsBytes(<int>[
      ...'%PDF-1.7\n'.codeUnits,
      ...List<int>.filled(128, 0x20),
    ], flush: true);

    final files = await Future.wait(
      List<Future<SnackChatSelectedFile>>.generate(
        12,
        (_) => SnackChatFilePolicy.validatePath(
          file.path,
          displayName: 'lecture.pdf',
        ),
      ),
    );

    expect(files, hasLength(12));
    expect(files.every((selected) => selected.fileExtension == 'pdf'), isTrue);
  });
}
