// lib/screens/user_posts_screen.dart
// 마이페이지에서 게시글 목록 확인 용도

import 'package:flutter/material.dart';
import '../models/post.dart';
import '../services/user_stats_service.dart';
import '../l10n/app_localizations.dart';
import '../constants/app_constants.dart';
import 'post_detail_screen.dart';

class UserPostsScreen extends StatefulWidget {
  const UserPostsScreen({Key? key}) : super(key: key);

  @override
  State<UserPostsScreen> createState() => _UserPostsScreenState();
}

class _UserPostsScreenState extends State<UserPostsScreen> {
  final UserStatsService _userStatsService = UserStatsService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF111827)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          AppLocalizations.of(context)!.myPosts ?? "",
          style: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Color(0xFF111827),
          ),
        ),
        centerTitle: false,
      ),
      body: StreamBuilder<List<Post>>(
        stream: _userStatsService.getUserPosts(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text(AppLocalizations.of(context)!.error ?? ""));
          }

          final posts = snapshot.data ?? [];

          if (posts.isEmpty) {
            return Center(
              child: Text(
                AppLocalizations.of(context)!.noWrittenPosts ?? "",
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF6B7280),
                ),
              ),
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 게시글 수 표시 부분
              Container(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Text(
                  AppLocalizations.of(context)!.totalPostsCount(posts.length),
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 14,
                    color: Color(0xFF6B7280),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),

              Container(
                height: 1,
                color: const Color(0xFFF3F4F6),
              ),

              // 게시글 목록
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: posts.length,
                  separatorBuilder: (context, index) => Container(
                    height: 1,
                    margin: const EdgeInsets.symmetric(vertical: 12),
                    color: const Color(0xFFF3F4F6),
                  ),
                  itemBuilder: (context, index) {
                    final post = posts[index];
                    return InkWell(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => PostDetailScreen(post: post),
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              post.title,
                              style: const TextStyle(
                                fontFamily: 'Pretendard',
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF111827),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              post.getPreviewContent(),
                              style: const TextStyle(
                                fontFamily: 'Pretendard',
                                fontSize: 14,
                                fontWeight: FontWeight.w400,
                                color: Color(0xFF6B7280),
                                height: 1.5,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Text(
                                  post.getFormattedTime(context),
                                  style: const TextStyle(
                                    fontFamily: 'Pretendard',
                                    color: Color(0xFF9CA3AF),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                                const Spacer(),
                                // 좋아요 표시
                                if (post.likes > 0) ...[
                                  const Icon(
                                    Icons.favorite,
                                    size: 16,
                                    color: Color(0xFFEF4444),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${post.likes}',
                                    style: const TextStyle(
                                      fontFamily: 'Pretendard',
                                      color: Color(0xFF6B7280),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                ],
                                // 댓글 수 표시
                                if (post.commentCount > 0) ...[
                                  const Icon(
                                    Icons.chat_bubble_outline,
                                    size: 16,
                                    color: AppColors.pointColor,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${post.commentCount}',
                                    style: const TextStyle(
                                      fontFamily: 'Pretendard',
                                      color: Color(0xFF6B7280),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
