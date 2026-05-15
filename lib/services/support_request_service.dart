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

    await FirebaseFirestore.instance.collection("support_requests").add({
      "userId": user.uid,
      "userRole": userRole,
      "role": userRole,
      "type": result.type,
      "requestType": result.type,
      "typeLabel": requestTypes[result.type] ?? result.type,
      "requestTypeLabel": requestTypes[result.type] ?? result.type,
      "message": result.message,
      "attachments": result.attachments,
      "hasAttachments": result.attachments.isNotEmpty,
      "status": "open",
      "readByAdmin": false,
      "viewedByAdmin": false,
      "createdAt": FieldValue.serverTimestamp(),
      "updatedAt": FieldValue.serverTimestamp(),
    });

    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Support request submitted")),
    );
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
            children: [
              DropdownButtonFormField<String>(
                initialValue: selectedType,
                isExpanded: true,
                decoration: const InputDecoration(labelText: "Type"),
                selectedItemBuilder: (context) {
                  return widget.requestTypes.values.map((label) {
                    return Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList();
                },
                items: widget.requestTypes.entries
                    .map(
                      (entry) => DropdownMenuItem(
                        value: entry.key,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: dialogWidth - 96,
                          ),
                          child: Text(
                            entry.value,
                            softWrap: true,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: submitting
                    ? null
                    : (value) {
                        if (value == null || !mounted) return;
                        setState(() => selectedType = value);
                      },
              ),
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
