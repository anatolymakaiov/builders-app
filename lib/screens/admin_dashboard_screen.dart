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

    await _sendAdminInboxMessage(
      userId: job.ownerId,
      title: "Job publication rejected",
      message: reason.trim().isEmpty
          ? "${job.displayTitle} was rejected by admin."
          : "${job.displayTitle} was rejected by admin:\n\n${reason.trim()}",
      audience: "employer",
      relatedTargetType: "job",
      relatedTargetId: job.id,
    );

    return true;
  }

  Future<void> holdJob(
    BuildContext context,
    DocumentReference ref,
  ) async {
    final reason = await _askAdminReply(
      context,
      title: "Put job on hold",
      label: "Message to employer",
      hint: "Explain what should be clarified before approval",
    );
    if (reason == null) return;

    final jobSnap = await ref.get();
    final jobData = jobSnap.data() as Map<String, dynamic>? ?? {};
    final job = Job.fromFirestore(ref.id, jobData);

    await ref.set({
      "moderationStatus": "on_hold",
      "moderationReason": reason,
      "moderatedAt": FieldValue.serverTimestamp(),
      "updatedAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await _sendAdminInboxMessage(
      userId: job.ownerId,
      title: "Job publication on hold",
      message: reason.trim().isEmpty
          ? "${job.displayTitle} was put on hold by admin."
          : "${job.displayTitle} was put on hold by admin:\n\n${reason.trim()}",
      audience: "employer",
      relatedTargetType: "job",
      relatedTargetId: job.id,
    );
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
          onHold: holdJob,
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
        onSupportStatusChanged: updateSupportRequestStatus,
        onReportStatusChanged: updateReportStatus,
      ),
      _PaymentRequestsSection(
        onStatusChanged: updatePaymentRequestStatus,
      ),
      const _FinancialReportsSection(
        complaintsSection: SizedBox.shrink(),
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

Future<String?> _askAdminReply(
  BuildContext context, {
  required String title,
  required String label,
  String? hint,
}) async {
  final controller = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          maxLines: 5,
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            border: const StroykaInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text("Send"),
          ),
        ],
      );
    },
  );
  controller.dispose();
  return result;
}

Future<void> _sendAdminInboxMessage({
  required String userId,
  required String title,
  required String message,
  required String audience,
  String? relatedTargetType,
  String? relatedTargetId,
}) async {
  if (userId.trim().isEmpty || title.trim().isEmpty || message.trim().isEmpty) {
    return;
  }

  final firestore = FirebaseFirestore.instance;
  final batch = firestore.batch();
  final inboxRef =
      firestore.collection("users").doc(userId).collection("admin_inbox").doc();
  final sentRef = firestore.collection("admin_inbox_messages").doc();
  final payload = {
    "userId": userId,
    "title": title.trim(),
    "message": message.trim(),
    "type": "admin_message",
    "audience": audience,
    "read": false,
    if (relatedTargetType != null) "relatedTargetType": relatedTargetType,
    if (relatedTargetId != null) "relatedTargetId": relatedTargetId,
    "createdAt": FieldValue.serverTimestamp(),
  };

  batch.set(inboxRef, payload);
  batch.set(sentRef, {
    ...payload,
    "targetUserId": userId,
    "recipientCount": 1,
  });
  await batch.commit();
}

class _AdminInboxTab extends StatelessWidget {
  const _AdminInboxTab();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
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
                    ref: doc.reference,
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
  final DocumentReference ref;
  final ValueChanged<String> onStatusChanged;

  const _PaymentRequestCard({
    required this.data,
    required this.ref,
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
    final employerId = data["employerId"]?.toString() ?? "";

    return FutureBuilder<DocumentSnapshot>(
      future: employerId.isEmpty
          ? null
          : FirebaseFirestore.instance
              .collection("users")
              .doc(employerId)
              .get(),
      builder: (context, snapshot) {
        final employerData =
            snapshot.data?.data() as Map<String, dynamic>? ?? {};
        final companyName =
            (employerData["companyName"] ?? employerData["name"] ?? "Employer")
                .toString();

        return _AdminRequestListCard(
          title: companyName,
          subtitle: "$planName • ${BillingService.formatLabel(paymentMode)}",
          status: selectedStatus,
          chips: [
            _ReportMetaChip(label: "Plan", value: data["planId"]),
            _ReportMetaChip(label: "Employer", value: employerId),
          ],
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => _PaymentRequestDetailScreen(
                  ref: ref,
                  data: data,
                  companyName: companyName,
                  employerId: employerId,
                  status: selectedStatus,
                  onStatusChanged: onStatusChanged,
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _PaymentRequestDetailScreen extends StatelessWidget {
  final DocumentReference ref;
  final Map<String, dynamic> data;
  final String companyName;
  final String employerId;
  final String status;
  final ValueChanged<String> onStatusChanged;

  const _PaymentRequestDetailScreen({
    required this.ref,
    required this.data,
    required this.companyName,
    required this.employerId,
    required this.status,
    required this.onStatusChanged,
  });

  Future<void> reply(BuildContext context) async {
    final message = await _askAdminReply(
      context,
      title: "Message employer",
      label: "Message",
      hint: "Write a response about this billing request",
    );
    if (message == null || message.trim().isEmpty) return;

    await _sendAdminInboxMessage(
      userId: employerId,
      title: "Billing request update",
      message: message,
      audience: "employer",
      relatedTargetType: "payment_request",
      relatedTargetId: ref.id,
    );

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Message sent to employer inbox")),
    );
  }

  Future<void> changeStatus(BuildContext context, String nextStatus) async {
    onStatusChanged(nextStatus);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Billing request changed to $nextStatus")),
    );
  }

  @override
  Widget build(BuildContext context) {
    final planName = data["planName"]?.toString().trim() ?? "Plan";
    final planId = data["planId"]?.toString().trim() ?? "";
    final paymentMode = data["paymentMode"]?.toString().trim() ?? "";

    return Scaffold(
      appBar: AppBar(
        title: const Text("Billing request"),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == "message") {
                reply(context);
                return;
              }
              if (value == "approve") {
                changeStatus(context, "paid");
                return;
              }
              if (value == "reject") {
                changeStatus(context, "failed");
                return;
              }
              if (value == "cancel") {
                changeStatus(context, "cancelled");
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: "approve",
                child: ListTile(
                  leading: Icon(Icons.check_circle_outline),
                  title: Text("Approve"),
                ),
              ),
              PopupMenuItem(
                value: "reject",
                child: ListTile(
                  leading: Icon(Icons.cancel_outlined),
                  title: Text("Reject"),
                ),
              ),
              PopupMenuItem(
                value: "cancel",
                child: ListTile(
                  leading: Icon(Icons.remove_circle_outline),
                  title: Text("Cancel request"),
                ),
              ),
              PopupMenuItem(
                value: "message",
                child: ListTile(
                  leading: Icon(Icons.reply_outlined),
                  title: Text("Message employer"),
                ),
              ),
            ],
          ),
        ],
      ),
      body: StroykaScreenBody(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
          children: [
            StroykaSurface(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          companyName,
                          style: const TextStyle(
                            color: AppColors.ink,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      _AdminStatusPill(status),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _AdminMetaLine(label: "Employer ID", value: employerId),
                  _AdminMetaLine(label: "Requested plan", value: planName),
                  _AdminMetaLine(label: "Plan ID", value: planId),
                  _AdminMetaLine(
                    label: "Payment mode",
                    value: BillingService.formatLabel(paymentMode),
                  ),
                  _AdminMetaLine(label: "Request ID", value: ref.id),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminRequestListCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String status;
  final List<Widget> chips;
  final VoidCallback onTap;

  const _AdminRequestListCard({
    required this.title,
    required this.subtitle,
    required this.status,
    required this.chips,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
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
                _AdminStatusPill(status),
                const Icon(Icons.chevron_right, color: AppColors.muted),
              ],
            ),
            if (subtitle.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 6, children: chips),
          ],
        ),
      ),
    );
  }
}

class _AdminStatusPill extends StatelessWidget {
  final String status;

  const _AdminStatusPill(this.status);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.green.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.green.withValues(alpha: 0.22)),
      ),
      child: Text(
        BillingService.formatLabel(status),
        style: const TextStyle(
          color: AppColors.greenDark,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _AdminRequestDetailScreen extends StatelessWidget {
  final String title;
  final String body;
  final String userId;
  final String userRole;
  final DocumentReference ref;
  final String status;
  final List<String> statuses;
  final ValueChanged<String> onStatusChanged;
  final List<Widget> meta;

  const _AdminRequestDetailScreen({
    required this.title,
    required this.body,
    required this.userId,
    required this.userRole,
    required this.ref,
    required this.status,
    required this.statuses,
    required this.onStatusChanged,
    required this.meta,
  });

  Future<void> reply(BuildContext context) async {
    final message = await _askAdminReply(
      context,
      title: "Reply",
      label: "Message to user",
      hint: "Write admin response",
    );
    if (message == null || message.trim().isEmpty) return;

    await _sendAdminInboxMessage(
      userId: userId,
      title: "Admin response: $title",
      message: message,
      audience: userRole.isEmpty ? "user" : userRole,
      relatedTargetType: "support",
      relatedTargetId: ref.id,
    );
    await ref.set({
      "adminReply": message.trim(),
      "lastAdminReplyAt": FieldValue.serverTimestamp(),
      "status": status == "open" ? "in_review" : status,
      "updatedAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Reply sent to inbox")),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Request"),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == "reply") {
                await reply(context);
                return;
              }
              onStatusChanged(value);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text("Status changed to $value")),
              );
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: "reply",
                child: ListTile(
                  leading: Icon(Icons.reply_outlined),
                  title: Text("Reply"),
                ),
              ),
              ...statuses.map(
                (item) => PopupMenuItem(
                  value: item,
                  child: ListTile(
                    leading: const Icon(Icons.flag_outlined),
                    title: Text(BillingService.formatLabel(item)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      body: StroykaScreenBody(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
          children: [
            StroykaSurface(
              padding: const EdgeInsets.all(18),
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
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      _AdminStatusPill(status),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(body.isEmpty ? "No message provided" : body),
                  const SizedBox(height: 14),
                  ...meta,
                ],
              ),
            ),
            const SizedBox(height: 12),
            StroykaSurface(
              padding: const EdgeInsets.all(18),
              child: ElevatedButton.icon(
                onPressed: () => reply(context),
                icon: const Icon(Icons.reply_outlined),
                label: const Text("Reply to user"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SupportRequestsSection extends StatelessWidget {
  final Future<void> Function(DocumentReference ref, String status)
      onSupportStatusChanged;
  final Future<void> Function(DocumentReference ref, String status)
      onReportStatusChanged;

  const _SupportRequestsSection({
    required this.onSupportStatusChanged,
    required this.onReportStatusChanged,
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

              return Column(
                children: [
                  if (docs.isEmpty)
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text("No support requests yet"),
                    )
                  else
                    ...docs.map((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      return _SupportRequestCard(
                        data: data,
                        ref: doc.reference,
                        onStatusChanged: (status) {
                          onSupportStatusChanged(doc.reference, status);
                        },
                      );
                    }),
                  _SupportReportsList(
                    onStatusChanged: onReportStatusChanged,
                  ),
                ],
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
  final DocumentReference ref;
  final ValueChanged<String> onStatusChanged;

  const _SupportRequestCard({
    required this.data,
    required this.ref,
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

    return _AdminRequestListCard(
      title: supportTypeLabel(data),
      subtitle: message,
      status: selectedStatus,
      chips: [
        _ReportMetaChip(label: "Type", value: type),
        _ReportMetaChip(label: "User", value: data["userId"]),
        _ReportMetaChip(label: "Role", value: data["userRole"]),
      ],
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => _AdminRequestDetailScreen(
              title: supportTypeLabel(data),
              body: message,
              userId: data["userId"]?.toString() ?? "",
              userRole: data["userRole"]?.toString() ?? "",
              ref: ref,
              status: selectedStatus,
              statuses: statuses,
              onStatusChanged: onStatusChanged,
              meta: [
                _AdminMetaLine(label: "Type", value: type),
                _AdminMetaLine(
                  label: "User",
                  value: data["userId"]?.toString() ?? "",
                ),
                _AdminMetaLine(
                  label: "Role",
                  value: data["userRole"]?.toString() ?? "",
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SupportReportsList extends StatelessWidget {
  final Future<void> Function(DocumentReference ref, String status)
      onStatusChanged;

  const _SupportReportsList({
    required this.onStatusChanged,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection("reports")
          .orderBy("createdAt", descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const LinearProgressIndicator();
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            const Text(
              "Complaints and reports",
              style: TextStyle(
                color: AppColors.ink,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 10),
            ...docs.map((doc) {
              final data = doc.data() as Map<String, dynamic>;
              return _ReportCard(
                data: data,
                ref: doc.reference,
                onStatusChanged: (status) {
                  onStatusChanged(doc.reference, status);
                },
              );
            }),
          ],
        );
      },
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

class _ReportCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final DocumentReference ref;
  final ValueChanged<String> onStatusChanged;

  const _ReportCard({
    required this.data,
    required this.ref,
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

    return _AdminRequestListCard(
      title: type,
      subtitle: message,
      status: selectedStatus,
      chips: [
        _ReportMetaChip(label: "From", value: data["fromUserId"]),
        _ReportMetaChip(label: "Against", value: data["againstUserId"]),
        _ReportMetaChip(label: "Job", value: data["jobId"]),
        _ReportMetaChip(label: "Application", value: data["applicationId"]),
        _ReportMetaChip(label: "Chat", value: data["chatId"]),
      ],
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => _AdminRequestDetailScreen(
              title: type,
              body: message,
              userId: data["fromUserId"]?.toString() ?? "",
              userRole: "user",
              ref: ref,
              status: selectedStatus,
              statuses: statuses,
              onStatusChanged: onStatusChanged,
              meta: [
                _AdminMetaLine(
                  label: "From",
                  value: data["fromUserId"]?.toString() ?? "",
                ),
                _AdminMetaLine(
                  label: "Against",
                  value: data["againstUserId"]?.toString() ?? "",
                ),
                _AdminMetaLine(
                  label: "Job",
                  value: data["jobId"]?.toString() ?? "",
                ),
                _AdminMetaLine(
                  label: "Application",
                  value: data["applicationId"]?.toString() ?? "",
                ),
                _AdminMetaLine(
                  label: "Chat",
                  value: data["chatId"]?.toString() ?? "",
                ),
              ],
            ),
          ),
        );
      },
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
            stream: FirebaseFirestore.instance.collection("jobs").where(
              "moderationStatus",
              whereIn: ["pending_review", "on_hold"],
            ).snapshots(),
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

  const _PendingJobCard({
    required this.job,
    required this.onOpen,
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
  final Future<void> Function(BuildContext context, DocumentReference ref)
      onHold;

  const _AdminJobModerationDetailScreen({
    required this.job,
    required this.jobRef,
    required this.onApprove,
    required this.onReject,
    required this.onHold,
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

  Future<void> holdAndClose(BuildContext context) async {
    await onHold(context, jobRef);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Job put on hold")),
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
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == "approve") approveAndClose(context);
              if (value == "hold") holdAndClose(context);
              if (value == "reject") rejectAndClose(context);
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: "approve",
                child: ListTile(
                  leading: Icon(Icons.check_circle_outline),
                  title: Text("Approve"),
                ),
              ),
              PopupMenuItem(
                value: "hold",
                child: ListTile(
                  leading: Icon(Icons.pause_circle_outline),
                  title: Text("Put on hold"),
                ),
              ),
              PopupMenuItem(
                value: "reject",
                child: ListTile(
                  leading: Icon(Icons.cancel_outlined),
                  title: Text("Reject"),
                ),
              ),
            ],
          ),
        ],
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
                  _AdminEmployerSlotsLine(employerId: job.ownerId),
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

class _AdminEmployerSlotsLine extends StatelessWidget {
  final String employerId;

  const _AdminEmployerSlotsLine({
    required this.employerId,
  });

  @override
  Widget build(BuildContext context) {
    if (employerId.trim().isEmpty) return const SizedBox.shrink();

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection("users")
          .doc(employerId)
          .snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data() as Map<String, dynamic>? ?? {};
        final billing = BillingService.billingFromUserData(data);
        final available = BillingService.readInt(billing["availableJobPosts"]);
        final used = BillingService.readInt(billing["usedJobPosts"]);
        final free = (available - used).clamp(0, available);
        return _AdminMetaLine(
          label: "Free slots",
          value: "$free of $available",
        );
      },
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
