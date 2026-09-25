import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/services/auth_session_resolver.dart';
import 'package:test_app/services/registration_lifecycle.dart';
import 'package:test_app/services/registration_wizard_steps.dart';

void main() {
  test('Worker needs verified email but not verified phone', () {
    expect(
        RegistrationLifecycle.canComplete(
          role: 'worker',
          emailVerified: true,
          phoneVerified: false,
        ),
        isTrue);
    expect(RegistrationLifecycle.completionSteps('worker'), [
      ProfileCompletionStep.emailVerification,
      ProfileCompletionStep.optionalDetails,
    ]);
  });

  test('Employer needs verified email and phone', () {
    expect(
        RegistrationLifecycle.canComplete(
          role: 'employer',
          emailVerified: true,
          phoneVerified: false,
        ),
        isFalse);
    expect(
        RegistrationLifecycle.canComplete(
          role: 'employer',
          emailVerified: true,
          phoneVerified: true,
        ),
        isTrue);
    expect(RegistrationLifecycle.completionSteps('employer'), [
      ProfileCompletionStep.emailVerification,
      ProfileCompletionStep.phoneVerification,
      ProfileCompletionStep.optionalDetails,
    ]);
  });

  test('Explicit incomplete flags override a legacy-looking name', () {
    final incomplete = {
      'role': 'worker',
      'name': 'Alex Worker',
      'profileComplete': false,
    };
    expect(RegistrationLifecycle.isComplete(incomplete), isFalse);
    expect(RegistrationLifecycle.canDiscard(incomplete), isTrue);
    expect(
        AuthSessionResolver.classify(
          profile: incomplete,
          hasAcceptedLegal: (_, __) => true,
        ).destination,
        AuthSessionDestination.profile);
    expect(
        RegistrationLifecycle.canDiscard({
          'role': 'worker',
          'name': 'Alex Worker',
          'profileComplete': true,
        }),
        isFalse);
  });

  test('Legacy completed profiles are retained', () {
    expect(
        RegistrationLifecycle.isComplete({
          'role': 'employer',
          'companyName': 'Builders Ltd',
        }),
        isTrue);
    expect(
        RegistrationLifecycle.canDiscard({
          'role': 'employer',
          'companyName': 'Builders Ltd',
        }),
        isFalse);
  });

  test('Legacy-looking draft is not a completed profile', () {
    expect(
        RegistrationLifecycle.isComplete({
          'role': 'worker',
          'name': 'Alex Worker',
          'pendingRegistration': true,
        }),
        isFalse);
    expect(
        RegistrationLifecycle.canDiscard({
          'role': 'employer',
          'companyName': 'Builders Ltd',
          'registrationFormComplete': false,
        }),
        isTrue);
  });

  test('Saved draft resumes at the first missing logical step', () {
    final data = <String, dynamic>{
      'role': 'worker',
      'registrationFirstName': 'Alex',
      'registrationLastName': 'Worker',
      'registrationPosition': 'Fixer',
      'addressLine1': '1 High Street',
      'townCity': 'London',
      'postcode': 'SW1A 1AA',
      'country': 'United Kingdom',
      'email': 'alex@example.com',
    };
    expect(RegistrationLifecycle.resumeStep(data, 'worker'),
        RegistrationWizardStep.phone.index);
    data['phone'] = '+447700900123';
    expect(RegistrationLifecycle.resumeStep(data, 'worker'),
        RegistrationWizardStep.credentials.index);
  });

  test('Edited phone invalidates an older asynchronous availability result',
      () async {
    final revision = RegistrationInputRevision();
    final oldRequest = Completer<bool>();
    final oldVersion = revision.value;
    revision.changed();
    final newVersion = revision.value;
    oldRequest.complete(false);
    await oldRequest.future;
    expect(revision.isCurrent(oldVersion), isFalse);
    expect(revision.isCurrent(newVersion), isTrue);
  });

  test('Edited email invalidates prior verification result', () {
    final revision = RegistrationInputRevision();
    final oldVersion = revision.value;
    revision.changed();
    expect(revision.isCurrent(oldVersion), isFalse);
  });

  test('Completed user stays out of registration even with a stale draft', () {
    final route = AuthSessionResolver.classify(
      profile: {'role': 'worker', 'profileComplete': true},
      draft: {'registrationFormComplete': false},
      hasAcceptedLegal: (_, __) => true,
    );
    expect(route.destination, AuthSessionDestination.home);
  });

  test('Legacy incomplete user and draft resume registration', () {
    final route = AuthSessionResolver.classify(
      profile: {'role': 'worker', 'profileComplete': false},
      draft: {'registrationFormComplete': false},
      hasAcceptedLegal: (_, __) => true,
    );
    expect(route.destination, AuthSessionDestination.registration);
  });

  test('Latest draft legal state wins over an older incomplete user document',
      () {
    final route = AuthSessionResolver.classify(
      profile: {
        'role': 'worker',
        'profileComplete': false,
        'legalAccepted': false
      },
      draft: {
        'role': 'worker',
        'registrationFormComplete': true,
        'legalAccepted': true
      },
      hasAcceptedLegal: (data, _) => data['legalAccepted'] == true,
    );
    expect(route.destination, AuthSessionDestination.profile);
  });

  test('Existing user legal acceptance survives a stale draft flag', () {
    final route = AuthSessionResolver.classify(
      profile: {
        'role': 'worker',
        'profileComplete': false,
        'legalAccepted': true,
      },
      draft: {
        'role': 'worker',
        'registrationFormComplete': true,
        'legalAccepted': false,
      },
      hasAcceptedLegal: (data, _) => data['legalAccepted'] == true,
    );
    expect(route.destination, AuthSessionDestination.profile);
  });
}
