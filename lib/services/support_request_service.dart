import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

class SupportRequestService {
  static const workerRequestTypes = {
    "technical_issue": "Technical issue",
    "employer_complaint": "Complaint about employer/company",
    "participant_complaint": "Complaint about another participant",
    "job_ad_complaint": "Job advert complaint",
    "application_issue": "Application issue",
    "chat_media_issue": "Chat or media issue",
    "profile_account_issue": "Profile/account issue",
    "safety_abuse_report": "Safety or abuse report",
    "other": "Other",
  };

  static const employerRequestTypes = {
    "billing": "Billing",
    "payment": "Payment",
    "tariff_plan": "Tariff plan",
    "direct_debit": "Direct debit",
    "invoice": "Invoice",
    "job_posting_issue": "Job posting issue",
    "job_moderation_issue": "Job moderation issue",
    "technical_issue": "Technical issue",
    "worker_team_complaint": "Complaint about worker/team",
    "chat_media_issue": "Chat or media issue",
    "profile_company_account_issue": "Profile/company account issue",
    "safety_abuse_report": "Safety or abuse report",
    "other": "Other",
  };

  static Future<void> showSupportDialog(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final userDoc = await FirebaseFirestore.instance
        .collection("users")
        .doc(user.uid)
        .get();
    if (!context.mounted) return;

    final userRole = userDoc.data()?["role"]?.toString().toLowerCase() ?? "";
    final requestTypes =
        userRole == "worker" ? workerRequestTypes : employerRequestTypes;

    final result = await showDialog<_SupportRequestResult>(
      context: context,
      builder: (_) => _SupportRequestDialog(
        requestTypes: requestTypes,
        userId: user.uid,
      ),
    );

    if (result == null || result.message.isEmpty) return;

    try {
      final firestore = FirebaseFirestore.instance;
      final supportRef = firestore.collection("support_requests").doc();
      final threadRef = firestore.collection("message_threads").doc();
      final typeLabel = requestTypes[result.type] ?? result.type;
      debugPrint(
        "SUPPORT REQUEST SUBMIT: path=${supportRef.path} uid=${user.uid} role=$userRole",
      );
      await supportRef.set({
        "userId": user.uid,
        "userRole": userRole,
        "role": userRole,
        "type": result.type,
        "requestType": result.type,
        "typeLabel": typeLabel,
        "requestTypeLabel": typeLabel,
        "subject": typeLabel,
        "message": result.message,
        "attachments": result.attachments,
        "hasAttachments": result.attachments.isNotEmpty,
        "status": "open",
        "adminVisible": true,
        "readByAdmin": false,
        "viewedByAdmin": false,
        "threadId": threadRef.id,
        "adminMessageThreadId": threadRef.id,
        "createdAt": FieldValue.serverTimestamp(),
        "updatedAt": FieldValue.serverTimestamp(),
      });
      debugPrint("SUPPORT REQUEST WRITE SUCCESS: ${supportRef.path}");

      final threadId = await _createAdminInboxThreadForSupportRequest(
        supportRequestId: supportRef.id,
        threadRef: threadRef,
        userId: user.uid,
        userRole: userRole,
        userData: userDoc.data() ?? {},
        type: result.type,
        typeLabel: typeLabel,
        message: result.message,
        attachments: result.attachments,
      );
      debugPrint(
        "SUPPORT REQUEST THREAD SUCCESS: request=${supportRef.id} thread=$threadId",
      );

      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Your request has been sent successfully."),
        ),
      );
    } catch (e) {
      debugPrint("SUPPORT REQUEST SUBMIT ERROR: $e");
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Could not submit support request. Please try again."),
        ),
      );
    }
  }

  static Future<String> _createAdminInboxThreadForSupportRequest({
    required String supportRequestId,
    required DocumentReference<Map<String, dynamic>> threadRef,
    required String userId,
    required String userRole,
    required Map<String, dynamic> userData,
    required String type,
    required String typeLabel,
    required String message,
    required List<Map<String, dynamic>> attachments,
  }) async {
    final firestore = FirebaseFirestore.instance;
    final messageRef = firestore.collection("admin_messages").doc();
    final now = FieldValue.serverTimestamp();
    final senderName = (userRole == "employer"
            ? userData["companyName"] ?? userData["name"]
            : userData["name"] ?? userData["displayName"])
        ?.toString()
        .trim();
    final displayName = senderName?.isNotEmpty == true ? senderName! : "User";
    final subject = "Support: $typeLabel";

    final batch = firestore.batch();
    batch.set(messageRef, {
      "threadId": threadRef.id,
      "direction": "incoming",
      "senderId": userId,
      "senderName": displayName,
      "senderRole": userRole,
      "receiverId": "admin",
      "receiverName": "Admin",
      "receiverRole": "admin",
      "recipientId": "admin",
      "recipientRole": "admin",
      "threadParticipants": [userId, "admin"],
      "audienceType": "specific_admin",
      "canReply": true,
      "subject": subject,
      "message": message,
      "type": "support_request",
      "supportRequestType": type,
      "relatedSupportRequestId": supportRequestId,
      "relatedTargetType": "support_request",
      "relatedTargetId": supportRequestId,
      "readByAdmin": false,
      "readByReceiver": true,
      "important": false,
      "deletedByAdmin": false,
      "deletedByReceiver": false,
      "deletedBySender": false,
      "attachments": attachments,
      "hasAttachments": attachments.isNotEmpty,
      "createdAt": now,
    });
    batch.set(threadRef, {
      "subject": subject,
      "participants": [userId, "admin"],
      "createdBy": userId,
      "userId": userId,
      "userRole": userRole,
      "threadType": "support_request",
      "lastMessage": message,
      "lastMessageAt": now,
      "lastSenderId": userId,
      "unreadForAdmin": 1,
      "relatedSupportRequestId": supportRequestId,
      "updatedAt": now,
    });
    await batch.commit();
    return threadRef.id;
  }
}

class _SupportRequestResult {
  final String type;
  final String message;
  final List<Map<String, dynamic>> attachments;

  const _SupportRequestResult({
    required this.type,
    required this.message,
    required this.attachments,
  });
}

class _SupportRequestDialog extends StatefulWidget {
  final Map<String, String> requestTypes;
  final String userId;

  const _SupportRequestDialog({
    required this.requestTypes,
    required this.userId,
  });

  @override
  State<_SupportRequestDialog> createState() => _SupportRequestDialogState();
}

class _SupportRequestDialogState extends State<_SupportRequestDialog> {
  late String selectedType;
  late final TextEditingController controller;
  final List<PlatformFile> attachments = [];
  bool submitting = false;

  @override
  void initState() {
    super.initState();
    selectedType = widget.requestTypes.keys.first;
    controller = TextEditingController();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> pickAttachments() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
      type: FileType.any,
    );
    if (result == null || !mounted) return;

    setState(() {
      final existing = attachments.map((file) => file.name).toSet();
      attachments.addAll(
        result.files.where((file) => !existing.contains(file.name)),
      );
    });
  }

  Future<List<Map<String, dynamic>>> uploadAttachments() async {
    final uploaded = <Map<String, dynamic>>[];
    final storage = FirebaseStorage.instance;
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    for (var index = 0; index < attachments.length; index++) {
      final file = attachments[index];
      final bytes = file.bytes;
      if (bytes == null) continue;

      final safeName = file.name.replaceAll(RegExp(r"[^A-Za-z0-9._-]"), "_");
      final extension = file.extension?.toLowerCase() ?? "";
      final path =
          "support_requests/${widget.userId}/${timestamp}_${index}_$safeName";
      final ref = storage.ref(path);

      await ref.putData(
        bytes,
        SettableMetadata(
          contentType: _contentTypeForExtension(extension),
          customMetadata: {
            "fileName": file.name,
            "fileType": extension,
          },
        ),
      );
      final url = await ref.getDownloadURL();
      uploaded.add({
        "fileName": file.name,
        "fileUrl": url,
        "fileType": extension.isEmpty ? "file" : extension,
        "uploadedAt": Timestamp.now(),
        "size": file.size,
        // Compatibility with existing admin mail/support attachment widgets.
        "name": file.name,
        "url": url,
        "type": extension.isEmpty ? "file" : extension,
      });
    }

    return uploaded;
  }

  String _contentTypeForExtension(String extension) {
    switch (extension) {
      case "jpg":
      case "jpeg":
        return "image/jpeg";
      case "png":
        return "image/png";
      case "gif":
        return "image/gif";
      case "webp":
        return "image/webp";
      case "pdf":
        return "application/pdf";
      case "doc":
        return "application/msword";
      case "docx":
        return "application/vnd.openxmlformats-officedocument.wordprocessingml.document";
      case "txt":
        return "text/plain";
      case "mp4":
        return "video/mp4";
      case "mov":
        return "video/quicktime";
      case "zip":
        return "application/zip";
      default:
        return "application/octet-stream";
    }
  }

  Future<void> closeWithResult() async {
    final message = controller.text.trim();
    if (message.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please describe your request")),
      );
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => submitting = true);

    try {
      final uploadedAttachments = await uploadAttachments();
      if (!mounted) return;
      Navigator.of(context).pop(
        _SupportRequestResult(
          type: selectedType,
          message: message,
          attachments: uploadedAttachments,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not upload attachments")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final dialogWidth = screenWidth < 440 ? screenWidth - 48 : 420.0;

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      title: const Text("Support request"),
      content: SizedBox(
        width: dialogWidth,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Type",
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              ...widget.requestTypes.entries.map((entry) {
                final selected = selectedType == entry.key;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: submitting
                        ? null
                        : () => setState(() => selectedType = entry.key),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 140),
                      curve: Curves.easeOut,
                      width: double.infinity,
                      constraints: const BoxConstraints(minHeight: 48),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 11,
                      ),
                      decoration: BoxDecoration(
                        color: selected
                            ? Theme.of(context)
                                .colorScheme
                                .primary
                                .withValues(alpha: 0.08)
                            : Colors.white.withValues(alpha: 0.72),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: selected
                              ? Theme.of(context).colorScheme.primary
                              : Colors.black.withValues(alpha: 0.16),
                          width: selected ? 1.4 : 1,
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Icon(
                            selected
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                            size: 20,
                            color: selected
                                ? Theme.of(context).colorScheme.primary
                                : Colors.black.withValues(alpha: 0.45),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              entry.value,
                              softWrap: true,
                              style: TextStyle(
                                fontWeight: selected
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                                height: 1.25,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                enabled: !submitting,
                maxLines: 5,
                minLines: 3,
                textInputAction: TextInputAction.newline,
                decoration: const InputDecoration(
                  labelText: "Message",
                  hintText: "Describe what you need help with",
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: submitting ? null : pickAttachments,
                  icon: const Icon(Icons.attach_file),
                  label: const Text("Attach files"),
                ),
              ),
              if (attachments.isNotEmpty) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: attachments.map((file) {
                      return InputChip(
                        avatar: const Icon(Icons.insert_drive_file, size: 18),
                        label: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: dialogWidth - 120,
                          ),
                          child: Text(
                            file.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        onDeleted: submitting
                            ? null
                            : () {
                                setState(() => attachments.remove(file));
                              },
                      );
                    }).toList(),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: submitting ? null : () => Navigator.of(context).pop(null),
          child: const Text("Cancel"),
        ),
        ElevatedButton(
          onPressed: submitting ? null : closeWithResult,
          child: submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text("Submit"),
        ),
      ],
    );
  }
}
