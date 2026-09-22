import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/services/multi_account_service.dart';

void main() {
  test('linked employer identity keeps only safe display fields', () {
    final identity = LinkedAccountIdentity.fromMap({
      'uid': 'employer-a',
      'role': 'employer',
      'displayName': 'Company A',
      'avatarUrl': 'https://example.test/logo.jpg',
      'username': 'company-a',
      'email': 'private@example.test',
    });

    expect(identity.uid, 'employer-a');
    expect(identity.displayName, 'Company A');
    expect(identity.username, 'company-a');
    expect(identity.isEmployer, isTrue);
  });

  test('linked worker identity defaults to worker semantics', () {
    final identity = LinkedAccountIdentity.fromMap({
      'uid': 'worker-a',
      'displayName': 'Worker A',
    });

    expect(identity.role, 'worker');
    expect(identity.isEmployer, isFalse);
  });

  test('newly linked identity is immediately merged into the open list', () {
    const current = LinkedAccountIdentity(
      uid: 'worker-a',
      role: 'worker',
      displayName: 'Worker A',
      avatarUrl: '',
      username: 'worker-a',
    );
    const linked = LinkedAccountIdentity(
      uid: 'employer-b',
      role: 'employer',
      displayName: 'Company B',
      avatarUrl: '',
      username: 'company-b',
    );

    final merged = mergeLinkedAccountIdentity([current], linked);

    expect(merged.map((account) => account.uid), ['worker-a', 'employer-b']);
  });

  test('merging a refreshed identity does not duplicate its uid', () {
    const oldIdentity = LinkedAccountIdentity(
      uid: 'worker-a',
      role: 'worker',
      displayName: 'Old name',
      avatarUrl: '',
      username: '',
    );
    const refreshedIdentity = LinkedAccountIdentity(
      uid: 'worker-a',
      role: 'worker',
      displayName: 'New name',
      avatarUrl: 'https://example.test/avatar.jpg',
      username: 'worker-a',
    );

    final merged = mergeLinkedAccountIdentity(
      [oldIdentity],
      refreshedIdentity,
    );

    expect(merged, hasLength(1));
    expect(merged.single.displayName, 'New name');
  });

  test('switch target verification accepts only the requested uid', () {
    expect(
      () => verifyLinkedAccountSwitchTarget(
        expectedUid: 'worker-b',
        authenticatedUid: 'worker-b',
      ),
      returnsNormally,
    );
    expect(
      () => verifyLinkedAccountSwitchTarget(
        expectedUid: 'worker-b',
        authenticatedUid: 'worker-a',
      ),
      throwsA(
        isA<FirebaseAuthException>().having(
          (error) => error.code,
          'code',
          'account-switch-target-mismatch',
        ),
      ),
    );
  });

  test('current account indicator follows the active Firebase uid', () {
    expect(isCurrentLinkedAccount('worker-a', 'worker-a'), isTrue);
    expect(isCurrentLinkedAccount('worker-a', 'employer-b'), isFalse);
    expect(isCurrentLinkedAccount(null, 'worker-a'), isFalse);
  });

  test('multi-account mutations invalidate linked account state', () {
    final before = MultiAccountState.revision.value;

    MultiAccountState.invalidate();

    expect(MultiAccountState.revision.value, before + 1);
  });
}
