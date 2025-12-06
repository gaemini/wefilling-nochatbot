// lib/ui/dialogs/block_dialog.dart
// 사용자 차단/차단해제 다이얼로그

import 'package:flutter/material.dart';
import '../../services/report_service.dart';
import '../../services/content_filter_service.dart';
import '../../l10n/app_localizations.dart';

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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: Colors.white,
      elevation: 8,
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      actionsPadding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
      title: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: const Color(0xFFEF4444).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.block,
              color: Color(0xFFEF4444),
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            AppLocalizations.of(context)!.blockUserTitle,
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF111827),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppLocalizations.of(context)!.blockUserMessage(widget.userName),
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: Color(0xFF374151),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFDE68A)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: Colors.amber[800]),
                    const SizedBox(width: 8),
                    Text(
                      AppLocalizations.of(context)!.blockUserWarningTitle,
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF92400E),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  '• ${AppLocalizations.of(context)!.blockUserWarning1}\n'
                  '• ${AppLocalizations.of(context)!.blockUserWarning2}\n'
                  '• ${AppLocalizations.of(context)!.blockUserWarning3}\n'
                  '• ${AppLocalizations.of(context)!.blockUserWarning4}',
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF78350F),
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: isBlocking ? null : () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.grey.shade300, width: 1),
                  ),
                  backgroundColor: Colors.white,
                ),
                child: Text(
                  AppLocalizations.of(context)!.cancel,
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: isBlocking ? null : _blockUser,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  backgroundColor: const Color(0xFFEF4444),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  disabledBackgroundColor: const Color(0xFFE5E7EB),
                ),
                child: isBlocking 
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : Text(
                        AppLocalizations.of(context)!.blockUserButton,
                        style: const TextStyle(
                          fontFamily: 'Pretendard',
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
          ],
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: Colors.white,
      elevation: 8,
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      actionsPadding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
      title: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.person_add_outlined,
              color: Color(0xFF10B981),
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            AppLocalizations.of(context)!.unblockUserTitle,
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF111827),
            ),
          ),
        ],
      ),
      content: Text(
        AppLocalizations.of(context)!.unblockUserMessage(widget.userName),
        style: const TextStyle(
          fontFamily: 'Pretendard',
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: Color(0xFF374151),
          height: 1.5,
        ),
      ),
      actions: [
        Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: isUnblocking ? null : () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.grey.shade300, width: 1),
                  ),
                  backgroundColor: Colors.white,
                ),
                child: Text(
                  AppLocalizations.of(context)!.cancel,
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: isUnblocking ? null : _unblockUser,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  disabledBackgroundColor: const Color(0xFFE5E7EB),
                ),
                child: isUnblocking 
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : Text(
                        AppLocalizations.of(context)!.unblockUserButton,
                        style: const TextStyle(
                          fontFamily: 'Pretendard',
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
          ],
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






