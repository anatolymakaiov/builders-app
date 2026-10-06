import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/services/vacancy_invitation_service.dart';

void main() {
  test('opportunity states are actionable only while open', () {
    VacancyInvitation invitation(String status) => VacancyInvitation(
          id: 'invite',
          vacancyId: 'job',
          workerId: 'worker',
          title: 'Dryliner',
          company: 'Company',
          tradeId: 'dryliner',
          generalLocation: 'Manchester',
          status: status,
        );

    expect(invitation('pending').actionable, isTrue);
    expect(invitation('viewed').actionable, isTrue);
    expect(invitation('applied').actionable, isFalse);
    expect(invitation('not_interested').actionable, isFalse);
    expect(invitation('vacancy_closed').actionable, isFalse);
    expect(invitation('vacancy_filled').actionable, isFalse);
    expect(invitation('vacancy_filled').statusLabel, 'Vacancy filled');
  });
}
