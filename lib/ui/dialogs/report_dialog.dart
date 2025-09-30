// lib/ui/dialogs/report_dialog.dart
// 신고하기 다이얼로그

import 'package:flutter/material.dart';
import '../../models/report.dart';
import '../../services/report_service.dart';

class ReportDialog extends StatefulWidget {
  final String reportedUserId;
  final String targetType;
  final String targetId;
  final String? targetTitle; // 신고 대상의 제목 (선택사항)

  const ReportDialog({
    Key? key,
    required this.reportedUserId,
    required this.targetType,
    required this.targetId,
    this.targetTitle,
  }) : super(key: key);

  @override
  State<ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<ReportDialog> {
  String? selectedReason;
  final TextEditingController descriptionController = TextEditingController();
  bool isSubmitting = false;

  @override
  void dispose() {
    descriptionController.dispose();
    super.dispose();
  }

  String get targetTypeKorean {
    switch (widget.targetType) {
      case 'post':
        return '게시물';
      case 'comment':
        return '댓글';
      case 'meetup':
        return '모임';
      case 'user':
        return '사용자';
      default:
        return '콘텐츠';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.report_outlined, color: Colors.red[600]),
          const SizedBox(width: 8),
          Text(
            '$targetTypeKorean 신고하기',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.targetTitle != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: Colors.grey[600]),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.targetTitle!,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[700],
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            
            const Text(
              '신고 사유를 선택해주세요',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 12),
            
            // 신고 사유 선택
            ...ReportReasons.allReasons.map((reason) => 
              RadioListTile<String>(
                title: Text(reason),
                value: reason,
                groupValue: selectedReason,
                onChanged: (value) {
                  setState(() {
                    selectedReason = value;
                  });
                },
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
            ),
            
            const SizedBox(height: 16),
            
            // 상세 설명 (선택사항)
            const Text(
              '상세 설명 (선택사항)',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: descriptionController,
              maxLines: 3,
              maxLength: 500,
              decoration: const InputDecoration(
                hintText: '신고 사유에 대한 자세한 설명을 입력해주세요',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.all(12),
              ),
            ),
            
            const SizedBox(height: 8),
            Text(
              '신고는 검토 후 처리되며, 허위 신고 시 제재를 받을 수 있습니다.',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: isSubmitting ? null : () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        ElevatedButton(
          onPressed: selectedReason == null || isSubmitting 
              ? null 
              : _submitReport,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red[600],
            foregroundColor: Colors.white,
          ),
          child: isSubmitting 
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('신고하기'),
        ),
      ],
    );
  }

  Future<void> _submitReport() async {
    if (selectedReason == null) return;
    
    setState(() {
      isSubmitting = true;
    });

    try {
      final success = await ReportService.reportContent(
        reportedUserId: widget.reportedUserId,
        targetType: widget.targetType,
        targetId: widget.targetId,
        reason: selectedReason!,
        description: descriptionController.text.trim().isEmpty 
            ? null 
            : descriptionController.text.trim(),
        targetTitle: widget.targetTitle,
      );

      if (success) {
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('신고가 접수되었습니다. 검토 후 처리하겠습니다.'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('신고 접수에 실패했습니다. 다시 시도해주세요.'),
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
          isSubmitting = false;
        });
      }
    }
  }
}

// 신고하기 다이얼로그 표시 함수
Future<void> showReportDialog(
  BuildContext context, {
  required String reportedUserId,
  required String targetType,
  required String targetId,
  String? targetTitle,
}) {
  return showDialog(
    context: context,
    builder: (context) => ReportDialog(
      reportedUserId: reportedUserId,
      targetType: targetType,
      targetId: targetId,
      targetTitle: targetTitle,
    ),
  );
}

