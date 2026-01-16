import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../constants/app_constants.dart';
import '../../l10n/app_localizations.dart';
import '../../services/post_service.dart';

class PollPostWidget extends StatefulWidget {
  final String postId;

  const PollPostWidget({super.key, required this.postId});

  @override
  State<PollPostWidget> createState() => _PollPostWidgetState();
}

class _PollPostWidgetState extends State<PollPostWidget> {
  final PostService _postService = PostService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String? _selectedOptionId;
  bool _isVoting = false;

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final postRef = _firestore.collection('posts').doc(widget.postId);
    final voteRef = user != null
        ? postRef.collection('pollVotes').doc(user.uid)
        : null;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: postRef.snapshots(),
      builder: (context, postSnap) {
        final postData = postSnap.data?.data();
        if (postData == null) {
          return const SizedBox.shrink();
        }

        final type = postData['type'] ?? 'text';
        if (type != 'poll') return const SizedBox.shrink();

        final rawOptions = postData['pollOptions'];
        final options = <Map<String, dynamic>>[];
        if (rawOptions is List) {
          for (final item in rawOptions) {
            if (item is Map) {
              options.add(Map<String, dynamic>.from(item));
            }
          }
        }

        final totalVotes = (postData['pollTotalVotes'] is int)
            ? (postData['pollTotalVotes'] as int)
            : 0;

        Widget contentForVote(String? votedOptionId, bool hasVoted) {
          if (options.isEmpty) return const SizedBox.shrink();

          if (hasVoted) {
            return Column(
              children: options.map((o) {
                final id = o['id']?.toString() ?? '';
                final text = o['text']?.toString() ?? '';
                final votes = (o['votes'] is int) ? (o['votes'] as int) : 0;
                final ratio = totalVotes <= 0 ? 0.0 : (votes / totalVotes);
                final percent = (ratio * 100).round();

                final isMine = votedOptionId != null && votedOptionId == id;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              text,
                              style: TextStyle(
                                fontFamily: 'Pretendard',
                                fontSize: 14,
                                fontWeight: isMine ? FontWeight.w700 : FontWeight.w600,
                                color: const Color(0xFF111827),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '$percent%',
                            style: TextStyle(
                              fontFamily: 'Pretendard',
                              fontSize: 12,
                              fontWeight: isMine ? FontWeight.w700 : FontWeight.w600,
                              color: isMine ? const Color(0xFF10B981) : const Color(0xFF6B7280),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          minHeight: 10,
                          value: ratio.clamp(0.0, 1.0),
                          backgroundColor: const Color(0xFFE5E7EB),
                          valueColor: AlwaysStoppedAnimation<Color>(
                            isMine ? const Color(0xFF10B981) : AppColors.pointColor,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        AppLocalizations.of(context)!.pollVotesUnit(votes),
                        style: const TextStyle(
                          fontFamily: 'Pretendard',
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            );
          }

          // 투표 전 UI
          return Column(
            children: [
              ...options.map((o) {
                final id = o['id']?.toString() ?? '';
                final text = o['text']?.toString() ?? '';
                final selected = _selectedOptionId == id;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: user == null
                        ? null
                        : () {
                            setState(() => _selectedOptionId = id);
                          },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(
                        color: selected ? const Color(0xFFE8EAF6) : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: selected ? AppColors.pointColor : const Color(0xFFE5E7EB),
                          width: selected ? 2 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              text,
                              style: const TextStyle(
                                fontFamily: 'Pretendard',
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF111827),
                              ),
                            ),
                          ),
                          if (selected)
                            Icon(Icons.check_circle, color: AppColors.pointColor, size: 18),
                        ],
                      ),
                    ),
                  ),
                );
              }),
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: (user == null || _selectedOptionId == null || _isVoting)
                      ? null
                      : () async {
                          setState(() => _isVoting = true);
                          final ok = await _postService.voteOnPoll(widget.postId, _selectedOptionId!);
                          if (mounted) {
                            setState(() => _isVoting = false);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  ok
                                      ? AppLocalizations.of(context)!.pollVoteSuccess
                                      : AppLocalizations.of(context)!.pollVoteFailed,
                                ),
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.pointColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isVoting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Text(
                          AppLocalizations.of(context)!.pollVoteButton,
                          style: const TextStyle(
                            fontFamily: 'Pretendard',
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
              if (user == null)
                Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    AppLocalizations.of(context)!.pollLoginToVote,
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ),
            ],
          );
        }

        Widget buildCard({required bool hasVoted, String? votedOptionId}) {
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.how_to_vote_outlined, size: 18, color: Color(0xFF111827)),
                    const SizedBox(width: 6),
                    Text(
                      AppLocalizations.of(context)!.pollVoteLabel,
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF111827),
                      ),
                    ),
                    const Spacer(),
                    if (hasVoted)
                      Text(
                        AppLocalizations.of(context)!.pollParticipantsCount(totalVotes),
                        style: const TextStyle(
                          fontFamily: 'Pretendard',
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF6B7280),
                        ),
                      )
                    else
                      Text(
                        AppLocalizations.of(context)!.pollVoteToSeeResults,
                        style: const TextStyle(
                          fontFamily: 'Pretendard',
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                contentForVote(votedOptionId, hasVoted),
              ],
            ),
          );
        }

        if (voteRef == null) {
          return buildCard(hasVoted: false, votedOptionId: null);
        }

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: voteRef.snapshots(),
          builder: (context, voteSnap) {
            final hasVoted = voteSnap.data?.exists == true;
            final votedOptionId = voteSnap.data?.data()?['optionId']?.toString();
            return buildCard(hasVoted: hasVoted, votedOptionId: votedOptionId);
          },
        );
      },
    );
  }
}

