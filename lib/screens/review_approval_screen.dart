// lib/screens/review_approval_screen.dart
// 후기 수락/거절 화면
// 모임장이 작성한 후기를 확인하고 수락 또는 거절

import 'package:flutter/material.dart';
import '../services/meetup_service.dart';
import '../l10n/app_localizations.dart';

class ReviewApprovalScreen extends StatefulWidget {
  final String requestId;
  final String reviewId;
  final String meetupTitle;
  final String imageUrl;
  final String content;
  final String authorName;

  const ReviewApprovalScreen({
    Key? key,
    required this.requestId,
    required this.reviewId,
    required this.meetupTitle,
    required this.imageUrl,
    required this.content,
    required this.authorName,
  }) : super(key: key);

  @override
  State<ReviewApprovalScreen> createState() => _ReviewApprovalScreenState();
}

class _ReviewApprovalScreenState extends State<ReviewApprovalScreen> {
  final MeetupService _meetupService = MeetupService();
  bool _isProcessing = false;
  bool _isLoading = true;
  String? _currentStatus; // 'pending', 'accepted', 'rejected'

  @override
  void initState() {
    super.initState();
    _checkRequestStatus();
  }

  /// 요청의 현재 상태 확인
  Future<void> _checkRequestStatus() async {
    try {
      final requestDoc = await _meetupService.getReviewRequestStatus(widget.requestId);
      
      if (mounted) {
        setState(() {
          _currentStatus = requestDoc?['status'] as String?;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('❌ 요청 상태 확인 오류: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleResponse(bool accept) async {
    setState(() {
      _isProcessing = true;
    });

    try {
      final success = await _meetupService.respondToReviewRequest(
        requestId: widget.requestId,
        accept: accept,
      );

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(accept
                  ? (AppLocalizations.of(context)!.reviewAccepted ?? "") : AppLocalizations.of(context)!.reviewRejected),
            ),
          );
          Navigator.of(context).pop(true);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppLocalizations.of(context)!.reviewProcessError ?? "")),
          );
        }
      }
    } catch (e) {
      print('❌ 후기 수락/거절 처리 오류: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.error ?? "")),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    
    // 로딩 중
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: Text(l10n?.reviewApprovalRequest ?? ""),
          elevation: 0,
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    // 이미 응답한 요청
    final alreadyResponded = _currentStatus != null && _currentStatus != 'pending';
    
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n?.reviewApprovalRequest ?? ""),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 모임 정보
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.event, color: Colors.blue[700]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.meetupTitle,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue[900],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          AppLocalizations.of(context)!.reviewByAuthor(widget.authorName),
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.blue[700],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // 후기 사진
            Container(
              height: 300,
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  widget.imageUrl,
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Center(
                      child: CircularProgressIndicator(
                        value: loadingProgress.expectedTotalBytes != null
                            ? loadingProgress.cumulativeBytesLoaded /
                                loadingProgress.expectedTotalBytes!
                            : null,
                      ),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      color: Colors.grey[200],
                      child: const Center(
                        child: Icon(Icons.error_outline, size: 48, color: Colors.grey),
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 24),

            // 후기 내용
            Text(
              AppLocalizations.of(context)!.reviewContent,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Text(
                widget.content,
                style: const TextStyle(
                  fontSize: 15,
                  height: 1.5,
                ),
              ),
            ),
            const SizedBox(height: 24),

            // 안내 문구
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber[200]!),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, color: Colors.amber[800], size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      AppLocalizations.of(context)!.reviewApprovalInfo,
                      style: TextStyle(
                        color: Colors.amber[900],
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // 버튼들 또는 상태 메시지
            if (alreadyResponded)
              // 이미 응답한 경우 상태 표시
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _currentStatus == 'accepted' ? Colors.green[50] : Colors.red[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _currentStatus == 'accepted' ? Colors.green[200]! : Colors.red[200]!,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _currentStatus == 'accepted' ? Icons.check_circle : Icons.cancel,
                      color: _currentStatus == 'accepted' ? Colors.green[700] : Colors.red[700],
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _currentStatus == 'accepted'
                            ? l10n?.reviewAlreadyAccepted ?? ""
                            : l10n?.reviewAlreadyRejected ?? "",
                        style: TextStyle(
                          color: _currentStatus == 'accepted' ? Colors.green[900] : Colors.red[900],
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              // 아직 응답하지 않은 경우 버튼 표시
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 50,
                      child: OutlinedButton(
                        onPressed: _isProcessing ? null : () => _handleResponse(false),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _isProcessing
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.red),
                                ),
                              )
                            : Text(
                                l10n?.reject ?? "",
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _isProcessing ? null : () => _handleResponse(true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _isProcessing
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : Text(
                                l10n?.accept ?? "",
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

