import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'image_viewer_screen.dart';
import '../services/chat_profile_navigation_service.dart';
import '../services/report_service.dart';
import '../services/chat_service.dart';
import '../theme/app_theme.dart';
import '../theme/stroyka_background.dart';

class ChatScreen extends StatefulWidget {
  final String chatId;

  const ChatScreen({super.key, required this.chatId});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final controller = TextEditingController();
  final scrollController = ScrollController();
  final picker = ImagePicker();
  final audioRecorder = AudioRecorder();
  Timer? typingTimer;

  String? workerId;
  String? employerId;
  List<String> chatMembers = [];
  bool _preloaded = false;
  bool _isTyping = false;
  bool _chatLoaded = false;
  bool isRecording = false;
  bool isUploadingMedia = false;
  final List<_PendingChatAttachment> pendingAttachments = [];
  final Set<String> _markedRead = {};

  @override
  void initState() {
    super.initState();
    initChat();
  }

  @override
  void dispose() {
    typingTimer?.cancel();
    updateTyping(false);
    audioRecorder.dispose();
    controller.dispose();
    scrollController.dispose();
    super.dispose();
  }

  String chatAttachmentPreview(List<Map<String, dynamic>> attachments) {
    if (attachments.isEmpty) return "";
    if (attachments.length == 1) {
      final type = attachments.first["type"]?.toString();
      if (type == "image") return "Photo";
      if (type == "video") return "Video";
      return "File";
    }
    return "${attachments.length} attachments";
  }

  Future<void> initChat() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final chatDoc = await FirebaseFirestore.instance
        .collection("chats")
        .doc(widget.chatId)
        .get();

    final data = chatDoc.data();
    if (data == null) return;

    setChatData(data);

    final isWorker = user.uid == workerId;

    await FirebaseFirestore.instance
        .collection("chats")
        .doc(widget.chatId)
        .set({
      if (isWorker) "unreadCount_worker": 0 else "unreadCount_employer": 0,
      "unreadFor": FieldValue.arrayRemove([user.uid]),
    }, SetOptions(merge: true));
  }

  void setChatData(Map<String, dynamic> data) {
    workerId = data["workerId"]?.toString();
    employerId = data["employerId"]?.toString();
    chatMembers = chatRecipientIds(data);
    _chatLoaded = true;
  }

  Future<bool> ensureChatDataLoaded() async {
    if (_chatLoaded && chatMembers.isNotEmpty) return true;

    final chatDoc = await FirebaseFirestore.instance
        .collection("chats")
        .doc(widget.chatId)
        .get();
    final data = chatDoc.data();
    if (data == null) return false;

    setChatData(data);
    return chatMembers.isNotEmpty;
  }

  List<String> chatRecipientIds(Map<String, dynamic> data) {
    final ids = <String>{};

    final members = data["members"];
    if (members is List) {
      ids.addAll(members.map((item) => item.toString()));
    }

    final participants = data["participants"];
    if (participants is List) {
      ids.addAll(participants.map((item) => item.toString()));
    }

    final worker = data["workerId"]?.toString();
    final employer = data["employerId"]?.toString();
    if (worker != null && worker.isNotEmpty) ids.add(worker);
    if (employer != null && employer.isNotEmpty) ids.add(employer);

    return ids.where((id) => id.isNotEmpty).toList();
  }

  List<String> unreadRecipients(String senderId) {
    final recipients = chatMembers
        .where((id) => id.isNotEmpty && id != senderId)
        .toSet()
        .toList();
    return recipients;
  }

  bool isChatInactive(Map<String, dynamic> data) {
    return data["active"] == false ||
        data["canSendMessages"] == false ||
        data["chatStatus"]?.toString() == "inactive";
  }

  String inactiveChatMessage(Map<String, dynamic> data) {
    final role = data["participantDeletedRole"]?.toString();
    if (role == "employer") {
      return "Conversation inactive. This employer has deleted their profile.";
    }
    return "Conversation inactive. This user has deleted their profile.";
  }

  void preloadImages(List<QueryDocumentSnapshot> messages) {
    if (_preloaded) return;

    int count = 0;

    for (var doc in messages) {
      if (count >= 10) break;

      final data = doc.data() as Map<String, dynamic>;

      if (data["type"] == "image" && data["imageUrl"] != null) {
        precacheImage(
          NetworkImage(data["imageUrl"].toString()),
          context,
        );
        count++;
      }
    }

    _preloaded = true;
  }

  void markUnreadMessagesRead(
      List<QueryDocumentSnapshot> messages, String uid) {
    final unread = messages.where((doc) {
      if (_markedRead.contains(doc.id)) return false;
      final data = doc.data() as Map<String, dynamic>;
      final readBy = List<String>.from(data["readBy"] ?? []);
      return !readBy.contains(uid);
    }).toList();

    if (unread.isEmpty) return;

    for (final doc in unread) {
      _markedRead.add(doc.id);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final batch = FirebaseFirestore.instance.batch();
        for (final doc in unread) {
          batch.update(doc.reference, {
            "readBy": FieldValue.arrayUnion([uid]),
          });
        }
        await batch.commit();
      } on FirebaseException catch (error) {
        debugPrint("Mark messages read failed: ${error.code}");
      }
    });
  }

  String messagePreview(Map<String, dynamic> data) {
    if (data["deletedForEveryone"] == true) return "Message deleted";

    final attachments = attachmentsFromMessage(data);
    if (attachments.isNotEmpty) {
      final text = data["text"]?.toString().trim() ?? "";
      if (text.isNotEmpty) return text;
      return chatAttachmentPreview(attachments);
    }

    final type = data["type"]?.toString() ?? "text";
    switch (type) {
      case "image":
        return "Photo";
      case "video":
        return "Video";
      case "audio":
        return "Voice message";
      default:
        return data["text"]?.toString() ?? "";
    }
  }

  List<Map<String, dynamic>> attachmentsFromMessage(Map<String, dynamic> data) {
    final rawAttachments = data["attachments"];
    if (rawAttachments is List) {
      return rawAttachments
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .where((item) => (item["url"]?.toString().isNotEmpty ?? false))
          .toList();
    }

    final type = data["type"]?.toString();
    final url = (data["mediaUrl"] ?? data["imageUrl"] ?? data["videoUrl"])
        ?.toString()
        .trim();
    if (url == null || url.isEmpty) return [];

    if (type == "image" || data["imageUrl"] != null) {
      return [
        {
          "type": "image",
          "url": url,
          "fileName": data["fileName"]?.toString() ?? "Photo",
        }
      ];
    }
    if (type == "video" || data["videoUrl"] != null) {
      return [
        {
          "type": "video",
          "url": url,
          "fileName": data["fileName"]?.toString() ?? "Video",
        }
      ];
    }
    return [];
  }

  Future<void> refreshChatLastMessage() async {
    final latest = await FirebaseFirestore.instance
        .collection("chats")
        .doc(widget.chatId)
        .collection("messages")
        .orderBy("createdAt", descending: true)
        .limit(20)
        .get();

    QueryDocumentSnapshot<Map<String, dynamic>>? latestVisible;
    for (final doc in latest.docs) {
      final data = doc.data();
      if (data["deletedForEveryone"] == true) continue;
      latestVisible = doc;
      break;
    }

    await FirebaseFirestore.instance
        .collection("chats")
        .doc(widget.chatId)
        .set({
      "lastMessage":
          latestVisible == null ? "" : messagePreview(latestVisible.data()),
      "lastMessageType": latestVisible == null
          ? "text"
          : latestVisible.data()["type"] ?? "text",
    }, SetOptions(merge: true));
  }

  Future<bool> isLatestGlobalMessage(String messageId) async {
    final latest = await FirebaseFirestore.instance
        .collection("chats")
        .doc(widget.chatId)
        .collection("messages")
        .orderBy("createdAt", descending: true)
        .limit(20)
        .get();

    for (final doc in latest.docs) {
      final data = doc.data();
      if (data["deletedForEveryone"] == true) continue;
      return doc.id == messageId;
    }

    return false;
  }

  Future<void> editTextMessage(
    QueryDocumentSnapshot message,
    Map<String, dynamic> data,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final type = data["type"]?.toString() ?? "text";
    final isSender = data["senderId"]?.toString() == user.uid;
    final deletedForEveryone = data["deletedForEveryone"] == true;
    if (!isSender || type != "text" || deletedForEveryone) return;

    final currentText = data["text"]?.toString() ?? "";
    if (currentText.trim().isEmpty) return;

    final editController = TextEditingController(text: currentText);

    final editedText = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text("Edit message"),
          content: TextField(
            controller: editController,
            autofocus: true,
            minLines: 1,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: "Message",
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(null),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(editController.text),
              child: const Text("Save"),
            ),
          ],
        );
      },
    );

    editController.dispose();

    final text = editedText?.trim() ?? "";
    if (!mounted || editedText == null) return;
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Message cannot be empty")),
      );
      return;
    }
    if (text == currentText) return;

    final latestMessage = await message.reference.get();
    final latestData = latestMessage.data() as Map<String, dynamic>?;
    if (latestData == null ||
        latestData["senderId"]?.toString() != user.uid ||
        (latestData["type"]?.toString() ?? "text") != "text" ||
        latestData["deletedForEveryone"] == true) {
      return;
    }

    await message.reference.update({
      "text": text,
      "editedAt": FieldValue.serverTimestamp(),
    });

    if (await isLatestGlobalMessage(message.id)) {
      await FirebaseFirestore.instance
          .collection("chats")
          .doc(widget.chatId)
          .set({
        "lastMessage": text,
        "lastMessageType": "text",
      }, SetOptions(merge: true));
    }
  }

  Future<void> deleteMessageForMe(String messageId, String uid) async {
    await FirebaseFirestore.instance
        .collection("chats")
        .doc(widget.chatId)
        .collection("messages")
        .doc(messageId)
        .set({
      "hiddenFor": FieldValue.arrayUnion([uid]),
    }, SetOptions(merge: true));
  }

  Future<void> deleteMessageForEveryone(
    QueryDocumentSnapshot message,
    String uid,
  ) async {
    await message.reference.set({
      "deletedForEveryone": true,
      "deletedAt": FieldValue.serverTimestamp(),
      "deletedBy": uid,
      "editedAt": FieldValue.delete(),
    }, SetOptions(merge: true));

    await refreshChatLastMessage();
  }

  Future<void> showMessageActions({
    required QueryDocumentSnapshot message,
    required Map<String, dynamic> data,
    required String uid,
  }) async {
    final isMe = data["senderId"] == uid;
    final type = data["type"]?.toString() ?? "text";
    final deletedForEveryone = data["deletedForEveryone"] == true;
    final canEdit = isMe && type == "text" && !deletedForEveryone;

    if (deletedForEveryone) return;

    await showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (canEdit)
                ListTile(
                  leading: const Icon(Icons.edit),
                  title: const Text("Edit message"),
                  onTap: () async {
                    Navigator.pop(context);
                    await Future<void>.delayed(
                      const Duration(milliseconds: 120),
                    );
                    if (!mounted) return;
                    editTextMessage(message, data);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.visibility_off_outlined),
                title: const Text("Delete for me"),
                onTap: () {
                  Navigator.pop(context);
                  deleteMessageForMe(message.id, uid);
                },
              ),
              if (isMe)
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.red),
                  title: const Text("Delete for everyone"),
                  textColor: Colors.red,
                  onTap: () async {
                    Navigator.pop(context);
                    await deleteMessageForEveryone(message, uid);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  /// 🔤 TEXT
  Future<void> sendMessage() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    if (!await ensureChatDataLoaded()) return;

    final chatDoc = await FirebaseFirestore.instance
        .collection("chats")
        .doc(widget.chatId)
        .get();
    final chatData = chatDoc.data();
    if (chatData == null || isChatInactive(chatData)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              "Message cannot be sent. This user has deleted their profile."),
        ),
      );
      return;
    }

    final text = controller.text.trim();
    if (text.isEmpty && pendingAttachments.isEmpty) return;
    if (isUploadingMedia) return;

    final isWorker = user.uid == workerId;
    final messageRef = FirebaseFirestore.instance
        .collection("chats")
        .doc(widget.chatId)
        .collection("messages")
        .doc();

    try {
      if (mounted) setState(() => isUploadingMedia = true);

      final attachments = await uploadPendingAttachments(
        messageId: messageRef.id,
        senderId: user.uid,
      );
      final firstAttachment =
          attachments.isNotEmpty ? attachments.first : <String, dynamic>{};
      final attachmentType = firstAttachment["type"]?.toString();
      final messageType = attachments.isEmpty
          ? "text"
          : attachments.length == 1 && attachmentType != "file"
              ? attachmentType
              : "attachments";
      final preview = text.isNotEmpty
          ? text
          : attachments.isNotEmpty
              ? "Sent an attachment"
              : "";

      await messageRef.set({
        "messageId": messageRef.id,
        "chatId": widget.chatId,
        "type": messageType,
        "text": text,
        "attachments": attachments,
        if (attachments.isNotEmpty) "mediaUrl": firstAttachment["url"],
        if (attachmentType == "image") "imageUrl": firstAttachment["url"],
        if (attachmentType == "video") "videoUrl": firstAttachment["url"],
        if (firstAttachment["fileName"] != null)
          "fileName": firstAttachment["fileName"],
        "senderId": user.uid,
        "senderRole": isWorker ? "worker" : "employer",
        "createdAt": FieldValue.serverTimestamp(),
        "readBy": [user.uid],
      });

      await FirebaseFirestore.instance
          .collection("chats")
          .doc(widget.chatId)
          .update({
        "lastMessage": preview,
        "lastMessageType": messageType,
        "updatedAt": FieldValue.serverTimestamp(),
        "unreadFor": FieldValue.arrayUnion(unreadRecipients(user.uid)),
        if (isWorker)
          "unreadCount_employer": FieldValue.increment(1)
        else
          "unreadCount_worker": FieldValue.increment(1),
        "typing_worker": false,
        "typing_employer": false,
      });

      controller.clear();
      typingTimer?.cancel();
      _isTyping = false;
      if (mounted) pendingAttachments.clear();
      scrollToBottom();
    } catch (e) {
      debugPrint("SEND MESSAGE ERROR: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Could not send message")),
        );
      }
    } finally {
      if (mounted) setState(() => isUploadingMedia = false);
    }
  }

  Uri? normalizeUrl(String text) {
    final match =
        RegExp(r'(https?:\/\/[^\s]+|www\.[^\s]+)').firstMatch(text.trim());
    if (match == null) return null;

    final value = match.group(0)?.replaceAll(RegExp(r'[.,!?;:]+$'), '') ?? "";
    if (value.isEmpty) return null;

    final normalized = value.startsWith("www.") ? "https://$value" : value;

    final uri = Uri.tryParse(normalized);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
    return uri;
  }

  String extensionForPickedFile(XFile picked, String fallback) {
    final namePart = picked.name.split(".").last;
    if (namePart != picked.name && namePart.trim().isNotEmpty) {
      return namePart.toLowerCase();
    }

    final pathPart = picked.path.split(".").last;
    if (pathPart != picked.path && pathPart.trim().isNotEmpty) {
      return pathPart.toLowerCase();
    }

    return fallback;
  }

  String mediaContentType(String type, String extension) {
    final ext = extension.toLowerCase();

    if (type == "image") {
      if (ext == "jpg") return "image/jpeg";
      if (ext == "heic" || ext == "heif") return "image/heic";
      return "image/$ext";
    }

    if (type == "video") {
      if (ext == "mov") return "video/quicktime";
      if (ext == "m4v") return "video/x-m4v";
      return "video/$ext";
    }

    return "application/octet-stream";
  }

  String sanitizeStorageName(String value) {
    final name = value.trim().isEmpty ? "attachment" : value.trim();
    return name.replaceAll(RegExp(r"[^A-Za-z0-9._-]+"), "_");
  }

  String fileContentType(String extension) {
    final ext = extension.toLowerCase();
    const types = {
      "pdf": "application/pdf",
      "doc": "application/msword",
      "docx":
          "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
      "xls": "application/vnd.ms-excel",
      "xlsx":
          "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
      "ppt": "application/vnd.ms-powerpoint",
      "pptx":
          "application/vnd.openxmlformats-officedocument.presentationml.presentation",
      "txt": "text/plain",
      "csv": "text/csv",
      "zip": "application/zip",
    };
    return types[ext] ?? "application/octet-stream";
  }

  Future<List<Map<String, dynamic>>> uploadPendingAttachments({
    required String messageId,
    required String senderId,
  }) async {
    final uploaded = <Map<String, dynamic>>[];

    for (final attachment in pendingAttachments) {
      final extension = attachment.extension;
      final fileName = sanitizeStorageName(attachment.fileName);
      final storagePath =
          "chat_attachments/${widget.chatId}/$messageId/$senderId/${DateTime.now().microsecondsSinceEpoch}_$fileName";
      final ref = FirebaseStorage.instance.ref().child(storagePath);
      final contentType = attachment.mimeType ??
          (attachment.type == "file"
              ? fileContentType(extension)
              : mediaContentType(attachment.type, extension));
      final metadata = SettableMetadata(contentType: contentType);

      if (attachment.path != null) {
        await ref.putFile(File(attachment.path!), metadata);
      } else if (attachment.bytes != null) {
        await ref.putData(attachment.bytes!, metadata);
      } else {
        throw StateError("Selected attachment has no readable file data");
      }

      final url = await ref.getDownloadURL();
      uploaded.add({
        "type": attachment.type,
        "url": url,
        "storagePath": storagePath,
        "fileName": attachment.fileName,
        "mimeType": contentType,
        if (attachment.size != null) "size": attachment.size,
        "uploadedAt": DateTime.now().toIso8601String(),
        "uploadedBy": senderId,
      });
    }

    return uploaded;
  }

  Future<void> updateChatAfterMedia({
    required String lastMessage,
    required String lastMessageType,
    required bool isWorker,
    required String senderId,
  }) async {
    if (!await ensureChatDataLoaded()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not open chat")),
      );
      return;
    }

    await FirebaseFirestore.instance
        .collection("chats")
        .doc(widget.chatId)
        .set({
      "lastMessage": lastMessage,
      "lastMessageType": lastMessageType,
      "updatedAt": FieldValue.serverTimestamp(),
      "unreadFor": FieldValue.arrayUnion(unreadRecipients(senderId)),
      if (isWorker)
        "unreadCount_employer": FieldValue.increment(1)
      else
        "unreadCount_worker": FieldValue.increment(1),
      if (isWorker) "typing_worker": false else "typing_employer": false,
    }, SetOptions(merge: true));
  }

  Future<void> sendPickedMedia({
    required XFile picked,
    required String type,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    if (isUploadingMedia) return;
    if (!await ensureChatDataLoaded()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not open chat")),
      );
      return;
    }

    final file = File(picked.path);
    if (!file.existsSync()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not read selected file")),
      );
      return;
    }

    final extension =
        extensionForPickedFile(picked, type == "video" ? "mp4" : "jpg");

    try {
      if (mounted) setState(() => isUploadingMedia = true);

      final ref = FirebaseStorage.instance.ref().child(
          "chat_media/${widget.chatId}/${DateTime.now().millisecondsSinceEpoch}.$extension");

      await ref.putFile(
        file,
        SettableMetadata(contentType: mediaContentType(type, extension)),
      );
      final url = await ref.getDownloadURL();

      final isWorker = user.uid == workerId;
      final fileName = picked.name;

      await FirebaseFirestore.instance
          .collection("chats")
          .doc(widget.chatId)
          .collection("messages")
          .add({
        "type": type,
        "mediaUrl": url,
        if (type == "image") "imageUrl": url,
        if (type == "video") "videoUrl": url,
        "fileName": fileName,
        "senderId": user.uid,
        "createdAt": FieldValue.serverTimestamp(),
        "readBy": [user.uid],
      });

      await updateChatAfterMedia(
        lastMessage: type == "video" ? "Video" : "Photo",
        lastMessageType: type,
        isWorker: isWorker,
        senderId: user.uid,
      );

      scrollToBottom();
    } catch (e) {
      debugPrint("MEDIA ERROR: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Could not send $type")),
        );
      }
    } finally {
      if (mounted) setState(() => isUploadingMedia = false);
    }
  }

  Future<void> sendImage() async {
    List<XFile> picked = [];
    try {
      picked = await picker.pickMultiImage();
      if (picked.isEmpty) return;
    } catch (e) {
      debugPrint("PICK IMAGE ERROR: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not select photo")),
      );
      return;
    }

    setState(() {
      pendingAttachments.addAll(
        picked.map(
          (item) => _PendingChatAttachment(
            type: "image",
            fileName: item.name,
            path: item.path,
            mimeType: mediaContentType(
              "image",
              extensionForPickedFile(item, "jpg"),
            ),
          ),
        ),
      );
    });
  }

  Future<void> sendVideo() async {
    FilePickerResult? picked;
    try {
      picked = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.video,
        withData: false,
      );
      if (picked == null) return;
    } catch (e) {
      debugPrint("PICK VIDEO ERROR: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not select video")),
      );
      return;
    }

    setState(() {
      pendingAttachments.addAll(
        picked!.files
            .where((item) => item.path != null || item.bytes != null)
            .map(
              (item) => _PendingChatAttachment(
                type: "video",
                fileName: item.name,
                path: item.path,
                bytes: item.bytes,
                size: item.size,
                mimeType: mediaContentType(
                  "video",
                  item.extension ?? "mp4",
                ),
              ),
            ),
      );
    });
  }

  Future<void> sendFiles() async {
    FilePickerResult? picked;
    try {
      picked = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.any,
        withData: false,
      );
      if (picked == null) return;
    } catch (e) {
      debugPrint("PICK FILE ERROR: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not select file")),
      );
      return;
    }

    setState(() {
      pendingAttachments.addAll(
        picked!.files
            .where((item) => item.path != null || item.bytes != null)
            .map(
              (item) => _PendingChatAttachment(
                type: "file",
                fileName: item.name,
                path: item.path,
                bytes: item.bytes,
                size: item.size,
                mimeType: item.extension == null
                    ? null
                    : fileContentType(item.extension!),
              ),
            ),
      );
    });
  }

  Future<void> toggleRecording() async {
    if (isRecording) {
      await stopRecordingAndSend();
    } else {
      await startRecording();
    }
  }

  Future<void> startRecording() async {
    try {
      if (!await ensureChatDataLoaded()) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Could not open chat")),
        );
        return;
      }

      final hasPermission = await audioRecorder.hasPermission();
      if (!hasPermission) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Microphone permission is required")),
        );
        return;
      }

      final dir = await getTemporaryDirectory();
      final path =
          "${dir.path}/voice_${widget.chatId}_${DateTime.now().millisecondsSinceEpoch}.m4a";

      await audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
        ),
        path: path,
      );

      setState(() {
        isRecording = true;
      });
    } catch (e) {
      debugPrint("START RECORDING ERROR: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not start recording")),
      );
    }
  }

  Future<void> stopRecordingAndSend() async {
    String? path;
    try {
      path = await audioRecorder.stop();
    } catch (e) {
      debugPrint("STOP RECORDING ERROR: $e");
    } finally {
      if (mounted) {
        setState(() {
          isRecording = false;
        });
      }
    }

    if (path == null) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    if (!await ensureChatDataLoaded()) return;

    final file = File(path);
    if (!file.existsSync()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not read voice recording")),
      );
      return;
    }

    try {
      if (mounted) setState(() => isUploadingMedia = true);

      final ref = FirebaseStorage.instance.ref().child(
          "chat_voice/${widget.chatId}/${DateTime.now().millisecondsSinceEpoch}.m4a");

      await ref.putFile(
        file,
        SettableMetadata(contentType: "audio/mp4"),
      );
      final url = await ref.getDownloadURL();

      final isWorker = user.uid == workerId;

      await FirebaseFirestore.instance
          .collection("chats")
          .doc(widget.chatId)
          .collection("messages")
          .add({
        "type": "audio",
        "audioUrl": url,
        "mediaUrl": url,
        "senderId": user.uid,
        "createdAt": FieldValue.serverTimestamp(),
        "readBy": [user.uid],
      });

      await updateChatAfterMedia(
        lastMessage: "Voice message",
        lastMessageType: "audio",
        isWorker: isWorker,
        senderId: user.uid,
      );

      scrollToBottom();
    } catch (e) {
      debugPrint("SEND AUDIO ERROR: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not send voice message")),
      );
    } finally {
      if (mounted) setState(() => isUploadingMedia = false);
    }
  }

  Future<void> showAttachmentMenu() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text("Photos"),
                onTap: () {
                  Navigator.pop(context);
                  sendImage();
                },
              ),
              ListTile(
                leading: const Icon(Icons.videocam),
                title: const Text("Videos"),
                onTap: () {
                  Navigator.pop(context);
                  sendVideo();
                },
              ),
              ListTile(
                leading: const Icon(Icons.attach_file),
                title: const Text("Files"),
                onTap: () {
                  Navigator.pop(context);
                  sendFiles();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void scrollToBottom() async {
    await Future.delayed(const Duration(milliseconds: 100));
    if (scrollController.hasClients) {
      scrollController.animateTo(
        scrollController.position.maxScrollExtent + 100,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> updateTyping(bool isTyping) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    if (workerId == null || employerId == null) return;
    if (_isTyping == isTyping) return;

    _isTyping = isTyping;

    final isWorker = user.uid == workerId;

    await FirebaseFirestore.instance
        .collection("chats")
        .doc(widget.chatId)
        .update({
      if (isWorker) "typing_worker": isTyping else "typing_employer": isTyping,
    });
  }

  void handleTypingChanged(String value) {
    final hasText = value.trim().isNotEmpty;

    updateTyping(hasText);
    typingTimer?.cancel();

    if (!hasText) return;

    typingTimer = Timer(const Duration(seconds: 2), () {
      updateTyping(false);
    });
  }

  String formatLastSeen(Timestamp? ts) {
    if (ts == null) return "offline";

    final dt = ts.toDate();
    final diff = DateTime.now().difference(dt);

    if (diff.inMinutes < 1) return "online";
    if (diff.inMinutes < 60) return "${diff.inMinutes} min ago";
    if (diff.inHours < 24) return "${diff.inHours} h ago";

    return "${dt.day}.${dt.month}";
  }

  String formatTime(Timestamp? ts) {
    if (ts == null) return "";
    final dt = ts.toDate();
    return "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
  }

  String formatAttachmentSize(dynamic value) {
    final bytes = value is int ? value : int.tryParse(value?.toString() ?? "");
    if (bytes == null || bytes <= 0) return "";
    if (bytes < 1024) return "$bytes B";
    if (bytes < 1024 * 1024) return "${(bytes / 1024).toStringAsFixed(1)} KB";
    return "${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB";
  }

  Widget buildAttachmentPreview(Map<String, dynamic> attachment) {
    final type = attachment["type"]?.toString() ?? "file";
    final url = attachment["url"]?.toString() ?? "";
    final fileName = attachment["fileName"]?.toString() ?? "Attachment";

    if (type == "image") {
      return GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ImageViewerScreen(imageUrl: url),
            ),
          );
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.network(
            url,
            width: 200,
            height: 150,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return Container(
                width: 200,
                height: 150,
                alignment: Alignment.center,
                color: AppColors.surfaceAlt,
                child: const Icon(Icons.image_outlined, color: AppColors.muted),
              );
            },
            errorBuilder: (context, error, stackTrace) => Container(
              width: 200,
              height: 150,
              alignment: Alignment.center,
              color: AppColors.surfaceAlt,
              child: const Icon(Icons.broken_image, color: AppColors.muted),
            ),
          ),
        ),
      );
    }

    if (type == "video") {
      return VideoMessagePreview(url: url);
    }

    final sizeLabel = formatAttachmentSize(attachment["size"]);
    return InkWell(
      onTap: () async {
        final uri = Uri.tryParse(url);
        if (uri == null) return;
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      },
      child: Container(
        width: 220,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.blueprintLine),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.insert_drive_file_outlined, size: 26),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    fileName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  if (sizeLabel.isNotEmpty)
                    Text(
                      sizeLabel,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.muted,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildMessageAttachments(List<Map<String, dynamic>> attachments) {
    if (attachments.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < attachments.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          buildAttachmentPreview(attachments[i]),
        ],
      ],
    );
  }

  Widget buildPendingAttachments() {
    if (pendingAttachments.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (var i = 0; i < pendingAttachments.length; i++)
            InputChip(
              avatar: Icon(
                pendingAttachments[i].icon,
                size: 18,
                color: AppColors.navy,
              ),
              label: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: Text(
                  pendingAttachments[i].fileName,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              onDeleted: isUploadingMedia
                  ? null
                  : () {
                      setState(() => pendingAttachments.removeAt(i));
                    },
            ),
        ],
      ),
    );
  }

  String formatDateLabel(DateTime date) {
    final now = DateTime.now();
    final diff = DateTime(now.year, now.month, now.day)
        .difference(DateTime(date.year, date.month, date.day))
        .inDays;

    if (diff == 0) return "Today";
    if (diff == 1) return "Yesterday";

    return "${date.day}.${date.month}.${date.year}";
  }

  List<Map<String, String>> contactPhones(Map<String, dynamic>? userData) {
    if (userData == null) return [];

    final contacts = <Map<String, String>>[];

    void addPhone(String label, dynamic value) {
      final phone = value?.toString().trim() ?? "";
      if (phone.isEmpty) return;
      if (contacts.any((item) => item["phone"] == phone)) return;

      contacts.add({
        "label": label,
        "phone": phone,
      });
    }

    addPhone("Main phone", userData["phone"]);

    final extraPhones = userData["phones"];
    if (extraPhones is List) {
      for (var i = 0; i < extraPhones.length; i++) {
        addPhone("Phone ${i + 2}", extraPhones[i]);
      }
    }

    final contactPeople = userData["contacts"];
    if (contactPeople is List) {
      for (final contact in contactPeople) {
        if (contact is! Map) continue;
        final name = contact["name"]?.toString().trim();
        addPhone(
          name == null || name.isEmpty ? "Contact" : name,
          contact["phone"],
        );
      }
    }

    return contacts;
  }

  Future<void> callPhone(String phone) async {
    final cleanPhone = phone.replaceAll(RegExp(r'[^0-9+]'), "");
    if (cleanPhone.isEmpty) return;

    final uri = Uri(scheme: "tel", path: cleanPhone);
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);

    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not start phone call")),
      );
    }
  }

  Future<void> showCallOptions(
    BuildContext context,
    Map<String, dynamic>? userData,
  ) async {
    final phones = contactPhones(userData);

    if (phones.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No phone number available")),
      );
      return;
    }

    if (phones.length == 1) {
      await callPhone(phones.first["phone"]!);
      return;
    }

    await showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: phones.map((item) {
              return ListTile(
                leading: const Icon(Icons.call),
                title: Text(item["label"]!),
                subtitle: Text(item["phone"]!),
                onTap: () {
                  Navigator.pop(context);
                  callPhone(item["phone"]!);
                },
              );
            }).toList(),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: Text("Not logged in")));
    }

    final uid = user.uid;

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection("chats")
          .doc(widget.chatId)
          .snapshots(),
      builder: (context, chatSnapshot) {
        if (!chatSnapshot.hasData || !chatSnapshot.data!.exists) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }

        final chatData = chatSnapshot.data!.data() as Map<String, dynamic>;
        final inactive = isChatInactive(chatData);
        final inactiveMessage = inactiveChatMessage(chatData);

        final isInternalTeamChat = chatData["type"] == "internal_team";
        final isTeamChat =
            chatData["type"] == "team" || chatData["teamId"] != null;
        final isWorker = uid == chatData["workerId"];
        final showTeamHeader = isInternalTeamChat ||
            (isTeamChat && uid == chatData["employerId"]?.toString());
        final otherUserId = showTeamHeader
            ? chatData["teamId"]
            : (isWorker ? chatData["employerId"] : chatData["workerId"]);
        final otherProfileId = otherUserId?.toString() ?? "__missing_profile__";
        final profileCollection = showTeamHeader ? "teams" : "users";
        final jobId = chatData["jobId"]?.toString();

        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection(profileCollection)
              .doc(otherProfileId)
              .snapshots(),
          builder: (context, userSnapshot) {
            final userData = userSnapshot.data?.data() as Map<String, dynamic>?;

            final isOnline =
                showTeamHeader ? false : userData?["isOnline"] ?? false;

            final lastSeenRaw = userData?["lastSeen"];
            final Timestamp? lastSeen =
                lastSeenRaw is Timestamp ? lastSeenRaw : null;

            final typingWorker = chatData["typing_worker"] ?? false;
            final typingEmployer = chatData["typing_employer"] ?? false;
            final isTyping = !isInternalTeamChat &&
                (isWorker ? typingEmployer : typingWorker) &&
                isOnline;

            return StreamBuilder<DocumentSnapshot>(
              stream: jobId == null || jobId.isEmpty
                  ? null
                  : FirebaseFirestore.instance
                      .collection("jobs")
                      .doc(jobId)
                      .snapshots(),
              builder: (context, jobSnapshot) {
                final jobData =
                    jobSnapshot.data?.data() as Map<String, dynamic>?;
                final name = ChatService.chatDisplayName(
                  chatData: chatData,
                  participantData: userData,
                  jobData: jobData,
                  currentUserIsWorker: isWorker,
                  isInternalTeamChat: isInternalTeamChat,
                  showTeamAvatar: showTeamHeader,
                );

                return StroykaBackground(
                  asset: AppAssets.backgroundWorkersCity,
                  child: Scaffold(
                    appBar: AppBar(
                      title: InkWell(
                        onTap: () => ChatProfileNavigationService.openFromChat(
                          context,
                          chatData: chatData,
                          currentUserId: uid,
                          preferTeamTarget: showTeamHeader,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name),
                            Text(
                              isTyping
                                  ? "typing..."
                                  : isOnline
                                      ? "Online"
                                      : formatLastSeen(lastSeen),
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      actions: [
                        if (!isInternalTeamChat)
                          IconButton(
                            tooltip: "Call",
                            icon: const Icon(Icons.call),
                            onPressed: () => showCallOptions(context, userData),
                          ),
                        IconButton(
                          tooltip: "Report chat",
                          icon: const Icon(Icons.flag_outlined),
                          onPressed: () => ReportService.showReportDialog(
                            context,
                            type: "chat",
                            againstUserId: isInternalTeamChat
                                ? null
                                : otherUserId?.toString(),
                            chatId: widget.chatId,
                            jobId: chatData["jobId"]?.toString(),
                          ),
                        ),
                      ],
                    ),
                    body: StroykaScreenBody(
                      child: Column(
                        children: [
                          Expanded(
                            child: StreamBuilder<QuerySnapshot>(
                              stream: FirebaseFirestore.instance
                                  .collection("chats")
                                  .doc(widget.chatId)
                                  .collection("messages")
                                  .orderBy("createdAt")
                                  .snapshots(),
                              builder: (context, snapshot) {
                                if (!snapshot.hasData) {
                                  return const Center(
                                      child: CircularProgressIndicator());
                                }

                                final messages =
                                    snapshot.data!.docs.where((doc) {
                                  final data =
                                      doc.data() as Map<String, dynamic>;
                                  final hiddenFor = List<String>.from(
                                      data["hiddenFor"] ?? []);
                                  return !hiddenFor.contains(uid);
                                }).toList();
                                preloadImages(messages);
                                markUnreadMessagesRead(messages, uid);

                                return ListView.builder(
                                  controller: scrollController,
                                  padding: const EdgeInsets.all(10),
                                  itemCount: messages.length,
                                  itemBuilder: (context, index) {
                                    final doc = messages[index];
                                    final data =
                                        doc.data() as Map<String, dynamic>;

                                    final isMe = data["senderId"] == uid;
                                    final type = data["type"] ?? "text";
                                    final deletedForEveryone =
                                        data["deletedForEveryone"] == true;
                                    final attachments =
                                        attachmentsFromMessage(data);
                                    final text = data["text"]?.toString() ?? "";
                                    final editedAt = data["editedAt"];
                                    final isEdited =
                                        type == "text" && editedAt != null;

                                    final ts = data["createdAt"] as Timestamp?;
                                    final date = ts?.toDate();
                                    final time = formatTime(ts);

                                    bool showDate = index == 0;

                                    if (!showDate && index > 0) {
                                      final prev = messages[index - 1].data()
                                          as Map<String, dynamic>;
                                      final prevDate =
                                          (prev["createdAt"] as Timestamp?)
                                              ?.toDate();

                                      if (date != null && prevDate != null) {
                                        showDate = date.day != prevDate.day ||
                                            date.month != prevDate.month ||
                                            date.year != prevDate.year;
                                      }
                                    }

                                    final readBy =
                                        List<String>.from(data["readBy"] ?? []);
                                    final isRead = readBy.length > 1;

                                    return Column(
                                      children: [
                                        if (showDate && date != null)
                                          Padding(
                                            padding: const EdgeInsets.symmetric(
                                                vertical: 10),
                                            child: Text(formatDateLabel(date)),
                                          ),
                                        Align(
                                          alignment: isMe
                                              ? Alignment.centerRight
                                              : Alignment.centerLeft,
                                          child: GestureDetector(
                                            onLongPress: () =>
                                                showMessageActions(
                                              message: doc,
                                              data: data,
                                              uid: uid,
                                            ),
                                            child: Container(
                                              margin:
                                                  const EdgeInsets.symmetric(
                                                      vertical: 4),
                                              padding: const EdgeInsets.all(12),
                                              constraints: const BoxConstraints(
                                                  maxWidth: 260),
                                              decoration: BoxDecoration(
                                                color: isMe
                                                    ? AppColors.surfaceAlt
                                                    : Colors.grey.shade200,
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.end,
                                                children: [
                                                  if (deletedForEveryone)
                                                    const Text(
                                                      "Message deleted",
                                                      style: TextStyle(
                                                        fontStyle:
                                                            FontStyle.italic,
                                                        color: Colors.grey,
                                                      ),
                                                    ),
                                                  if (!deletedForEveryone &&
                                                      text.trim().isNotEmpty &&
                                                      type != "audio")
                                                    _TextMessageContent(
                                                      text: text,
                                                      normalizeUrl:
                                                          normalizeUrl,
                                                    ),
                                                  if (!deletedForEveryone &&
                                                      attachments.isNotEmpty)
                                                    Padding(
                                                      padding: EdgeInsets.only(
                                                        top: text
                                                                .trim()
                                                                .isNotEmpty
                                                            ? 8
                                                            : 0,
                                                      ),
                                                      child:
                                                          buildMessageAttachments(
                                                              attachments),
                                                    ),
                                                  if (!deletedForEveryone &&
                                                      type == "audio" &&
                                                      (data["audioUrl"] !=
                                                              null ||
                                                          data["mediaUrl"] !=
                                                              null))
                                                    AudioMessageBubble(
                                                      url: data["audioUrl"] ??
                                                          data["mediaUrl"],
                                                    ),
                                                  if (!deletedForEveryone &&
                                                      type == "link" &&
                                                      (data["url"] != null ||
                                                          data["text"] != null))
                                                    InkWell(
                                                      onTap: () async {
                                                        final raw =
                                                            data["url"] ??
                                                                data["text"];
                                                        final uri =
                                                            normalizeUrl(
                                                                raw.toString());
                                                        if (uri == null) return;
                                                        await launchUrl(
                                                          uri,
                                                          mode: LaunchMode
                                                              .externalApplication,
                                                        );
                                                      },
                                                      child: Row(
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        children: [
                                                          const Icon(Icons.link,
                                                              size: 18),
                                                          const SizedBox(
                                                              width: 6),
                                                          Flexible(
                                                            child: Text(
                                                              (data["url"] ??
                                                                      data[
                                                                          "text"])
                                                                  .toString(),
                                                              style:
                                                                  const TextStyle(
                                                                decoration:
                                                                    TextDecoration
                                                                        .underline,
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  const SizedBox(height: 4),
                                                  Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      if (isEdited) ...[
                                                        const Text(
                                                          "edited",
                                                          style: TextStyle(
                                                            fontSize: 10,
                                                            color: Colors.grey,
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                            width: 4),
                                                      ],
                                                      Text(time,
                                                          style:
                                                              const TextStyle(
                                                                  fontSize:
                                                                      10)),
                                                      const SizedBox(width: 4),
                                                      if (isMe)
                                                        Icon(Icons.done_all,
                                                            size: 16,
                                                            color: isRead
                                                                ? AppColors
                                                                    .greenDark
                                                                : Colors.grey),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                );
                              },
                            ),
                          ),
                          if (isTyping)
                            const Padding(
                              padding: EdgeInsets.only(left: 12, bottom: 6),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text("typing..."),
                              ),
                            ),
                          if (inactive)
                            Container(
                              width: double.infinity,
                              margin: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color:
                                    AppColors.warning.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color:
                                      AppColors.warning.withValues(alpha: 0.4),
                                ),
                              ),
                              child: Text(
                                inactiveMessage,
                                style: const TextStyle(
                                  color: AppColors.ink,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          SafeArea(
                            child: Container(
                              color: AppColors.navy,
                              padding:
                                  const EdgeInsets.fromLTRB(10, 10, 10, 10),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (isUploadingMedia)
                                    const Padding(
                                      padding: EdgeInsets.only(bottom: 8),
                                      child: LinearProgressIndicator(),
                                    ),
                                  buildPendingAttachments(),
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      IconButton.filled(
                                        style: IconButton.styleFrom(
                                          backgroundColor: AppColors.green,
                                          foregroundColor: Colors.white,
                                        ),
                                        icon: const Icon(Icons.add),
                                        onPressed: isUploadingMedia || inactive
                                            ? null
                                            : showAttachmentMenu,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: TextField(
                                          controller: controller,
                                          onChanged: handleTypingChanged,
                                          keyboardType: TextInputType.multiline,
                                          textInputAction:
                                              TextInputAction.newline,
                                          minLines: 1,
                                          maxLines: 6,
                                          decoration: const InputDecoration(
                                            hintText: "Type a message",
                                            filled: true,
                                            fillColor: Colors.white,
                                            contentPadding:
                                                EdgeInsets.symmetric(
                                              horizontal: 16,
                                              vertical: 12,
                                            ),
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        icon: Icon(
                                          isRecording
                                              ? Icons.stop_circle
                                              : Icons.mic,
                                          color: isRecording
                                              ? Colors.red
                                              : Colors.white,
                                        ),
                                        onPressed: isUploadingMedia || inactive
                                            ? null
                                            : toggleRecording,
                                      ),
                                      IconButton.filled(
                                        style: IconButton.styleFrom(
                                          backgroundColor: Colors.white70,
                                          foregroundColor: AppColors.navy,
                                        ),
                                        icon: const Icon(Icons.send),
                                        onPressed: isUploadingMedia || inactive
                                            ? null
                                            : sendMessage,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _PendingChatAttachment {
  final String type;
  final String fileName;
  final String? path;
  final Uint8List? bytes;
  final int? size;
  final String? mimeType;

  const _PendingChatAttachment({
    required this.type,
    required this.fileName,
    this.path,
    this.bytes,
    this.size,
    this.mimeType,
  });

  String get extension {
    final parts = fileName.split(".");
    if (parts.length > 1 && parts.last.trim().isNotEmpty) {
      return parts.last.toLowerCase();
    }
    if (type == "image") return "jpg";
    if (type == "video") return "mp4";
    return "bin";
  }

  IconData get icon {
    if (type == "image") return Icons.image_outlined;
    if (type == "video") return Icons.videocam_outlined;
    return Icons.insert_drive_file_outlined;
  }
}

class _TextMessageContent extends StatelessWidget {
  final String text;
  final Uri? Function(String text) normalizeUrl;

  const _TextMessageContent({
    required this.text,
    required this.normalizeUrl,
  });

  @override
  Widget build(BuildContext context) {
    final uri = normalizeUrl(text);
    if (uri == null) return Text(text);

    return InkWell(
      onTap: () => launchUrl(uri, mode: LaunchMode.externalApplication),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.link, size: 18),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              style: const TextStyle(decoration: TextDecoration.underline),
            ),
          ),
        ],
      ),
    );
  }
}

class AudioMessageBubble extends StatefulWidget {
  final String url;

  const AudioMessageBubble({
    super.key,
    required this.url,
  });

  @override
  State<AudioMessageBubble> createState() => _AudioMessageBubbleState();
}

class _AudioMessageBubbleState extends State<AudioMessageBubble> {
  final player = AudioPlayer();
  bool isPlaying = false;

  @override
  void initState() {
    super.initState();
    player.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          isPlaying = false;
        });
      }
    });
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }

  Future<void> togglePlayback() async {
    if (isPlaying) {
      await player.pause();
      setState(() {
        isPlaying = false;
      });
      return;
    }

    await player.play(UrlSource(widget.url));
    setState(() {
      isPlaying = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: togglePlayback,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(isPlaying ? Icons.pause_circle : Icons.play_circle, size: 28),
          const SizedBox(width: 8),
          const Text("Voice message"),
        ],
      ),
    );
  }
}

class VideoMessagePreview extends StatefulWidget {
  final String url;

  const VideoMessagePreview({
    super.key,
    required this.url,
  });

  @override
  State<VideoMessagePreview> createState() => _VideoMessagePreviewState();
}

class _VideoMessagePreviewState extends State<VideoMessagePreview> {
  late final VideoPlayerController controller;
  bool initialized = false;

  @override
  void initState() {
    super.initState();
    controller = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..initialize().then((_) {
        if (mounted) {
          setState(() {
            initialized = true;
          });
        }
      });
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> togglePlayback() async {
    if (!initialized) return;

    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      await controller.play();
    }

    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!initialized) {
      return Container(
        width: 200,
        height: 120,
        alignment: Alignment.center,
        child: const CircularProgressIndicator(strokeWidth: 2),
      );
    }

    return GestureDetector(
      onTap: togglePlayback,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 200,
            child: AspectRatio(
              aspectRatio: controller.value.aspectRatio,
              child: VideoPlayer(controller),
            ),
          ),
          if (!controller.value.isPlaying)
            Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.play_arrow, color: Colors.white),
            ),
        ],
      ),
    );
  }
}
