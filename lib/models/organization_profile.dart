class OrganizationProfile {
  const OrganizationProfile({
    required this.id,
    required this.name,
    required this.handle,
    this.organizationType = '',
    this.affiliation = '',
    this.activityArea = '',
    this.logoUrl = '',
    this.coverImageUrl = '',
    this.shortDescription = '',
    this.description = '',
    this.publicContact = '',
    this.websiteUrl = '',
    this.verificationStatus = '',
    this.partnerStatus = '',
  });

  final String id;
  final String name;
  final String handle;
  final String organizationType;
  final String affiliation;
  final String activityArea;
  final String logoUrl;
  final String coverImageUrl;
  final String shortDescription;
  final String description;
  final String publicContact;
  final String websiteUrl;
  final String verificationStatus;
  final String partnerStatus;

  factory OrganizationProfile.fromMap(Map<dynamic, dynamic> map) {
    String value(String key) => (map[key] ?? '').toString().trim();
    return OrganizationProfile(
      id: value('id').isNotEmpty ? value('id') : value('organizationId'),
      name: value('name'),
      handle: value('handle'),
      organizationType: value('organizationType'),
      affiliation: value('affiliation'),
      activityArea: value('activityArea'),
      logoUrl: value('logoUrl'),
      coverImageUrl: value('coverImageUrl'),
      shortDescription: value('shortDescription'),
      description: value('description'),
      publicContact: value('publicContact'),
      websiteUrl: value('websiteUrl'),
      verificationStatus: value('verificationStatus'),
      partnerStatus: value('partnerStatus'),
    );
  }
}

class OrganizationAccess {
  const OrganizationAccess({
    required this.membershipId,
    required this.organizationId,
    required this.role,
    required this.membershipStatus,
    required this.lifecycleStatus,
    required this.organization,
  });

  final String membershipId;
  final String organizationId;
  final String role;
  final String membershipStatus;
  final String lifecycleStatus;
  final OrganizationProfile? organization;

  factory OrganizationAccess.fromMap(Map<dynamic, dynamic> map) {
    String value(String key) => (map[key] ?? '').toString().trim();
    final rawOrganization = map['organization'];
    return OrganizationAccess(
      membershipId: value('membershipId'),
      organizationId: value('organizationId'),
      role: value('role'),
      membershipStatus: value('membershipStatus'),
      lifecycleStatus: value('lifecycleStatus'),
      organization: rawOrganization is Map
          ? OrganizationProfile.fromMap(rawOrganization)
          : null,
    );
  }
}
