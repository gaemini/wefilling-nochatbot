import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/app_constants.dart';
import '../models/organization_profile.dart';
import '../l10n/ui_locale.dart';

class OrganizationProfileScreen extends StatelessWidget {
  const OrganizationProfileScreen({
    super.key,
    required this.organization,
  });

  final OrganizationProfile organization;

  String _copy(BuildContext context, String ko, String en, String zh) {
    final code = Localizations.localeOf(context).languageCode;
    return code == 'zh'
        ? zh
        : code == 'ko'
            ? ko
            : en;
  }

  Future<void> _open(String raw) async {
    final uri = Uri.tryParse(raw);
    if (uri != null && (uri.scheme == 'https' || uri.scheme == 'http')) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _contact(String raw) async {
    final value = raw.trim();
    if (value.isEmpty) return;
    final parsed = Uri.tryParse(value);
    final uri =
        parsed != null && (parsed.scheme == 'https' || parsed.scheme == 'http')
            ? parsed
            : Uri(scheme: 'mailto', path: value);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        title: Text(
          _copy(context, '단체 프로필', 'Organization', '机构资料'),
          style: TextStyle(
            fontFamily: uiFontFamily(context, 'Inter'),
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            22,
            18,
            22,
            MediaQuery.viewPaddingOf(context).bottom + 28,
          ),
          children: [
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
                              ),
                            ),
                          ),
                          if (organization.verificationStatus ==
                              'verified') ...[
                            const SizedBox(width: 6),
                            const Icon(Icons.verified_rounded,
                                color: AppColors.pointColor, size: 19),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '@${organization.handle}',
                        style: const TextStyle(
                          color: Color(0xFF667085),
                          fontSize: 13.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (organization.organizationType.isNotEmpty ||
                organization.affiliation.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                [organization.organizationType, organization.affiliation]
                    .where((value) => value.isNotEmpty)
                    .join(' · '),
                style: const TextStyle(
                  color: Color(0xFF475467),
                  fontSize: 14,
                  height: 1.45,
                ),
              ),
            ],
            if (organization.activityArea.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.place_outlined,
                    size: 17,
                    color: Color(0xFF667085),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      organization.activityArea,
                      style: const TextStyle(
                        color: Color(0xFF667085),
                        fontSize: 13.5,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (organization.shortDescription.isNotEmpty) ...[
              const SizedBox(height: 18),
              Text(
                organization.shortDescription,
                style: const TextStyle(
                  color: Color(0xFF344054),
                  fontSize: 15,
                  height: 1.55,
                ),
              ),
            ],
            const SizedBox(height: 18),
            _OrganizationFollowButton(
              organizationId: organization.id,
            ),
            if (organization.description.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text(
                organization.description,
                style: const TextStyle(
                  color: Color(0xFF475467),
                  fontSize: 14,
                  height: 1.6,
                ),
              ),
            ],
            if (organization.websiteUrl.isNotEmpty ||
                organization.publicContact.isNotEmpty) ...[
              const SizedBox(height: 22),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  if (organization.publicContact.isNotEmpty)
                    TextButton.icon(
                      onPressed: () => _contact(organization.publicContact),
                      icon: const Icon(Icons.mail_outline_rounded, size: 18),
                      label: Text(_copy(context, '문의', 'Contact', '咨询')),
                    ),
                  if (organization.websiteUrl.isNotEmpty)
                    TextButton.icon(
                      onPressed: () => _open(organization.websiteUrl),
                      icon: const Icon(Icons.open_in_new_rounded, size: 18),
                      label: Text(
                        _copy(context, '웹사이트', 'Website', '网站'),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _OrganizationFollowButton extends StatelessWidget {
  const _OrganizationFollowButton({required this.organizationId});

  final String organizationId;

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || organizationId.isEmpty) return const SizedBox.shrink();
    final reference = FirebaseFirestore.instance
        .collection('organization_follows')
        .doc('${organizationId}_$uid');
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: reference.snapshots(),
      builder: (context, snapshot) {
        final following = snapshot.data?.exists == true;
        return OutlinedButton(
          onPressed: () async {
            if (following) {
              await reference.delete();
            } else {
              await reference.set(<String, dynamic>{
                'organizationId': organizationId,
                'followerUid': uid,
                'createdAt': FieldValue.serverTimestamp(),
              });
            }
          },
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(44),
          ),
          child: Text(
            Localizations.localeOf(context).languageCode == 'zh'
                ? following
                    ? '已关注'
                    : '关注'
                : Localizations.localeOf(context).languageCode == 'ko'
                    ? following
                        ? '팔로잉'
                        : '팔로우'
                    : following
                        ? 'Following'
                        : 'Follow',
          ),
        );
      },
    );
  }
}
