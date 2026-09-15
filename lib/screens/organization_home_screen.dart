import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants/app_constants.dart';
import '../providers/auth_provider.dart';
import '../models/organization_profile.dart';
import '../services/organization_account_service.dart';
import '../l10n/ui_locale.dart';
import 'organization_profile_edit_screen.dart';

class OrganizationHomeScreen extends StatefulWidget {
  const OrganizationHomeScreen({super.key});

  @override
  State<OrganizationHomeScreen> createState() => _OrganizationHomeScreenState();
}

class _OrganizationHomeScreenState extends State<OrganizationHomeScreen> {
  late Future<List<OrganizationAccess>> _access;
  String? _selectedOrganizationId;

  @override
  void initState() {
    super.initState();
    _access = OrganizationAccountService.instance.getMyAccess();
  }

  String _copy(String ko, String en, String zh) {
    final code = Localizations.localeOf(context).languageCode;
    return code == 'zh'
        ? zh
        : code == 'ko'
            ? ko
            : en;
  }

  void _retry() => setState(() {
        _access = OrganizationAccountService.instance.getMyAccess();
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        title: Text(
          _copy('단체 프로필', 'Organization profile', '机构资料'),
          style: TextStyle(
            fontFamily: uiFontFamily(context, 'Inter'),
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: _copy('로그아웃', 'Sign out', '退出登录'),
            onPressed: context.read<AuthProvider>().signOut,
            icon: const Icon(Icons.logout_rounded, size: 21),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: FutureBuilder<List<OrganizationAccess>>(
          future: _access,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _Status(
                icon: Icons.error_outline_rounded,
                title: _copy('단체 정보를 불러오지 못했습니다.',
                    'Could not load organization access.', '无法加载机构权限。'),
                action: _copy('다시 시도', 'Retry', '重试'),
                onAction: _retry,
              );
            }
            final access = snapshot.data ?? const <OrganizationAccess>[];
            final active = access
                .where((value) =>
                    value.membershipStatus == 'active' &&
                    value.lifecycleStatus == 'active' &&
                    value.organization != null)
                .toList(growable: false);
            if (active.isEmpty) {
              return _Status(
                icon: Icons.apartment_rounded,
                title: _copy('단체 운영 권한이 아직 활성화되지 않았습니다.',
                    'Organization access is not active yet.', '机构管理权限尚未启用。'),
                action: _copy('새로고침', 'Refresh', '刷新'),
                onAction: _retry,
              );
            }
            final selected = active.firstWhere(
              (value) => value.organizationId == _selectedOrganizationId,
              orElse: () => active.first,
            );
            _selectedOrganizationId = selected.organizationId;
            return _OrganizationProfileBody(
              access: selected,
              allAccess: active,
              onUpdated: _retry,
              onSelected: (value) => setState(() {
                _selectedOrganizationId = value;
              }),
            );
          },
        ),
      ),
    );
  }
}

class _OrganizationProfileBody extends StatelessWidget {
  const _OrganizationProfileBody({
    required this.access,
    required this.allAccess,
    required this.onUpdated,
    required this.onSelected,
  });

  final OrganizationAccess access;
  final List<OrganizationAccess> allAccess;
  final VoidCallback onUpdated;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final organization = access.organization!;
    return ListView(
      padding: EdgeInsets.fromLTRB(
        22,
        18,
        22,
        MediaQuery.viewPaddingOf(context).bottom + 28,
      ),
      children: [
        if (allAccess.length > 1)
          Align(
            alignment: Alignment.centerLeft,
            child: DropdownButton<String>(
              value: access.organizationId,
              underline: const SizedBox.shrink(),
              items: allAccess
                  .map((item) => DropdownMenuItem(
                        value: item.organizationId,
                        child: Text(
                            item.organization?.name ?? item.organizationId),
                      ))
                  .toList(growable: false),
              onChanged: (value) {
                if (value != null) onSelected(value);
              },
            ),
          ),
        if (organization.coverImageUrl.isNotEmpty)
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: AspectRatio(
              aspectRatio: 2.4,
              child: CachedNetworkImage(
                imageUrl: organization.coverImageUrl,
                fit: BoxFit.cover,
              ),
            ),
          ),
        const SizedBox(height: 18),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 34,
              backgroundColor: const Color(0xFFF2F4F7),
              backgroundImage: organization.logoUrl.isNotEmpty
                  ? CachedNetworkImageProvider(organization.logoUrl)
                  : null,
              child: organization.logoUrl.isEmpty
                  ? const Icon(Icons.apartment_rounded,
                      color: Color(0xFF667085), size: 30)
                  : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          organization.name,
                          style: TextStyle(
                            fontFamily: uiFontFamily(context, 'Inter'),
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF101828),
                            height: 1.25,
                          ),
                        ),
                      ),
                      if (organization.verificationStatus == 'verified') ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.verified_rounded,
                            size: 19, color: AppColors.pointColor),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '@${organization.handle}',
                    style: const TextStyle(
                      fontSize: 13.5,
                      color: Color(0xFF667085),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        if (organization.shortDescription.isNotEmpty)
          Text(
            organization.shortDescription,
            style: const TextStyle(
              fontSize: 15,
              height: 1.55,
              color: Color(0xFF344054),
            ),
          ),
        const SizedBox(height: 20),
        _InfoLine(
          icon: Icons.category_outlined,
          value: organization.organizationType,
        ),
        _InfoLine(
          icon: Icons.account_balance_outlined,
          value: organization.affiliation,
        ),
        _InfoLine(
          icon: Icons.place_outlined,
          value: organization.activityArea,
        ),
        _InfoLine(
          icon: Icons.language_rounded,
          value: organization.websiteUrl,
        ),
        _InfoLine(
          icon: Icons.mail_outline_rounded,
          value: organization.publicContact,
        ),
        if (organization.description.isNotEmpty) ...[
          const SizedBox(height: 22),
          Text(
            organization.description,
            style: const TextStyle(
              fontSize: 14,
              height: 1.6,
              color: Color(0xFF475467),
            ),
          ),
        ],
        const SizedBox(height: 26),
        Text(
          'Role · ${access.role}',
          style: const TextStyle(fontSize: 12, color: Color(0xFF98A2B3)),
        ),
        if (const {'owner', 'manager', 'editor'}.contains(access.role)) ...[
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: () async {
              final updated = await Navigator.of(context).push<bool>(
                MaterialPageRoute<bool>(
                  builder: (_) => OrganizationProfileEditScreen(
                    access: access,
                  ),
                ),
              );
              if (updated == true) onUpdated();
            },
            icon: const Icon(Icons.edit_outlined, size: 19),
            label: Text(
              Localizations.localeOf(context).languageCode == 'zh'
                  ? '编辑资料'
                  : Localizations.localeOf(context).languageCode == 'ko'
                      ? '프로필 수정'
                      : 'Edit profile',
            ),
          ),
        ],
      ],
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.icon, required this.value});

  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 19, color: const Color(0xFF667085)),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                height: 1.45,
                color: Color(0xFF344054),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Status extends StatelessWidget {
  const _Status({
    required this.icon,
    required this.title,
    required this.action,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 38, color: const Color(0xFF98A2B3)),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                height: 1.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 14),
            TextButton(onPressed: onAction, child: Text(action)),
          ],
        ),
      ),
    );
  }
}
