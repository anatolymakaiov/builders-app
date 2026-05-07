import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../screens/edit_profile_screen.dart';
import '../services/billing_service.dart';
import '../theme/app_theme.dart';
import '../theme/stroyka_background.dart';

class ProfileHamburgerMenu extends StatelessWidget {
  final String role;

  const ProfileHamburgerMenu({
    super.key,
    required this.role,
  });

  String? get userId => FirebaseAuth.instance.currentUser?.uid;

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
                          builder: (_) => AdminInboxScreen(userId: uid),
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
                      _InfoRow("Name", data["name"] ?? data["companyName"]),
                      _InfoRow("Email", email),
                      _InfoRow("Role", role),
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
                      ],
                      const SizedBox(height: 12),
                      const _SectionTitle("Authentication settings"),
                      const Text(
                        "Password login, passwordless login, and biometric login are prepared for future setup.",
                      ),
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

class ProfileSettingsScreen extends StatelessWidget {
  const ProfileSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Settings")),
      body: StroykaScreenBody(
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: const [
            StroykaSurface(
              padding: EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SectionTitle("App language"),
                  Text(
                    "English is active now. English/Russian localization support is planned for a future release.",
                  ),
                  SizedBox(height: 14),
                  _SectionTitle("Authentication"),
                  Text(
                    "Password login, passwordless login, and biometric login are reserved for future setup.",
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

class AdminInboxScreen extends StatelessWidget {
  final String userId;

  const AdminInboxScreen({
    super.key,
    required this.userId,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Inbox from Admin")),
      body: StroykaScreenBody(
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection("users")
              .doc(userId)
              .collection("notifications")
              .where("type", isEqualTo: "admin_message")
              .orderBy("createdAt", descending: true)
              .snapshots(),
          builder: (context, snapshot) {
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
                final data = docs[index].data();
                return StroykaSurface(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        data["title"]?.toString() ?? "Admin message",
                        style: const TextStyle(
                          color: AppColors.ink,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        (data["message"] ?? data["body"])?.toString() ?? "",
                      ),
                    ],
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

class AboutAppScreen extends StatelessWidget {
  const AboutAppScreen({super.key});

  static const docs = [
    "Privacy Policy",
    "Terms of Use",
    "Code of Conduct",
    "Worker Terms",
    "Employer Posting Policy",
    "Refund Policy",
    "Complaints Policy",
    "Cookie Policy",
    "Data Retention Policy",
    "UK Privacy Notice",
    "Company Information",
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("About App")),
      body: StroykaScreenBody(
        child: ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final title = docs[index];
            return StroykaSurface(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => LegalDocumentScreen(title: title),
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

class LegalDocumentScreen extends StatelessWidget {
  final String title;

  const LegalDocumentScreen({
    super.key,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: const StroykaScreenBody(
        child: Padding(
          padding: EdgeInsets.all(12),
          child: StroykaSurface(
            padding: EdgeInsets.all(18),
            child: Text(
              "This document is reserved for the final legal text. The section is available now so the app structure is ready for publication documents.",
            ),
          ),
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
