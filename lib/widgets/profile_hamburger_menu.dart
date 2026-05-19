import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io';

import '../screens/edit_profile_screen.dart';
import '../screens/login_screen.dart';
import '../services/auth_preferences_service.dart';
import '../services/billing_service.dart';
import '../services/notification_service.dart';
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

  static Stream<int> unreadAdminInboxCountStream(String uid) {
    return FirebaseFirestore.instance
        .collection("admin_messages")
        .where("receiverId", isEqualTo: uid)
        .where("readByReceiver", isEqualTo: false)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .where((doc) => doc.data()["deletedByReceiver"] != true)
            .length);
  }

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
                  if (uid == null)
                    _MenuTile(
                      icon: Icons.mark_email_unread_outlined,
                      title: "Inbox from Admin",
                      onTap: () {},
                    )
                  else
                    StreamBuilder<int>(
                      stream:
                          ProfileHamburgerMenu.unreadAdminInboxCountStream(uid),
                      builder: (context, snapshot) {
                        final unread = snapshot.data ?? 0;
                        return _MenuTile(
                          icon: Icons.mark_email_unread_outlined,
                          title: "Inbox from Admin",
                          badgeCount: unread,
                          onTap: () {
                            Navigator.pop(context);
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

class ProfileHamburgerButton extends StatelessWidget {
  const ProfileHamburgerButton({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return IconButton(
        tooltip: "Menu",
        icon: const Icon(Icons.menu),
        onPressed: () => Scaffold.of(context).openDrawer(),
      );
    }

    return StreamBuilder<int>(
      stream: ProfileHamburgerMenu.unreadAdminInboxCountStream(uid),
      builder: (context, snapshot) {
        final unread = snapshot.data ?? 0;
        return IconButton(
          tooltip: "Menu",
          icon: Badge(
            isLabelVisible: unread > 0,
            label: Text(unread > 9 ? "9+" : unread.toString()),
            child: const Icon(Icons.menu),
          ),
          onPressed: () => Scaffold.of(context).openDrawer(),
        );
      },
    );
  }
}

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final bool danger;
  final int badgeCount;

  const _MenuTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.danger = false,
    this.badgeCount = 0,
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
      trailing: badgeCount > 0
          ? Badge.count(
              count: badgeCount,
              backgroundColor: AppColors.danger,
            )
          : null,
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
  bool savingNotificationPreference = false;

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

  Map<String, bool> notificationPrefsFromUserData(Map<String, dynamic> data) {
    final settings = data["settings"] is Map
        ? Map<String, dynamic>.from(data["settings"])
        : <String, dynamic>{};
    final raw = settings["notifications"] is Map
        ? Map<String, dynamic>.from(settings["notifications"])
        : data["notificationPreferences"] is Map
            ? Map<String, dynamic>.from(data["notificationPreferences"])
            : <String, dynamic>{};

    return {
      for (final entry in NotificationService.defaultPreferences.entries)
        entry.key:
            raw[entry.key] is bool ? raw[entry.key] as bool : entry.value,
    };
  }

  Future<void> saveNotificationSetting(String key, bool value) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() => savingNotificationPreference = true);
    try {
      await NotificationService().saveNotificationPreference(
        userId: uid,
        key: key,
        value: value,
      );
      await NotificationService().syncUnreadBadgeCount(uid);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Notification setting saved")),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not save notification setting")),
      );
    } finally {
      if (mounted) setState(() => savingNotificationPreference = false);
    }
  }

  Widget buildNotificationSwitch({
    required String title,
    required String subtitle,
    required String keyName,
    required Map<String, bool> preferences,
  }) {
    final enabled = preferences["enabled"] != false;
    final isGlobal = keyName == "enabled";
    return SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      subtitle: Text(subtitle),
      value: preferences[keyName] != false,
      onChanged: savingNotificationPreference || (!enabled && !isGlobal)
          ? null
          : (value) => saveNotificationSetting(keyName, value),
    );
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
            final notificationPreferences = notificationPrefsFromUserData(data);

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
                        icon: Icons.login,
                        title: "Simple Enter",
                        subtitle:
                            "Show an Enter button on launch when your Firebase session is still valid. Password remains the fallback.",
                        value: AuthPreferenceMethod.simpleEnter,
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
                const SizedBox(height: 12),
                StroykaSurface(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _SectionTitle("Notification preferences"),
                      const Text(
                        "Choose which phone alerts, sounds and app badge counts are enabled for this account.",
                      ),
                      if (savingNotificationPreference) ...[
                        const SizedBox(height: 10),
                        const LinearProgressIndicator(minHeight: 2),
                      ],
                      const SizedBox(height: 8),
                      buildNotificationSwitch(
                        title: "All notifications",
                        subtitle: "Master switch for phone push alerts.",
                        keyName: "enabled",
                        preferences: notificationPreferences,
                      ),
                      buildNotificationSwitch(
                        title: "Job alerts",
                        subtitle: "New matching jobs and job updates.",
                        keyName: "jobAlerts",
                        preferences: notificationPreferences,
                      ),
                      buildNotificationSwitch(
                        title: "Application updates",
                        subtitle: "Application status changes and decisions.",
                        keyName: "applicationUpdates",
                        preferences: notificationPreferences,
                      ),
                      buildNotificationSwitch(
                        title: "Offers",
                        subtitle:
                            "New offers, accepted offers and rejected offers.",
                        keyName: "offers",
                        preferences: notificationPreferences,
                      ),
                      buildNotificationSwitch(
                        title: "Messages and chats",
                        subtitle: "Unread chat message alerts.",
                        keyName: "messages",
                        preferences: notificationPreferences,
                      ),
                      buildNotificationSwitch(
                        title: "Admin messages",
                        subtitle: "Inbox from Admin and official notices.",
                        keyName: "adminMessages",
                        preferences: notificationPreferences,
                      ),
                      buildNotificationSwitch(
                        title: "Billing notifications",
                        subtitle:
                            "Invoices, payment reminders and plan updates.",
                        keyName: "billing",
                        preferences: notificationPreferences,
                      ),
                      buildNotificationSwitch(
                        title: "Support replies",
                        subtitle: "Replies and updates for support requests.",
                        keyName: "supportReplies",
                        preferences: notificationPreferences,
                      ),
                      buildNotificationSwitch(
                        title: "Policy/document updates",
                        subtitle: "Required legal document and policy updates.",
                        keyName: "policyUpdates",
                        preferences: notificationPreferences,
                      ),
                      buildNotificationSwitch(
                        title: "Sound",
                        subtitle: "Play sound for eligible push notifications.",
                        keyName: "sound",
                        preferences: notificationPreferences,
                      ),
                      buildNotificationSwitch(
                        title: "Badge counts",
                        subtitle:
                            "Show unread count on the app icon when supported.",
                        keyName: "badges",
                        preferences: notificationPreferences,
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

class AdminInboxScreen extends StatefulWidget {
  final String userId;
  final String role;

  const AdminInboxScreen({
    super.key,
    required this.userId,
    required this.role,
  });

  @override
  State<AdminInboxScreen> createState() => _AdminInboxScreenState();
}

class _AdminInboxScreenState extends State<AdminInboxScreen>
    with SingleTickerProviderStateMixin {
  late final TabController tabController;

  @override
  void initState() {
    super.initState();
    tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    tabController.dispose();
    super.dispose();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> streamFor(String mailbox) {
    final base = FirebaseFirestore.instance.collection("admin_messages");
    if (mailbox == "sent") {
      return base
          .where("senderId", isEqualTo: widget.userId)
          .orderBy("createdAt", descending: true)
          .snapshots();
    }
    if (mailbox == "deleted") {
      return base
          .where("threadParticipants", arrayContains: widget.userId)
          .snapshots();
    }
    return base
        .where("receiverId", isEqualTo: widget.userId)
        .orderBy("createdAt", descending: true)
        .snapshots();
  }

  Widget buildMailbox(String mailbox) {
    return StroykaSurface(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: streamFor(mailbox),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text("Could not load inbox messages"));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final threads = _UserAdminMailThread.group(
            snapshot.data!.docs,
            mailbox: mailbox,
            userId: widget.userId,
          );
          if (threads.isEmpty) {
            return Center(
              child: Text(
                mailbox == "incoming"
                    ? "No incoming admin mail yet"
                    : mailbox == "sent"
                        ? "No sent admin mail yet"
                        : "No deleted admin mail",
              ),
            );
          }

          return ListView.separated(
            itemCount: threads.length,
            separatorBuilder: (_, __) => Divider(
              height: 1,
              color: AppColors.muted.withValues(alpha: 0.18),
            ),
            itemBuilder: (context, index) {
              return _UserAdminMailRow(
                thread: threads[index],
                userId: widget.userId,
                role: widget.role,
              );
            },
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Inbox from Admin"),
        bottom: TabBar(
          controller: tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelStyle: AppTypography.tab,
          unselectedLabelStyle: AppTypography.tabUnselected,
          labelPadding: const EdgeInsets.symmetric(horizontal: 20),
          tabs: [
            Tab(
              height: 48,
              child: StreamBuilder<int>(
                stream: ProfileHamburgerMenu.unreadAdminInboxCountStream(
                  widget.userId,
                ),
                builder: (context, snapshot) {
                  final count = snapshot.data ?? 0;
                  return Badge(
                    isLabelVisible: count > 0,
                    label: Text(count > 9 ? "9+" : count.toString()),
                    child: const Text("Incoming"),
                  );
                },
              ),
            ),
            const Tab(height: 48, text: "Sent"),
            const Tab(height: 48, text: "Deleted"),
          ],
        ),
      ),
      body: StroykaScreenBody(
        child: TabBarView(
          controller: tabController,
          children: [
            buildMailbox("incoming"),
            buildMailbox("sent"),
            buildMailbox("deleted"),
          ],
        ),
      ),
    );
  }
}

class _UserAdminMailThread {
  final String key;
  final String userId;
  final String normalizedSubject;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  final QueryDocumentSnapshot<Map<String, dynamic>> latestDoc;
  final String mailbox;

  const _UserAdminMailThread({
    required this.key,
    required this.userId,
    required this.normalizedSubject,
    required this.docs,
    required this.latestDoc,
    required this.mailbox,
  });

  bool get unread => docs.any((doc) {
        final data = doc.data();
        return data["receiverId"] == userId &&
            data["readByReceiver"] != true &&
            data["deletedByReceiver"] != true;
      });

  bool get important =>
      docs.any((doc) => doc.data()["importantForReceiver"] == true);

  List<DocumentReference<Map<String, dynamic>>> get unreadRefs => docs
      .where((doc) {
        final data = doc.data();
        return data["receiverId"] == userId &&
            data["readByReceiver"] != true &&
            data["deletedByReceiver"] != true;
      })
      .map((doc) => doc.reference)
      .toList();

  static List<_UserAdminMailThread> group(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, {
    required String mailbox,
    required String userId,
  }) {
    final grouped =
        <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};

    for (final doc in docs) {
      final data = doc.data();
      final isReceived = data["receiverId"] == userId;
      final isSent = data["senderId"] == userId;
      final deleted = isReceived
          ? data["deletedByReceiver"] == true
          : data["deletedBySender"] == true;
      if (mailbox == "deleted") {
        if (!deleted) continue;
      } else if (deleted) {
        continue;
      }
      if (mailbox == "incoming" && !isReceived) continue;
      if (mailbox == "sent" && !isSent) continue;

      final participant = isSent
          ? (data["receiverId"]?.toString() ?? "admin")
          : (data["senderId"]?.toString() ?? "admin");
      final subject = _userAdminMailNormalizeSubject(data["subject"]);
      final key = "$participant::$subject";
      grouped.putIfAbsent(key, () => []).add(doc);
    }

    final threads = <_UserAdminMailThread>[];
    for (final entry in grouped.entries) {
      final threadDocs = entry.value..sort(_compareUserAdminMailDocs);
      threads.add(
        _UserAdminMailThread(
          key: entry.key,
          userId: userId,
          normalizedSubject: entry.key.split("::").skip(1).join("::"),
          docs: List.unmodifiable(threadDocs),
          latestDoc: threadDocs.last,
          mailbox: mailbox,
        ),
      );
    }
    threads.sort((a, b) => _compareUserAdminMailDocs(b.latestDoc, a.latestDoc));
    return threads;
  }
}

int _compareUserAdminMailDocs(
  QueryDocumentSnapshot<Map<String, dynamic>> a,
  QueryDocumentSnapshot<Map<String, dynamic>> b,
) {
  return (_userAdminMailDate(a.data()) ??
          DateTime.fromMillisecondsSinceEpoch(0))
      .compareTo(
    _userAdminMailDate(b.data()) ?? DateTime.fromMillisecondsSinceEpoch(0),
  );
}

DateTime? _userAdminMailDate(Map<String, dynamic> data) {
  final value = data["createdAt"];
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}

String _userAdminMailNormalizeSubject(dynamic value) {
  var subject = value?.toString().trim() ?? "No subject";
  final prefix = RegExp(r"^(re|fw|fwd)\s*:\s*", caseSensitive: false);
  while (prefix.hasMatch(subject)) {
    subject = subject.replaceFirst(prefix, "").trim();
  }
  return subject.isEmpty ? "no subject" : subject.toLowerCase();
}

String _userAdminMailDisplaySubject(dynamic value) {
  final normalized = _userAdminMailNormalizeSubject(value);
  if (normalized == "no subject") return "No subject";
  return normalized
      .split(" ")
      .map((word) => word.isEmpty
          ? word
          : "${word[0].toUpperCase()}${word.length > 1 ? word.substring(1) : ""}")
      .join(" ");
}

String _userAdminMailTimeLabel(DateTime? date) {
  if (date == null) return "";
  final now = DateTime.now();
  if (date.year == now.year && date.month == now.month && date.day == now.day) {
    return "${date.hour.toString().padLeft(2, "0")}:${date.minute.toString().padLeft(2, "0")}";
  }
  return "${date.day.toString().padLeft(2, "0")}/${date.month.toString().padLeft(2, "0")}";
}

IconData _userAdminMailAttachmentIcon(String type) {
  final normalized = type.toLowerCase();
  if (normalized.contains("image") ||
      ["jpg", "jpeg", "png", "gif", "webp"].contains(normalized)) {
    return Icons.image_outlined;
  }
  if (normalized.contains("pdf")) return Icons.picture_as_pdf_outlined;
  if (normalized.contains("doc")) return Icons.description_outlined;
  if (normalized.contains("video") || normalized == "mp4") {
    return Icons.video_file_outlined;
  }
  if (normalized.contains("audio") || normalized == "mp3") {
    return Icons.audio_file_outlined;
  }
  if (normalized.contains("zip") || normalized.contains("archive")) {
    return Icons.folder_zip_outlined;
  }
  return Icons.attach_file;
}

class _UserAdminMailRow extends StatelessWidget {
  final _UserAdminMailThread thread;
  final String userId;
  final String role;

  const _UserAdminMailRow({
    required this.thread,
    required this.userId,
    required this.role,
  });

  @override
  Widget build(BuildContext context) {
    final data = thread.latestDoc.data();
    final unread = thread.unread;
    final important = thread.important;
    final subject = _userAdminMailDisplaySubject(data["subject"]);
    final message = data["message"]?.toString() ?? "";
    final createdAt = _userAdminMailDate(data);
    final attachments = thread.docs
        .expand((doc) =>
            (doc.data()["attachments"] as List?)?.whereType<Map>() ??
            const Iterable<Map>.empty())
        .toList();
    final displayName = data["senderId"] == userId
        ? (data["receiverName"]?.toString() ?? "Admin")
        : (data["senderName"]?.toString() ?? "Admin");

    return InkWell(
      onTap: () async {
        if (unread) {
          for (final ref in thread.unreadRefs) {
            await _markUserAdminMailRead(ref);
          }
          await _markUserAdminMailNotificationsRead(
            userId: userId,
            threadId: data["threadId"]?.toString() ?? thread.latestDoc.id,
          );
        }
        if (!context.mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => AdminInboxMessageScreen(
              userId: userId,
              role: role,
              threadId: data["threadId"]?.toString() ?? thread.latestDoc.id,
              initialMessageId: thread.latestDoc.id,
              normalizedSubject: thread.normalizedSubject,
            ),
          ),
        );
      },
      onLongPress: () => _showUserAdminMailActions(
        context,
        thread.latestDoc.reference,
        unread: unread,
        important: important,
        deleted: data["deletedByReceiver"] == true,
      ),
      child: Container(
        color: unread
            ? AppColors.blueprintLine.withValues(alpha: 0.12)
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(
                important ? Icons.star : Icons.star_border,
                color: important ? AppColors.warning : AppColors.muted,
              ),
              onPressed: () => _toggleUserAdminMailImportant(
                thread.latestDoc.reference,
                important,
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.ink,
                  fontWeight: unread ? FontWeight.w900 : FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          thread.docs.length > 1
                              ? "$subject (${thread.docs.length})"
                              : subject,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.ink,
                            fontWeight:
                                unread ? FontWeight.w900 : FontWeight.w700,
                          ),
                        ),
                      ),
                      if (attachments.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.attach_file,
                          size: 16,
                          color: AppColors.greenDark,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    message,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.muted,
                      fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 52,
              child: Text(
                _userAdminMailTimeLabel(createdAt),
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: AppColors.muted,
                  fontSize: 12,
                  fontWeight: unread ? FontWeight.w900 : FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AdminInboxMessageScreen extends StatelessWidget {
  final String userId;
  final String role;
  final String threadId;
  final String initialMessageId;
  final String? normalizedSubject;

  const AdminInboxMessageScreen({
    super.key,
    required this.userId,
    required this.role,
    required this.threadId,
    required this.initialMessageId,
    this.normalizedSubject,
  });

  Future<void> reply(BuildContext context, Map<String, dynamic> source) async {
    if (source["canReply"] == false) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Informational message. Reply is not available."),
        ),
      );
      return;
    }
    final draft = await _showUserAdminReplyComposer(context);
    if (draft == null) return;
    if (draft.message.trim().isEmpty && draft.attachments.isEmpty) return;

    final userDoc =
        await FirebaseFirestore.instance.collection("users").doc(userId).get();
    final data = userDoc.data() ?? {};
    final senderName = (role == "employer"
                ? data["companyName"] ?? data["name"]
                : data["name"] ?? data["displayName"])
            ?.toString() ??
        "User";
    final subject = source["subject"]?.toString() ?? "Admin message";
    final message = draft.message.trim();
    await FirebaseFirestore.instance.collection("admin_messages").add({
      "threadId": threadId,
      "direction": "incoming",
      "senderId": userId,
      "senderName": senderName,
      "senderRole": role,
      "receiverId": "admin",
      "receiverName": "Admin",
      "receiverRole": "admin",
      "threadParticipants": [userId, "admin"],
      "subject":
          subject.toLowerCase().startsWith("re:") ? subject : "RE: $subject",
      "message": message,
      "type": "admin_message",
      "readByAdmin": false,
      "readByReceiver": true,
      "deletedByAdmin": false,
      "deletedBySender": false,
      "deletedByReceiver": false,
      "attachments": draft.attachments,
      "hasAttachments": draft.attachments.isNotEmpty,
      if (source["relatedTargetType"] != null)
        "relatedTargetType": source["relatedTargetType"],
      if (source["relatedTargetId"] != null)
        "relatedTargetId": source["relatedTargetId"],
      if (source["relatedSupportRequestId"] != null)
        "relatedSupportRequestId": source["relatedSupportRequestId"],
      if (source["relatedBillingRequestId"] != null)
        "relatedBillingRequestId": source["relatedBillingRequestId"],
      "createdAt": FieldValue.serverTimestamp(),
    });
    for (final attachment in draft.attachments) {
      await FirebaseFirestore.instance.collection("message_attachments").add({
        ...attachment,
        "threadId": threadId,
        "senderId": userId,
        "senderRole": role,
        "createdAt": FieldValue.serverTimestamp(),
      });
    }
    await FirebaseFirestore.instance
        .collection("message_threads")
        .doc(threadId)
        .set({
      "lastMessage": message,
      "lastMessageAt": FieldValue.serverTimestamp(),
      "lastSenderId": userId,
      "unreadForAdmin": FieldValue.increment(1),
      "updatedAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await FirebaseFirestore.instance
        .collection("unread_counters")
        .doc("admin")
        .set({
      "unreadInbox": FieldValue.increment(1),
      "updatedAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Reply sent")),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Admin mail")),
      body: StroykaScreenBody(
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection("admin_messages")
              .where("threadId", isEqualTo: threadId)
              .where("receiverId", isEqualTo: userId)
              .snapshots(),
          builder: (context, incomingSnapshot) {
            if (incomingSnapshot.hasError) {
              return const Center(child: Text("Could not load message thread"));
            }
            if (!incomingSnapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection("admin_messages")
                  .where("threadId", isEqualTo: threadId)
                  .where("senderId", isEqualTo: userId)
                  .snapshots(),
              builder: (context, sentSnapshot) {
                if (sentSnapshot.hasError) {
                  return const Center(
                    child: Text("Could not load message thread"),
                  );
                }
                if (!sentSnapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = [
                  ...incomingSnapshot.data!.docs.where(
                    (doc) => doc.data()["deletedByReceiver"] != true,
                  ),
                  ...sentSnapshot.data!.docs.where(
                    (doc) => doc.data()["deletedBySender"] != true,
                  ),
                ]..sort(_compareUserAdminMailDocs);
                if (docs.isEmpty) {
                  return const Center(child: Text("Message thread not found"));
                }
                final first = docs.first.data();
                var selectedDoc = docs.last;
                for (final doc in docs) {
                  if (doc.id == initialMessageId) selectedDoc = doc;
                }
                final selectedData = selectedDoc.data();
                final canReply = selectedData["canReply"] != false;
                final unreadRefs = docs.where((doc) {
                  final data = doc.data();
                  return data["receiverId"] == userId &&
                      data["readByReceiver"] != true &&
                      data["deletedByReceiver"] != true;
                }).map((doc) => doc.reference);
                if (unreadRefs.isNotEmpty) {
                  WidgetsBinding.instance.addPostFrameCallback((_) async {
                    for (final ref in unreadRefs) {
                      await _markUserAdminMailRead(ref);
                    }
                    await _markUserAdminMailNotificationsRead(
                      userId: userId,
                      threadId: threadId,
                    );
                  });
                }

                return ListView(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
                  children: [
                    StroykaSurface(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const CircleAvatar(
                                radius: 24,
                                backgroundColor: Color(0x297DB9D8),
                                child: Icon(
                                  Icons.admin_panel_settings_outlined,
                                  color: AppColors.greenDark,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _userAdminMailDisplaySubject(
                                    first["subject"],
                                  ),
                                  style: const TextStyle(
                                    color: AppColors.ink,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              _UserAdminMailThreadMenu(
                                source: selectedData,
                                selectedRef: selectedDoc.reference,
                                userId: userId,
                                role: role,
                                onReply: () => reply(context, selectedData),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (!canReply) ...[
                      const SizedBox(height: 10),
                      const StroykaSurface(
                        padding: EdgeInsets.all(12),
                        child: Text(
                          "Informational message. Reply is not available.",
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    ...docs.map((doc) => _UserAdminMailMessageCard(
                          doc: doc,
                          selected: doc.id == selectedDoc.id,
                        )),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _UserAdminMailMessageCard extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final bool selected;

  const _UserAdminMailMessageCard({
    required this.doc,
    required this.selected,
  });

  @override
  Widget build(BuildContext context) {
    final data = doc.data();
    final sender = data["senderName"]?.toString() ?? "Sender";
    final receiver = data["receiverName"]?.toString() ?? "Receiver";
    final senderRole = data["senderRole"]?.toString() ?? "";
    final senderId = data["senderId"]?.toString() ?? "";
    final message = data["message"]?.toString() ?? "";
    final createdAt = _userAdminMailDate(data);
    final attachments =
        (data["attachments"] as List?)?.whereType<Map>().toList() ?? [];

    return StroykaSurface(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: const Color(0x297DB9D8),
                child: Icon(
                  senderRole == "admin"
                      ? Icons.admin_panel_settings_outlined
                      : Icons.person_outline,
                  color: AppColors.greenDark,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sender,
                      style: const TextStyle(
                        color: AppColors.ink,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      "To $receiver • ${BillingService.formatLabel(senderRole)}"
                      "${senderId.isNotEmpty ? " • $senderId" : ""}",
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                _userAdminMailTimeLabel(createdAt),
                style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          if (selected) ...[
            const SizedBox(height: 8),
            const Chip(label: Text("Opened")),
          ],
          const SizedBox(height: 12),
          SelectableText(message),
          if (attachments.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: attachments.map((attachment) {
                final name = (attachment["name"] ?? attachment["fileName"])
                        ?.toString() ??
                    "Attachment";
                final type = (attachment["type"] ?? attachment["fileType"])
                        ?.toString()
                        .trim() ??
                    "";
                final url = (attachment["url"] ?? attachment["fileUrl"])
                        ?.toString()
                        .trim() ??
                    "";
                return ActionChip(
                  avatar: Icon(_userAdminMailAttachmentIcon(type), size: 18),
                  label: Text(name, overflow: TextOverflow.ellipsis),
                  onPressed: url.isEmpty
                      ? null
                      : () async {
                          final uri = Uri.tryParse(url);
                          if (uri == null) return;
                          await launchUrl(
                            uri,
                            mode: LaunchMode.externalApplication,
                          );
                        },
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }
}

class _UserAdminMailThreadMenu extends StatelessWidget {
  final Map<String, dynamic> source;
  final DocumentReference<Map<String, dynamic>> selectedRef;
  final String userId;
  final String role;
  final VoidCallback onReply;

  const _UserAdminMailThreadMenu({
    required this.source,
    required this.selectedRef,
    required this.userId,
    required this.role,
    required this.onReply,
  });

  @override
  Widget build(BuildContext context) {
    final canReply = source["canReply"] != false;
    return PopupMenuButton<String>(
      tooltip: "Mail actions",
      icon: const Icon(Icons.more_horiz, color: AppColors.ink),
      onSelected: (value) async {
        if (value == "reply") {
          onReply();
          return;
        }
        if (value == "forward") {
          onReply();
          return;
        }
        if (value == "unread") {
          await _markUserAdminMailUnread(selectedRef);
          if (context.mounted) Navigator.pop(context);
          return;
        }
        if (value == "delete") {
          await _deleteUserAdminMail(selectedRef, userId);
          if (context.mounted) Navigator.pop(context);
        }
      },
      itemBuilder: (context) => [
        if (canReply)
          const PopupMenuItem(
            value: "reply",
            child: ListTile(
              leading: Icon(Icons.reply),
              title: Text("Reply"),
              dense: true,
            ),
          ),
        const PopupMenuItem(
          value: "forward",
          child: ListTile(
            leading: Icon(Icons.forward),
            title: Text("Forward"),
            dense: true,
          ),
        ),
        const PopupMenuItem(
          value: "unread",
          child: ListTile(
            leading: Icon(Icons.mark_email_unread_outlined),
            title: Text("Mark unread"),
            dense: true,
          ),
        ),
        const PopupMenuItem(
          value: "delete",
          child: ListTile(
            leading: Icon(Icons.delete_outline),
            title: Text("Delete"),
            dense: true,
          ),
        ),
      ],
    );
  }
}

class _UserAdminReplyDraft {
  final String message;
  final List<Map<String, dynamic>> attachments;

  const _UserAdminReplyDraft({
    required this.message,
    required this.attachments,
  });
}

Future<_UserAdminReplyDraft?> _showUserAdminReplyComposer(
  BuildContext context,
) async {
  return showModalBottomSheet<_UserAdminReplyDraft>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => Padding(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        top: 12,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 12,
      ),
      child: const SingleChildScrollView(
        child: _UserAdminReplyComposer(),
      ),
    ),
  );
}

class _UserAdminReplyComposer extends StatefulWidget {
  const _UserAdminReplyComposer();

  @override
  State<_UserAdminReplyComposer> createState() =>
      _UserAdminReplyComposerState();
}

class _UserAdminReplyComposerState extends State<_UserAdminReplyComposer> {
  final messageController = TextEditingController();
  final attachments = <PlatformFile>[];
  bool sending = false;

  @override
  void dispose() {
    messageController.dispose();
    super.dispose();
  }

  Future<void> pickAttachments() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: false,
      type: FileType.any,
    );
    if (result == null || result.files.isEmpty || !mounted) return;
    setState(() {
      final existing = attachments.map((file) => file.name).toSet();
      attachments.addAll(
        result.files.where((file) => !existing.contains(file.name)),
      );
    });
  }

  Future<void> send() async {
    final message = messageController.text.trim();
    if (message.isEmpty && attachments.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Write a message or attach a file")),
      );
      return;
    }

    setState(() => sending = true);
    try {
      final uploaded = await _uploadUserAdminReplyFiles(attachments);
      if (!mounted) return;
      Navigator.pop(
        context,
        _UserAdminReplyDraft(
          message: message,
          attachments: uploaded,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not upload attachments")),
      );
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StroykaSurface(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            "Reply to Admin",
            style: TextStyle(
              color: AppColors.ink,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: messageController,
            enabled: !sending,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(
              labelText: "Message",
              hintText: "Write your reply",
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: sending ? null : pickAttachments,
                icon: const Icon(Icons.attach_file),
                label: const Text("Attach files"),
              ),
              ...attachments.map(
                (file) => InputChip(
                  avatar: Icon(_userAdminMailAttachmentIcon(
                    file.extension ?? "",
                  )),
                  label: Text(file.name, overflow: TextOverflow.ellipsis),
                  onDeleted: sending
                      ? null
                      : () => setState(() => attachments.remove(file)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: sending ? null : () => Navigator.pop(context),
                  child: const Text("Cancel"),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: sending ? null : send,
                  icon: sending
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                  label: Text(sending ? "Sending..." : "Send"),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Future<List<Map<String, dynamic>>> _uploadUserAdminReplyFiles(
  List<PlatformFile> files,
) async {
  final uploaded = <Map<String, dynamic>>[];
  final uid = FirebaseAuth.instance.currentUser?.uid ?? "user";
  for (final file in files) {
    final path = file.path;
    if (path == null || path.isEmpty) continue;

    final name = file.name.isNotEmpty
        ? file.name
        : "attachment_${DateTime.now().microsecondsSinceEpoch}";
    final safeName = name.replaceAll(RegExp(r"[^A-Za-z0-9._-]"), "_");
    final extension =
        name.contains(".") ? name.split(".").last.toLowerCase() : "";
    final ref = FirebaseStorage.instance.ref(
      "admin_mail/$uid/${DateTime.now().microsecondsSinceEpoch}_$safeName",
    );

    await ref.putFile(File(path));
    final url = await ref.getDownloadURL();
    uploaded.add({
      "name": name,
      "fileName": name,
      "url": url,
      "fileUrl": url,
      "type": extension.isEmpty ? "file" : extension,
      "fileType": extension.isEmpty ? "file" : extension,
      "size": file.size,
      "uploadedAt": Timestamp.now(),
      "uploadedBy": uid,
    });
  }
  return uploaded;
}

Future<void> _showUserAdminMailActions(
  BuildContext context,
  DocumentReference<Map<String, dynamic>> ref, {
  required bool unread,
  required bool important,
  required bool deleted,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    builder: (context) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!deleted)
              ListTile(
                leading: Icon(unread
                    ? Icons.mark_email_read_outlined
                    : Icons.mark_email_unread_outlined),
                title: Text(unread ? "Mark as read" : "Mark unread"),
                onTap: () async {
                  Navigator.pop(context);
                  if (unread) {
                    await _markUserAdminMailRead(ref);
                  } else {
                    await _markUserAdminMailUnread(ref);
                  }
                },
              ),
            if (!deleted)
              ListTile(
                leading:
                    Icon(important ? Icons.star_border : Icons.star_outline),
                title: Text(important ? "Remove important" : "Mark important"),
                onTap: () async {
                  Navigator.pop(context);
                  await _toggleUserAdminMailImportant(ref, important);
                },
              ),
            if (!deleted)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text("Delete"),
                onTap: () async {
                  Navigator.pop(context);
                  final uid = FirebaseAuth.instance.currentUser?.uid;
                  if (uid != null) await _deleteUserAdminMail(ref, uid);
                },
              ),
          ],
        ),
      );
    },
  );
}

Future<void> _markUserAdminMailRead(
  DocumentReference<Map<String, dynamic>> ref,
) async {
  await ref.set({
    "readByReceiver": true,
    "readAt": FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
}

Future<void> _markUserAdminMailUnread(
  DocumentReference<Map<String, dynamic>> ref,
) async {
  await ref.set({
    "readByReceiver": false,
    "readAt": FieldValue.delete(),
  }, SetOptions(merge: true));
}

Future<void> _toggleUserAdminMailImportant(
  DocumentReference<Map<String, dynamic>> ref,
  bool important,
) async {
  await ref.set({
    "importantForReceiver": !important,
    "updatedAt": FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
}

Future<void> _deleteUserAdminMail(
  DocumentReference<Map<String, dynamic>> ref,
  String userId,
) async {
  final snap = await ref.get();
  final data = snap.data() ?? {};
  await ref.set({
    data["senderId"] == userId ? "deletedBySender" : "deletedByReceiver": true,
    "deletedAt": FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
}

Future<void> _markUserAdminMailNotificationsRead({
  required String userId,
  required String threadId,
}) async {
  if (userId.trim().isEmpty || threadId.trim().isEmpty) return;
  final snapshot = await FirebaseFirestore.instance
      .collection("users")
      .doc(userId)
      .collection("notifications")
      .where("read", isEqualTo: false)
      .where("threadId", isEqualTo: threadId)
      .get();
  if (snapshot.docs.isEmpty) return;
  final batch = FirebaseFirestore.instance.batch();
  for (final doc in snapshot.docs) {
    batch.set(
        doc.reference,
        {
          "read": true,
          "readAt": FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true));
  }
  await batch.commit();
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
