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
}
