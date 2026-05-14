import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io';

import '../models/job.dart';
import '../services/billing_service.dart';
import '../services/job_alert_service.dart';
import '../services/notification_service.dart';
import 'employer_profile_screen.dart';
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
        destinations: [
          NavigationDestination(
            icon: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection("admin_messages")
                  .where("direction", isEqualTo: "incoming")
                  .where("readByAdmin", isEqualTo: false)
                  .where("deletedByAdmin", isEqualTo: false)
                  .snapshots(),
              builder: (context, snapshot) {
                final count = snapshot.data?.docs.length ?? 0;
                if (count == 0) {
                  return const Icon(Icons.mark_email_unread_outlined);
                }
                return Badge.count(
                  count: count,
                  child: const Icon(Icons.mark_email_unread_outlined),
                );
              },
            ),
            label: "Inbox",
          ),
          const NavigationDestination(
            icon: Icon(Icons.fact_check_outlined),
            label: "Jobs",
          ),
          const NavigationDestination(
            icon: Icon(Icons.support_agent_outlined),
            label: "Support",
          ),
          const NavigationDestination(
            icon: Icon(Icons.payments_outlined),
            label: "Billing",
          ),
          const NavigationDestination(
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

  await _createAdminMailMessage(
    direction: "outgoing",
    receiverId: userId,
    receiverRole: audience,
    subject: title,
    message: message,
    relatedTargetType: relatedTargetType,
    relatedTargetId: relatedTargetId,
  );
}

Future<String> _createAdminMailMessage({
  required String direction,
  required String receiverId,
  required String receiverRole,
  required String subject,
  required String message,
  String? threadId,
  String? senderId,
  String? senderName,
  String? senderRole,
  String? relatedTargetType,
  String? relatedTargetId,
  List<Map<String, dynamic>> attachments = const [],
}) async {
  if (subject.trim().isEmpty || message.trim().isEmpty) return "";

  final firestore = FirebaseFirestore.instance;
  final batch = firestore.batch();
  final resolvedThreadId =
      threadId?.trim().isNotEmpty == true ? threadId!.trim() : null;
  final threadRef = resolvedThreadId == null
      ? firestore.collection("message_threads").doc()
      : firestore.collection("message_threads").doc(resolvedThreadId);
  final messageRef = firestore.collection("admin_messages").doc();

  Map<String, dynamic> userData = {};
  if (receiverId.trim().isNotEmpty) {
    final userSnap = await firestore.collection("users").doc(receiverId).get();
    userData = userSnap.data() ?? {};
  }

  final receiverName = (userData["companyName"] ??
          userData["name"] ??
          userData["displayName"] ??
          receiverId)
      .toString();
  final normalizedDirection = direction == "incoming" ? "incoming" : "outgoing";
  final now = FieldValue.serverTimestamp();

  final payload = <String, dynamic>{
    "threadId": threadRef.id,
    "direction": normalizedDirection,
    "senderId": senderId ?? "admin",
    "senderName": senderName ?? "Admin",
    "senderRole": senderRole ?? "admin",
    "receiverId": receiverId,
    "receiverName": receiverName,
    "receiverRole": receiverRole,
    "subject": subject.trim(),
    "message": message.trim(),
    "type": "admin_message",
    "readByAdmin": normalizedDirection == "outgoing",
    "important": false,
    "deletedByAdmin": false,
    "attachments": attachments,
    "hasAttachments": attachments.isNotEmpty,
    if (relatedTargetType != null) "relatedTargetType": relatedTargetType,
    if (relatedTargetId != null) "relatedTargetId": relatedTargetId,
    "createdAt": now,
  };

  batch.set(messageRef, payload);
  batch.set(
    threadRef,
    {
      "subject": subject.trim(),
      "participants": [
        "admin",
        if (receiverId.trim().isNotEmpty) receiverId,
      ],
      "lastMessage": message.trim(),
      "lastMessageAt": now,
      "lastSenderId": senderId ?? "admin",
      "unreadForAdmin": normalizedDirection == "incoming" ? 1 : 0,
      "updatedAt": now,
    },
    SetOptions(merge: true),
  );

  for (final attachment in attachments) {
    batch.set(firestore.collection("message_attachments").doc(), {
      ...attachment,
      "threadId": threadRef.id,
      "messageId": messageRef.id,
      "createdAt": now,
    });
  }

  if (normalizedDirection == "outgoing" && receiverId.trim().isNotEmpty) {
    final inboxRef = firestore
        .collection("users")
        .doc(receiverId)
        .collection("admin_inbox")
        .doc();
    final sentRef = firestore.collection("admin_inbox_messages").doc();
    final legacyPayload = {
      "userId": receiverId,
      "title": subject.trim(),
      "message": message.trim(),
      "type": "admin_message",
      "audience": receiverRole,
      "read": false,
      "threadId": threadRef.id,
      "adminMessageId": messageRef.id,
      if (relatedTargetType != null) "relatedTargetType": relatedTargetType,
      if (relatedTargetId != null) "relatedTargetId": relatedTargetId,
      "createdAt": now,
    };
    batch.set(inboxRef, legacyPayload);
    batch.set(sentRef, {
      ...legacyPayload,
      "targetUserId": receiverId,
      "recipientCount": 1,
    });
  }

  batch.set(
    firestore.collection("unread_counters").doc("admin"),
    {
      if (normalizedDirection == "incoming")
        "unreadInbox": FieldValue.increment(1),
      "updatedAt": now,
    },
    SetOptions(merge: true),
  );

  await batch.commit();
  return messageRef.id;
}

Future<List<Map<String, dynamic>>> _uploadAdminMailImages(
  List<XFile> files,
) async {
  final uploaded = <Map<String, dynamic>>[];
  final uid = FirebaseAuth.instance.currentUser?.uid ?? "admin";
  for (final file in files) {
    final name = file.name.isNotEmpty
        ? file.name
        : "attachment_${DateTime.now().microsecondsSinceEpoch}.jpg";
    final ref = FirebaseStorage.instance
        .ref("admin_mail/$uid/${DateTime.now().microsecondsSinceEpoch}_$name");
    await ref.putFile(File(file.path));
    final url = await ref.getDownloadURL();
    uploaded.add({
      "name": name,
      "url": url,
      "type": "image",
    });
  }
  return uploaded;
}

Future<void> _markAdminMessageRead(DocumentReference ref) async {
  await ref.set({
    "readByAdmin": true,
    "readAt": FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
}

Future<void> _markAdminMessageUnread(DocumentReference ref) async {
  await ref.set({
    "readByAdmin": false,
    "readAt": FieldValue.delete(),
  }, SetOptions(merge: true));
}

Future<void> _deleteAdminMessage(DocumentReference ref) async {
  await ref.set({
    "deletedByAdmin": true,
    "deletedAt": FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
}

Future<void> _toggleAdminMessageImportant(
  DocumentReference ref,
  bool important,
) async {
  await ref.set({
    "important": !important,
    "updatedAt": FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
}

String _adminMailTimeLabel(DateTime? date) {
  if (date == null) return "";
  final now = DateTime.now();
  if (date.year == now.year && date.month == now.month && date.day == now.day) {
    return "${date.hour.toString().padLeft(2, "0")}:"
        "${date.minute.toString().padLeft(2, "0")}";
  }
  return "${date.day.toString().padLeft(2, "0")}/"
      "${date.month.toString().padLeft(2, "0")}";
}

IconData _attachmentIcon(String type) {
  final normalized = type.toLowerCase();
  if (normalized.contains("image")) return Icons.image_outlined;
  if (normalized.contains("pdf")) return Icons.picture_as_pdf_outlined;
  if (normalized.contains("doc")) return Icons.description_outlined;
  if (normalized.contains("video")) return Icons.video_file_outlined;
  if (normalized.contains("audio")) return Icons.audio_file_outlined;
  if (normalized.contains("zip") || normalized.contains("archive")) {
    return Icons.folder_zip_outlined;
  }
  return Icons.attach_file;
}

class _AdminInboxTab extends StatefulWidget {
  const _AdminInboxTab();

  @override
  State<_AdminInboxTab> createState() => _AdminInboxTabState();
}

class _AdminInboxTabState extends State<_AdminInboxTab>
    with SingleTickerProviderStateMixin {
  late final TabController controller;

  @override
  void initState() {
    super.initState();
    controller = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        StroykaSurface(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(8),
          child: TabBar(
            controller: controller,
            labelColor: AppColors.greenDark,
            unselectedLabelColor: AppColors.muted,
            indicatorSize: TabBarIndicatorSize.tab,
            tabs: const [
              Tab(text: "Incoming"),
              Tab(text: "Sent"),
              Tab(text: "Deleted"),
            ],
          ),
        ),
        SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.68,
          child: TabBarView(
            controller: controller,
            children: const [
              _AdminMailboxList(mailbox: "incoming"),
              _AdminMailboxList(mailbox: "sent"),
              _AdminMailboxList(mailbox: "deleted"),
            ],
          ),
        ),
      ],
    );
  }
}

class _AdminMailboxList extends StatelessWidget {
  final String mailbox;

  const _AdminMailboxList({
    required this.mailbox,
  });

  Query<Map<String, dynamic>> query() {
    return FirebaseFirestore.instance
        .collection("admin_messages")
        .orderBy("createdAt", descending: true);
  }

  @override
  Widget build(BuildContext context) {
    return StroykaSurface(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: query().snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const LinearProgressIndicator();
          final docs = snapshot.data!.docs.where((doc) {
            final data = doc.data();
            final direction = data["direction"]?.toString() ?? "incoming";
            final deleted = data["deletedByAdmin"] == true;
            if (mailbox == "sent") return direction == "outgoing" && !deleted;
            if (mailbox == "deleted") return deleted;
            return direction == "incoming" && !deleted;
          }).toList();
          if (docs.isEmpty) {
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
            itemCount: docs.length,
            separatorBuilder: (_, __) => Divider(
              height: 1,
              color: AppColors.muted.withValues(alpha: 0.18),
            ),
            itemBuilder: (context, index) {
              return _AdminMailListRow(
                doc: docs[index],
                mailbox: mailbox,
              );
            },
          );
        },
      ),
    );
  }
}

class _AdminMailListRow extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final String mailbox;

  const _AdminMailListRow({
    required this.doc,
    required this.mailbox,
  });

  @override
  Widget build(BuildContext context) {
    final data = doc.data();
    final direction = data["direction"]?.toString() ?? "incoming";
    final isDeleted = data["deletedByAdmin"] == true;
    final unread = direction == "incoming" && data["readByAdmin"] != true;
    final important = data["important"] == true;
    final subject = data["subject"]?.toString() ?? "No subject";
    final message = data["message"]?.toString() ?? "";
    final createdAt = data["createdAt"] is Timestamp
        ? (data["createdAt"] as Timestamp).toDate()
        : null;
    final attachments =
        (data["attachments"] as List?)?.whereType<Map>().toList() ?? [];
    final displayName = direction == "outgoing"
        ? (data["receiverName"]?.toString() ?? "Recipient")
        : (data["senderName"]?.toString() ?? "Sender");
    final role = direction == "outgoing"
        ? (data["receiverRole"]?.toString() ?? "")
        : (data["senderRole"]?.toString() ?? "");

    return InkWell(
      onTap: () async {
        if (unread) await _markAdminMessageRead(doc.reference);
        if (!context.mounted) return;
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => _AdminMailThreadScreen(
              threadId: data["threadId"]?.toString() ?? doc.id,
              initialMessageId: doc.id,
            ),
          ),
        );
      },
      onLongPress: () => _showAdminMailRowActions(
        context,
        doc.reference,
        unread: unread,
        important: important,
        deleted: isDeleted,
      ),
      child: Container(
        color: unread
            ? AppColors.blueprintLine.withValues(alpha: 0.12)
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(
                important ? Icons.star : Icons.star_border,
                color: important ? AppColors.warning : AppColors.muted,
              ),
              onPressed: () =>
                  _toggleAdminMessageImportant(doc.reference, important),
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
                          subject,
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
                        Icon(
                          _attachmentIcon(
                            attachments.first["type"]?.toString() ?? "",
                          ),
                          size: 16,
                          color: AppColors.greenDark,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    message,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.muted,
                      fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  if (role.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        BillingService.formatLabel(role),
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 54,
              child: Text(
                _adminMailTimeLabel(createdAt),
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

Future<void> _showAdminMailRowActions(
  BuildContext context,
  DocumentReference ref, {
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
                    await _markAdminMessageRead(ref);
                  } else {
                    await _markAdminMessageUnread(ref);
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
                  await _toggleAdminMessageImportant(ref, important);
                },
              ),
            if (!deleted)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text("Delete"),
                onTap: () async {
                  Navigator.pop(context);
                  await _deleteAdminMessage(ref);
                },
              ),
          ],
        ),
      );
    },
  );
}

class _AdminMailThreadScreen extends StatelessWidget {
  final String threadId;
  final String initialMessageId;

  const _AdminMailThreadScreen({
    required this.threadId,
    required this.initialMessageId,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Admin mail")),
      body: StroykaScreenBody(
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection("admin_messages")
              .where("threadId", isEqualTo: threadId)
              .orderBy("createdAt")
              .snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final docs = snapshot.data!.docs;
            if (docs.isEmpty) {
              return const Center(child: Text("Message thread not found"));
            }
            final first = docs.first.data();
            final latest = docs.last.data();
            final subject = first["subject"]?.toString() ?? "No subject";
            final participantName =
                first["receiverName"]?.toString().isNotEmpty == true
                    ? first["receiverName"].toString()
                    : latest["senderName"]?.toString() ?? "Participant";
            final participantRole =
                first["receiverRole"]?.toString().isNotEmpty == true
                    ? first["receiverRole"].toString()
                    : latest["senderRole"]?.toString() ?? "";
            final selectedDoc = docs.firstWhere(
              (doc) => doc.id == initialMessageId,
              orElse: () => docs.last,
            );
            final selectedData = selectedDoc.data();

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
                              Icons.mark_email_unread_outlined,
                              color: AppColors.greenDark,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  participantName,
                                  style: const TextStyle(
                                    color: AppColors.ink,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                Text(
                                  BillingService.formatLabel(participantRole),
                                  style: const TextStyle(
                                    color: AppColors.muted,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text(
                        subject,
                        style: const TextStyle(
                          color: AppColors.ink,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                ...docs.map((doc) {
                  return _AdminMailMessageCard(
                    doc: doc,
                    selected: doc.id == selectedDoc.id,
                  );
                }),
                const SizedBox(height: 8),
                StroykaSurface(
                  padding: const EdgeInsets.all(12),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ElevatedButton.icon(
                        onPressed: () => _showAdminMailReplyComposer(
                          context,
                          source: selectedData,
                          threadId: threadId,
                          forward: false,
                        ),
                        icon: const Icon(Icons.reply),
                        label: const Text("Reply"),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _showAdminMailReplyComposer(
                          context,
                          source: selectedData,
                          threadId: threadId,
                          forward: true,
                        ),
                        icon: const Icon(Icons.forward),
                        label: const Text("Forward"),
                      ),
                      OutlinedButton.icon(
                        onPressed: () =>
                            _markAdminMessageUnread(selectedDoc.reference),
                        icon: const Icon(Icons.mark_email_unread_outlined),
                        label: const Text("Mark unread"),
                      ),
                      OutlinedButton.icon(
                        onPressed: () async {
                          await _deleteAdminMessage(selectedDoc.reference);
                          if (context.mounted) Navigator.pop(context);
                        },
                        icon: const Icon(Icons.delete_outline),
                        label: const Text("Delete"),
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

class _AdminMailMessageCard extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final bool selected;

  const _AdminMailMessageCard({
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
    final createdAt = data["createdAt"] is Timestamp
        ? (data["createdAt"] as Timestamp).toDate()
        : null;
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
                _formatAdminDate(createdAt),
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
            const _ReportMetaChip(label: "Opened", value: "current"),
          ],
          const SizedBox(height: 12),
          Text(message),
          if (attachments.isNotEmpty) ...[
            const SizedBox(height: 12),
            _AdminMailAttachmentWrap(attachments: attachments),
          ],
        ],
      ),
    );
  }
}

class _AdminMailAttachmentWrap extends StatelessWidget {
  final List<Map> attachments;

  const _AdminMailAttachmentWrap({
    required this.attachments,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: attachments.map((attachment) {
        final type = attachment["type"]?.toString() ?? "";
        final name = attachment["name"]?.toString() ?? "Attachment";
        final url = attachment["url"]?.toString() ?? "";
        return ActionChip(
          avatar: Icon(_attachmentIcon(type), size: 18),
          label: Text(name),
          onPressed: url.isEmpty
              ? null
              : () async {
                  final uri = Uri.tryParse(url);
                  if (uri == null) return;
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                },
        );
      }).toList(),
    );
  }
}

Future<void> _showAdminMailReplyComposer(
  BuildContext context, {
  required Map<String, dynamic> source,
  required String threadId,
  required bool forward,
}) async {
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
        child: SingleChildScrollView(
          child: _AdminMailReplyComposer(
            source: source,
            threadId: threadId,
            forward: forward,
          ),
        ),
      );
    },
  );
}

class _AdminMailReplyComposer extends StatefulWidget {
  final Map<String, dynamic> source;
  final String threadId;
  final bool forward;

  const _AdminMailReplyComposer({
    required this.source,
    required this.threadId,
    required this.forward,
  });

  @override
  State<_AdminMailReplyComposer> createState() =>
      _AdminMailReplyComposerState();
}

class _AdminMailReplyComposerState extends State<_AdminMailReplyComposer> {
  final receiverController = TextEditingController();
  final messageController = TextEditingController();
  bool sending = false;

  @override
  void initState() {
    super.initState();
    if (widget.forward) {
      messageController.text =
          "\n\nForwarded message:\n${widget.source["message"] ?? ""}";
    }
  }

  @override
  void dispose() {
    receiverController.dispose();
    messageController.dispose();
    super.dispose();
  }

  Future<void> send() async {
    final message = messageController.text.trim();
    final receiverId = widget.forward
        ? receiverController.text.trim()
        : (widget.source["senderRole"] == "admin"
            ? widget.source["receiverId"]?.toString() ?? ""
            : widget.source["senderId"]?.toString() ?? "");
    final receiverRole = widget.forward
        ? "worker"
        : (widget.source["senderRole"] == "admin"
            ? widget.source["receiverRole"]?.toString() ?? ""
            : widget.source["senderRole"]?.toString() ?? "");

    if (receiverId.isEmpty || message.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Enter recipient and message")),
      );
      return;
    }

    setState(() => sending = true);
    try {
      await _createAdminMailMessage(
        direction: "outgoing",
        receiverId: receiverId,
        receiverRole: receiverRole,
        subject:
            "${widget.forward ? "Fwd" : "Re"}: ${widget.source["subject"] ?? "Admin mail"}",
        message: message,
        threadId: widget.forward ? null : widget.threadId,
        attachments: widget.forward
            ? ((widget.source["attachments"] as List?)
                    ?.whereType<Map>()
                    .map((item) => Map<String, dynamic>.from(item))
                    .toList() ??
                const [])
            : const [],
      );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.forward ? "Forwarded" : "Reply sent")),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not send message")),
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
        children: [
          Text(
            widget.forward ? "Forward message" : "Reply",
            style: const TextStyle(
              color: AppColors.ink,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (widget.forward) ...[
            const SizedBox(height: 10),
            TextField(
              controller: receiverController,
              enabled: !sending,
              decoration: const InputDecoration(
                labelText: "Recipient user ID",
              ),
            ),
          ],
          const SizedBox(height: 10),
          TextField(
            controller: messageController,
            enabled: !sending,
            maxLines: 5,
            decoration: const InputDecoration(labelText: "Message"),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
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
  final picker = ImagePicker();
  final attachments = <XFile>[];
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

      final uploadedAttachments = await _uploadAdminMailImages(attachments);
      for (final userId in recipients) {
        await _createAdminMailMessage(
          direction: "outgoing",
          receiverId: userId,
          receiverRole: audience,
          subject: title,
          message: message,
          attachments: uploadedAttachments,
        );
      }

      if (!mounted) return;
      titleController.clear();
      messageController.clear();
      attachments.clear();
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

  Future<void> pickAttachments() async {
    final files = await picker.pickMultiImage();
    if (files.isEmpty) return;
    setState(() => attachments.addAll(files));
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
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: sending ? null : pickAttachments,
                icon: const Icon(Icons.attach_file),
                label: const Text("Attach images"),
              ),
              ...attachments.map(
                (file) => InputChip(
                  avatar: const Icon(Icons.image_outlined, size: 18),
                  label: Text(
                    file.name,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onDeleted: sending
                      ? null
                      : () => setState(() => attachments.remove(file)),
                ),
              ),
            ],
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
          leading: _AdminAvatar(
            data: employerData,
            fallbackIcon: Icons.business_outlined,
          ),
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
                        child: TextButton(
                          style: TextButton.styleFrom(
                            alignment: Alignment.centerLeft,
                            padding: EdgeInsets.zero,
                          ),
                          onPressed: employerId.isEmpty
                              ? null
                              : () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => EmployerProfileScreen(
                                        userId: employerId,
                                      ),
                                    ),
                                  );
                                },
                          child: Text(
                            companyName,
                            style: const TextStyle(
                              color: AppColors.greenDark,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              decoration: TextDecoration.underline,
                            ),
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
  final Widget? leading;
  final VoidCallback onTap;

  const _AdminRequestListCard({
    required this.title,
    required this.subtitle,
    required this.status,
    required this.chips,
    this.leading,
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
                if (leading != null) ...[
                  leading!,
                  const SizedBox(width: 12),
                ],
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

class _AdminAvatar extends StatelessWidget {
  final Map<String, dynamic> data;
  final IconData fallbackIcon;

  const _AdminAvatar({
    required this.data,
    this.fallbackIcon = Icons.person_outline,
  });

  @override
  Widget build(BuildContext context) {
    final url = (data["photoUrl"] ??
            data["avatarUrl"] ??
            data["profileImageUrl"] ??
            data["logoUrl"] ??
            data["companyLogoUrl"] ??
            "")
        .toString()
        .trim();
    final fallback = Icon(fallbackIcon, color: AppColors.greenDark);

    return ClipOval(
      child: Container(
        width: 48,
        height: 48,
        color: AppColors.green.withValues(alpha: 0.12),
        child: url.isEmpty
            ? fallback
            : Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => fallback,
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return fallback;
                },
              ),
      ),
    );
  }
}

class _AdminUserRequestCard extends StatelessWidget {
  final String userId;
  final String fallbackTitle;
  final String fallbackRole;
  final String subtitle;
  final String status;
  final List<Widget> chips;
  final VoidCallback onTap;

  const _AdminUserRequestCard({
    required this.userId,
    required this.fallbackTitle,
    required this.fallbackRole,
    required this.subtitle,
    required this.status,
    required this.chips,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot>(
      future: userId.trim().isEmpty
          ? null
          : FirebaseFirestore.instance.collection("users").doc(userId).get(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data() as Map<String, dynamic>? ?? {};
        final role = (data["role"] ?? fallbackRole).toString();
        final title = (role == "employer"
                ? data["companyName"] ?? data["name"]
                : data["name"] ?? data["displayName"])
            ?.toString()
            .trim();
        final displayTitle =
            title == null || title.isEmpty ? fallbackTitle : title;

        return _AdminRequestListCard(
          title: displayTitle,
          subtitle: subtitle,
          status: status,
          leading: _AdminAvatar(
            data: data,
            fallbackIcon:
                role == "employer" ? Icons.business_outlined : Icons.person,
          ),
          chips: [
            _ReportMetaChip(label: "Role", value: role),
            ...chips,
          ],
          onTap: onTap,
        );
      },
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

    return _AdminUserRequestCard(
      userId: data["userId"]?.toString() ?? "",
      fallbackTitle: supportTypeLabel(data),
      fallbackRole: data["userRole"]?.toString() ?? "",
      subtitle: message,
      status: selectedStatus,
      chips: [
        _ReportMetaChip(label: "Topic", value: supportTypeLabel(data)),
        _ReportMetaChip(label: "Type", value: type),
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

    return _AdminUserRequestCard(
      userId: data["fromUserId"]?.toString() ?? "",
      fallbackTitle: type,
      fallbackRole: "user",
      subtitle: message,
      status: selectedStatus,
      chips: [
        _ReportMetaChip(label: "Topic", value: type),
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
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
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
                const CircleAvatar(
                  radius: 24,
                  backgroundColor: Color(0x297DB9D8),
                  child: Icon(
                    Icons.work_outline,
                    color: AppColors.greenDark,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        job.displayTitle,
                        style: const TextStyle(
                          color: AppColors.ink,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        job.companyName,
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                _AdminStatusPill(job.moderationStatus),
                const Icon(
                  Icons.chevron_right,
                  color: AppColors.muted,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _ReportMetaChip(label: "Trade", value: job.trade),
                _ReportMetaChip(label: "Site", value: job.site),
                _ReportMetaChip(label: "Location", value: location),
                _ReportMetaChip(
                  label: "Created",
                  value: _formatAdminDate(job.createdAt),
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
