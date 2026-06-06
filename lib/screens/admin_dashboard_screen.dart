import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io';

import '../models/job.dart';
import '../services/billing_service.dart';
import '../services/job_alert_service.dart';
import '../services/notification_service.dart';
import '../widgets/job_card.dart';
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
      "status": "active",
      "visibility": "public",
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
    final reason = await _askAdminReply(
      context,
      title: "Reject job",
      label: "Moderation reason",
      hint: "Explain why this job was rejected",
      requiredMessage: true,
    );
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
      requiredMessage: true,
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

    await NotificationService().notifyEmployerJobModeration(
      employerId: job.ownerId,
      jobId: job.id,
      jobTitle: job.displayTitle,
      moderationStatus: "on_hold",
      reason: reason,
    );

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
    await doc.reference.set({
      "viewedByAdmin": true,
      "lastAdminViewedAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    if (!mounted || !context.mounted) return;

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
        onPaymentStatusChanged: updatePaymentRequestStatus,
      ),
      const _FinancialReportsSection(
        complaintsSection: SizedBox.shrink(),
      ),
    ];
    final currentIndex =
        selectedIndex >= pages.length ? pages.length - 1 : selectedIndex;

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
          children: [pages[currentIndex]],
        ),
      ),
      floatingActionButton: currentIndex == 0
          ? FloatingActionButton(
              tooltip: "New admin message",
              onPressed: () => _showAdminMessageComposer(context),
              child: const Icon(Icons.mark_email_unread_outlined),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
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
          NavigationDestination(
            icon: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection("jobs")
                  .where("moderationStatus", isEqualTo: "pending_review")
                  .snapshots(),
              builder: (context, snapshot) {
                final count = snapshot.data?.docs.where((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      return data["viewedByAdmin"] != true;
                    }).length ??
                    0;
                if (count == 0) return const Icon(Icons.fact_check_outlined);
                return Badge.count(
                  count: count,
                  child: const Icon(Icons.fact_check_outlined),
                );
              },
            ),
            label: "Jobs",
          ),
          const NavigationDestination(
            icon: _AdminSupportNavIcon(),
            label: "Support\nBilling",
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

class _AdminSupportNavIcon extends StatelessWidget {
  const _AdminSupportNavIcon();

  bool _isUnread(Map<String, dynamic> data) {
    final deleted = data["deletedByAdmin"] == true;
    if (deleted) return false;
    return data["readByAdmin"] != true && data["viewedByAdmin"] != true;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream:
          FirebaseFirestore.instance.collection("support_requests").snapshots(),
      builder: (context, supportSnapshot) {
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection("reports").snapshots(),
          builder: (context, reportsSnapshot) {
            return StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection("payment_requests")
                  .snapshots(),
              builder: (context, paymentsSnapshot) {
                var count = 0;
                for (final snapshot in [
                  supportSnapshot.data,
                  reportsSnapshot.data,
                  paymentsSnapshot.data,
                ]) {
                  if (snapshot == null) continue;
                  count += snapshot.docs.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    return _isUnread(data);
                  }).length;
                }
                if (count == 0) return const Icon(Icons.support_agent_outlined);
                return Badge.count(
                  count: count,
                  child: const Icon(Icons.support_agent_outlined),
                );
              },
            );
          },
        );
      },
    );
  }
}

Future<String?> _askAdminReply(
  BuildContext context, {
  required String title,
  required String label,
  String? hint,
  bool requiredMessage = false,
}) async {
  final controller = TextEditingController();
  String? errorText;
  final result = await showDialog<String>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(title),
            content: TextField(
              controller: controller,
              maxLines: 5,
              decoration: InputDecoration(
                labelText: label,
                hintText: hint,
                errorText: errorText,
                border: const StroykaInputBorder(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Cancel"),
              ),
              ElevatedButton(
                onPressed: () {
                  final text = controller.text.trim();
                  if (requiredMessage && text.isEmpty) {
                    setDialogState(() {
                      errorText = "Moderator message is required";
                    });
                    return;
                  }
                  Navigator.pop(context, text);
                },
                child: const Text("Send"),
              ),
            ],
          );
        },
      );
    },
  );
  await Future<void>.delayed(const Duration(milliseconds: 16));
  controller.dispose();
  return result;
}

class _AdminReplyDraft {
  final String message;
  final List<Map<String, dynamic>> attachments;

  const _AdminReplyDraft({
    required this.message,
    required this.attachments,
  });
}

Future<_AdminReplyDraft?> _askAdminReplyWithAttachments(
  BuildContext context, {
  required String title,
  required String label,
  String? hint,
  bool requiredMessage = false,
}) async {
  final controller = TextEditingController();
  final attachments = <PlatformFile>[];
  String? errorText;

  final result = await showModalBottomSheet<_AdminReplyDraft>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) {
      var uploading = false;
      return StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> pickFiles() async {
            final files = await FilePicker.platform.pickFiles(
              allowMultiple: true,
              withData: false,
            );
            if (files == null || files.files.isEmpty || !context.mounted) {
              return;
            }
            setDialogState(() => attachments.addAll(files.files));
          }

          Future<void> send() async {
            final text = controller.text.trim();
            if (requiredMessage && text.isEmpty) {
              setDialogState(() {
                errorText = "Moderator message is required";
              });
              return;
            }
            if (text.isEmpty && attachments.isEmpty) {
              setDialogState(() {
                errorText = "Enter message or attach a file";
              });
              return;
            }
            setDialogState(() => uploading = true);
            try {
              final uploaded = await _uploadAdminMailFiles(attachments);
              if (!context.mounted) return;
              Navigator.pop(
                context,
                _AdminReplyDraft(message: text, attachments: uploaded),
              );
            } catch (_) {
              if (!context.mounted) return;
              setDialogState(() {
                uploading = false;
                errorText = "Could not upload attachments";
              });
            }
          }

          return Padding(
            padding: EdgeInsets.only(
              left: 12,
              right: 12,
              top: 12,
              bottom: MediaQuery.viewInsetsOf(context).bottom + 12,
            ),
            child: StroykaSurface(
              padding: const EdgeInsets.all(14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
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
                  TextField(
                    controller: controller,
                    enabled: !uploading,
                    maxLines: 5,
                    decoration: InputDecoration(
                      labelText: label,
                      hintText: hint,
                      errorText: errorText,
                      border: const StroykaInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      OutlinedButton.icon(
                        onPressed: uploading ? null : pickFiles,
                        icon: const Icon(Icons.attach_file),
                        label: const Text("Attach files"),
                      ),
                      ...attachments.map(
                        (file) => InputChip(
                          avatar: Icon(_attachmentIcon(file.extension ?? "")),
                          label:
                              Text(file.name, overflow: TextOverflow.ellipsis),
                          onDeleted: uploading
                              ? null
                              : () => setDialogState(
                                    () => attachments.remove(file),
                                  ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      TextButton(
                        onPressed:
                            uploading ? null : () => Navigator.pop(context),
                        child: const Text("Cancel"),
                      ),
                      const Spacer(),
                      ElevatedButton.icon(
                        onPressed: uploading ? null : send,
                        icon: uploading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.send),
                        label: Text(uploading ? "Sending..." : "Send"),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
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
  String? threadId,
  String? relatedTargetType,
  String? relatedTargetId,
  List<Map<String, dynamic>> attachments = const [],
}) async {
  if (userId.trim().isEmpty ||
      title.trim().isEmpty ||
      (message.trim().isEmpty && attachments.isEmpty)) {
    return;
  }

  await _createAdminMailMessage(
    direction: "outgoing",
    receiverId: userId,
    receiverRole: audience,
    subject: title,
    message: message,
    threadId: threadId,
    attachments: attachments,
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
  final audienceType =
      receiverRole.trim().isEmpty ? "specific_user" : receiverRole.trim();
  final canReply = !audienceType.startsWith("all_");
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
    "recipientId": receiverId,
    "recipientRole": receiverRole,
    "threadParticipants": [
      "admin",
      if (receiverId.trim().isNotEmpty) receiverId.trim(),
    ],
    "audienceType": audienceType,
    "canReply": canReply,
    "subject": subject.trim(),
    "message": message.trim(),
    "type": "admin_message",
    if (relatedTargetType == "support" ||
        relatedTargetType == "support_request")
      "relatedSupportRequestId": relatedTargetId,
    if (relatedTargetType == "payment_request" ||
        relatedTargetType == "billing")
      "relatedBillingRequestId": relatedTargetId,
    "readByAdmin": normalizedDirection == "outgoing",
    "readByReceiver": normalizedDirection == "incoming",
    "important": false,
    "deletedByAdmin": false,
    "deletedByReceiver": false,
    "deletedBySender": false,
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
      "targetType": "admin_message",
      "targetId": threadRef.id,
      "audience": receiverRole,
      "audienceType": audienceType,
      "canReply": canReply,
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
    final notificationRef = firestore
        .collection("users")
        .doc(receiverId)
        .collection("notifications")
        .doc();
    batch.set(notificationRef, {
      "notificationId": notificationRef.id,
      "userId": receiverId,
      "type": "admin_message",
      "category": "admin",
      "targetType": "admin_message",
      "targetId": threadRef.id,
      "threadId": threadRef.id,
      "adminMessageId": messageRef.id,
      "title": subject.trim(),
      "message": message.trim(),
      "read": false,
      "badgeEligible": true,
      "pushEligible": true,
      "push": {
        "title": subject.trim(),
        "body": message.trim(),
        "category": "admin",
        "sound": true,
        "badge": true,
        "data": {
          "notificationId": notificationRef.id,
          "userId": receiverId,
          "type": "admin_message",
          "category": "admin",
          "targetType": "admin_message",
          "targetId": threadRef.id,
          "threadId": threadRef.id,
          "adminMessageId": messageRef.id,
        },
      },
      "createdAt": now,
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

Future<List<Map<String, dynamic>>> _uploadAdminMailFiles(
  List<PlatformFile> files,
) async {
  final uploaded = <Map<String, dynamic>>[];
  final uid = FirebaseAuth.instance.currentUser?.uid ?? "admin";
  for (final file in files) {
    final path = file.path;
    if (path == null || path.isEmpty) continue;
    final name = file.name.isNotEmpty
        ? file.name
        : "attachment_${DateTime.now().microsecondsSinceEpoch}";
    final extension =
        name.contains(".") ? name.split(".").last.toLowerCase() : "";
    final ref = FirebaseStorage.instance
        .ref("admin_mail/$uid/${DateTime.now().microsecondsSinceEpoch}_$name");
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

String _normalizeAdminSupportStatus(dynamic value) {
  final status = value?.toString().trim() ?? "";
  if (status == "in_review") return "in_progress";
  if (status == "rejected") return "closed";
  if (status.isEmpty) return "open";
  return status;
}

DateTime _adminRequestSortDate(Map<String, dynamic> data) {
  final value = data["createdAt"] ?? data["updatedAt"];
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value) ?? DateTime(0);
  return DateTime(0);
}

bool _adminRequestUnread(Map<String, dynamic> data) {
  return data["readByAdmin"] != true && data["viewedByAdmin"] != true;
}

class _AdminSupportListItem {
  final QueryDocumentSnapshot doc;
  final String kind;
  final DateTime createdAt;
  final bool unread;

  const _AdminSupportListItem({
    required this.doc,
    required this.kind,
    required this.createdAt,
    required this.unread,
  });

  Map<String, dynamic> get data => doc.data() as Map<String, dynamic>;
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
            labelStyle: AppTypography.tab,
            unselectedLabelStyle: AppTypography.tabUnselected,
            labelPadding: const EdgeInsets.symmetric(horizontal: 20),
            tabs: const [
              Tab(height: 48, text: "Incoming"),
              Tab(height: 48, text: "Sent"),
              Tab(height: 48, text: "Deleted"),
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
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  "Could not load admin mail: ${snapshot.error}",
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          if (!snapshot.hasData) return const LinearProgressIndicator();
          final threads = _AdminMailThreadPreview.group(
            snapshot.data!.docs,
            mailbox: mailbox,
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
              return _AdminMailListRow(
                thread: threads[index],
                mailbox: mailbox,
              );
            },
          );
        },
      ),
    );
  }
}

class _AdminMailThreadPreview {
  final String key;
  final String participantKey;
  final String normalizedSubject;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  final QueryDocumentSnapshot<Map<String, dynamic>> latestDoc;
  final String mailbox;

  const _AdminMailThreadPreview({
    required this.key,
    required this.participantKey,
    required this.normalizedSubject,
    required this.docs,
    required this.latestDoc,
    required this.mailbox,
  });

  bool get unread => docs.any((doc) {
        final data = doc.data();
        return data["direction"] == "incoming" &&
            data["readByAdmin"] != true &&
            data["deletedByAdmin"] != true;
      });

  bool get important => docs.any((doc) => doc.data()["important"] == true);

  List<DocumentReference<Map<String, dynamic>>> get unreadRefs => docs
      .where((doc) {
        final data = doc.data();
        return data["direction"] == "incoming" &&
            data["readByAdmin"] != true &&
            data["deletedByAdmin"] != true;
      })
      .map((doc) => doc.reference)
      .toList();

  static List<_AdminMailThreadPreview> group(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, {
    required String mailbox,
  }) {
    final grouped =
        <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};

    for (final doc in docs) {
      final data = doc.data();
      final deleted = data["deletedByAdmin"] == true;
      if (mailbox == "deleted") {
        if (!deleted) continue;
      } else if (deleted) {
        continue;
      }

      final participantKey = _adminMailParticipantKey(data);
      final subject = _normalizeAdminMailSubject(data["subject"]?.toString());
      final key = "$participantKey::$subject";
      grouped.putIfAbsent(key, () => []).add(doc);
    }

    final previews = <_AdminMailThreadPreview>[];
    for (final entry in grouped.entries) {
      final threadDocs = entry.value..sort(_compareAdminMailDocs);
      final hasIncoming =
          threadDocs.any((doc) => doc.data()["direction"] == "incoming");
      final hasOutgoing =
          threadDocs.any((doc) => doc.data()["direction"] == "outgoing");
      if (mailbox == "incoming" && !hasIncoming) continue;
      if (mailbox == "sent" && !hasOutgoing) continue;

      final latest = threadDocs.last;
      final parts = entry.key.split("::");
      previews.add(
        _AdminMailThreadPreview(
          key: entry.key,
          participantKey: parts.first,
          normalizedSubject:
              parts.length > 1 ? parts.sublist(1).join("::") : "",
          docs: List.unmodifiable(threadDocs),
          latestDoc: latest,
          mailbox: mailbox,
        ),
      );
    }

    previews.sort((a, b) => _compareAdminMailDocs(b.latestDoc, a.latestDoc));
    return previews;
  }
}

int _compareAdminMailDocs(
  QueryDocumentSnapshot<Map<String, dynamic>> a,
  QueryDocumentSnapshot<Map<String, dynamic>> b,
) {
  return (_adminMailDate(a.data()) ?? DateTime.fromMillisecondsSinceEpoch(0))
      .compareTo(
    _adminMailDate(b.data()) ?? DateTime.fromMillisecondsSinceEpoch(0),
  );
}

DateTime? _adminMailDate(Map<String, dynamic> data) {
  final value = data["createdAt"];
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}

String _adminMailParticipantKey(Map<String, dynamic> data) {
  final direction = data["direction"]?.toString() ?? "incoming";
  final id = direction == "outgoing"
      ? data["receiverId"]?.toString()
      : data["senderId"]?.toString();
  if (id != null && id.trim().isNotEmpty && id != "admin") {
    return id.trim();
  }
  final name = direction == "outgoing"
      ? data["receiverName"]?.toString()
      : data["senderName"]?.toString();
  return name?.trim().toLowerCase() ?? "unknown";
}

String _normalizeAdminMailSubject(String? value) {
  var subject = value?.trim() ?? "No subject";
  final prefix = RegExp(r"^(re|fw|fwd)\s*:\s*", caseSensitive: false);
  while (prefix.hasMatch(subject)) {
    subject = subject.replaceFirst(prefix, "").trim();
  }
  return subject.isEmpty ? "No subject" : subject.toLowerCase();
}

String _displayAdminMailSubject(String? value) {
  final normalized = _normalizeAdminMailSubject(value);
  if (normalized == "no subject") return "No subject";
  return normalized
      .split(" ")
      .map((word) => word.isEmpty
          ? word
          : "${word[0].toUpperCase()}${word.length > 1 ? word.substring(1) : ""}")
      .join(" ");
}

class _AdminMailListRow extends StatelessWidget {
  final _AdminMailThreadPreview thread;
  final String mailbox;

  const _AdminMailListRow({
    required this.thread,
    required this.mailbox,
  });

  @override
  Widget build(BuildContext context) {
    final data = thread.latestDoc.data();
    final direction = data["direction"]?.toString() ?? "incoming";
    final isDeleted = data["deletedByAdmin"] == true;
    final unread = thread.unread;
    final important = thread.important;
    final subject = _displayAdminMailSubject(data["subject"]?.toString());
    final message = data["message"]?.toString() ?? "";
    final createdAt = _adminMailDate(data);
    final attachments = thread.docs
        .expand((doc) =>
            (doc.data()["attachments"] as List?)?.whereType<Map>() ??
            const Iterable<Map>.empty())
        .toList();
    final displayName = direction == "outgoing"
        ? (data["receiverName"]?.toString() ?? "Recipient")
        : (data["senderName"]?.toString() ?? "Sender");
    final role = direction == "outgoing"
        ? (data["receiverRole"]?.toString() ?? "")
        : (data["senderRole"]?.toString() ?? "");

    return InkWell(
      onTap: () async {
        if (unread) {
          for (final ref in thread.unreadRefs) {
            await _markAdminMessageRead(ref);
          }
        }
        if (!context.mounted) return;
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => _AdminMailThreadScreen(
              threadId: data["threadId"]?.toString() ?? thread.latestDoc.id,
              initialMessageId: thread.latestDoc.id,
              participantKey: thread.participantKey,
              normalizedSubject: thread.normalizedSubject,
            ),
          ),
        );
      },
      onLongPress: () => _showAdminMailRowActions(
        context,
        thread.latestDoc.reference,
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
              onPressed: () => _toggleAdminMessageImportant(
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
  final String? participantKey;
  final String? normalizedSubject;

  const _AdminMailThreadScreen({
    required this.threadId,
    required this.initialMessageId,
    this.participantKey,
    this.normalizedSubject,
  });

  @override
  Widget build(BuildContext context) {
    final hasGroupedThread = participantKey?.isNotEmpty == true &&
        normalizedSubject?.isNotEmpty == true;
    return Scaffold(
      appBar: AppBar(title: const Text("Admin mail")),
      body: StroykaScreenBody(
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: hasGroupedThread
              ? FirebaseFirestore.instance
                  .collection("admin_messages")
                  .snapshots()
              : FirebaseFirestore.instance
                  .collection("admin_messages")
                  .where("threadId", isEqualTo: threadId)
                  .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    "Could not load message thread: ${snapshot.error}",
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final docs = snapshot.data!.docs.where((doc) {
              final data = doc.data();
              if (data["deletedByAdmin"] == true) return false;
              if (!hasGroupedThread) return true;
              return _adminMailParticipantKey(data) == participantKey &&
                  _normalizeAdminMailSubject(data["subject"]?.toString()) ==
                      normalizedSubject;
            }).toList()
              ..sort(_compareAdminMailDocs);
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
            var selectedDoc = docs.last;
            for (final doc in docs) {
              if (doc.id == initialMessageId) {
                selectedDoc = doc;
                break;
              }
            }
            final selectedData = selectedDoc.data();
            DocumentReference? markUnreadRef;
            for (final doc in docs.reversed) {
              final data = doc.data();
              if (data["direction"] == "incoming" &&
                  data["deletedByAdmin"] != true) {
                markUnreadRef = doc.reference;
                break;
              }
            }
            final unreadRefs = docs.where((doc) {
              final data = doc.data();
              return data["direction"] == "incoming" &&
                  data["readByAdmin"] != true &&
                  data["deletedByAdmin"] != true;
            }).map((doc) => doc.reference);
            if (unreadRefs.isNotEmpty) {
              WidgetsBinding.instance.addPostFrameCallback((_) async {
                for (final ref in unreadRefs) {
                  await _markAdminMessageRead(ref);
                }
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
                              Icons.mark_email_unread_outlined,
                              color: AppColors.greenDark,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  "Admin Mail",
                                  style: TextStyle(
                                    color: AppColors.muted,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
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
                          _AdminMailThreadActionsMenu(
                            source: selectedData,
                            threadId: threadId,
                            selectedRef: selectedDoc.reference,
                            markUnreadRef: markUnreadRef,
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
              ],
            );
          },
        ),
      ),
    );
  }
}

class _AdminMailThreadActionsMenu extends StatelessWidget {
  final Map<String, dynamic> source;
  final String threadId;
  final DocumentReference selectedRef;
  final DocumentReference? markUnreadRef;

  const _AdminMailThreadActionsMenu({
    required this.source,
    required this.threadId,
    required this.selectedRef,
    this.markUnreadRef,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: "Mail actions",
      icon: const Icon(Icons.more_horiz, color: AppColors.ink),
      onSelected: (value) async {
        switch (value) {
          case "reply":
            await _showAdminMailReplyComposer(
              context,
              source: source,
              threadId: threadId,
              forward: false,
            );
            break;
          case "forward":
            await _showAdminMailReplyComposer(
              context,
              source: source,
              threadId: threadId,
              forward: true,
            );
            break;
          case "unread":
            final navigator = Navigator.of(context);
            navigator.pop();
            await _markAdminMessageUnread(markUnreadRef ?? selectedRef);
            break;
          case "delete":
            await _deleteAdminMessage(selectedRef);
            if (context.mounted) Navigator.pop(context);
            break;
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: "reply",
          child: ListTile(
            leading: Icon(Icons.reply),
            title: Text("Reply"),
            dense: true,
          ),
        ),
        PopupMenuItem(
          value: "forward",
          child: ListTile(
            leading: Icon(Icons.forward),
            title: Text("Forward"),
            dense: true,
          ),
        ),
        PopupMenuItem(
          value: "unread",
          child: ListTile(
            leading: Icon(Icons.mark_email_unread_outlined),
            title: Text("Mark unread"),
            dense: true,
          ),
        ),
        PopupMenuItem(
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
        final type =
            (attachment["type"] ?? attachment["fileType"])?.toString().trim() ??
                "";
        final name =
            (attachment["name"] ?? attachment["fileName"])?.toString().trim() ??
                "Attachment";
        final url =
            (attachment["url"] ?? attachment["fileUrl"])?.toString().trim() ??
                "";
        return ActionChip(
          avatar: Icon(_attachmentIcon(type), size: 18),
          label: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Text(
              name,
              overflow: TextOverflow.ellipsis,
            ),
          ),
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
  final attachments = <PlatformFile>[];
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
      final uploadedAttachments = await _uploadAdminMailFiles(attachments);
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
            : uploadedAttachments,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.forward ? "Forwarded" : "Reply sent")),
      );
      Navigator.pop(context);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not send message")),
      );
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> pickAttachments() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: false,
    );
    if (result == null || result.files.isEmpty || !mounted) return;
    setState(() => attachments.addAll(result.files));
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
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              OutlinedButton.icon(
                onPressed: sending || widget.forward ? null : pickAttachments,
                icon: const Icon(Icons.attach_file),
                label: const Text("Attach files"),
              ),
              ...attachments.map(
                (file) => InputChip(
                  avatar: Icon(_attachmentIcon(file.extension ?? "")),
                  label: Text(file.name, overflow: TextOverflow.ellipsis),
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
  final attachments = <PlatformFile>[];
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
      case "all_users":
        return "All users";
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

    final users = audience == "all_users"
        ? await FirebaseFirestore.instance.collection("users").get()
        : await FirebaseFirestore.instance
            .collection("users")
            .where(
              "role",
              isEqualTo: audience == "all_employers" ? "employer" : "worker",
            )
            .get();

    return users.docs
        .where((doc) =>
            doc.data()["accountDeleted"] != true &&
            doc.data()["role"] != "admin")
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

      final uploadedAttachments = await _uploadAdminMailFiles(attachments);
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Admin message sent to ${recipients.length}")),
        );
        Navigator.pop(context);
        return;
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
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: false,
    );
    if (result == null || result.files.isEmpty || !mounted) return;
    setState(() => attachments.addAll(result.files));
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
              DropdownMenuItem(
                value: "all_users",
                child: Text("All users"),
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
                label: const Text("Attach files"),
              ),
              ...attachments.map(
                (file) => InputChip(
                  avatar: Icon(_attachmentIcon(file.extension ?? ""), size: 18),
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

class _PaymentRequestCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final DocumentReference ref;
  final Future<void> Function(String status) onStatusChanged;

  const _PaymentRequestCard({
    required this.data,
    required this.ref,
    required this.onStatusChanged,
  });

  static const statuses = [
    "pending",
    "approved",
    "failed",
    "on_hold",
    "cancelled",
    "rejected",
    "pending_user_reply",
  ];

  @override
  Widget build(BuildContext context) {
    final rawStatus = data["status"]?.toString();
    final status = rawStatus == "paid" ? "approved" : rawStatus;
    final selectedStatus = statuses.contains(status) ? status! : "pending";
    final planApprovalStatus =
        data["billingPlanStatus"]?.toString() ?? selectedStatus;
    final paymentStatus = data["paymentStatus"]?.toString() ?? "pending";
    final planName = data["planName"]?.toString().trim() ?? "Plan";
    final paymentMode = data["paymentMode"]?.toString().trim() ?? "";
    final employerId = data["employerId"]?.toString() ?? "";
    final createdAt = data["createdAt"] is Timestamp
        ? (data["createdAt"] as Timestamp).toDate()
        : null;
    final unread = data["readByAdmin"] != true && data["viewedByAdmin"] != true;

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
          status: planApprovalStatus,
          unread: unread,
          dateText: _adminMailTimeLabel(createdAt),
          leading: _AdminAvatar(
            data: employerData,
            fallbackIcon: Icons.business_outlined,
          ),
          chips: [
            _ReportMetaChip(label: "Plan", value: planName),
            _ReportMetaChip(
              label: "Payment",
              value: BillingService.formatLabel(paymentStatus),
            ),
            _ReportMetaChip(
              label: "Method",
              value: BillingService.formatLabel(paymentMode),
            ),
          ],
          onTap: () async {
            await ref.set({
              "readByAdmin": true,
              "viewedByAdmin": true,
              "viewedAt": FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
            if (!context.mounted) return;
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => _PaymentRequestDetailScreen(
                  ref: ref,
                  data: data,
                  companyName: companyName,
                  employerId: employerId,
                  status: planApprovalStatus,
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
  final Future<void> Function(String status) onStatusChanged;

  const _PaymentRequestDetailScreen({
    required this.ref,
    required this.data,
    required this.companyName,
    required this.employerId,
    required this.status,
    required this.onStatusChanged,
  });

  Future<void> reply(BuildContext context) async {
    final draft = await _askAdminReplyWithAttachments(
      context,
      title: "Message employer",
      label: "Message",
      hint: "Write a response about this billing request",
    );
    if (draft == null ||
        (draft.message.trim().isEmpty && draft.attachments.isEmpty)) {
      return;
    }

    await _sendAdminInboxMessage(
      userId: employerId,
      title: "Billing request update",
      message: draft.message,
      audience: "employer",
      relatedTargetType: "payment_request",
      relatedTargetId: ref.id,
      attachments: draft.attachments,
    );

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Message sent to employer inbox")),
    );
  }

  Future<void> changeStatus(
    BuildContext context,
    String nextStatus, {
    bool requireMessage = false,
    bool optionalNote = false,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    String? message;
    if (requireMessage || optionalNote) {
      message = await _askAdminReply(
        context,
        title: BillingService.formatLabel(nextStatus),
        label: requireMessage ? "Explanation" : "Optional note",
        hint: requireMessage
            ? "Explain this billing decision"
            : "Leave empty to continue without a note",
        requiredMessage: requireMessage,
      );
      if (message == null) return;
    }

    try {
      await onStatusChanged(nextStatus);
      if (message != null && message.trim().isNotEmpty) {
        await _sendAdminInboxMessage(
          userId: employerId,
          title: "Billing request update",
          message: message.trim(),
          audience: "employer",
          relatedTargetType: "payment_request",
          relatedTargetId: ref.id,
        );
        await ref.set({
          "adminReply": message.trim(),
          "updatedAt": FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } on BillingApprovalException catch (e) {
      debugPrint("Billing approval blocked: ${e.message}");
      messenger.showSnackBar(
        SnackBar(content: Text(e.message)),
      );
      return;
    } catch (e) {
      debugPrint("Billing status update error: $e");
      messenger.showSnackBar(
        const SnackBar(
          content: Text("Could not update billing request. Please try again."),
        ),
      );
      return;
    }

    if (!context.mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text("Billing request changed to $nextStatus")),
    );
  }

  @override
  Widget build(BuildContext context) {
    final planName = data["planName"]?.toString().trim() ?? "Plan";
    final planId = data["planId"]?.toString().trim() ?? "";
    final paymentMode = data["paymentMode"]?.toString().trim() ?? "";
    final planApprovalStatus = data["billingPlanStatus"]?.toString() ?? status;
    final paymentStatus = data["paymentStatus"]?.toString() ?? "pending";
    final invoiceStatus = data["invoiceStatus"]?.toString() ?? "";
    final billingEmail = data["billingEmail"]?.toString().trim() ?? "";
    final billingEmailVerified = data["billingEmailVerified"] == true;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Billing request"),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) async {
              await Future<void>.delayed(const Duration(milliseconds: 120));
              if (!context.mounted) return;
              if (value == "message") {
                await reply(context);
                return;
              }
              if (value == "approve") {
                await changeStatus(context, "approved", optionalNote: true);
                return;
              }
              if (value == "reject") {
                await changeStatus(context, "rejected", requireMessage: true);
                return;
              }
              if (value == "hold") {
                await changeStatus(
                  context,
                  "on_hold",
                  requireMessage: true,
                );
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
                value: "hold",
                child: ListTile(
                  leading: Icon(Icons.pause_circle_outline),
                  title: Text("Hold"),
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
                      _AdminStatusPill(planApprovalStatus),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _AdminMetaLine(label: "Employer ID", value: employerId),
                  _AdminMetaLine(
                    label: "Current plan",
                    value: data["currentPlanName"]?.toString() ??
                        data["currentPlanId"]?.toString() ??
                        "",
                  ),
                  _AdminMetaLine(label: "Requested plan", value: planName),
                  _AdminMetaLine(label: "Plan ID", value: planId),
                  _AdminMetaLine(
                    label: "Payment method",
                    value: BillingService.formatLabel(paymentMode),
                  ),
                  _AdminMetaLine(
                    label: "Billing email",
                    value: billingEmail.isEmpty ? "Missing" : billingEmail,
                  ),
                  _AdminMetaLine(
                    label: "Billing email status",
                    value: billingEmailVerified ? "Verified" : "Provided",
                  ),
                  _AdminMetaLine(
                    label: "Plan approval status",
                    value: BillingService.formatLabel(planApprovalStatus),
                  ),
                  _AdminMetaLine(
                    label: "Payment status",
                    value: BillingService.formatLabel(paymentStatus),
                  ),
                  _AdminMetaLine(
                    label: "Direct debit",
                    value: paymentMode == "direct_debit"
                        ? "Configured"
                        : "Not configured",
                  ),
                  if (invoiceStatus.isNotEmpty)
                    _AdminMetaLine(
                      label: "Invoice status",
                      value: BillingService.formatLabel(invoiceStatus),
                    ),
                  if ((data["invoicePdfUrl"]?.toString() ?? "").isNotEmpty)
                    _AdminMetaLine(
                      label: "Invoice PDF",
                      value: data["invoicePdfUrl"].toString(),
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
  final bool unread;
  final String? dateText;

  const _AdminRequestListCard({
    required this.title,
    required this.subtitle,
    required this.status,
    required this.chips,
    this.leading,
    required this.onTap,
    this.unread = false,
    this.dateText,
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
          color: unread
              ? AppColors.surface.withValues(alpha: 0.99)
              : AppColors.surface.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: unread
                ? AppColors.green.withValues(alpha: 0.72)
                : Colors.white.withValues(alpha: 0.95),
            width: unread ? 1.4 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (unread) ...[
                  Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      color: AppColors.green,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                if (leading != null) ...[
                  leading!,
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: AppColors.ink,
                          fontSize: 16,
                          fontWeight:
                              unread ? FontWeight.w900 : FontWeight.w800,
                        ),
                      ),
                      if (dateText?.trim().isNotEmpty == true)
                        Text(
                          dateText!.trim(),
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                    ],
                  ),
                ),
                _AdminStatusPill(status),
                const SizedBox(width: 4),
                const Icon(
                  Icons.chevron_right,
                  color: AppColors.muted,
                  size: 20,
                ),
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
    final color = AppColors.status(status);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 116),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.32)),
        ),
        child: Text(
          BillingService.formatLabel(status),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w900,
          ),
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
            data["photo"] ??
            data["avatarUrl"] ??
            data["profilePhotoUrl"] ??
            data["profileImageUrl"] ??
            data["profileImage"] ??
            data["imageUrl"] ??
            data["image"] ??
            data["companyLogo"] ??
            data["logoUrl"] ??
            data["logo"] ??
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
  final bool unread;
  final DateTime? date;

  const _AdminUserRequestCard({
    required this.userId,
    required this.fallbackTitle,
    required this.fallbackRole,
    required this.subtitle,
    required this.status,
    required this.chips,
    required this.onTap,
    this.unread = false,
    this.date,
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
          unread: unread,
          dateText: _adminMailTimeLabel(date),
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
  final String requestType;
  final List<Map> attachments;

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
    this.requestType = "support",
    this.attachments = const [],
  });

  Future<void> reply(BuildContext context) async {
    final draft = await _askAdminReplyWithAttachments(
      context,
      title: "Reply",
      label: "Message to user",
      hint: "Write admin response",
    );
    if (draft == null ||
        (draft.message.trim().isEmpty && draft.attachments.isEmpty)) {
      return;
    }

    final threadId = await existingRequestThreadId();
    await _sendAdminInboxMessage(
      userId: userId,
      title: "Admin response: $title",
      message: draft.message,
      audience: userRole.isEmpty ? "user" : userRole,
      threadId: threadId,
      relatedTargetType: "support",
      relatedTargetId: ref.id,
      attachments: draft.attachments,
    );
    await ref.set({
      "adminReply": draft.message.trim(),
      "lastAdminReplyAt": FieldValue.serverTimestamp(),
      "status": "pending_user_reply",
      "updatedAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Reply sent to inbox")),
    );
  }

  Future<void> changeStatus(
    BuildContext context,
    String nextStatus, {
    bool requireMessage = false,
  }) async {
    String? message;
    if (requireMessage) {
      message = await _askAdminReply(
        context,
        title: BillingService.formatLabel(nextStatus),
        label: "Message to user",
        hint: "Explain the decision",
        requiredMessage: true,
      );
      if (message == null) return;
      final threadId = await existingRequestThreadId();
      await _sendAdminInboxMessage(
        userId: userId,
        title: "Admin update: $title",
        message: message,
        audience: userRole.isEmpty ? "user" : userRole,
        threadId: threadId,
        relatedTargetType: requestType,
        relatedTargetId: ref.id,
      );
    }

    onStatusChanged(nextStatus);
    await ref.set({
      "status": nextStatus,
      if (message != null && message.trim().isNotEmpty)
        "adminReply": message.trim(),
      "updatedAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Status changed to $nextStatus")),
    );
  }

  Future<String?> existingRequestThreadId() async {
    final direct = await FirebaseFirestore.instance
        .collection("admin_messages")
        .where("relatedSupportRequestId", isEqualTo: ref.id)
        .limit(1)
        .get();
    if (direct.docs.isNotEmpty) {
      return direct.docs.first.data()["threadId"]?.toString();
    }

    final target = await FirebaseFirestore.instance
        .collection("admin_messages")
        .where("relatedTargetId", isEqualTo: ref.id)
        .limit(1)
        .get();
    if (target.docs.isNotEmpty) {
      return target.docs.first.data()["threadId"]?.toString();
    }

    return null;
  }

  Future<void> markUnread(BuildContext context) async {
    await ref.set({
      "readByAdmin": false,
      "viewedByAdmin": false,
      "updatedAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    if (!context.mounted) return;
    Navigator.pop(context);
  }

  Future<void> deleteRequest(BuildContext context) async {
    await ref.set({
      "deletedByAdmin": true,
      "deletedAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    if (!context.mounted) return;
    Navigator.pop(context);
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
              if (value == "unread") {
                await markUnread(context);
                return;
              }
              if (value == "delete") {
                await deleteRequest(context);
                return;
              }
              if (value == "resolve") {
                await changeStatus(context, "resolved");
                return;
              }
              if (value == "hold") {
                await changeStatus(
                  context,
                  "pending_user_reply",
                  requireMessage: true,
                );
                return;
              }
              await changeStatus(context, value);
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: "reply",
                child: ListTile(
                  leading: Icon(Icons.reply_outlined),
                  title: Text("Reply"),
                ),
              ),
              const PopupMenuItem(
                value: "unread",
                child: ListTile(
                  leading: Icon(Icons.mark_email_unread_outlined),
                  title: Text("Mark unread"),
                ),
              ),
              const PopupMenuItem(
                value: "resolve",
                child: ListTile(
                  leading: Icon(Icons.check_circle_outline),
                  title: Text("Resolve"),
                ),
              ),
              const PopupMenuItem(
                value: "hold",
                child: ListTile(
                  leading: Icon(Icons.pause_circle_outline),
                  title: Text("Hold"),
                ),
              ),
              const PopupMenuItem(
                value: "delete",
                child: ListTile(
                  leading: Icon(Icons.delete_outline),
                  title: Text("Delete"),
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
                  if (attachments.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    _AdminMailAttachmentWrap(attachments: attachments),
                  ],
                  const SizedBox(height: 14),
                  ...meta,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SupportRequestsSection extends StatefulWidget {
  final Future<void> Function(DocumentReference ref, String status)
      onSupportStatusChanged;
  final Future<void> Function(DocumentReference ref, String status)
      onReportStatusChanged;
  final Future<void> Function(DocumentReference ref, String status)
      onPaymentStatusChanged;

  const _SupportRequestsSection({
    required this.onSupportStatusChanged,
    required this.onReportStatusChanged,
    required this.onPaymentStatusChanged,
  });

  @override
  State<_SupportRequestsSection> createState() =>
      _SupportRequestsSectionState();
}

class _SupportRequestsSectionState extends State<_SupportRequestsSection> {
  String filter = "all";

  static const filters = [
    ("all", "All"),
    ("technical_issue", "Technical issue"),
    ("billing", "Billing"),
    ("complaint", "Complaint"),
    ("compliance", "Compliance"),
    ("abuse_report", "Abuse report"),
    ("recommendation", "Recommendation"),
    ("other", "Other"),
  ];

  String categoryForSupport(Map<String, dynamic> data) {
    final type = data["type"]?.toString().toLowerCase() ?? "";
    if (type.contains("technical")) return "technical_issue";
    if (type.contains("payment") ||
        type.contains("billing") ||
        type.contains("tariff") ||
        type.contains("direct_debit") ||
        type.contains("invoice")) {
      return "billing";
    }
    if (type.contains("complaint")) return "complaint";
    if (type.contains("compliance")) return "compliance";
    if (type.contains("abuse") || type.contains("safety")) {
      return "abuse_report";
    }
    if (type.contains("recommendation")) return "recommendation";
    return "other";
  }

  String categoryForReport(Map<String, dynamic> data) {
    final type = data["type"]?.toString().toLowerCase() ?? "";
    if (type.contains("abuse")) return "abuse_report";
    if (type.contains("compliance")) return "compliance";
    if (type.contains("recommendation")) return "recommendation";
    return "complaint";
  }

  bool matchesFilter(String category) {
    return filter == "all" || filter == category;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
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
                      Icons.support_agent_outlined,
                      color: AppColors.greenDark,
                    ),
                  ),
                  SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      "Support & Billing",
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
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: filters.map((item) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(item.$2),
                        selected: filter == item.$1,
                        onSelected: (_) => setState(() => filter = item.$1),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection("support_requests")
              .orderBy("createdAt", descending: true)
              .snapshots(),
          builder: (context, snapshot) {
            return StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection("reports")
                  .orderBy("createdAt", descending: true)
                  .snapshots(),
              builder: (context, reportsSnapshot) {
                return StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection("payment_requests")
                      .orderBy("createdAt", descending: true)
                      .snapshots(),
                  builder: (context, paymentsSnapshot) {
                    if (!snapshot.hasData ||
                        !reportsSnapshot.hasData ||
                        !paymentsSnapshot.hasData) {
                      return const LinearProgressIndicator();
                    }

                    final supportDocs = snapshot.data!.docs.where((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      return matchesFilter(categoryForSupport(data)) &&
                          data["deletedByAdmin"] != true;
                    }).toList();
                    final reportDocs = reportsSnapshot.data!.docs.where((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      return matchesFilter(categoryForReport(data)) &&
                          data["deletedByAdmin"] != true;
                    }).toList();
                    final paymentDocs =
                        paymentsSnapshot.data!.docs.where((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      return matchesFilter("billing") &&
                          data["deletedByAdmin"] != true;
                    }).toList();
                    final items = [
                      ...supportDocs.map((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        return _AdminSupportListItem(
                          doc: doc,
                          kind: "support",
                          createdAt: _adminRequestSortDate(data),
                          unread: _adminRequestUnread(data),
                        );
                      }),
                      ...reportDocs.map((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        return _AdminSupportListItem(
                          doc: doc,
                          kind: "report",
                          createdAt: _adminRequestSortDate(data),
                          unread: _adminRequestUnread(data),
                        );
                      }),
                      ...paymentDocs.map((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        return _AdminSupportListItem(
                          doc: doc,
                          kind: "payment",
                          createdAt: _adminRequestSortDate(data),
                          unread: _adminRequestUnread(data),
                        );
                      }),
                    ]..sort((a, b) {
                        if (a.unread != b.unread) {
                          return a.unread ? -1 : 1;
                        }
                        return b.createdAt.compareTo(a.createdAt);
                      });

                    if (items.isEmpty) {
                      return const Align(
                        alignment: Alignment.centerLeft,
                        child: Text("No support requests in this filter"),
                      );
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: items.map((item) {
                        final data = item.data;
                        if (item.kind == "support") {
                          return _SupportRequestCard(
                            data: data,
                            ref: item.doc.reference,
                            onStatusChanged: (status) {
                              widget.onSupportStatusChanged(
                                item.doc.reference,
                                status,
                              );
                            },
                          );
                        }

                        if (item.kind == "report") {
                          return _ReportCard(
                            data: data,
                            ref: item.doc.reference,
                            onStatusChanged: (status) {
                              widget.onReportStatusChanged(
                                item.doc.reference,
                                status,
                              );
                            },
                          );
                        }

                        return _PaymentRequestCard(
                          data: data,
                          ref: item.doc.reference,
                          onStatusChanged: (status) =>
                              widget.onPaymentStatusChanged(
                            item.doc.reference,
                            status,
                          ),
                        );
                      }).toList(),
                    );
                  },
                );
              },
            );
          },
        ),
      ],
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
    "in_progress",
    "pending_user_reply",
    "resolved",
    "closed",
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
      case "application_issue":
        return "Application issue";
      case "chat_media_issue":
        return "Chat or media issue";
      case "profile_account_issue":
        return "Profile/account issue";
      case "safety_abuse_report":
        return "Safety or abuse report";
      case "billing":
        return "Billing";
      case "payment":
        return "Payment";
      case "tariff_plan":
        return "Tariff plan";
      case "direct_debit":
        return "Direct debit";
      case "invoice":
        return "Invoice";
      case "job_posting_issue":
        return "Job posting issue";
      case "job_moderation_issue":
        return "Job moderation issue";
      case "worker_team_complaint":
        return "Complaint about worker/team";
      case "profile_company_account_issue":
        return "Profile/company account issue";
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
    final status = _normalizeAdminSupportStatus(data["status"]);
    final selectedStatus = statuses.contains(status) ? status : "open";
    final type = data["type"]?.toString().trim() ?? "support";
    final message = data["message"]?.toString().trim() ?? "";
    final createdAt = data["createdAt"] is Timestamp
        ? (data["createdAt"] as Timestamp).toDate()
        : null;
    final unread = data["readByAdmin"] != true && data["viewedByAdmin"] != true;

    return _AdminUserRequestCard(
      userId: data["userId"]?.toString() ?? "",
      fallbackTitle: supportTypeLabel(data),
      fallbackRole: data["userRole"]?.toString() ?? "",
      subtitle: message,
      status: selectedStatus,
      unread: unread,
      date: createdAt,
      chips: [
        _ReportMetaChip(label: "Topic", value: supportTypeLabel(data)),
        if ((data["attachments"] as List?)?.isNotEmpty == true)
          const _ReportMetaChip(label: "Files", value: "Attached"),
      ],
      onTap: () async {
        await ref.set({
          "readByAdmin": true,
          "viewedByAdmin": true,
          "viewedAt": FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        if (!context.mounted) return;
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
              requestType: "support",
              attachments:
                  (data["attachments"] as List?)?.whereType<Map>().toList() ??
                      const [],
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
                _AdminMetaLine(
                  label: "Created",
                  value: _formatAdminDate(createdAt),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _FinancialReportsSection extends StatefulWidget {
  final Widget complaintsSection;

  const _FinancialReportsSection({
    required this.complaintsSection,
  });

  @override
  State<_FinancialReportsSection> createState() =>
      _FinancialReportsSectionState();
}

class _FinancialReportsSectionState extends State<_FinancialReportsSection> {
  int selectedTab = 0;
  _AdminAnalyticsPeriod selectedPeriod = _AdminAnalyticsPeriod.monthly;

  double readMoney(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) {
      return double.tryParse(value.replaceAll(RegExp(r"[^0-9.]"), "")) ?? 0;
    }
    return 0;
  }

  Widget _buildLoading() {
    return const StroykaSurface(
      padding: EdgeInsets.all(18),
      child: LinearProgressIndicator(),
    );
  }

  Widget _buildTabs() {
    final labels = ["Financial reports", "Analytics"];
    return StroykaSurface(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(8),
      child: Row(
        children: List.generate(labels.length, (index) {
          final selected = selectedTab == index;
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(left: index == 0 ? 0 : 6),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => setState(() => selectedTab = index),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    color: selected
                        ? AppColors.green.withValues(alpha: 0.22)
                        : Colors.white.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selected
                          ? AppColors.blueprintLine
                          : Colors.white.withValues(alpha: 0.9),
                    ),
                  ),
                  child: Text(
                    labels[index],
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.tab.copyWith(
                      color: selected ? AppColors.ink : AppColors.muted,
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildFinancialReports(_AdminReportsData reports) {
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
                    label: "Total users",
                    value: reports.totalUsers.toString(),
                    icon: Icons.people_outline,
                  ),
                  _AdminMetricTile(
                    label: "Total workers",
                    value: reports.totalWorkers.toString(),
                    icon: Icons.engineering_outlined,
                  ),
                  _AdminMetricTile(
                    label: "Total employers",
                    value: reports.totalEmployers.toString(),
                    icon: Icons.business_outlined,
                  ),
                  _AdminMetricTile(
                    label: "Active paid employers",
                    value: reports.activePaidEmployers.toString(),
                    icon: Icons.verified_outlined,
                  ),
                  _AdminMetricTile(
                    label: "Direct debit users",
                    value: reports.directDebitUsers.toString(),
                    icon: Icons.sync_alt_outlined,
                  ),
                  _AdminMetricTile(
                    label: "Invoice-based users",
                    value: reports.invoiceBasedUsers.toString(),
                    icon: Icons.receipt_long_outlined,
                  ),
                  _AdminMetricTile(
                    label: "Expected monthly revenue",
                    value: reports.money(reports.expectedMonthlyRevenue),
                    icon: Icons.request_quote_outlined,
                  ),
                  _AdminMetricTile(
                    label: "Received monthly revenue",
                    value: reports.money(reports.receivedMonthlyRevenue),
                    icon: Icons.payments_outlined,
                  ),
                  _AdminMetricTile(
                    label: "Pending payment requests",
                    value: reports.pendingPaymentRequests.toString(),
                    icon: Icons.pending_actions_outlined,
                  ),
                  _AdminMetricTile(
                    label: "Projected revenue",
                    value: reports.money(reports.projectedRevenue),
                    icon: Icons.trending_up_outlined,
                  ),
                ],
              ),
            ],
          ),
        ),
        StroykaSurface(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Monthly performance",
                style: TextStyle(
                  color: AppColors.ink,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _AdminComparisonTile(
                    label: "Users",
                    current: reports.currentMonthUsers.toDouble(),
                    previous: reports.previousMonthUsers.toDouble(),
                    currentLabel: reports.currentMonthUsers.toString(),
                    previousLabel: reports.previousMonthUsers.toString(),
                  ),
                  _AdminComparisonTile(
                    label: "Revenue",
                    current: reports.receivedMonthlyRevenue,
                    previous: reports.previousMonthRevenue,
                    currentLabel: reports.money(reports.receivedMonthlyRevenue),
                    previousLabel: reports.money(reports.previousMonthRevenue),
                  ),
                  _AdminComparisonTile(
                    label: "Employers",
                    current: reports.currentMonthEmployers.toDouble(),
                    previous: reports.previousMonthEmployers.toDouble(),
                    currentLabel: reports.currentMonthEmployers.toString(),
                    previousLabel: reports.previousMonthEmployers.toString(),
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
              if (reports.revenueByMode.isEmpty)
                const Text("No received payments this month yet")
              else
                ...reports.revenueByMode.entries.map(
                  (entry) => _AdminMetaLine(
                    label: BillingService.formatLabel(entry.key),
                    value: reports.money(entry.value),
                  ),
                ),
            ],
          ),
        ),
        _AdminInsightsSection(reports: reports),
        widget.complaintsSection,
      ],
    );
  }

  Widget _buildAnalytics(_AdminReportsData reports) {
    final users = reports.series(
      period: selectedPeriod,
      role: null,
      cumulative: true,
    );
    final workers = reports.series(
      period: selectedPeriod,
      role: "worker",
      cumulative: true,
    );
    final employers = reports.series(
      period: selectedPeriod,
      role: "employer",
      cumulative: true,
    );
    final revenue = reports.revenueSeries(period: selectedPeriod);

    return Column(
      children: [
        StroykaSurface(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Analytics dashboard",
                style: TextStyle(
                  color: AppColors.ink,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _AdminAnalyticsPeriod.values.map((period) {
                  return ChoiceChip(
                    selected: selectedPeriod == period,
                    label: Text(period.label),
                    onSelected: (_) => setState(() => selectedPeriod = period),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
        _AdminLineChartCard(
          title: "Total users growth",
          points: users,
          color: AppColors.blueprintLine,
          valueFormatter: (value) => value.round().toString(),
        ),
        _AdminLineChartCard(
          title: "Workers growth",
          points: workers,
          color: AppColors.success,
          valueFormatter: (value) => value.round().toString(),
        ),
        _AdminLineChartCard(
          title: "Employers growth",
          points: employers,
          color: AppColors.purple,
          valueFormatter: (value) => value.round().toString(),
        ),
        _AdminLineChartCard(
          title: "Revenue growth",
          points: revenue,
          color: AppColors.warning,
          valueFormatter: reports.money,
        ),
        _AdminInsightsSection(reports: reports),
      ],
    );
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
                  .snapshots(),
              builder: (context, paymentsSnapshot) {
                return StreamBuilder<QuerySnapshot>(
                  stream:
                      FirebaseFirestore.instance.collection("jobs").snapshots(),
                  builder: (context, jobsSnapshot) {
                    return StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection("support_requests")
                          .snapshots(),
                      builder: (context, supportSnapshot) {
                        return StreamBuilder<QuerySnapshot>(
                          stream: FirebaseFirestore.instance
                              .collection("reports")
                              .snapshots(),
                          builder: (context, reportsSnapshot) {
                            if (!plansSnapshot.hasData ||
                                !usersSnapshot.hasData ||
                                !paymentsSnapshot.hasData ||
                                !jobsSnapshot.hasData ||
                                !supportSnapshot.hasData ||
                                !reportsSnapshot.hasData) {
                              return _buildLoading();
                            }

                            final reports = _AdminReportsData.fromSnapshots(
                              usersSnapshot.data!.docs,
                              paymentsSnapshot.data!.docs,
                              jobsSnapshot.data!.docs,
                              supportSnapshot.data!.docs,
                              reportsSnapshot.data!.docs,
                              planPrices,
                              planCurrency,
                            );

                            return Column(
                              children: [
                                _buildTabs(),
                                if (selectedTab == 0)
                                  _buildFinancialReports(reports)
                                else
                                  _buildAnalytics(reports),
                              ],
                            );
                          },
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}

enum _AdminAnalyticsPeriod {
  weekly("Weekly"),
  monthly("Monthly"),
  yearly("Yearly");

  final String label;

  const _AdminAnalyticsPeriod(this.label);
}

class _AdminSeriesPoint {
  final String label;
  final double value;

  const _AdminSeriesPoint({
    required this.label,
    required this.value,
  });
}

class _AdminReportsData {
  final List<Map<String, dynamic>> users;
  final List<Map<String, dynamic>> payments;
  final List<Map<String, dynamic>> jobs;
  final List<Map<String, dynamic>> supportRequests;
  final List<Map<String, dynamic>> reports;
  final Map<String, double> planPrices;
  final Map<String, String> planCurrency;
  final DateTime now;

  late final DateTime currentMonthStart = DateTime(now.year, now.month);
  late final DateTime previousMonthStart = DateTime(now.year, now.month - 1);
  late final DateTime nextMonthStart = DateTime(now.year, now.month + 1);

  late final int totalUsers = users.where(_isPlatformUser).length;
  late final int totalWorkers =
      users.where((data) => _role(data) == "worker").length;
  late final int totalEmployers =
      users.where((data) => _role(data) == "employer").length;
  late final List<Map<String, dynamic>> employers =
      users.where((data) => _role(data) == "employer").toList();
  late final List<Map<String, dynamic>> activePaidEmployerDocs =
      employers.where(_isActivePaidEmployer).toList();
  late final int activePaidEmployers = activePaidEmployerDocs.length;
  late final int directDebitUsers =
      activePaidEmployerDocs.where(_usesDirectDebit).length;
  late final int invoiceBasedUsers =
      activePaidEmployerDocs.where(_usesInvoice).length;
  late final int pendingPaymentRequests =
      payments.where((data) => _status(data) == "pending").length;

  late final int currentMonthUsers =
      users.where((data) => _isInMonth(_date(data["createdAt"]), now)).length;
  late final int previousMonthUsers = users
      .where((data) => _isInRange(
            _date(data["createdAt"]),
            previousMonthStart,
            currentMonthStart,
          ))
      .length;
  late final int currentMonthEmployers = employers
      .where((data) => _isInMonth(_date(data["createdAt"]), now))
      .length;
  late final int previousMonthEmployers = employers
      .where((data) => _isInRange(
            _date(data["createdAt"]),
            previousMonthStart,
            currentMonthStart,
          ))
      .length;

  late final double expectedMonthlyRevenue =
      activePaidEmployerDocs.fold<double>(
    0,
    (total, employer) {
      final billing = BillingService.billingFromUserData(employer);
      final planId = billing["planId"]?.toString() ?? "";
      return total + (planPrices[planId] ?? 0);
    },
  );

  late final Map<String, double> revenueByMode = _revenueByModeForMonth(now);
  late final double receivedMonthlyRevenue = revenueByMode.values.fold<double>(
    0,
    (total, value) => total + value,
  );
  late final double previousMonthRevenue =
      _revenueForRange(previousMonthStart, currentMonthStart);
  late final double pendingPaymentValue =
      payments.where((data) => _status(data) == "pending").fold<double>(
            0,
            (total, payment) => total + _paymentValue(payment),
          );
  late final double projectedRevenue =
      expectedMonthlyRevenue + pendingPaymentValue;

  late final int activeJobs = jobs.where(_isActiveJob).length;
  late final int jobsPendingModeration =
      jobs.where((data) => _moderationStatus(data) == "pending_review").length;
  late final int rejectedJobs =
      jobs.where((data) => _moderationStatus(data) == "rejected").length;
  late final int supportLoad =
      supportRequests.where(_isOpenSupportItem).length +
          reports.where(_isOpenSupportItem).length;
  late final int activeSubscriptions = activePaidEmployers;
  late final double conversionRate =
      totalEmployers == 0 ? 0 : activePaidEmployers / totalEmployers * 100;

  late final String currency = _resolveCurrency();

  _AdminReportsData({
    required this.users,
    required this.payments,
    required this.jobs,
    required this.supportRequests,
    required this.reports,
    required this.planPrices,
    required this.planCurrency,
    required this.now,
  });

  factory _AdminReportsData.fromSnapshots(
    List<QueryDocumentSnapshot> userDocs,
    List<QueryDocumentSnapshot> paymentDocs,
    List<QueryDocumentSnapshot> jobDocs,
    List<QueryDocumentSnapshot> supportDocs,
    List<QueryDocumentSnapshot> reportDocs,
    Map<String, double> planPrices,
    Map<String, String> planCurrency,
  ) {
    List<Map<String, dynamic>> read(List<QueryDocumentSnapshot> docs) {
      return docs
          .map((doc) => doc.data() as Map<String, dynamic>)
          .where((data) => data["deletedByAdmin"] != true)
          .toList();
    }

    return _AdminReportsData(
      users: read(userDocs)
          .where((data) => data["accountDeleted"] != true)
          .toList(),
      payments: read(paymentDocs),
      jobs: read(jobDocs),
      supportRequests: read(supportDocs),
      reports: read(reportDocs),
      planPrices: planPrices,
      planCurrency: planCurrency,
      now: DateTime.now(),
    );
  }

  String money(double value) => "$currency ${value.toStringAsFixed(2)}";

  List<_AdminSeriesPoint> series({
    required _AdminAnalyticsPeriod period,
    required String? role,
    required bool cumulative,
  }) {
    final buckets = _buckets(period);
    var runningTotal = users.where((data) {
      final createdAt = _date(data["createdAt"]);
      if (createdAt != null && !createdAt.isBefore(buckets.first.start)) {
        return false;
      }
      return _matchesRole(data, role);
    }).length;

    return buckets.map((bucket) {
      final count = users.where((data) {
        final createdAt = _date(data["createdAt"]);
        if (!_isInRange(createdAt, bucket.start, bucket.end)) return false;
        return _matchesRole(data, role);
      }).length;
      if (cumulative) {
        runningTotal += count;
        return _AdminSeriesPoint(
          label: bucket.label,
          value: runningTotal.toDouble(),
        );
      }
      return _AdminSeriesPoint(label: bucket.label, value: count.toDouble());
    }).toList();
  }

  List<_AdminSeriesPoint> revenueSeries({
    required _AdminAnalyticsPeriod period,
  }) {
    return _buckets(period).map((bucket) {
      return _AdminSeriesPoint(
        label: bucket.label,
        value: _revenueForRange(bucket.start, bucket.end),
      );
    }).toList();
  }

  Map<String, double> _revenueByModeForMonth(DateTime month) {
    final map = <String, double>{};
    for (final payment in payments) {
      if (!_isConfirmedReceivedPayment(payment)) continue;
      if (!_isInMonth(_paymentDate(payment), month)) continue;
      final mode = payment["paymentMode"]?.toString() ?? "manual_invoice";
      map[mode] = (map[mode] ?? 0) + _paymentValue(payment);
    }
    return map;
  }

  double _revenueForRange(DateTime start, DateTime end) {
    return payments.where((payment) {
      return _isConfirmedReceivedPayment(payment) &&
          _isInRange(_paymentDate(payment), start, end);
    }).fold<double>(
      0,
      (total, payment) => total + _paymentValue(payment),
    );
  }

  bool _isConfirmedReceivedPayment(Map<String, dynamic> payment) {
    final status = _status(payment);
    final paymentStatus =
        payment["paymentStatus"]?.toString().trim().toLowerCase() ?? "";
    final invoiceStatus =
        payment["invoiceStatus"]?.toString().trim().toLowerCase() ?? "";
    final hasConfirmedDate = _date(payment["paidAt"]) != null ||
        _date(payment["confirmedAt"]) != null ||
        _date(payment["providerPaidAt"]) != null;
    final hasProviderReference =
        (payment["providerPaymentId"]?.toString().trim().isNotEmpty == true) ||
            (payment["transactionId"]?.toString().trim().isNotEmpty == true) ||
            (payment["paymentIntentId"]?.toString().trim().isNotEmpty == true);

    if (status == "paid" ||
        paymentStatus == "paid" ||
        invoiceStatus == "paid") {
      return hasConfirmedDate || hasProviderReference;
    }
    return false;
  }

  double _paymentValue(Map<String, dynamic> payment) {
    final explicitAmount =
        payment["amount"] ?? payment["total"] ?? payment["price"];
    final parsed = _readMoney(explicitAmount);
    if (parsed > 0) return parsed;
    final planId = payment["planId"]?.toString() ?? "";
    return planPrices[planId] ?? 0;
  }

  DateTime? _paymentDate(Map<String, dynamic> payment) {
    return _date(payment["paidAt"]) ??
        _date(payment["confirmedAt"]) ??
        _date(payment["providerPaidAt"]) ??
        _date(payment["updatedAt"]) ??
        _date(payment["createdAt"]);
  }

  List<_AdminReportBucket> _buckets(_AdminAnalyticsPeriod period) {
    switch (period) {
      case _AdminAnalyticsPeriod.weekly:
        final today = DateTime(now.year, now.month, now.day);
        return List.generate(7, (index) {
          final start = today.subtract(Duration(days: 6 - index));
          return _AdminReportBucket(
            label: "${start.day}/${start.month}",
            start: start,
            end: start.add(const Duration(days: 1)),
          );
        });
      case _AdminAnalyticsPeriod.monthly:
        return List.generate(6, (index) {
          final start = DateTime(now.year, now.month - (5 - index));
          return _AdminReportBucket(
            label: _monthLabel(start),
            start: start,
            end: DateTime(start.year, start.month + 1),
          );
        });
      case _AdminAnalyticsPeriod.yearly:
        return List.generate(5, (index) {
          final year = now.year - (4 - index);
          return _AdminReportBucket(
            label: year.toString(),
            start: DateTime(year),
            end: DateTime(year + 1),
          );
        });
    }
  }

  String _resolveCurrency() {
    for (final employer in activePaidEmployerDocs) {
      final billing = BillingService.billingFromUserData(employer);
      final planId = billing["planId"]?.toString() ?? "";
      final value = planCurrency[planId];
      if (value != null && value.isNotEmpty) return value;
    }
    for (final value in planCurrency.values) {
      if (value.isNotEmpty) return value;
    }
    return "GBP";
  }

  bool _isActivePaidEmployer(Map<String, dynamic> data) {
    final billing = BillingService.billingFromUserData(data);
    final status = billing["status"]?.toString() ?? "";
    final billingPlanStatus = billing["billingPlanStatus"]?.toString() ?? "";
    final planId =
        (billing["activePlanId"] ?? billing["planId"])?.toString() ?? "";
    return planId.isNotEmpty &&
        (status == "active" || billingPlanStatus == "approved");
  }

  bool _usesDirectDebit(Map<String, dynamic> data) {
    final billing = BillingService.billingFromUserData(data);
    final mode = billing["paymentMode"]?.toString().toLowerCase() ?? "";
    return billing["directDebitEnabled"] == true ||
        mode.contains("direct_debit") ||
        mode.contains("direct debit");
  }

  bool _usesInvoice(Map<String, dynamic> data) {
    final billing = BillingService.billingFromUserData(data);
    final mode = billing["paymentMode"]?.toString().toLowerCase() ?? "";
    return mode.contains("invoice") || mode.contains("manual");
  }

  bool _isActiveJob(Map<String, dynamic> data) {
    final moderation = _moderationStatus(data);
    final status = _status(data);
    return moderation == "approved" &&
        (status.isEmpty ||
            status == "active" ||
            status == "published" ||
            status == "open");
  }

  bool _isOpenSupportItem(Map<String, dynamic> data) {
    final status = _status(data);
    return status != "resolved" &&
        status != "closed" &&
        status != "rejected" &&
        status != "deleted";
  }

  static bool _matchesRole(Map<String, dynamic> data, String? role) {
    if (role == null) return _isPlatformUser(data);
    return _role(data) == role;
  }

  static bool _isPlatformUser(Map<String, dynamic> data) {
    final role = _role(data);
    return role == "worker" || role == "employer";
  }

  static String _role(Map<String, dynamic> data) {
    final explicit = _normalizeRole(data["role"] ??
        data["userRole"] ??
        data["accountType"] ??
        data["profileType"] ??
        data["type"] ??
        "");
    if (explicit.isNotEmpty) return explicit;
    if ((data["companyName"]?.toString().trim().isNotEmpty ?? false) ||
        (data["billing"] is Map)) {
      return "employer";
    }
    if ((data["trade"]?.toString().trim().isNotEmpty ?? false) ||
        (data["skills"] is List) ||
        (data["portfolio"] is List)) {
      return "worker";
    }
    return "";
  }

  static String _normalizeRole(dynamic value) {
    final role = value?.toString().toLowerCase().trim() ?? "";
    if (role.contains("worker") ||
        role.contains("candidate") ||
        role.contains("employee")) {
      return "worker";
    }
    if (role.contains("employer") ||
        role.contains("company") ||
        role.contains("client")) {
      return "employer";
    }
    if (role.contains("admin")) return "admin";
    return role;
  }

  static String _status(Map<String, dynamic> data) =>
      data["status"]?.toString().toLowerCase().trim() ?? "";

  static String _moderationStatus(Map<String, dynamic> data) =>
      data["moderationStatus"]?.toString().toLowerCase().trim() ?? "";

  static DateTime? _date(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  static bool _isInMonth(DateTime? date, DateTime month) {
    if (date == null) return false;
    return date.year == month.year && date.month == month.month;
  }

  static bool _isInRange(DateTime? date, DateTime start, DateTime end) {
    if (date == null) return false;
    return !date.isBefore(start) && date.isBefore(end);
  }

  static double _readMoney(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) {
      return double.tryParse(value.replaceAll(RegExp(r"[^0-9.]"), "")) ?? 0;
    }
    return 0;
  }

  static String _monthLabel(DateTime date) {
    const months = [
      "Jan",
      "Feb",
      "Mar",
      "Apr",
      "May",
      "Jun",
      "Jul",
      "Aug",
      "Sep",
      "Oct",
      "Nov",
      "Dec",
    ];
    return months[date.month - 1];
  }
}

class _AdminReportBucket {
  final String label;
  final DateTime start;
  final DateTime end;

  const _AdminReportBucket({
    required this.label,
    required this.start,
    required this.end,
  });
}

class _AdminComparisonTile extends StatelessWidget {
  final String label;
  final double current;
  final double previous;
  final String currentLabel;
  final String previousLabel;

  const _AdminComparisonTile({
    required this.label,
    required this.current,
    required this.previous,
    required this.currentLabel,
    required this.previousLabel,
  });

  @override
  Widget build(BuildContext context) {
    final difference = current - previous;
    final percent = previous == 0 ? 0 : difference / previous * 100;
    final isPositive = difference >= 0;
    final color = isPositive ? AppColors.success : AppColors.danger;

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
          Text(
            label,
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            currentLabel,
            style: const TextStyle(
              color: AppColors.ink,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(
                isPositive
                    ? Icons.trending_up_outlined
                    : Icons.trending_down_outlined,
                color: color,
                size: 16,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  previous == 0
                      ? "Prev $previousLabel"
                      : "${percent >= 0 ? "+" : ""}${percent.toStringAsFixed(1)}%",
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AdminInsightsSection extends StatelessWidget {
  final _AdminReportsData reports;

  const _AdminInsightsSection({required this.reports});

  @override
  Widget build(BuildContext context) {
    return StroykaSurface(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Admin insights",
            style: TextStyle(
              color: AppColors.ink,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _AdminMetricTile(
                label: "Active jobs",
                value: reports.activeJobs.toString(),
                icon: Icons.work_outline,
              ),
              _AdminMetricTile(
                label: "Jobs pending moderation",
                value: reports.jobsPendingModeration.toString(),
                icon: Icons.rule_folder_outlined,
              ),
              _AdminMetricTile(
                label: "Rejected jobs",
                value: reports.rejectedJobs.toString(),
                icon: Icons.block_outlined,
              ),
              _AdminMetricTile(
                label: "Support load",
                value: reports.supportLoad.toString(),
                icon: Icons.support_agent_outlined,
              ),
              _AdminMetricTile(
                label: "Active subscriptions",
                value: reports.activeSubscriptions.toString(),
                icon: Icons.workspace_premium_outlined,
              ),
              _AdminMetricTile(
                label: "Employer conversion",
                value: "${reports.conversionRate.toStringAsFixed(1)}%",
                icon: Icons.insights_outlined,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AdminLineChartCard extends StatelessWidget {
  final String title;
  final List<_AdminSeriesPoint> points;
  final Color color;
  final String Function(double value) valueFormatter;

  const _AdminLineChartCard({
    required this.title,
    required this.points,
    required this.color,
    required this.valueFormatter,
  });

  @override
  Widget build(BuildContext context) {
    final latest = points.isEmpty ? 0.0 : points.last.value;
    return StroykaSurface(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
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
              Text(
                valueFormatter(latest),
                style: TextStyle(
                  color: color,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 180,
            width: double.infinity,
            child: CustomPaint(
              painter: _AdminLineChartPainter(
                points: points,
                color: color,
                valueFormatter: valueFormatter,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminLineChartPainter extends CustomPainter {
  final List<_AdminSeriesPoint> points;
  final Color color;
  final String Function(double value) valueFormatter;

  const _AdminLineChartPainter({
    required this.points,
    required this.color,
    required this.valueFormatter,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = AppColors.blueprintLine.withValues(alpha: 0.16)
      ..strokeWidth = 1;
    final axisPaint = Paint()
      ..color = AppColors.muted.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final dotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    const left = 36.0;
    const right = 8.0;
    const top = 12.0;
    const bottom = 32.0;
    final chart = Rect.fromLTWH(
      left,
      top,
      size.width - left - right,
      size.height - top - bottom,
    );

    for (var i = 0; i <= 3; i++) {
      final y = chart.top + chart.height / 3 * i;
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), gridPaint);
    }
    canvas.drawLine(
      Offset(chart.left, chart.bottom),
      Offset(chart.right, chart.bottom),
      axisPaint,
    );

    if (points.isEmpty) {
      _drawText(
          canvas,
          "No data",
          Offset(chart.center.dx - 28, chart.center.dy),
          AppColors.muted,
          12,
          FontWeight.w800);
      return;
    }

    final maxValue = points
        .map((point) => point.value)
        .fold<double>(0, (a, b) => a > b ? a : b);
    final safeMax = maxValue <= 0 ? 1.0 : maxValue;
    final stepX = points.length <= 1 ? 0 : chart.width / (points.length - 1);
    final offsets = <Offset>[];

    for (var i = 0; i < points.length; i++) {
      final x = points.length <= 1 ? chart.center.dx : chart.left + stepX * i;
      final y = chart.bottom - (points[i].value / safeMax * chart.height);
      offsets.add(Offset(x, y));
    }

    if (offsets.length == 1) {
      canvas.drawCircle(offsets.first, 4, dotPaint);
    } else {
      final path = Path()..moveTo(offsets.first.dx, offsets.first.dy);
      for (final point in offsets.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path, linePaint);
      for (final point in offsets) {
        canvas.drawCircle(point, 4, dotPaint);
      }
    }

    _drawText(
      canvas,
      valueFormatter(safeMax),
      Offset(0, chart.top - 2),
      AppColors.muted,
      10,
      FontWeight.w800,
    );
    _drawText(
      canvas,
      "0",
      Offset(0, chart.bottom - 10),
      AppColors.muted,
      10,
      FontWeight.w800,
    );

    for (var i = 0; i < points.length; i++) {
      if (points.length > 6 && i.isOdd) continue;
      final x = points.length <= 1 ? chart.center.dx : chart.left + stepX * i;
      _drawText(
        canvas,
        points[i].label,
        Offset(x - 14, chart.bottom + 10),
        AppColors.muted,
        10,
        FontWeight.w800,
      );
    }
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset offset,
    Color color,
    double fontSize,
    FontWeight weight,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: weight,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _AdminLineChartPainter oldDelegate) {
    return oldDelegate.points != points || oldDelegate.color != color;
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
    "in_progress",
    "pending_user_reply",
    "resolved",
    "closed",
  ];

  @override
  Widget build(BuildContext context) {
    final status = _normalizeAdminSupportStatus(data["status"]);
    final selectedStatus = statuses.contains(status) ? status : "open";
    final message = data["message"]?.toString().trim() ?? "";
    final type = data["type"]?.toString().trim() ?? "report";
    final createdAt = data["createdAt"] is Timestamp
        ? (data["createdAt"] as Timestamp).toDate()
        : null;
    final unread = data["readByAdmin"] != true && data["viewedByAdmin"] != true;

    return _AdminUserRequestCard(
      userId: data["fromUserId"]?.toString() ?? "",
      fallbackTitle: type,
      fallbackRole: "user",
      subtitle: message,
      status: selectedStatus,
      unread: unread,
      date: createdAt,
      chips: [
        _ReportMetaChip(label: "Topic", value: type),
        if ((data["attachments"] as List?)?.isNotEmpty == true)
          const _ReportMetaChip(label: "Files", value: "Attached"),
      ],
      onTap: () async {
        await ref.set({
          "readByAdmin": true,
          "viewedByAdmin": true,
          "viewedAt": FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        if (!context.mounted) return;
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
              requestType: "report",
              attachments:
                  (data["attachments"] as List?)?.whereType<Map>().toList() ??
                      const [],
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
                _AdminMetaLine(
                  label: "Created",
                  value: _formatAdminDate(createdAt),
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
    final screenWidth = MediaQuery.sizeOf(context).width;
    final maxWidth = screenWidth < 380 ? screenWidth - 76 : 300.0;

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.green.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          "$label: $text",
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppColors.greenDark,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
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
                .orderBy("createdAt", descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Text(
                    "Could not load moderation queue: ${snapshot.error}");
              }
              if (!snapshot.hasData) {
                return const LinearProgressIndicator();
              }

              final docs = snapshot.data!.docs.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final status = data["moderationStatus"]?.toString() ?? "";
                return status == "pending_review" ||
                    status == "approved" ||
                    status == "on_hold" ||
                    status == "rejected";
              }).toList();
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
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection("jobs").doc(job.id).get(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data() as Map<String, dynamic>? ?? {};
        final unread = job.moderationStatus == "pending_review" &&
            data["viewedByAdmin"] != true;
        return JobCard(
          job: job,
          onTap: onOpen,
          unread: unread,
          margin: const EdgeInsets.only(bottom: 10),
          statusText: job.moderationLabel,
          statusColor: AppColors.status(job.moderationStatus),
          detailText: "Published ${_formatAdminDate(job.createdAt)}",
          trailingAction: const Icon(
            Icons.more_horiz,
            color: AppColors.muted,
          ),
        );
      },
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
    final note = await _askAdminReply(
      context,
      title: "Approve job",
      label: "Optional note to employer",
      hint: "Leave empty to approve without a message",
    );
    if (note == null) return;
    await onApprove(jobRef, job);
    if (note.trim().isNotEmpty) {
      await _sendAdminInboxMessage(
        userId: job.ownerId,
        title: "Job publication approved",
        message: note.trim(),
        audience: "employer",
        relatedTargetType: "job",
        relatedTargetId: job.id,
      );
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Job approved")),
    );
    Navigator.pop(context);
  }

  Future<void> messageEmployer(BuildContext context) async {
    final message = await _askAdminReply(
      context,
      title: "Message employer",
      label: "Message",
      hint: "Write a message about this job publication",
      requiredMessage: true,
    );
    if (message == null) return;
    await _sendAdminInboxMessage(
      userId: job.ownerId,
      title: "Message about ${job.displayTitle}",
      message: message,
      audience: "employer",
      relatedTargetType: "job",
      relatedTargetId: job.id,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Message sent")),
    );
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
              if (value == "message") messageEmployer(context);
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
              PopupMenuItem(
                value: "message",
                child: ListTile(
                  leading: Icon(Icons.mail_outline),
                  title: Text("Send message to employer"),
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
            _AdminModerationOverview(job: job),
            const SizedBox(height: 12),
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

class _AdminModerationOverview extends StatelessWidget {
  final Job job;

  const _AdminModerationOverview({
    required this.job,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection("users")
          .doc(job.ownerId)
          .snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data() as Map<String, dynamic>? ?? {};
        final billing = BillingService.billingFromUserData(data);
        final companyName =
            (data["companyName"] ?? data["name"] ?? job.companyName)
                .toString()
                .trim();
        final logo =
            (data["companyLogo"] ?? data["profilePhotoUrl"] ?? job.companyLogo)
                ?.toString();
        final available = BillingService.readInt(billing["availableJobPosts"]);
        final used = BillingService.readInt(billing["usedJobPosts"]);
        final free = (available - used).clamp(0, available);
        final plan =
            (billing["planName"] ?? billing["planId"] ?? "No plan").toString();
        final billingStatus =
            (billing["status"] ?? data["billing.status"] ?? "not set")
                .toString();

        return StroykaSurface(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: const Color(0x297DB9D8),
                    backgroundImage: logo != null && logo.trim().isNotEmpty
                        ? NetworkImage(logo.trim())
                        : null,
                    child: logo == null || logo.trim().isEmpty
                        ? const Icon(
                            Icons.business_outlined,
                            color: AppColors.greenDark,
                          )
                        : null,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Moderation overview",
                          style: TextStyle(
                            color: AppColors.ink,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          companyName.isEmpty ? "Company" : companyName,
                          style: const TextStyle(
                            color: AppColors.ink,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _AdminStatusPill(job.moderationStatus),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _ReportMetaChip(label: "Plan", value: plan),
                  _ReportMetaChip(
                    label: "Billing",
                    value: BillingService.formatLabel(billingStatus),
                  ),
                  _ReportMetaChip(
                      label: "Free slots", value: "$free/$available"),
                  _ReportMetaChip(
                    label: "Published",
                    value: _formatAdminDate(job.createdAt),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _AdminMetaLine(label: "Employer ID", value: job.ownerId),
              _AdminMetaLine(
                label: "Moderation",
                value: job.moderationLabel,
              ),
              _AdminMetaLine(
                label: "Reason/history",
                value: job.moderationReason.trim().isEmpty
                    ? "No moderation notes yet"
                    : job.moderationReason,
              ),
            ],
          ),
        );
      },
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
