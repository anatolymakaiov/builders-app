class WebCompanyBranding {
  const WebCompanyBranding({this.logoUrl = '', this.headerUrl = ''});

  final String logoUrl;
  final String headerUrl;

  factory WebCompanyBranding.fromProfile(Map<String, dynamic> profile) {
    String first(List<String> fields) {
      for (final field in fields) {
        final value = profile[field]?.toString().trim() ?? '';
        if (value.isNotEmpty) return value;
      }
      return '';
    }

    return WebCompanyBranding(
      logoUrl: first(const [
        'companyLogoUrl',
        'companyLogo',
        'companyAvatarUrl',
        'logo',
        'employerAvatarUrl',
        'avatarUrl',
        'profilePhotoUrl',
        'photoUrl',
        'photo',
      ]),
      headerUrl: first(const [
        'profileHeaderImage',
        'headerImage',
        'headerImageUrl',
        'backgroundImageUrl',
        'coverPhotoUrl',
        'companyHeaderUrl',
        'backgroundUrl',
        'backgroundImage',
      ]),
    );
  }
}

Map<String, dynamic> webJobWithoutSnapshotBranding(
    Map<String, dynamic> jobData) {
  return {...jobData, 'companyLogo': ''};
}
