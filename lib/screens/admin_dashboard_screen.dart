import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/job.dart';
import '../services/billing_service.dart';
import '../services/job_alert_service.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';
import '../theme/stroyka_background.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  int selectedIndex = 0;

  Future<void> approveJob(DocumentReference ref, Job job) async {
    final data = {
      "moderationStatus": "approved",
      "moderationReason": "",
      "moderatedAt": FieldValue.serverTimestamp(),
      "updatedAt": FieldValue.serverTimestamp(),
    };

    await BillingService().approveJobAndCountSlot(
      jobRef: ref,
      employerId: job.ownerId,
      moderationData: data,
    );

    await NotificationService().notifyEmployerJobModeration(
      employerId: job.ownerId,
      jobId: job.id,
      jobTitle: job.displayTitle,
      moderationStatus: "approved",
    );

    await JobAlertService().notifyMatchingWorkers(
      jobId: job.id,
      jobData: {
        "title": job.title,
        "trade": job.trade,
        "jobType": job.jobType,
        "lat": job.lat,
        "lng": job.lng,
      },
    );
  }

  Future<bool> rejectJob(
    BuildContext context,
    DocumentReference ref,
  ) async {
    final controller = TextEditingController();

    final reason = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Reject job"),
          content: TextField(
            controller: controller,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: "Moderation reason",
              hintText: "Explain why this job was rejected",
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text("Reject"),
            ),
          ],
        );
      },
    );

    controller.dispose();
    if (reason == null) return false;

    final jobSnap = await ref.get();
    final jobData = jobSnap.data() as Map<String, dynamic>? ?? {};
    final job = Job.fromFirestore(ref.id, jobData);

    await ref.set({
      "moderationStatus": "rejected",
      "moderationReason": reason,
      "moderatedAt": FieldValue.serverTimestamp(),
      "updatedAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await NotificationService().notifyEmployerJobModeration(
      employerId: job.ownerId,
      jobId: job.id,
      jobTitle: job.displayTitle,
      moderationStatus: "rejected",
      reason: reason,
    );

    return true;
  }

  Future<void> openJobModerationDetail(
    BuildContext context,
    DocumentSnapshot doc,
  ) async {
    final data = doc.data() as Map<String, dynamic>;
    final job = Job.fromFirestore(doc.id, data);

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _AdminJobModerationDetailScreen(
          job: job,
          jobRef: doc.reference,
          onApprove: approveJob,
          onReject: rejectJob,
        ),
      ),
    );
  }

  Future<void> updateReportStatus(
    DocumentReference ref,
    String status,
  ) async {
    final reportSnap = await ref.get();
    final reportData =
        reportSnap.data() as Map<String, dynamic>? ?? <String, dynamic>{};

    await ref.set({
      "status": status,
      "updatedAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    final againstUserId = reportData["againstUserId"]?.toString() ?? "";
    if (againstUserId.isNotEmpty) {
      final targetSnap = await FirebaseFirestore.instance
          .collection("users")
          .doc(againstUserId)
          .get();
      final targetRole = targetSnap.data()?["role"]?.toString() ?? "";
      if (targetRole != "employer") return;

      await NotificationService().notifyEmployerReportStatusChanged(
        employerId: againstUserId,
        reportId: ref.id,
        status: status,
      );
    }
  }

  Future<void> updateSupportRequestStatus(
    DocumentReference ref,
    String status,
  ) async {
    await ref.set({
      "status": status,
      "updatedAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> updatePaymentRequestStatus(
    DocumentReference ref,
    String status,
  ) async {
    await BillingService().updatePaymentRequestStatus(ref, status);
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      const _AdminInboxTab(),
      _JobModerationSection(
        onApprove: approveJob,
        onReject: rejectJob,
        onOpen: openJobModerationDetail,
      ),
      _SupportRequestsSection(
        onStatusChanged: updateSupportRequestStatus,
      ),
      _PaymentRequestsSection(
        onStatusChanged: updatePaymentRequestStatus,
      ),
      _FinancialReportsSection(
        complaintsSection: _ReportsSection(
          onStatusChanged: updateReportStatus,
        ),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text("Admin"),
        actions: [
          IconButton(
            tooltip: "Logout",
            icon: const Icon(Icons.logout),
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
      body: StroykaScreenBody(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
          children: [pages[selectedIndex]],
        ),
      ),
      floatingActionButton: selectedIndex == 0
          ? FloatingActionButton(
              tooltip: "New admin message",
              onPressed: () => _showAdminMessageComposer(context),
              child: const Icon(Icons.mark_email_unread_outlined),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) => setState(() => selectedIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.mark_email_unread_outlined),
            label: "Inbox",
          ),
          NavigationDestination(
            icon: Icon(Icons.fact_check_outlined),
            label: "Jobs",
          ),
          NavigationDestination(
            icon: Icon(Icons.support_agent_outlined),
            label: "Support",
          ),
          NavigationDestination(
            icon: Icon(Icons.payments_outlined),
            label: "Billing",
          ),
          NavigationDestination(
            icon: Icon(Icons.analytics_outlined),
            label: "Reports",
          ),
        ],
      ),
    );
  }
}

Future<void> _showAdminMessageComposer(BuildContext context) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) {
      return Padding(
        padding: EdgeInsets.only(
          left: 12,
          right: 12,
          top: 12,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 12,
        ),
        child: const SingleChildScrollView(
          child: _AdminInboxSenderSection(compact: true),
        ),
      );
    },
  );
}

class _AdminInboxTab extends StatelessWidget {
  const _AdminInboxTab();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        _AdminInboxSenderSection(),
        _AdminSentInboxMessagesSection(),
      ],
    );
  }
}

class _AdminInboxSenderSection extends StatefulWidget {
  final bool compact;

  const _AdminInboxSenderSection({
    this.compact = false,
  });

  @override
  State<_AdminInboxSenderSection> createState() =>
      _AdminInboxSenderSectionState();
}

class _AdminInboxSenderSectionState extends State<_AdminInboxSenderSection> {
  final userIdController = TextEditingController();
  final titleController = TextEditingController();
  final messageController = TextEditingController();
  String audience = "worker";
  bool sending = false;

  @override
  void dispose() {
    userIdController.dispose();
    titleController.dispose();
    messageController.dispose();
    super.dispose();
  }

  String audienceLabel(String value) {
    switch (value) {
      case "employer":
        return "Specific employer";
      case "all_employers":
        return "All employers";
      case "all_workers":
        return "All workers";
      case "worker":
      default:
        return "Specific worker";
    }
  }

  bool get requiresUserId => audience == "worker" || audience == "employer";

  Future<List<String>> resolveRecipients() async {
    if (requiresUserId) {
      final id = userIdController.text.trim();
      if (id.isEmpty) return [];
      return [id];
    }

    final role = audience == "all_employers" ? "employer" : "worker";
    final users = await FirebaseFirestore.instance
        .collection("users")
        .where("role", isEqualTo: role)
        .get();

    return users.docs
        .where((doc) => doc.data()["accountDeleted"] != true)
        .map((doc) => doc.id)
        .toList();
  }

  Future<void> sendAdminMessage() async {
    final title = titleController.text.trim();
    final message = messageController.text.trim();

    if (title.isEmpty || message.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Enter title and message")),
      );
      return;
    }

    setState(() => sending = true);
    try {
      final recipients = await resolveRecipients();
      if (recipients.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("No recipients found")),
        );
        return;
      }

      final batch = FirebaseFirestore.instance.batch();
      final sentRef =
          FirebaseFirestore.instance.collection("admin_inbox_messages").doc();
      for (final userId in recipients) {
        final ref = FirebaseFirestore.instance
            .collection("users")
            .doc(userId)
            .collection("admin_inbox")
            .doc();
        batch.set(ref, {
          "userId": userId,
          "title": title,
          "message": message,
          "type": "admin_message",
          "audience": audience,
          "read": false,
          "createdAt": FieldValue.serverTimestamp(),
        });
      }
      batch.set(sentRef, {
        "title": title,
        "message": message,
        "type": "admin_message",
        "audience": audience,
        "recipientCount": recipients.length,
        if (requiresUserId) "targetUserId": recipients.first,
        "createdAt": FieldValue.serverTimestamp(),
      });
      await batch.commit();

      if (!mounted) return;
      titleController.clear();
      messageController.clear();
      if (requiresUserId) userIdController.clear();
      if (widget.compact && context.mounted) {
        Navigator.pop(context);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Admin message sent to ${recipients.length}")),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not send admin message")),
      );
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StroykaSurface(
      margin: const EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(widget.compact ? 14 : 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: Color(0x297DB9D8),
                child: Icon(
                  Icons.mark_email_unread_outlined,
                  color: AppColors.greenDark,
                ),
              ),
              SizedBox(width: 14),
              Expanded(
                child: Text(
                  "Admin inbox messages",
                  style: TextStyle(
                    color: AppColors.ink,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: audience,
            decoration: const InputDecoration(labelText: "Send to"),
            items: const [
              DropdownMenuItem(value: "worker", child: Text("Specific worker")),
              DropdownMenuItem(
                value: "employer",
                child: Text("Specific employer"),
              ),
              DropdownMenuItem(
                value: "all_workers",
                child: Text("All workers"),
              ),
              DropdownMenuItem(
                value: "all_employers",
                child: Text("All employers"),
              ),
            ],
            onChanged: sending
                ? null
                : (value) {
                    if (value == null) return;
                    setState(() => audience = value);
                  },
          ),
          if (requiresUserId) ...[
            const SizedBox(height: 10),
            TextField(
              controller: userIdController,
              enabled: !sending,
              decoration: InputDecoration(
                labelText: "${audienceLabel(audience)} user ID",
              ),
            ),
          ],
          const SizedBox(height: 10),
          TextField(
            controller: titleController,
            enabled: !sending,
            decoration: const InputDecoration(labelText: "Title"),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: messageController,
            enabled: !sending,
            maxLines: 4,
            decoration: const InputDecoration(labelText: "Message"),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: sending ? null : sendAdminMessage,
              icon: sending
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
              label: Text(sending ? "Sending..." : "Send admin message"),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminSentInboxMessagesSection extends StatelessWidget {
  const _AdminSentInboxMessagesSection();

  @override
  Widget build(BuildContext context) {
    return StroykaSurface(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: Color(0x297DB9D8),
                child: Icon(
                  Icons.outbox_outlined,
                  color: AppColors.greenDark,
                ),
              ),
              SizedBox(width: 14),
              Expanded(
                child: Text(
                  "Sent admin inbox messages",
                  style: TextStyle(
                    color: AppColors.ink,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection("admin_inbox_messages")
                .orderBy("createdAt", descending: true)
                .limit(50)
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const LinearProgressIndicator();

              final docs = snapshot.data!.docs;
              if (docs.isEmpty) {
                return const Text("No admin inbox messages sent yet");
              }

              return Column(
                children: docs.map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final audience = data["audience"]?.toString() ?? "";
                  final recipientCount = data["recipientCount"]?.toString();
                  final targetUserId = data["targetUserId"]?.toString() ?? "";
                  final createdAt = data["createdAt"] is Timestamp
                      ? (data["createdAt"] as Timestamp).toDate()
                      : null;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          data["title"]?.toString() ?? "Admin message",
                          style: const TextStyle(
                            color: AppColors.ink,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(data["message"]?.toString() ?? ""),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            _ReportMetaChip(label: "Audience", value: audience),
                            _ReportMetaChip(
                              label: "Recipients",
                              value: recipientCount,
                            ),
                            _ReportMetaChip(label: "User", value: targetUserId),
                            _ReportMetaChip(
                              label: "Sent",
                              value: _formatAdminDate(createdAt),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _PaymentRequestsSection extends StatelessWidget {
  final Future<void> Function(DocumentReference ref, String status)
      onStatusChanged;

  const _PaymentRequestsSection({
    required this.onStatusChanged,
  });

  @override
  Widget build(BuildContext context) {
    return StroykaSurface(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: Color(0x297DB9D8),
                child: Icon(
                  Icons.payments_outlined,
                  color: AppColors.greenDark,
                ),
              ),
              SizedBox(width: 14),
              Expanded(
                child: Text(
                  "Billing/payment requests",
                  style: TextStyle(
                    color: AppColors.ink,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection("payment_requests")
                .orderBy("createdAt", descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const LinearProgressIndicator();
              }

              final docs = snapshot.data!.docs;
              if (docs.isEmpty) {
                return const Text("No payment requests yet");
              }

              return Column(
                children: docs.map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  return _PaymentRequestCard(
                    data: data,
                    onStatusChanged: (status) {
                      onStatusChanged(doc.reference, status);
                    },
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _PaymentRequestCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final ValueChanged<String> onStatusChanged;

  const _PaymentRequestCard({
    required this.data,
    required this.onStatusChanged,
  });

  static const statuses = [
    "pending",
    "paid",
    "failed",
    "cancelled",
  ];

  @override
  Widget build(BuildContext context) {
    final status = data["status"]?.toString();
    final selectedStatus = statuses.contains(status) ? status! : "pending";
    final planName = data["planName"]?.toString().trim() ?? "Plan";
    final paymentMode = data["paymentMode"]?.toString().trim() ?? "";

    return _AdminStatusCard(
      title: planName,
      body: paymentMode,
      statuses: statuses,
      selectedStatus: selectedStatus,
      onStatusChanged: onStatusChanged,
      meta: [
        _ReportMetaChip(label: "Employer", value: data["employerId"]),
        _ReportMetaChip(label: "Plan", value: data["planId"]),
      ],
    );
  }
}

class _AdminStatusCard extends StatelessWidget {
  final String title;
  final String body;
  final List<String> statuses;
  final String selectedStatus;
  final ValueChanged<String> onStatusChanged;
  final List<Widget> meta;

  const _AdminStatusCard({
    required this.title,
    required this.body,
    required this.statuses,
    required this.selectedStatus,
    required this.onStatusChanged,
    required this.meta,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.9)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              DropdownButton<String>(
                value: selectedStatus,
                underline: const SizedBox(),
                items: statuses
                    .map(
                      (status) => DropdownMenuItem(
                        value: status,
                        child: Text(status),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null || value == selectedStatus) return;
                  onStatusChanged(value);
                },
              ),
            ],
          ),
          if (body.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              body,
              style: const TextStyle(
                color: AppColors.ink,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: meta,
          ),
        ],
      ),
    );
  }
}

class _SupportRequestsSection extends StatelessWidget {
  final Future<void> Function(DocumentReference ref, String status)
      onStatusChanged;

  const _SupportRequestsSection({
    required this.onStatusChanged,
  });

  @override
  Widget build(BuildContext context) {
    return StroykaSurface(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: Color(0x297DB9D8),
                child: Icon(
                  Icons.support_agent_outlined,
                  color: AppColors.greenDark,
                ),
              ),
              SizedBox(width: 14),
              Expanded(
                child: Text(
                  "Support requests",
                  style: TextStyle(
                    color: AppColors.ink,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection("support_requests")
                .orderBy("createdAt", descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const LinearProgressIndicator();
              }

              final docs = snapshot.data!.docs;
              if (docs.isEmpty) {
                return const Text("No support requests yet");
              }

              return Column(
                children: docs.map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  return _SupportRequestCard(
                    data: data,
                    onStatusChanged: (status) {
                      onStatusChanged(doc.reference, status);
                    },
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SupportRequestCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final ValueChanged<String> onStatusChanged;

  const _SupportRequestCard({
    required this.data,
    required this.onStatusChanged,
  });

  static const statuses = [
    "open",
    "in_review",
    "resolved",
    "rejected",
  ];

  String supportTypeLabel(Map<String, dynamic> data) {
    final storedLabel = data["typeLabel"]?.toString().trim();
    if (storedLabel != null && storedLabel.isNotEmpty) return storedLabel;

    final type = data["type"]?.toString().trim() ?? "support";
    switch (type) {
      case "participant_complaint":
        return "Complaint about another participant";
      case "employer_complaint":
        return "Complaint about employer/company";
      case "technical_issue":
        return "Technical issue with app/site";
      case "job_ad_complaint":
        return "Complaint about advertisement/job post";
      case "payment":
        return "Payment";
      case "job_publishing":
      case "job publishing":
        return "Job publishing";
      case "job_extension":
      case "job extension":
        return "Job extension";
      case "job_pause_removal":
      case "job pause/removal":
        return "Job pause/removal";
      case "other":
        return "Other";
      default:
        return type;
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = data["status"]?.toString();
    final selectedStatus = statuses.contains(status) ? status! : "open";
    final type = data["type"]?.toString().trim() ?? "support";
    final message = data["message"]?.toString().trim() ?? "";

    return _AdminStatusCard(
      title: supportTypeLabel(data),
      body: message,
      statuses: statuses,
      selectedStatus: selectedStatus,
      onStatusChanged: onStatusChanged,
      meta: [
        _ReportMetaChip(label: "Type", value: type),
        _ReportMetaChip(label: "User", value: data["userId"]),
        _ReportMetaChip(label: "Role", value: data["userRole"]),
      ],
    );
  }
}

class _FinancialReportsSection extends StatelessWidget {
  final Widget complaintsSection;

  const _FinancialReportsSection({
    required this.complaintsSection,
  });

  double readMoney(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) {
      return double.tryParse(value.replaceAll(RegExp(r"[^0-9.]"), "")) ?? 0;
    }
    return 0;
  }

  bool isThisMonth(dynamic value) {
    if (value is! Timestamp) return false;
    final date = value.toDate();
    final now = DateTime.now();
    return date.year == now.year && date.month == now.month;
  }

  Map<String, dynamic> billingFromUser(Map<String, dynamic> data) {
    return BillingService.billingFromUserData(data);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection("plans").snapshots(),
      builder: (context, plansSnapshot) {
        final planPrices = <String, double>{};
        final planCurrency = <String, String>{};
        if (plansSnapshot.hasData) {
          for (final doc in plansSnapshot.data!.docs) {
            final data = doc.data() as Map<String, dynamic>;
            planPrices[doc.id] = readMoney(data["price"]);
            planCurrency[doc.id] = data["currency"]?.toString() ?? "GBP";
          }
        }

        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection("users").snapshots(),
          builder: (context, usersSnapshot) {
            return StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection("payment_requests")
                  .orderBy("createdAt", descending: true)
                  .snapshots(),
              builder: (context, paymentsSnapshot) {
                if (!usersSnapshot.hasData || !paymentsSnapshot.hasData) {
                  return const LinearProgressIndicator();
                }

                final users = usersSnapshot.data!.docs
                    .map((doc) => doc.data() as Map<String, dynamic>)
                    .where((data) => data["accountDeleted"] != true)
                    .toList();
                final payments = paymentsSnapshot.data!.docs
                    .map((doc) => doc.data() as Map<String, dynamic>)
                    .toList();

                final workers = users
                    .where((data) => data["role"]?.toString() == "worker")
                    .length;
                final employers = users
                    .where((data) => data["role"]?.toString() == "employer")
                    .toList();
                final payingEmployers = employers.where((data) {
                  final billing = billingFromUser(data);
                  final status = billing["status"]?.toString() ?? "";
                  final planId = billing["planId"]?.toString() ?? "";
                  return planId.isNotEmpty &&
                      (status == "active" || status == "payment_pending");
                }).toList();

                double expectedMonthlyRevenue = 0;
                var currency = "GBP";
                for (final employer in payingEmployers) {
                  final billing = billingFromUser(employer);
                  final planId = billing["planId"]?.toString() ?? "";
                  expectedMonthlyRevenue += planPrices[planId] ?? 0;
                  currency = planCurrency[planId] ?? currency;
                }

                final currentMonthPayments = payments
                    .where((data) =>
                        isThisMonth(data["paidAt"]) ||
                        (data["paidAt"] == null &&
                            isThisMonth(data["updatedAt"])))
                    .toList();
                final paidThisMonth = currentMonthPayments
                    .where((data) => data["status"]?.toString() == "paid")
                    .toList();
                final pendingRequests = payments
                    .where((data) => data["status"]?.toString() == "pending")
                    .length;

                final revenueByMode = <String, double>{};
                for (final payment in paidThisMonth) {
                  final mode =
                      payment["paymentMode"]?.toString() ?? "manual_invoice";
                  final planId = payment["planId"]?.toString() ?? "";
                  revenueByMode[mode] =
                      (revenueByMode[mode] ?? 0) + (planPrices[planId] ?? 0);
                }
                final receivedThisMonth = revenueByMode.values.fold<double>(
                  0,
                  (total, value) => total + value,
                );

                return Column(
                  children: [
                    StroykaSurface(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              CircleAvatar(
                                radius: 24,
                                backgroundColor: Color(0x297DB9D8),
                                child: Icon(
                                  Icons.analytics_outlined,
                                  color: AppColors.greenDark,
                                ),
                              ),
                              SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  "Financial reports",
                                  style: TextStyle(
                                    color: AppColors.ink,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              _AdminMetricTile(
                                label: "All users",
                                value: users.length.toString(),
                                icon: Icons.people_outline,
                              ),
                              _AdminMetricTile(
                                label: "Workers",
                                value: workers.toString(),
                                icon: Icons.engineering_outlined,
                              ),
                              _AdminMetricTile(
                                label: "Employers",
                                value: employers.length.toString(),
                                icon: Icons.business_outlined,
                              ),
                              _AdminMetricTile(
                                label: "Paying clients",
                                value: payingEmployers.length.toString(),
                                icon: Icons.verified_outlined,
                              ),
                              _AdminMetricTile(
                                label: "Expected / month",
                                value:
                                    "$currency ${expectedMonthlyRevenue.toStringAsFixed(2)}",
                                icon: Icons.request_quote_outlined,
                              ),
                              _AdminMetricTile(
                                label: "Received this month",
                                value:
                                    "$currency ${receivedThisMonth.toStringAsFixed(2)}",
                                icon: Icons.payments_outlined,
                              ),
                              _AdminMetricTile(
                                label: "Pending payment requests",
                                value: pendingRequests.toString(),
                                icon: Icons.pending_actions_outlined,
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          const Text(
                            "Received by payment method",
                            style: TextStyle(
                              color: AppColors.ink,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (revenueByMode.isEmpty)
                            const Text("No received payments this month yet")
                          else
                            ...revenueByMode.entries.map(
                              (entry) => _AdminMetaLine(
                                label: BillingService.formatLabel(entry.key),
                                value:
                                    "$currency ${entry.value.toStringAsFixed(2)}",
                              ),
                            ),
                        ],
                      ),
                    ),
                    complaintsSection,
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
}

class _AdminMetricTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _AdminMetricTile({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 155,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.74),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.9)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.greenDark),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.ink,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportsSection extends StatelessWidget {
  final Future<void> Function(DocumentReference ref, String status)
      onStatusChanged;

  const _ReportsSection({
    required this.onStatusChanged,
  });

  @override
  Widget build(BuildContext context) {
    return StroykaSurface(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: Color(0x297DB9D8),
                child: Icon(
                  Icons.report_problem_outlined,
                  color: AppColors.greenDark,
                ),
              ),
              SizedBox(width: 14),
              Expanded(
                child: Text(
                  "Reports",
                  style: TextStyle(
                    color: AppColors.ink,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection("reports")
                .orderBy("createdAt", descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const LinearProgressIndicator();
              }

              final docs = snapshot.data!.docs;
              if (docs.isEmpty) {
                return const Text("No reports yet");
              }

              return Column(
                children: docs.map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  return _ReportCard(
                    data: data,
                    onStatusChanged: (status) {
                      onStatusChanged(doc.reference, status);
                    },
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final ValueChanged<String> onStatusChanged;

  const _ReportCard({
    required this.data,
    required this.onStatusChanged,
  });

  static const statuses = [
    "open",
    "in_review",
    "resolved",
    "rejected",
  ];

  @override
  Widget build(BuildContext context) {
    final status = data["status"]?.toString();
    final selectedStatus = statuses.contains(status) ? status! : "open";
    final message = data["message"]?.toString().trim() ?? "";
    final type = data["type"]?.toString().trim() ?? "report";

    return _AdminStatusCard(
      title: type,
      body: message,
      statuses: statuses,
      selectedStatus: selectedStatus,
      onStatusChanged: onStatusChanged,
      meta: [
        _ReportMetaChip(label: "From", value: data["fromUserId"]),
        _ReportMetaChip(label: "Against", value: data["againstUserId"]),
        _ReportMetaChip(label: "Job", value: data["jobId"]),
        _ReportMetaChip(label: "Application", value: data["applicationId"]),
        _ReportMetaChip(label: "Chat", value: data["chatId"]),
      ],
    );
  }
}

class _ReportMetaChip extends StatelessWidget {
  final String label;
  final dynamic value;

  const _ReportMetaChip({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final text = value?.toString().trim() ?? "";
    if (text.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.green.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        "$label: $text",
        style: const TextStyle(
          color: AppColors.greenDark,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _JobModerationSection extends StatelessWidget {
  final Future<void> Function(DocumentReference ref, Job job) onApprove;
  final Future<bool> Function(BuildContext context, DocumentReference ref)
      onReject;
  final Future<void> Function(BuildContext context, DocumentSnapshot doc)
      onOpen;

  const _JobModerationSection({
    required this.onApprove,
    required this.onReject,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return StroykaSurface(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: Color(0x297DB9D8),
                child: Icon(
                  Icons.fact_check_outlined,
                  color: AppColors.greenDark,
                ),
              ),
              SizedBox(width: 14),
              Expanded(
                child: Text(
                  "Job moderation",
                  style: TextStyle(
                    color: AppColors.ink,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection("jobs")
                .where("moderationStatus", isEqualTo: "pending_review")
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const LinearProgressIndicator();
              }

              final docs = snapshot.data!.docs;
              if (docs.isEmpty) {
                return const Text("No jobs waiting for review");
              }

              return Column(
                children: docs.map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final job = Job.fromFirestore(doc.id, data);
                  return _PendingJobCard(
                    job: job,
                    onOpen: () => onOpen(context, doc),
                    onApprove: () async => onApprove(doc.reference, job),
                    onReject: () async => onReject(context, doc.reference),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _PendingJobCard extends StatelessWidget {
  final Job job;
  final VoidCallback onOpen;
  final Future<void> Function() onApprove;
  final Future<bool> Function() onReject;

  const _PendingJobCard({
    required this.job,
    required this.onOpen,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final location = [
      job.city,
      job.postcode,
    ].where((item) => item.trim().isNotEmpty).join(" ");

    return InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.78),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppColors.greenDark.withValues(alpha: 0.22),
            width: 1.2,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    job.displayTitle,
                    style: const TextStyle(
                      color: AppColors.ink,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  color: AppColors.muted,
                ),
              ],
            ),
            const SizedBox(height: 8),
            _AdminMetaLine(label: "Trade", value: job.trade),
            _AdminMetaLine(label: "Site", value: job.site),
            _AdminMetaLine(label: "Location", value: location),
            _AdminMetaLine(label: "Employer", value: job.companyName),
            _AdminMetaLine(
              label: "Created",
              value: _formatAdminDate(job.createdAt),
            ),
            _AdminMetaLine(
              label: "Status",
              value: job.moderationLabel,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onReject,
                    child: const Text("Reject"),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: onApprove,
                    child: const Text("Approve"),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminJobModerationDetailScreen extends StatelessWidget {
  final Job job;
  final DocumentReference jobRef;
  final Future<void> Function(DocumentReference ref, Job job) onApprove;
  final Future<bool> Function(BuildContext context, DocumentReference ref)
      onReject;

  const _AdminJobModerationDetailScreen({
    required this.job,
    required this.jobRef,
    required this.onApprove,
    required this.onReject,
  });

  Future<void> approveAndClose(BuildContext context) async {
    await onApprove(jobRef, job);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Job approved")),
    );
    Navigator.pop(context);
  }

  Future<void> rejectAndClose(BuildContext context) async {
    final rejected = await onReject(context, jobRef);
    if (!context.mounted) return;
    if (!rejected) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Job rejected")),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final location = [
      job.street,
      job.city,
      job.postcode,
    ].where((item) => item.trim().isNotEmpty).join(", ");

    return Scaffold(
      appBar: AppBar(
        title: const Text("Review job"),
      ),
      body: StroykaScreenBody(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 120),
          children: [
            StroykaSurface(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    job.displayTitle,
                    style: const TextStyle(
                      color: AppColors.ink,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _AdminMetaLine(label: "Trade", value: job.trade),
                  _AdminMetaLine(label: "Company", value: job.companyName),
                  _AdminMetaLine(label: "Site", value: job.site),
                  _AdminMetaLine(label: "Location", value: location),
                  _AdminMetaLine(
                      label: "Work format", value: job.workFormatText),
                  _AdminMetaLine(label: "Duration", value: job.duration),
                  _AdminMetaLine(label: "Hours/week", value: job.weeklyHours),
                  _AdminMetaLine(label: "Rate", value: job.rateText),
                  _AdminMetaLine(
                    label: "Workers needed",
                    value: job.positions.toString(),
                  ),
                  _AdminMetaLine(
                    label: "Created",
                    value: _formatAdminDate(job.createdAt),
                  ),
                  _AdminMetaLine(
                    label: "Moderation status",
                    value: job.moderationLabel,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _AdminTextSection(
              title: "Job description",
              text: job.description,
              emptyText: "No job description provided",
            ),
            _AdminTextSection(
              title: "Candidate requirements",
              text: job.candidateRequirements,
              emptyText: "No candidate requirements provided",
            ),
            _AdminTextSection(
              title: "Required documents / certifications",
              text: job.requiredDocuments,
              emptyText: "No required documents provided",
            ),
            if (job.photos.isNotEmpty) ...[
              const SizedBox(height: 12),
              StroykaSurface(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Photos",
                      style: TextStyle(
                        color: AppColors.ink,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 12),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: job.photos.length,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                      ),
                      itemBuilder: (context, index) {
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.network(
                            job.photos[index],
                            fit: BoxFit.cover,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: StroykaSurface(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => rejectAndClose(context),
                  child: const Text("Reject"),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => approveAndClose(context),
                  child: const Text("Approve"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminTextSection extends StatelessWidget {
  final String title;
  final String text;
  final String emptyText;

  const _AdminTextSection({
    required this.title,
    required this.text,
    required this.emptyText,
  });

  @override
  Widget build(BuildContext context) {
    final cleanText = text.trim();

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: StroykaSurface(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: AppColors.ink,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 10),
            Text(cleanText.isEmpty ? emptyText : cleanText),
          ],
        ),
      ),
    );
  }
}

class _AdminMetaLine extends StatelessWidget {
  final String label;
  final String value;

  const _AdminMetaLine({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final cleanValue = value.trim();
    if (cleanValue.isEmpty) return const SizedBox();

    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 122,
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
              cleanValue,
              style: const TextStyle(
                color: AppColors.ink,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatAdminDate(DateTime? date) {
  if (date == null) return "";
  return "${date.day.toString().padLeft(2, "0")}/"
      "${date.month.toString().padLeft(2, "0")}/"
      "${date.year} "
      "${date.hour.toString().padLeft(2, "0")}:"
      "${date.minute.toString().padLeft(2, "0")}";
}
