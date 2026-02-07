// lib/screens/meetup_participants_screen.dart
// 모임 참여자 관리 화면

import 'package:flutter/material.dart';
import '../models/meetup.dart';
import '../models/meetup_participant.dart';
import '../services/meetup_service.dart';
import '../l10n/app_localizations.dart';
import '../ui/snackbar/app_snackbar.dart';

class MeetupParticipantsScreen extends StatefulWidget {
  final Meetup meetup;

  const MeetupParticipantsScreen({
    Key? key,
    required this.meetup,
  }) : super(key: key);

  @override
  State<MeetupParticipantsScreen> createState() => _MeetupParticipantsScreenState();
}

class _MeetupParticipantsScreenState extends State<MeetupParticipantsScreen>
    with SingleTickerProviderStateMixin {
  final MeetupService _meetupService = MeetupService();
  late TabController _tabController;
  
  List<MeetupParticipant> _pendingParticipants = [];
  List<MeetupParticipant> _approvedParticipants = [];
  List<MeetupParticipant> _rejectedParticipants = [];
  
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadParticipants();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadParticipants() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final pending = await _meetupService.getMeetupParticipantsByStatus(
        widget.meetup.id, 
        ParticipantStatus.pending,
      );
      final approved = await _meetupService.getMeetupParticipantsByStatus(
        widget.meetup.id, 
        ParticipantStatus.approved,
      );
      final rejected = await _meetupService.getMeetupParticipantsByStatus(
        widget.meetup.id, 
        ParticipantStatus.rejected,
      );

      setState(() {
        _pendingParticipants = pending;
        _approvedParticipants = approved;
        _rejectedParticipants = rejected;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        final isKo = Localizations.localeOf(context).languageCode == 'ko';
        final l10n = AppLocalizations.of(context)!;
        AppSnackBar.show(
          context,
          message: isKo
              ? '참여자 목록을 불러오는데 실패했습니다: $e'
              : '${l10n.error}: Failed to load participants: $e',
          type: AppSnackBarType.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              Localizations.localeOf(context).languageCode == 'ko' ? '참여자 관리' : 'Participants',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            Text(
              widget.meetup.title,
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        backgroundColor: Theme.of(context).colorScheme.surface,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(Localizations.localeOf(context).languageCode == 'ko' ? '대기중' : 'Pending'),
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.orange,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${_pendingParticipants.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(Localizations.localeOf(context).languageCode == 'ko' ? '승인됨' : 'Approved'),
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.green,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${_approvedParticipants.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(Localizations.localeOf(context).languageCode == 'ko' ? '거절됨' : 'Rejected'),
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${_rejectedParticipants.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildParticipantList(_pendingParticipants, ParticipantStatus.pending),
                _buildParticipantList(_approvedParticipants, ParticipantStatus.approved),
                _buildParticipantList(_rejectedParticipants, ParticipantStatus.rejected),
              ],
            ),
    );
  }

  Widget _buildParticipantList(List<MeetupParticipant> participants, String status) {
    if (participants.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _getStatusIcon(status),
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              _getEmptyMessage(status),
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadParticipants,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: participants.length,
        itemBuilder: (context, index) {
          final participant = participants[index];
          return _buildParticipantCard(participant, status);
        },
      ),
    );
  }

  Widget _buildParticipantCard(MeetupParticipant participant, String status) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 사용자 정보
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.grey[300],
                  ),
                  child: participant.userProfileImage != null
                      ? ClipOval(
                          child: Image.network(
                            participant.userProfileImage!,
                            width: 48,
                            height: 48,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Icon(
                              Icons.person,
                              size: 24,
                              color: Colors.grey[600],
                            ),
                          ),
                        )
                      : Icon(
                          Icons.person,
                          size: 24,
                          color: Colors.grey[600],
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        participant.userName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        participant.userEmail,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: participant.getStatusColor().withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    participant.getStatusTextLocalized(Localizations.localeOf(context).languageCode),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: participant.getStatusColor(),
                    ),
                  ),
                ),
              ],
            ),

            // 참여 신청 메시지
            if (participant.message != null && participant.message!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.message_outlined, size: 16, color: Colors.grey[600]),
                        const SizedBox(width: 4),
                        Text(
                          '신청 메시지',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      participant.message!,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ],
                ),
              ),
            ],

            // 신청 일시
            const SizedBox(height: 8),
            Text(
              '신청일시: ${participant.getFormattedJoinedAt()}',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),

            // 액션 버튼들
            if (status == ParticipantStatus.pending) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _approveParticipant(participant),
                      icon: const Icon(Icons.check, size: 16),
                      label: const Text('승인'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _rejectParticipant(participant),
                      icon: const Icon(Icons.close, size: 16),
                      label: const Text('거절'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ] else if (status == ParticipantStatus.approved) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _removeParticipant(participant),
                  icon: const Icon(Icons.person_remove, size: 16),
                  label: const Text('참여 취소'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red[100],
                    foregroundColor: Colors.red[700],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _approveParticipant(MeetupParticipant participant) async {
    final success = await _meetupService.approveParticipant(participant.id);
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${participant.userName}님의 참여를 승인했습니다.'),
          backgroundColor: Colors.green,
        ),
      );
      _loadParticipants();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('참여 승인에 실패했습니다. 다시 시도해주세요.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _rejectParticipant(MeetupParticipant participant) async {
    final success = await _meetupService.rejectParticipant(participant.id);
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${participant.userName}님의 참여를 거절했습니다.'),
          backgroundColor: Colors.orange,
        ),
      );
      _loadParticipants();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('참여 거절에 실패했습니다. 다시 시도해주세요.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _removeParticipant(MeetupParticipant participant) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('참여 취소'),
        content: Text('${participant.userName}님의 참여를 취소하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('확인'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await _meetupService.removeParticipant(participant.id);
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${participant.userName}님의 참여를 취소했습니다.'),
            backgroundColor: Colors.orange,
          ),
        );
        _loadParticipants();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('참여 취소에 실패했습니다. 다시 시도해주세요.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case ParticipantStatus.pending:
        return Icons.hourglass_empty;
      case ParticipantStatus.approved:
        return Icons.check_circle_outline;
      case ParticipantStatus.rejected:
        return Icons.cancel_outlined;
      default:
        return Icons.people_outline;
    }
  }

  String _getEmptyMessage(String status) {
    switch (status) {
      case ParticipantStatus.pending:
        return '대기중인 참여자가 없습니다.';
      case ParticipantStatus.approved:
        return '승인된 참여자가 없습니다.';
      case ParticipantStatus.rejected:
        return '거절된 참여자가 없습니다.';
      default:
        return '참여자가 없습니다.';
    }
  }
}






