import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/web_app/services/web_employer_entitlements_service.dart';

void main() {
  test('safe employer entitlement summary exposes limits and usage', () {
    const entitlement = WebEmployerEntitlements({
      'planName': 'Growth',
      'subscriptionStatus': 'trial',
      'canUseCandidateSearch': true,
      'canUseTalentPool': true,
      'canInviteToVacancy': true,
      'vacancyInviteMonthlyLimit': 200,
      'usage': {'vacancyInvitations': 4, 'talentOutreach': 0},
      'plans': [
        {'id': 'growth', 'name': 'Growth', 'candidateSearch': true}
      ],
    });
    expect(entitlement.planName, 'Growth');
    expect(entitlement.status, 'trial');
    expect(entitlement.candidateSearch, isTrue);
    expect(entitlement.talentPool, isTrue);
    expect(entitlement.vacancyInvites, isTrue);
    expect(entitlement.invitationUsed, 4);
    expect(entitlement.invitationLimit, 200);
    expect(entitlement.talentOutreach, isFalse);
    expect(entitlement.plans.single['id'], 'growth');
  });

  test('missing legacy fields remain safely locked', () {
    const entitlement = WebEmployerEntitlements({});
    expect(entitlement.candidateSearch, isFalse);
    expect(entitlement.talentPool, isFalse);
    expect(entitlement.vacancyInvites, isFalse);
    expect(entitlement.invitationLimit, 0);
    expect(entitlement.invitationUsed, 0);
  });
}
