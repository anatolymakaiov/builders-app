import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

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

    if (result == null ||
        (result.message.trim().isEmpty && result.attachments.isEmpty)) {
      return;
    }
    if (context.mounted) {
      FocusScope.of(context).unfocus();
    }

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

    final messagePayload = {
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
    };
    final threadPayload = {
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
    };

    await _loggedPostSubmitSet(
      ref: messageRef,
      data: messagePayload,
      uid: userId,
      role: userRole,
      purpose: "sent_message/admin_inbox",
    );
    await _loggedPostSubmitSet(
      ref: threadRef,
      data: threadPayload,
      uid: userId,
      role: userRole,
      purpose: "admin_thread",
    );
    return threadRef.id;
  }

  static Future<void> _loggedPostSubmitSet({
    required DocumentReference<Map<String, dynamic>> ref,
    required Map<String, dynamic> data,
    required String uid,
    required String role,
    required String purpose,
  }) async {
    debugPrint(
      "POST SUBMIT WRITE: path=${ref.path} uid=$uid role=$role purpose=$purpose",
    );
    try {
      await ref.set(data);
      debugPrint("POST SUBMIT WRITE SUCCESS: path=${ref.path}");
    } catch (e) {
      debugPrint("POST SUBMIT WRITE FAILED: path=${ref.path} error=$e");
      rethrow;
    }
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
  late final ScrollController scrollController;
  final ImagePicker mediaPicker = ImagePicker();
  final List<PlatformFile> attachments = [];
  bool submitting = false;

  @override
  void initState() {
    super.initState();
    selectedType = widget.requestTypes.keys.first;
    controller = TextEditingController();
    scrollController = ScrollController();
  }

  @override
  void dispose() {
    controller.dispose();
    scrollController.dispose();
    super.dispose();
  }

  void revealAttachmentsPreview() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !scrollController.hasClients) return;
      scrollController.animateTo(
        scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> pickAttachments({
    required List<String> allowedExtensions,
  }) async {
    FocusScope.of(context).unfocus();
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
      type: FileType.custom,
      allowedExtensions: allowedExtensions,
    );
    if (result == null || !mounted) return;

    setState(() {
      addUniqueAttachments(result.files);
    });
    revealAttachmentsPreview();
  }

  Future<void> pickMediaAttachments() async {
    FocusScope.of(context).unfocus();

    List<XFile> picked;
    try {
      picked = await mediaPicker.pickMultipleMedia();
    } catch (e) {
      debugPrint("SUPPORT MEDIA PICK ERROR: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not select media")),
      );
      return;
    }

    if (picked.isEmpty || !mounted) return;

    final converted = <PlatformFile>[];
    for (final file in picked) {
      final bytes = await file.readAsBytes();
      converted.add(
        PlatformFile(
          name: file.name,
          size: bytes.length,
          bytes: bytes,
          path: file.path,
        ),
      );
    }
    if (!mounted) return;

    setState(() {
      addUniqueAttachments(converted);
    });
    revealAttachmentsPreview();
  }

  Future<void> pickFileAttachments() {
    return pickAttachments(
      allowedExtensions: [
        "pdf",
        "doc",
        "docx",
        "xls",
        "xlsx",
        "txt",
        "zip",
        "csv",
      ],
    );
  }

  void addUniqueAttachments(List<PlatformFile> files) {
    final existing =
        attachments.map((file) => "${file.name}_${file.size}").toSet();
    attachments.addAll(
      files.where((file) => !existing.contains("${file.name}_${file.size}")),
    );
  }

  String _extensionForFile(PlatformFile file) {
    final directExtension = file.extension?.trim().toLowerCase() ?? "";
    if (directExtension.isNotEmpty) return directExtension;
    final name = file.name.trim().toLowerCase();
    final dotIndex = name.lastIndexOf(".");
    if (dotIndex < 0 || dotIndex == name.length - 1) return "";
    return name.substring(dotIndex + 1);
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
      final extension = _extensionForFile(file);
      final path =
          "support_requests/${widget.userId}/${timestamp}_${index}_$safeName";
      final ref = storage.ref(path);

      debugPrint(
        "SUPPORT ATTACHMENT UPLOAD START "
        "path=$path userId=${widget.userId} fileName=${file.name}",
      );
      String url;
      try {
        await ref.putData(
          bytes,
          SettableMetadata(
            contentType: _contentTypeForExtension(extension),
            customMetadata: {
              "fileName": file.name,
              "fileType": extension,
              "userId": widget.userId,
            },
          ),
        );
        url = await ref.getDownloadURL();
        debugPrint("SUPPORT ATTACHMENT UPLOAD SUCCESS path=$path");
      } catch (error) {
        debugPrint("SUPPORT ATTACHMENT UPLOAD FAILED path=$path error=$error");
        rethrow;
      }
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
      case "xls":
        return "application/vnd.ms-excel";
      case "xlsx":
        return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";
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

  bool _isImageExtension(String extension) {
    return const {"jpg", "jpeg", "png", "gif", "webp", "heic", "heif"}
        .contains(extension.toLowerCase());
  }

  bool _isVideoExtension(String extension) {
    return const {"mp4", "mov", "m4v", "avi", "webm"}
        .contains(extension.toLowerCase());
  }

  IconData _attachmentIcon(String extension) {
    final normalized = extension.toLowerCase();
    if (_isImageExtension(normalized)) return Icons.image_outlined;
    if (_isVideoExtension(normalized)) return Icons.videocam_outlined;
    if (normalized == "pdf") return Icons.picture_as_pdf_outlined;
    if (normalized == "doc" || normalized == "docx") {
      return Icons.description_outlined;
    }
    if (normalized == "xls" || normalized == "xlsx" || normalized == "csv") {
      return Icons.table_chart_outlined;
    }
    return Icons.insert_drive_file_outlined;
  }

  String _fileTypeLabel(String extension) {
    final normalized = extension.toLowerCase();
    if (_isImageExtension(normalized)) return "Photo";
    if (_isVideoExtension(normalized)) return "Video";
    if (normalized.isEmpty) return "File";
    return normalized.toUpperCase();
  }

  String _fileSizeLabel(int size) {
    if (size <= 0) return "";
    if (size < 1024) return "$size B";
    if (size < 1024 * 1024) {
      return "${(size / 1024).toStringAsFixed(1)} KB";
    }
    return "${(size / (1024 * 1024)).toStringAsFixed(1)} MB";
  }

  Widget _attachmentThumbnail(PlatformFile file) {
    final extension = _extensionForFile(file);
    if (_isImageExtension(extension)) {
      final bytes = file.bytes;
      if (bytes != null) {
        return Image.memory(bytes, fit: BoxFit.cover);
      }
      final path = file.path;
      if (path != null && path.isNotEmpty) {
        return Image.file(File(path), fit: BoxFit.cover);
      }
    }

    return Container(
      color: Colors.white.withValues(alpha: 0.6),
      alignment: Alignment.center,
      child: Icon(
        _attachmentIcon(extension),
        color: Theme.of(context).colorScheme.primary,
        size: 26,
      ),
    );
  }

  Widget _selectedAttachmentsPreview() {
    if (attachments.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Row(
          children: [
            const Expanded(
              child: Text(
                "Selected attachments",
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.24),
                ),
              ),
              child: Text(
                "${attachments.length}",
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...attachments.map((file) {
          final extension = _extensionForFile(file);
          final sizeLabel = _fileSizeLabel(file.size);

          return Container(
            key: ValueKey("${file.name}_${file.size}"),
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.86),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.black.withValues(alpha: 0.14)),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: _attachmentThumbnail(file),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        file.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        [
                          _fileTypeLabel(extension),
                          if (sizeLabel.isNotEmpty) sizeLabel,
                        ].join(" • "),
                        style: TextStyle(
                          color: Colors.black.withValues(alpha: 0.56),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: "Remove attachment",
                  onPressed: submitting
                      ? null
                      : () => setState(() => attachments.remove(file)),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Future<void> closeWithResult() async {
    final message = controller.text.trim();
    if (message.isEmpty && attachments.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Please describe your request or attach a file")),
      );
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => submitting = true);

    try {
      final uploadedAttachments = await uploadAttachments();
      if (!mounted) return;
      FocusScope.of(context).unfocus();
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
          controller: scrollController,
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
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: submitting ? null : pickMediaAttachments,
                    icon: const Icon(Icons.perm_media_outlined),
                    label: const Text("Attach media"),
                  ),
                  OutlinedButton.icon(
                    onPressed: submitting ? null : pickFileAttachments,
                    icon: const Icon(Icons.attach_file),
                    label: const Text("Attach files"),
                  ),
                ],
              ),
              _selectedAttachmentsPreview(),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: submitting
              ? null
              : () {
                  FocusScope.of(context).unfocus();
                  Navigator.of(context).pop(null);
                },
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
