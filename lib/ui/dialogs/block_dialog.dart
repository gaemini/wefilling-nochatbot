// lib/ui/dialogs/block_dialog.dart
// 사용자 차단/차단해제 다이얼로그

import 'package:flutter/material.dart';
import '../../services/report_service.dart';
import '../../services/content_filter_service.dart';

// 사용자 차단 확인 다이얼로그
class BlockUserDialog extends StatefulWidget {
  final String userId;
  final String userName;

  const BlockUserDialog({
    Key? key,
    required this.userId,
    required this.userName,
  }) : super(key: key);

  @override
  State<BlockUserDialog> createState() => _BlockUserDialogState();
}

class _BlockUserDialogState extends State<BlockUserDialog> {
  bool isBlocking = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.block, color: Colors.red[600]),
          const SizedBox(width: 8),
          const Text(
            '사용자 차단',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${widget.userName}님을 차단하시겠습니까?',
            style: const TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange[200]!),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: Colors.orange[700]),
                    const SizedBox(width: 8),
                    const Text(
                      '차단 시 다음과 같이 됩니다:',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  '• 해당 사용자의 게시물과 댓글이 보이지 않습니다\n'
                  '• 해당 사용자가 만든 모임이 보이지 않습니다\n'
                  '• 상호 간에 메시지를 주고받을 수 없습니다\n'
                  '• 언제든지 차단을 해제할 수 있습니다',
                  style: TextStyle(fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: isBlocking ? null : () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        ElevatedButton(
          onPressed: isBlocking ? null : _blockUser,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red[600],
            foregroundColor: Colors.white,
          ),
          child: isBlocking 
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('차단하기'),
        ),
      ],
    );
  }

  Future<void> _blockUser() async {
    setState(() {
      isBlocking = true;
    });

    try {
      final success = await ReportService.blockUser(widget.userId);

      if (success) {
        // 캐시 즉시 갱신
        ContentFilterService.refreshCache();
        
        if (mounted) {
          Navigator.pop(context, {
            'success': true,
            'blockedUserId': widget.userId,
          });
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white),
                  SizedBox(width: 8),
                  Text('${widget.userName}님을 차단했습니다.'),
                ],
              ),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 3),
              action: SnackBarAction(
                label: '실행 취소',
                textColor: Colors.white,
                onPressed: () => _undoBlock(),
              ),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('차단에 실패했습니다. 다시 시도해주세요.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('오류가 발생했습니다: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          isBlocking = false;
        });
      }
    }
  }

  Future<void> _undoBlock() async {
    final success = await ReportService.unblockUser(widget.userId);
    if (success) {
      ContentFilterService.refreshCache();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('차단을 취소했습니다.'),
            backgroundColor: Colors.blue,
          ),
        );
      }
    }
  }
}

// 사용자 차단 해제 확인 다이얼로그
class UnblockUserDialog extends StatefulWidget {
  final String userId;
  final String userName;

  const UnblockUserDialog({
    Key? key,
    required this.userId,
    required this.userName,
  }) : super(key: key);

  @override
  State<UnblockUserDialog> createState() => _UnblockUserDialogState();
}

class _UnblockUserDialogState extends State<UnblockUserDialog> {
  bool isUnblocking = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.person_add_outlined, color: Colors.green[600]),
          const SizedBox(width: 8),
          const Text(
            '차단 해제',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      content: Text(
        '${widget.userName}님의 차단을 해제하시겠습니까?\n\n'
        '차단 해제 후 해당 사용자의 콘텐츠를 다시 볼 수 있습니다.',
        style: const TextStyle(fontSize: 16),
      ),
      actions: [
        TextButton(
          onPressed: isUnblocking ? null : () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        ElevatedButton(
          onPressed: isUnblocking ? null : _unblockUser,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green[600],
            foregroundColor: Colors.white,
          ),
          child: isUnblocking 
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('차단 해제'),
        ),
      ],
    );
  }

  Future<void> _unblockUser() async {
    setState(() {
      isUnblocking = true;
    });

    try {
      final success = await ReportService.unblockUser(widget.userId);

      if (success) {
        if (mounted) {
          Navigator.pop(context, true); // 성공 시 true 반환
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${widget.userName}님의 차단을 해제했습니다.'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('차단 해제에 실패했습니다. 다시 시도해주세요.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('오류가 발생했습니다: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          isUnblocking = false;
        });
      }
    }
  }
}

// 차단하기 다이얼로그 표시 함수
Future<Map<String, dynamic>?> showBlockUserDialog(
  BuildContext context, {
  required String userId,
  required String userName,
}) {
  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (context) => BlockUserDialog(
      userId: userId,
      userName: userName,
    ),
  );
}

// 차단 해제 다이얼로그 표시 함수
Future<bool?> showUnblockUserDialog(
  BuildContext context, {
  required String userId,
  required String userName,
}) {
  return showDialog<bool>(
    context: context,
    builder: (context) => UnblockUserDialog(
      userId: userId,
      userName: userName,
    ),
  );
}






