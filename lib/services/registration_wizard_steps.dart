enum RegistrationWizardStep {
  accountType,
  identity,
  professionOrCompany,
  address,
  email,
  phone,
  credentials,
}

enum ProfileCompletionStep {
  emailVerification,
  phoneVerification,
  optionalDetails
}

extension ProfileCompletionStepInfo on ProfileCompletionStep {
  bool get optional => this == ProfileCompletionStep.optionalDetails;

  bool canContinue({
    required bool emailVerified,
    required bool phoneVerified,
  }) =>
      switch (this) {
        ProfileCompletionStep.emailVerification => emailVerified,
        ProfileCompletionStep.phoneVerification => phoneVerified,
        ProfileCompletionStep.optionalDetails => true,
      };
}

class RegistrationWizardSteps {
  static int get count => RegistrationWizardStep.values.length;

  static String title(RegistrationWizardStep step, String role) =>
      switch (step) {
        RegistrationWizardStep.accountType => 'Choose your account',
        RegistrationWizardStep.identity => 'Your name',
        RegistrationWizardStep.professionOrCompany =>
          role == 'employer' ? 'Your company' : 'Your trade',
        RegistrationWizardStep.address =>
          role == 'employer' ? 'Company address' : 'Your address',
        RegistrationWizardStep.email => 'Email address',
        RegistrationWizardStep.phone => 'Phone number',
        RegistrationWizardStep.credentials => 'Secure your account',
      };

  static String? validate(
    RegistrationWizardStep step, {
    required String role,
    String firstName = '',
    String lastName = '',
    String trade = '',
    String companyName = '',
    String addressLine1 = '',
    String townCity = '',
    String postcode = '',
    String country = '',
    String email = '',
    String phone = '',
    String password = '',
  }) {
    switch (step) {
      case RegistrationWizardStep.accountType:
        return role == 'worker' || role == 'employer'
            ? null
            : 'Choose Worker or Employer.';
      case RegistrationWizardStep.identity:
        return firstName.trim().isNotEmpty && lastName.trim().isNotEmpty
            ? null
            : 'Enter your first and last name.';
      case RegistrationWizardStep.professionOrCompany:
        return (role == 'employer' ? companyName : trade).trim().isNotEmpty
            ? null
            : role == 'employer'
                ? 'Enter your company name.'
                : 'Enter your profession or trade.';
      case RegistrationWizardStep.address:
        if (addressLine1.trim().isEmpty ||
            townCity.trim().isEmpty ||
            country.trim().isEmpty) {
          return 'Enter Address Line 1, town or city, and country.';
        }
        if (country.trim().toLowerCase() == 'united kingdom' &&
            !RegExp(r'^[A-Z]{1,2}[0-9][0-9A-Z]?\s?[0-9][A-Z]{2}$',
                    caseSensitive: false)
                .hasMatch(postcode.trim())) {
          return 'Enter a valid UK postcode.';
        }
        return null;
      case RegistrationWizardStep.email:
        return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email.trim())
            ? null
            : 'Enter a valid email address.';
      case RegistrationWizardStep.phone:
        return RegExp(r'^\+?[0-9]{10,15}$')
                .hasMatch(phone.replaceAll(RegExp(r'[\s()-]'), ''))
            ? null
            : 'Enter a valid phone number.';
      case RegistrationWizardStep.credentials:
        return password.length >= 6
            ? null
            : 'Enter a password of at least 6 characters, or choose a provider.';
    }
  }
}
