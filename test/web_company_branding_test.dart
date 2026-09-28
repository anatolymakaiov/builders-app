import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/web_app/services/web_company_branding.dart';

void main() {
  test('current company profile supplies both vacancy branding images', () {
    final branding = WebCompanyBranding.fromProfile(const {
      'companyLogoUrl': 'current-logo.png',
      'companyLogo': 'old-logo.png',
      'profileHeaderImage': 'current-header.jpg',
      'headerImage': 'old-header.jpg',
    });

    expect(branding.logoUrl, 'current-logo.png');
    expect(branding.headerUrl, 'current-header.jpg');
  });

  test('legacy job snapshot cannot supply Web company branding', () {
    final job = webJobWithoutSnapshotBranding(const {
      'companyLogo': 'old-logo.png',
      'companyHeaderUrl': 'old-header.jpg',
      'photos': ['vacancy-photo.jpg'],
    });
    final branding = WebCompanyBranding.fromProfile(const {
      'companyLogoUrl': 'new-logo.png',
      'profileHeaderImage': 'new-header.jpg',
    });

    expect(job['companyLogo'], isEmpty);
    expect(job['photos'], ['vacancy-photo.jpg']);
    expect(branding.logoUrl, 'new-logo.png');
    expect(branding.headerUrl, 'new-header.jpg');
  });

  test('missing company media uses empty image fallbacks', () {
    final branding = WebCompanyBranding.fromProfile(const {});
    expect(branding.logoUrl, isEmpty);
    expect(branding.headerUrl, isEmpty);
  });

  test('legacy company profile media remains readable', () {
    final branding = WebCompanyBranding.fromProfile(const {
      'companyLogo': 'legacy-logo.png',
      'headerImage': 'legacy-header.jpg',
    });
    expect(branding.logoUrl, 'legacy-logo.png');
    expect(branding.headerUrl, 'legacy-header.jpg');
  });
}
