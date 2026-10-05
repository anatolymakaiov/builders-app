import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/services/safe_profile_service.dart';

void main() {
  test('self reads are private, foreign reads use safe projection', () {
    expect(
        SafeProfileService.collectionFor(
            viewerUid: 'worker-a', targetUid: 'worker-a'),
        'users');
    expect(
        SafeProfileService.collectionFor(
            viewerUid: 'worker-a', targetUid: 'employer-b'),
        'public_profiles');
    expect(
        SafeProfileService.collectionFor(
            viewerUid: null, targetUid: 'worker-a'),
        'public_profiles');
  });

  test('account switch cannot reuse the previous account self scope', () {
    expect(
        SafeProfileService.collectionFor(
            viewerUid: 'worker-a', targetUid: 'worker-a'),
        'users');
    expect(
        SafeProfileService.collectionFor(
            viewerUid: 'employer-b', targetUid: 'worker-a'),
        'public_profiles');
  });
}
