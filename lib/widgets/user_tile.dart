// lib/widgets/user_tile.dart
// 사용자 목록에서 각 사용자를 표시하는 타일 위젯
// 프로필 이미지, 이름, 관계 상태, 액션 버튼 포함

import 'package:flutter/material.dart';
import '../models/user_profile.dart';
import '../models/relationship_status.dart';

class UserTile extends StatelessWidget {
  final UserProfile user;
  final RelationshipStatus relationshipStatus;
  final VoidCallback? onActionPressed;
  final VoidCallback? onTilePressed;
  final bool isLoading;

  const UserTile({
    super.key,
    required this.user,
    required this.relationshipStatus,
    this.onActionPressed,
    this.onTilePressed,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      elevation: 2,
      child: InkWell(
        onTap: onTilePressed,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // 프로필 이미지
              _buildProfileImage(),
              const SizedBox(width: 16),
              
              // 사용자 정보
              Expanded(
                child: _buildUserInfo(),
              ),
              
              // 액션 버튼
              _buildActionButton(),
            ],
          ),
        ),
      ),
    );
  }

  /// 프로필 이미지 위젯
  Widget _buildProfileImage() {
    return CircleAvatar(
      radius: 24,
      backgroundColor: Colors.grey[300],
      backgroundImage: user.hasProfileImage
          ? NetworkImage(user.photoURL!)
          : null,
      child: !user.hasProfileImage
          ? Text(
              user.displayNameOrNickname.isNotEmpty
                  ? user.displayNameOrNickname[0].toUpperCase()
                  : '?',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            )
          : null,
    );
  }

  /// 사용자 정보 위젯
  Widget _buildUserInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 사용자 이름
        Text(
          user.displayNameOrNickname,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        
        const SizedBox(height: 4),
        
        // 닉네임 (displayName과 다른 경우에만 표시)
        if (user.nickname != null && 
            user.nickname != user.displayName &&
            user.nickname!.isNotEmpty)
          Text(
            user.displayName,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        
        const SizedBox(height: 4),
        
        // 국적 정보
        if (user.nationality != null && user.nationality!.isNotEmpty)
          Row(
            children: [
              Icon(
                Icons.flag,
                size: 16,
                color: Colors.grey[600],
              ),
              const SizedBox(width: 4),
              Text(
                user.nationality!,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        
        const SizedBox(height: 4),
        
        // 친구 수
        Row(
          children: [
            Icon(
              Icons.people,
              size: 16,
              color: Colors.grey[600],
            ),
            const SizedBox(width: 4),
            Text(
              '친구 ${user.friendsCount}명',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 액션 버튼 위젯
  Widget _buildActionButton() {
    if (isLoading) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    // 차단당한 상태는 버튼 비활성화
    if (relationshipStatus == RelationshipStatus.blockedBy) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.grey[300],
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          '차단됨',
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
      );
    }

    // 관계 상태에 따른 버튼 스타일
    final buttonStyle = _getButtonStyle(relationshipStatus);
    
    return ElevatedButton(
      onPressed: relationshipStatus.isActionable ? onActionPressed : null,
      style: ElevatedButton.styleFrom(
        backgroundColor: Color(buttonStyle['color'] as int),
        foregroundColor: Color(buttonStyle['textColor'] as int),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        minimumSize: const Size(80, 36),
      ),
      child: Text(
        relationshipStatus.actionButtonText,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  /// 관계 상태에 따른 버튼 스타일 반환
  Map<String, int> _getButtonStyle(RelationshipStatus status) {
    switch (status) {
      case RelationshipStatus.none:
        return {
          'color': 0xFF2196F3, // 파란색
          'textColor': 0xFFFFFFFF, // 흰색
        };
      case RelationshipStatus.pendingOut:
        return {
          'color': 0xFFFFA000, // 주황색
          'textColor': 0xFFFFFFFF, // 흰색
        };
      case RelationshipStatus.pendingIn:
        return {
          'color': 0xFF4CAF50, // 초록색
          'textColor': 0xFFFFFFFF, // 흰색
        };
      case RelationshipStatus.friends:
        return {
          'color': 0xFFF44336, // 빨간색
          'textColor': 0xFFFFFFFF, // 흰색
        };
      case RelationshipStatus.blocked:
        return {
          'color': 0xFFF44336, // 빨간색
          'textColor': 0xFFFFFFFF, // 흰색
        };
      case RelationshipStatus.blockedBy:
        return {
          'color': 0xFF9E9E9E, // 회색
          'textColor': 0xFFFFFFFF, // 흰색
        };
    }
  }
}

/// 사용자 타일의 간단한 버전 (친구 목록 등에서 사용)
class SimpleUserTile extends StatelessWidget {
  final UserProfile user;
  final VoidCallback? onPressed;
  final Widget? trailing;

  const SimpleUserTile({
    super.key,
    required this.user,
    this.onPressed,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        radius: 20,
        backgroundColor: Colors.grey[300],
        backgroundImage: user.hasProfileImage
            ? NetworkImage(user.photoURL!)
            : null,
        child: !user.hasProfileImage
            ? Text(
                user.displayNameOrNickname.isNotEmpty
                    ? user.displayNameOrNickname[0].toUpperCase()
                    : '?',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              )
            : null,
      ),
      title: Text(
        user.displayNameOrNickname,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: user.nickname != null && 
                user.nickname != user.displayName &&
                user.nickname!.isNotEmpty
          ? Text(
              user.displayName,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            )
          : null,
      trailing: trailing,
      onTap: onPressed,
    );
  }
}
