import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/services/address_lookup_service.dart';
import 'package:test_app/services/registration_validation_service.dart';
import 'package:test_app/services/registration_wizard_steps.dart';

void main() {
  group('registration steps', () {
    test('all account creation steps are required for a worker', () {
      expect(
        RegistrationWizardSteps.validate(
          RegistrationWizardStep.accountType,
          role: '',
        ),
        isNotNull,
      );
      for (final step in RegistrationWizardStep.values) {
        if (step == RegistrationWizardStep.accountType) continue;
        expect(
          RegistrationWizardSteps.validate(step, role: 'worker'),
          isNotNull,
          reason: '${step.name} must not be skippable',
        );
      }
      expect(
        RegistrationWizardSteps.validate(
          RegistrationWizardStep.professionOrCompany,
          role: 'worker',
          trade: 'Dryliner',
        ),
        isNull,
      );
    });

    test('employer requires company identity but not worker trade', () {
      expect(
        RegistrationWizardSteps.validate(
          RegistrationWizardStep.professionOrCompany,
          role: 'employer',
          trade: 'Electrician',
        ),
        isNotNull,
      );
      expect(
        RegistrationWizardSteps.validate(
          RegistrationWizardStep.professionOrCompany,
          role: 'employer',
          companyName: 'Example Builders Ltd',
        ),
        isNull,
      );
    });

    test('address and contact validation permit optional address lines', () {
      expect(
        RegistrationWizardSteps.validate(
          RegistrationWizardStep.address,
          role: 'worker',
          addressLine1: '12 High Street',
          townCity: 'London',
          postcode: 'SW1A 1AA',
          country: 'United Kingdom',
        ),
        isNull,
      );
      expect(
        RegistrationWizardSteps.validate(
          RegistrationWizardStep.address,
          role: 'worker',
          addressLine1: '12 High Street',
          townCity: 'London',
          postcode: 'invalid',
          country: 'United Kingdom',
        ),
        isNotNull,
      );
      expect(
        RegistrationWizardSteps.validate(
          RegistrationWizardStep.email,
          role: 'worker',
          email: 'someone@example.com',
        ),
        isNull,
      );
      expect(
        RegistrationWizardSteps.validate(
          RegistrationWizardStep.phone,
          role: 'worker',
          phone: '+44 7700 900123',
        ),
        isNull,
      );
    });

    test('verification stages block Next until genuine verification', () {
      expect(ProfileCompletionStep.emailVerification.optional, isFalse);
      expect(ProfileCompletionStep.phoneVerification.optional, isFalse);
      expect(ProfileCompletionStep.optionalDetails.optional, isTrue);
      expect(
        ProfileCompletionStep.emailVerification.canContinue(
          emailVerified: false,
          phoneVerified: true,
        ),
        isFalse,
      );
      expect(
        ProfileCompletionStep.phoneVerification.canContinue(
          emailVerified: true,
          phoneVerified: false,
        ),
        isFalse,
      );
      expect(
        ProfileCompletionStep.phoneVerification.canContinue(
          emailVerified: true,
          phoneVerified: true,
        ),
        isTrue,
      );
      expect(
        ProfileCompletionStep.optionalDetails.canContinue(
          emailVerified: true,
          phoneVerified: true,
        ),
        isTrue,
      );
    });

    test('pending worker and employer details preserve values across steps',
        () {
      for (final role in ['worker', 'employer']) {
        final details = PendingRegistrationDetails(
          email: 'Test@Example.com',
          role: role,
          registrationName: 'Alex Morgan',
          firstName: 'Alex',
          lastName: 'Morgan',
          trade: role == 'worker' ? 'Fixer' : '',
          companyName: role == 'employer' ? 'Example Builders Ltd' : '',
          phone: '+447700900123',
          normalizedPhone: '+447700900123',
          address: const PostalAddress(
            addressLine1: '12 High Street',
            townCity: 'London',
            postcode: 'SW1A 1AA',
            country: 'United Kingdom',
          ),
        );
        final data = details.toUserDocument();
        expect(data['registrationFirstName'], 'Alex');
        expect(data['registrationLastName'], 'Morgan');
        expect(data['addressLine1'], '12 High Street');
        expect(data['postcode'], 'SW1A 1AA');
        expect(data['emailVerified'], isFalse);
        expect(data['phoneVerified'], isFalse);
        expect(data['profileComplete'], isFalse);
        expect(data['companyName'], isNull);
        if (role == 'worker') {
          expect(data['registrationPosition'], 'Fixer');
        } else {
          expect(data['registrationCompanyName'], 'Example Builders Ltd');
        }
      }
    });

    test('legacy pending registration remains supported', () {
      const details = PendingRegistrationDetails(
        email: 'old@example.com',
        role: 'worker',
        registrationName: 'Old Account',
        phone: '+447700900123',
        normalizedPhone: '+447700900123',
      );
      final data = details.toUserDocument();
      expect(data['registrationName'], 'Old Account');
      expect(data.containsKey('registrationFirstName'), isFalse);
      expect(data.containsKey('addressLine1'), isFalse);
    });
  });
}
