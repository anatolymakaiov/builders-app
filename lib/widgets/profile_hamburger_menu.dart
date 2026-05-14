import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/job.dart';
import '../screens/application_details_screen.dart';
import '../screens/edit_profile_screen.dart';
import '../screens/employer_profile_screen.dart';
import '../screens/job_details_screen.dart';
import '../screens/login_screen.dart';
import '../services/auth_preferences_service.dart';
import '../services/billing_service.dart';
import '../theme/app_theme.dart';
import '../theme/stroyka_background.dart';
import 'legal_documents.dart';

class ProfileHamburgerMenu extends StatelessWidget {
  final String role;

  const ProfileHamburgerMenu({
    super.key,
    required this.role,
  });

  String? get userId => FirebaseAuth.instance.currentUser?.uid;

  static Future<bool> _confirmDeleteAccount(BuildContext context) async {
    final first = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Are you sure you want to delete your account?"),
        content: const Text(
          "Deleting your account is permanent. All profile data will be deleted from the database where legally possible. Your profile cannot be restored. Only continue if you are sure.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text("Continue"),
          ),
        ],
      ),
    );

    if (first != true || !context.mounted) return false;

    final second = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("This action is permanent and cannot be undone."),
        content: const Text(
          "Your account will be marked as deleted, your profile will be hidden and anonymized, and you will be signed out.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text("Cancel"),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text("Delete account"),
          ),
        ],
      ),
    );

    return second == true;
  }

  static Future<void> _deletePortfolioDocuments(String uid) async {
    final portfolio = await FirebaseFirestore.instance
        .collection("users")
        .doc(uid)
        .collection("portfolio")
        .get();
    if (portfolio.docs.isEmpty) return;

    final batch = FirebaseFirestore.instance.batch();
    for (final doc in portfolio.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }

  static Future<void> _softDeleteAccount(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid;
    if (uid == null) return;

    final confirmed = await _confirmDeleteAccount(context);
    if (!confirmed) return;

    try {
      await _deletePortfolioDocuments(uid);

      await FirebaseFirestore.instance.collection("users").doc(uid).set({
        "accountDeleted": true,
        "profileHidden": true,
        "deletedAt": FieldValue.serverTimestamp(),
        "isOnline": false,
        "lastSeen": FieldValue.serverTimestamp(),
        "name": "Deleted account",
        "companyName": "Deleted account",
        "bio": FieldValue.delete(),
        "about": FieldValue.delete(),
        "phone": FieldValue.delete(),
        "phones": <String>[],
        "location": FieldValue.delete(),
        "website": FieldValue.delete(),
        "contactPerson": FieldValue.delete(),
        "photo": FieldValue.delete(),
        "avatarUrl": FieldValue.delete(),
        "headerImageUrl": FieldValue.delete(),
        "companyPhotos": <String>[],
        "companyGoals": FieldValue.delete(),
        "companyAdvantages": FieldValue.delete(),
        "companyClients": FieldValue.delete(),
        "companyWhoWeAre": FieldValue.delete(),
        "companyHistory": FieldValue.delete(),
      }, SetOptions(merge: true));

      await FirebaseAuth.instance.signOut();

      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
    } on FirebaseAuthException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? "Could not delete account")),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not delete account")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = userId;

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            DrawerHeader(
              margin: EdgeInsets.zero,
              child: Align(
                alignment: Alignment.bottomLeft,
                child: Text(
                  role == "employer" ? "Company Menu" : "Worker Menu",
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _MenuTile(
                    icon: Icons.account_circle_outlined,
                    title: "My Account",
                    onTap: () {
                      Navigator.pop(context);
                      if (uid == null) return;
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => MyAccountScreen(
                            userId: uid,
                            role: role,
                          ),
                        ),
                      );
                    },
                  ),
                  _MenuTile(
                    icon: Icons.settings_outlined,
                    title: "Settings",
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ProfileSettingsScreen(),
                        ),
                      );
                    },
                  ),
                  _MenuTile(
                    icon: Icons.mark_email_unread_outlined,
                    title: "Inbox from Admin",
                    onTap: () {
                      Navigator.pop(context);
                      if (uid == null) return;
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AdminInboxScreen(
                            userId: uid,
                            role: role,
                          ),
                        ),
                      );
                    },
                  ),
                  _MenuTile(
                    icon: Icons.info_outline,
                    title: "About App",
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const AboutAppScreen(),
                        ),
                      );
                    },
                  ),
                  const Divider(),
                  _MenuTile(
                    icon: Icons.logout,
                    title: "Logout",
                    danger: true,
                    onTap: () async {
                      Navigator.pop(context);
                      await FirebaseAuth.instance.signOut();
                    },
                  ),
                  _MenuTile(
                    icon: Icons.delete_forever_outlined,
                    title: "Delete Account",
                    danger: true,
                    onTap: () async {
                      Navigator.pop(context);
                      await _softDeleteAccount(context);
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final bool danger;

  const _MenuTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = danger ? Colors.red : AppColors.ink;

    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(
        title,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
        ),
      ),
      onTap: onTap,
    );
  }
}

class MyAccountScreen extends StatelessWidget {
  final String userId;
  final String role;

  const MyAccountScreen({
    super.key,
    required this.userId,
    required this.role,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("My Account")),
      body: StroykaScreenBody(
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection("users")
              .doc(userId)
              .snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final data = snapshot.data?.data() ?? {};
            final email = FirebaseAuth.instance.currentUser?.email ?? "";
            final billing = BillingService.billingFromUserData(data);
            final isEmployer = role == "employer";
            final accountType = isEmployer ? "Employer" : "Worker";
            final displayName = isEmployer
                ? data["companyName"]?.toString()
                : data["name"]?.toString();
            final phone = data["phone"]?.toString() ?? "";

            return ListView(
              padding: const EdgeInsets.all(12),
              children: [
                StroykaSurface(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SectionTitle(
                          isEmployer ? "Employer account" : "Worker account"),
                      _InfoRow("Account type", accountType),
                      _InfoRow(
                        isEmployer ? "Company name" : "Name",
                        displayName,
                      ),
                      if (!isEmployer && phone.isNotEmpty)
                        _InfoRow("Phone", phone),
                      if (!isEmployer && email.isNotEmpty)
                        _InfoRow("Email", email),
                      if (isEmployer) ...[
                        const SizedBox(height: 12),
                        const _SectionTitle("Billing"),
                        _InfoRow(
                          "Current plan",
                          billing["planName"] ?? billing["planId"],
                        ),
                        _InfoRow(
                          "Plan status",
                          BillingService.formatLabel(
                            billing["status"]?.toString() ?? "not_set",
                          ),
                        ),
                        _InfoRow(
                          "Payment method",
                          BillingService.formatLabel(
                            billing["paymentMode"]?.toString() ?? "not_set",
                          ),
                        ),
                        if (email.isNotEmpty) _InfoRow("Email", email),
                      ],
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const ProfileScreen(),
                              ),
                            );
                          },
                          icon: const Icon(Icons.edit),
                          label: const Text("Edit profile"),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            await FirebaseAuth.instance.signOut();
                          },
                          icon: const Icon(Icons.logout),
                          label: const Text("Logout"),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red),
                          ),
                          onPressed: () async {
                            await ProfileHamburgerMenu._softDeleteAccount(
                              context,
                            );
                          },
                          icon: const Icon(Icons.delete_forever_outlined),
                          label: const Text("Delete account"),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class ProfileSettingsScreen extends StatefulWidget {
  const ProfileSettingsScreen({super.key});

  @override
  State<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends State<ProfileSettingsScreen> {
  final AuthPreferencesService authPreferences = AuthPreferencesService();
  bool savingLanguage = false;
  bool savingAuthMethod = false;

  String languageLabel(String value) {
    switch (value) {
      case "ru":
        return "Russian";
      case "en":
      default:
        return "English";
    }
  }

  Future<void> saveLanguage(String language) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() => savingLanguage = true);
    try {
      await FirebaseFirestore.instance.collection("users").doc(uid).set({
        "settings.language": language,
        "settings.updatedAt": FieldValue.serverTimestamp(),
        "language": language,
      }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Language saved: ${languageLabel(language)}. Full app localization is future-ready.",
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not save language setting")),
      );
    } finally {
      if (mounted) setState(() => savingLanguage = false);
    }
  }

  Widget buildAuthenticationOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required String value,
    required String activeMethod,
  }) {
    final active = value == activeMethod;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      enabled: !savingAuthMethod,
      leading: Icon(
        icon,
        color: active ? AppColors.blueprintLine : AppColors.greenDark,
      ),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      subtitle: Text(subtitle),
      trailing: Icon(
        active ? Icons.check_circle : Icons.radio_button_unchecked,
        color: active ? AppColors.success : AppColors.muted,
      ),
      onTap: savingAuthMethod || active ? null : () => saveAuthMethod(value),
    );
  }

  Future<void> saveAuthMethod(String method) async {
    setState(() => savingAuthMethod = true);
    try {
      final result = await authPreferences.saveCurrentUserMethod(method);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message),
          backgroundColor: result.warning ? Colors.orange.shade800 : null,
        ),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? "Could not save auth setting")),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not save auth setting")),
      );
    } finally {
      if (mounted) setState(() => savingAuthMethod = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      appBar: AppBar(title: const Text("Settings")),
      body: StroykaScreenBody(
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: uid == null
              ? null
              : FirebaseFirestore.instance
                  .collection("users")
                  .doc(uid)
                  .snapshots(),
          builder: (context, snapshot) {
            final data = snapshot.data?.data() ?? {};
            final settings = data["settings"] is Map
                ? Map<String, dynamic>.from(data["settings"])
                : <String, dynamic>{};
            final language =
                (settings["language"] ?? data["language"] ?? "en").toString();
            final activeAuthMethod = authPreferences.methodFromUserData(data);

            return ListView(
              padding: const EdgeInsets.all(12),
              children: [
                StroykaSurface(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _SectionTitle("App language"),
                      Text("Current language: ${languageLabel(language)}"),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: language == "ru" ? "ru" : "en",
                        decoration: const InputDecoration(
                          labelText: "Change language",
                          border: StroykaInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: "en",
                            child: Text("English"),
                          ),
                          DropdownMenuItem(
                            value: "ru",
                            child: Text("Russian"),
                          ),
                        ],
                        onChanged: savingLanguage || uid == null
                            ? null
                            : (value) {
                                if (value == null || value == language) return;
                                saveLanguage(value);
                              },
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        "English remains active for the app interface now. Russian selection is stored for future localization support.",
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                StroykaSurface(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _SectionTitle("Authentication settings"),
                      Text(
                        "Current method: ${AuthPreferenceMethod.label(activeAuthMethod)}",
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      if (savingAuthMethod) ...[
                        const SizedBox(height: 10),
                        const LinearProgressIndicator(minHeight: 2),
                      ],
                      const SizedBox(height: 8),
                      buildAuthenticationOption(
                        icon: Icons.lock_outline,
                        title: "Password login",
                        subtitle:
                            "Use Firebase email and password. This remains available as a safe fallback.",
                        value: AuthPreferenceMethod.password,
                        activeMethod: activeAuthMethod,
                      ),
                      buildAuthenticationOption(
                        icon: Icons.mark_email_read_outlined,
                        title: "Passwordless login",
                        subtitle:
                            "Send an email sign-in link from the login screen when no password is entered.",
                        value: AuthPreferenceMethod.passwordless,
                        activeMethod: activeAuthMethod,
                      ),
                      buildAuthenticationOption(
                        icon: Icons.fingerprint,
                        title: "Biometric login",
                        subtitle:
                            "Validates Face ID / Touch ID availability and keeps password login as fallback.",
                        value: AuthPreferenceMethod.biometric,
                        activeMethod: activeAuthMethod,
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class AdminInboxScreen extends StatelessWidget {
  final String userId;
  final String role;

  const AdminInboxScreen({
    super.key,
    required this.userId,
    required this.role,
  });

  String? cleanId(dynamic value) {
    final text = value?.toString().trim() ?? "";
    if (text.isEmpty || text == "null") return null;
    return text;
  }

  String formatCreatedAt(dynamic value) {
    if (value is Timestamp) {
      final date = value.toDate();
      final day = date.day.toString().padLeft(2, "0");
      final month = date.month.toString().padLeft(2, "0");
      final hour = date.hour.toString().padLeft(2, "0");
      final minute = date.minute.toString().padLeft(2, "0");
      return "$day.$month.${date.year} $hour:$minute";
    }
    return "";
  }

  Future<void> markAsRead(
    DocumentReference<Map<String, dynamic>> ref,
  ) async {
    await ref.set({
      "read": true,
      "readAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> openInboxMessage(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    await markAsRead(doc.reference);

    if (!context.mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdminInboxMessageScreen(
          userId: userId,
          role: role,
          messageId: doc.id,
          initialData: doc.data(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Inbox from Admin")),
      body: StroykaScreenBody(
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection("users")
              .doc(userId)
              .collection("admin_inbox")
              .orderBy("createdAt", descending: true)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Center(
                child: Text("Could not load admin inbox messages"),
              );
            }

            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final docs = snapshot.data!.docs;
            if (docs.isEmpty) {
              return const Center(child: Text("No admin messages"));
            }

            return ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: docs.length,
              itemBuilder: (context, index) {
                final doc = docs[index];
                final data = docs[index].data();
                final read = data["read"] == true;
                final message =
                    (data["message"] ?? data["body"])?.toString() ?? "";
                final createdAt = formatCreatedAt(data["createdAt"]);

                return StroykaSurface(
                  margin: const EdgeInsets.only(bottom: 10),
                  texture: read
                      ? "assets/branding/texture_light_triangles.jpg"
                      : "assets/branding/texture_light_dots.jpg",
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 10,
                    ),
                    title: Text(
                      data["title"]?.toString() ?? "Admin message",
                      style: TextStyle(
                        color: AppColors.ink,
                        fontWeight: read ? FontWeight.w800 : FontWeight.w900,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (message.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            message,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        if (createdAt.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            createdAt,
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!read)
                          const Icon(
                            Icons.circle,
                            size: 10,
                            color: AppColors.green,
                          ),
                        const SizedBox(width: 8),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
                    onTap: () => openInboxMessage(context, doc),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class AdminInboxMessageScreen extends StatelessWidget {
  final String userId;
  final String role;
  final String messageId;
  final Map<String, dynamic> initialData;

  const AdminInboxMessageScreen({
    super.key,
    required this.userId,
    required this.role,
    required this.messageId,
    required this.initialData,
  });

  String? cleanId(dynamic value) {
    final text = value?.toString().trim() ?? "";
    if (text.isEmpty || text == "null") return null;
    return text;
  }

  String valueText(dynamic value) {
    if (value == null) return "";
    if (value is Timestamp) return value.toDate().toString();
    return value.toString();
  }

  bool hasRelatedTarget(Map<String, dynamic> data) {
    return cleanId(data["relatedTargetType"] ?? data["targetType"]) != null ||
        cleanId(data["relatedTargetId"] ?? data["targetId"]) != null ||
        cleanId(data["relatedApplicationId"] ?? data["applicationId"]) !=
            null ||
        cleanId(data["relatedJobId"] ?? data["jobId"]) != null ||
        cleanId(data["relatedPaymentRequestId"]) != null;
  }

  Future<void> openRelatedTarget(
    BuildContext context,
    Map<String, dynamic> data,
  ) async {
    final targetType = cleanId(data["relatedTargetType"] ?? data["targetType"]);
    final targetId = cleanId(data["relatedTargetId"] ?? data["targetId"]);
    final applicationId =
        cleanId(data["relatedApplicationId"] ?? data["applicationId"]);
    final jobId = cleanId(data["relatedJobId"] ?? data["jobId"]);
    final paymentRequestId = cleanId(data["relatedPaymentRequestId"]);

    Future<void> showUnavailable() async {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Related item is no longer available")),
      );
    }

    if (targetType == "application" || applicationId != null) {
      final id = applicationId ?? targetId;
      if (id == null) return showUnavailable();

      final appDoc = await FirebaseFirestore.instance
          .collection("applications")
          .doc(id)
          .get();

      if (!appDoc.exists || appDoc.data() == null) return showUnavailable();

      final appData = appDoc.data()!;
      appData["id"] = appDoc.id;

      if (!context.mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ApplicationDetailsScreen(
            applicationId: id,
            data: appData,
          ),
        ),
      );
      return;
    }

    if (targetType == "job" || jobId != null) {
      final id = jobId ?? targetId;
      if (id == null) return showUnavailable();

      final jobDoc =
          await FirebaseFirestore.instance.collection("jobs").doc(id).get();

      if (!jobDoc.exists || jobDoc.data() == null) return showUnavailable();

      final job = Job.fromFirestore(jobDoc.id, jobDoc.data()!);
      if (!context.mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => JobDetailScreen(job: job)),
      );
      return;
    }

    if (targetType == "billing" ||
        targetType == "payment" ||
        paymentRequestId != null) {
      if (role != "employer") return showUnavailable();

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => EmployerProfileScreen(
            userId: userId,
            initialTab: 4,
          ),
        ),
      );
      return;
    }

    await showUnavailable();
  }

  @override
  Widget build(BuildContext context) {
    final ref = FirebaseFirestore.instance
        .collection("users")
        .doc(userId)
        .collection("admin_inbox")
        .doc(messageId);

    return Scaffold(
      appBar: AppBar(title: const Text("Admin message")),
      body: StroykaScreenBody(
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: ref.snapshots(),
          builder: (context, snapshot) {
            final data = snapshot.data?.data() ?? initialData;
            final title = data["title"]?.toString() ?? "Admin message";
            final message = (data["message"] ?? data["body"])?.toString() ?? "";
            final rows = [
              ("Type", data["type"]),
              ("Created", data["createdAt"]),
              ("Related type", data["relatedTargetType"] ?? data["targetType"]),
              ("Related id", data["relatedTargetId"] ?? data["targetId"]),
            ];

            return ListView(
              padding: const EdgeInsets.all(12),
              children: [
                StroykaSurface(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: AppColors.ink,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      if (message.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        SelectableText(
                          message,
                          style: const TextStyle(
                            color: AppColors.ink,
                            height: 1.45,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      ...rows.map((row) {
                        final value = valueText(row.$2);
                        if (value.isEmpty) return const SizedBox();
                        return _InfoRow(row.$1, value);
                      }),
                      if (hasRelatedTarget(data)) ...[
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () => openRelatedTarget(context, data),
                            icon: const Icon(Icons.open_in_new),
                            label: const Text("Open related item"),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class AboutAppScreen extends StatelessWidget {
  const AboutAppScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("About App")),
      body: StroykaScreenBody(
        child: ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: LegalDocuments.all.length,
          itemBuilder: (context, index) {
            final doc = LegalDocuments.all[index];
            return StroykaSurface(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(
                  doc.title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => LegalDocumentScreen(document: doc),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;

  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.ink,
          fontSize: 16,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final dynamic value;

  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final text = value?.toString().trim() ?? "";
    if (text.isEmpty) return const SizedBox();

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.muted,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: AppColors.ink,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
