import 'package:firebase_auth/firebase_auth.dart';

import '../../services/social_auth_service.dart';

class WebPasswordSignIn {
  const WebPasswordSignIn();

  Future<void> call({required String email, required String password}) async {
    final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final user = credential.user;
    if (user == null) return;
    try {
      await SocialAuthService.linkAfterVerifiedPasswordSignIn(user);
    } catch (_) {
      // Optional account linking cannot invalidate a successful password login.
    }
  }
}
