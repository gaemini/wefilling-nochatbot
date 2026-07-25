// lib/widgets/user_tile.dart
// 사용자 목록에서 각 사용자를 표시하는 타일 위젯
// 프로필 이미지, 이름, 관계 상태, 액션 버튼 포함

import 'package:flutter/material.dart';
import '../models/user_profile.dart';
import '../models/relationship_status.dart';
import '../utils/country_flag_helper.dart';
import '../utils/responsive_helper.dart';
import '../l10n/app_localizations.dart';

class UserTile extends StatelessWidget {
  final UserProfile user;
  final RelationshipStatus relationshipStatus;
  final VoidCallback? onActionPressed;
  final VoidCallback? onTilePressed;
  final bool isLoading;
  final bool minimal;

  const UserTile({
    super.key,
    required this.user,
    required this.relationshipStatus,
    this.onActionPressed,
    this.onTilePressed,
    this.isLoading = false,
    this.minimal = false,
  });

  @override
  Widget build(BuildContext context) {
    if (minimal) {
      final width = MediaQuery.sizeOf(context).width;
      final isCompact = width < 360;
      final horizontalPadding = isCompact ? 12.0 : (width < 600 ? 16.0 : 24.0);

      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Material(
                color: Colors.white,
                child: InkWell(
                  onTap: onTilePressed,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding,
                      10,
                      horizontalPadding,
                      10,
                    ),
                    child: MediaQuery.withClampedTextScaling(
                      maxScaleFactor: 1.2,
                      child: Row(
                        children: [
                          _buildProfileImage(size: isCompact ? 40 : 44),
                          SizedBox(width: isCompact ? 10 : 12),
                          Expanded(
                              child: _buildUserInfo(context, compact: true)),
                          const SizedBox(width: 8),
                          Flexible(
                              child:
                                  _buildActionButton(context, compact: true)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Divider(
                height: 1,
                thickness: 1,
                indent: horizontalPadding + (isCompact ? 50 : 56),
                endIndent: horizontalPadding,
                color: const Color(0xFFEAECF0),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      elevation: 0,
      color: Colors.white,
      child: InkWell(
        onTap: onTilePressed,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              // 프로필 이미지
              _buildProfileImage(),
              const SizedBox(width: 12),

              // 사용자 정보
              Expanded(child: _buildUserInfo(context)),

              // 액션 버튼
              _buildActionButton(context),
            ],
          ),
        ),
      ),
    );
  }

  /// 프로필 이미지 위젯
  Widget _buildProfileImage({double size = 48}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.grey[300],
      ),
      child: user.hasProfileImage
          ? ClipOval(
              child: Image.network(
                user.photoURL!,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Icon(
                  Icons.person_outline_rounded,
                  size: size * 0.5,
                  color: Colors.grey[600],
                ),
              ),
            )
          : Icon(
              Icons.person_outline_rounded,
              size: size * 0.5,
              color: Colors.grey[600],
            ),
    );
  }

  /// 사용자 정보 위젯
  Widget _buildUserInfo(BuildContext context, {bool compact = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 사용자 이름
        Text(
          user.displayNameOrNickname,
          style: TextStyle(
            fontFamily: 'Pretendard',
            fontSize: compact ? context.rf(14).clamp(13, 15).toDouble() : 16,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF111827),
            height: 1.2,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),

        SizedBox(height: compact ? 3 : 8),

        // 국적 정보
        if (user.nationality != null && user.nationality!.isNotEmpty)
          Row(
            children: [
              Icon(
                Icons.flag_outlined,
                size: compact ? 13 : 16,
                color: const Color(0xFF98A2B3),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  CountryFlagHelper.getCountryInfo(
                        user.nationality!,
                      )?.getLocalizedName(
                        Localizations.localeOf(context).languageCode,
                      ) ??
                      user.nationality!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: compact ? 12 : 12.5,
                    color: const Color(0xFF8B93A1),
                    fontWeight: FontWeight.w500,
                    height: 1.2,
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }

  /// 액션 버튼 위젯
  Widget _buildActionButton(BuildContext context, {bool compact = false}) {
    if (isLoading) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    String _labelForStatus(BuildContext context, RelationshipStatus status) {
      final l10n = AppLocalizations.of(context);
      if (l10n == null) return '';
      switch (status) {
        case RelationshipStatus.none:
          // 친구요청 보내기
          return l10n.friendRequest;
        case RelationshipStatus.pendingOut:
          // 요청 취소
          return l10n.cancelFriendRequest;
        case RelationshipStatus.pendingIn:
          // 받은 요청(수락은 요청 페이지에서 진행)
          return l10n.accept;
        case RelationshipStatus.friends:
          return l10n.removeFriendAction;
        case RelationshipStatus.blocked:
          return l10n.unblock;
        case RelationshipStatus.blockedBy:
          return l10n.blockedUser;
      }
    }

    // 차단당한 상태는 버튼 비활성화
    if (relationshipStatus == RelationshipStatus.blockedBy) {
      final label = _labelForStatus(context, relationshipStatus);
      if (compact) {
        return Text(
          label.isNotEmpty ? label : 'Blocked',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFF98A2B3),
          ),
        );
      }
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.grey[300],
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label.isNotEmpty ? label : 'Blocked',
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
      );
    }

    // 관계 상태에 따른 버튼 스타일
    final buttonStyle = _getButtonStyle(relationshipStatus);

    if (compact) {
      return TextButton(
        onPressed: relationshipStatus.isActionable ? onActionPressed : null,
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xFF344054),
          disabledForegroundColor: const Color(0xFF98A2B3),
          minimumSize: const Size(0, 40),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          visualDensity: VisualDensity.compact,
        ),
        child: Text(
          _labelForStatus(context, relationshipStatus),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }

    return ElevatedButton(
      onPressed: relationshipStatus.isActionable ? onActionPressed : null,
      style: ElevatedButton.styleFrom(
        backgroundColor: Color(buttonStyle['color'] as int),
        foregroundColor: Color(buttonStyle['textColor'] as int),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        minimumSize: const Size(90, 40),
      ),
      child: Text(
        _labelForStatus(context, relationshipStatus),
        style: const TextStyle(
          fontFamily: 'Pretendard',
          fontSize: 13,
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
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.grey[300],
        ),
        child: user.hasProfileImage
            ? ClipOval(
                child: Image.network(
                  user.photoURL!,
                  width: 40,
                  height: 40,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Icon(
                    Icons.person,
                    size: 20,
                    color: Colors.grey[600],
                  ),
                ),
              )
            : Icon(
                Icons.person,
                size: 20,
                color: Colors.grey[600],
              ),
      ),
      title: Text(
        user.displayNameOrNickname,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
      subtitle: null,
      trailing: trailing,
      onTap: onPressed,
    );
  }
}
