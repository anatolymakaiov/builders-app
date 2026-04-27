import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'dart:async';
import 'dart:io';
import 'image_viewer_screen.dart';
import '../theme/app_theme.dart';

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
  bool _preloaded = false;
  bool _isTyping = false;
  bool isRecording = false;

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

  Future<void> initChat() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final chatDoc = await FirebaseFirestore.instance
        .collection("chats")
        .doc(widget.chatId)
        .get();

    final data = chatDoc.data();
    if (data == null) return;

    workerId = data["workerId"];
    employerId = data["employerId"];

    final isWorker = user.uid == workerId;

    await FirebaseFirestore.instance
        .collection("chats")
        .doc(widget.chatId)
        .update({
      if (isWorker) "unreadCount_worker": 0 else "unreadCount_employer": 0,
    });
  }

  void preloadImages(List<QueryDocumentSnapshot> messages) {
    if (_preloaded) return;

    int count = 0;

    for (var doc in messages) {
      if (count >= 10) break;

      final data = doc.data() as Map<String, dynamic>;

      if (data["type"] == "image" && data["imageUrl"] != null) {
        precacheImage(
          CachedNetworkImageProvider(data["imageUrl"]),
          context,
        );
        count++;
      }
    }

    _preloaded = true;
  }

  /// 🔤 TEXT
  Future<void> sendMessage() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final text = controller.text.trim();
    if (text.isEmpty) return;

    controller.clear();
    typingTimer?.cancel();
    _isTyping = false;

    final isWorker = user.uid == workerId;

    await FirebaseFirestore.instance
        .collection("chats")
        .doc(widget.chatId)
        .collection("messages")
        .add({
      "type": "text",
      "text": text,
      "senderId": user.uid,
      "createdAt": FieldValue.serverTimestamp(),
      "readBy": [user.uid],
    });

    await FirebaseFirestore.instance
        .collection("chats")
        .doc(widget.chatId)
        .update({
      "lastMessage": text,
      "lastMessageType": "text",
      "updatedAt": FieldValue.serverTimestamp(),
      if (isWorker)
        "unreadCount_employer": FieldValue.increment(1)
      else
        "unreadCount_worker": FieldValue.increment(1),
      "typing_worker": false,
      "typing_employer": false,
    });

    scrollToBottom();
  }

  Future<void> updateChatAfterMedia({
    required String lastMessage,
    required String lastMessageType,
    required bool isWorker,
  }) async {
    await FirebaseFirestore.instance
        .collection("chats")
        .doc(widget.chatId)
        .update({
      "lastMessage": lastMessage,
      "lastMessageType": lastMessageType,
      "updatedAt": FieldValue.serverTimestamp(),
      if (isWorker)
        "unreadCount_employer": FieldValue.increment(1)
      else
        "unreadCount_worker": FieldValue.increment(1),
      if (isWorker) "typing_worker": false else "typing_employer": false,
    });
  }

  Future<void> sendPickedMedia({
    required XFile picked,
    required String type,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final file = File(picked.path);
    final extension = picked.path.split(".").last;

    try {
      final ref = FirebaseStorage.instance.ref().child(
          "chat_media/${widget.chatId}/${DateTime.now().millisecondsSinceEpoch}.$extension");

      await ref.putFile(file);
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
      );

      scrollToBottom();
    } catch (e) {
      print("MEDIA ERROR: $e");
    }
  }

  Future<void> sendImage() async {
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    await sendPickedMedia(picked: picked, type: "image");
  }

  Future<void> sendVideo() async {
    final picked = await picker.pickVideo(source: ImageSource.gallery);
    if (picked == null) return;

    await sendPickedMedia(picked: picked, type: "video");
  }

  Future<void> sendLink() async {
    final linkController = TextEditingController();

    final link = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Send link"),
          content: TextField(
            controller: linkController,
            decoration: const InputDecoration(
              labelText: "Link",
              hintText: "https://example.com",
            ),
            keyboardType: TextInputType.url,
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context, linkController.text.trim());
              },
              child: const Text("Send"),
            ),
          ],
        );
      },
    );

    linkController.dispose();

    if (link == null || link.isEmpty) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final normalizedLink =
        link.startsWith("http://") || link.startsWith("https://")
            ? link
            : "https://$link";
    final isWorker = user.uid == workerId;

    await FirebaseFirestore.instance
        .collection("chats")
        .doc(widget.chatId)
        .collection("messages")
        .add({
      "type": "link",
      "url": normalizedLink,
      "text": normalizedLink,
      "senderId": user.uid,
      "createdAt": FieldValue.serverTimestamp(),
      "readBy": [user.uid],
    });

    await updateChatAfterMedia(
      lastMessage: normalizedLink,
      lastMessageType: "link",
      isWorker: isWorker,
    );

    scrollToBottom();
  }

  Future<void> toggleRecording() async {
    if (isRecording) {
      await stopRecordingAndSend();
    } else {
      await startRecording();
    }
  }

  Future<void> startRecording() async {
    final hasPermission = await audioRecorder.hasPermission();
    if (!hasPermission) return;

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
  }

  Future<void> stopRecordingAndSend() async {
    final path = await audioRecorder.stop();

    if (mounted) {
      setState(() {
        isRecording = false;
      });
    }

    if (path == null) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final file = File(path);
    if (!file.existsSync()) return;

    final ref = FirebaseStorage.instance.ref().child(
        "chat_voice/${widget.chatId}/${DateTime.now().millisecondsSinceEpoch}.m4a");

    await ref.putFile(file);
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
    );

    scrollToBottom();
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
                leading: const Icon(Icons.photo),
                title: const Text("Photo"),
                onTap: () {
                  Navigator.pop(context);
                  sendImage();
                },
              ),
              ListTile(
                leading: const Icon(Icons.videocam),
                title: const Text("Video"),
                onTap: () {
                  Navigator.pop(context);
                  sendVideo();
                },
              ),
              ListTile(
                leading: const Icon(Icons.link),
                title: const Text("Link"),
                onTap: () {
                  Navigator.pop(context);
                  sendLink();
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

        final isInternalTeamChat = chatData["type"] == "internal_team";
        final isWorker = uid == chatData["workerId"];
        final otherUserId =
            isWorker ? chatData["employerId"] : chatData["workerId"];

        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection("users")
              .doc(otherUserId)
              .snapshots(),
          builder: (context, userSnapshot) {
            final userData = userSnapshot.data?.data() as Map<String, dynamic>?;

            final name = isInternalTeamChat
                ? (chatData["teamName"] ?? "Team chat")
                : (userData?["name"] ?? "User");
            final isOnline = userData?["isOnline"] ?? false;

            final lastSeenRaw = userData?["lastSeen"];
            final Timestamp? lastSeen =
                lastSeenRaw is Timestamp ? lastSeenRaw : null;

            final typingWorker = chatData["typing_worker"] ?? false;
            final typingEmployer = chatData["typing_employer"] ?? false;
            final isTyping = !isInternalTeamChat &&
                (isWorker ? typingEmployer : typingWorker) &&
                isOnline;

            return Scaffold(
              appBar: AppBar(
                title: Column(
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
                actions: [
                  if (!isInternalTeamChat)
                    IconButton(
                      tooltip: "Call",
                      icon: const Icon(Icons.call),
                      onPressed: () => showCallOptions(context, userData),
                    ),
                ],
              ),
              body: Column(
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

                        final messages = snapshot.data!.docs;
                        preloadImages(messages);

                        return ListView.builder(
                          controller: scrollController,
                          padding: const EdgeInsets.all(10),
                          itemCount: messages.length,
                          itemBuilder: (context, index) {
                            final doc = messages[index];
                            final data = doc.data() as Map<String, dynamic>;

                            final isMe = data["senderId"] == uid;
                            final type = data["type"] ?? "text";

                            final ts = data["createdAt"] as Timestamp?;
                            final date = ts?.toDate();
                            final time = formatTime(ts);

                            bool showDate = index == 0;

                            if (!showDate && index > 0) {
                              final prev = messages[index - 1].data()
                                  as Map<String, dynamic>;
                              final prevDate =
                                  (prev["createdAt"] as Timestamp?)?.toDate();

                              if (date != null && prevDate != null) {
                                showDate = date.day != prevDate.day ||
                                    date.month != prevDate.month ||
                                    date.year != prevDate.year;
                              }
                            }

                            final readBy =
                                List<String>.from(data["readBy"] ?? []);
                            final isRead = readBy.length > 1;

                            if (!readBy.contains(uid)) {
                              FirebaseFirestore.instance
                                  .collection("chats")
                                  .doc(widget.chatId)
                                  .collection("messages")
                                  .doc(doc.id)
                                  .update({
                                "readBy": FieldValue.arrayUnion([uid]),
                              });
                            }

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
                                  child: Container(
                                    margin:
                                        const EdgeInsets.symmetric(vertical: 4),
                                    padding: const EdgeInsets.all(12),
                                    constraints:
                                        const BoxConstraints(maxWidth: 260),
                                    decoration: BoxDecoration(
                                      color: isMe
                                          ? AppColors.surfaceAlt
                                          : Colors.grey.shade200,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        if (type == "text")
                                          Text(data["text"] ?? ""),
                                        if (type == "image" &&
                                            (data["imageUrl"] != null ||
                                                data["mediaUrl"] != null))
                                          GestureDetector(
                                            onTap: () {
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (_) =>
                                                      ImageViewerScreen(
                                                          imageUrl: data[
                                                                  "imageUrl"] ??
                                                              data["mediaUrl"]),
                                                ),
                                              );
                                            },
                                            child: ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                              child: CachedNetworkImage(
                                                imageUrl: data["imageUrl"],
                                                width: 200,
                                                fit: BoxFit.cover,
                                                placeholder: (context, url) =>
                                                    Container(
                                                  width: 200,
                                                  height: 150,
                                                  alignment: Alignment.center,
                                                  child:
                                                      const CircularProgressIndicator(
                                                          strokeWidth: 2),
                                                ),
                                                errorWidget:
                                                    (context, url, error) =>
                                                        Container(
                                                  width: 200,
                                                  height: 150,
                                                  alignment: Alignment.center,
                                                  child: const Icon(
                                                      Icons.broken_image),
                                                ),
                                              ),
                                            ),
                                          ),
                                        if (type == "video" &&
                                            (data["videoUrl"] != null ||
                                                data["mediaUrl"] != null))
                                          VideoMessagePreview(
                                            url: data["videoUrl"] ??
                                                data["mediaUrl"],
                                          ),
                                        if (type == "audio" &&
                                            (data["audioUrl"] != null ||
                                                data["mediaUrl"] != null))
                                          AudioMessageBubble(
                                            url: data["audioUrl"] ??
                                                data["mediaUrl"],
                                          ),
                                        if (type == "link" &&
                                            (data["url"] != null ||
                                                data["text"] != null))
                                          InkWell(
                                            onTap: () async {
                                              final raw =
                                                  data["url"] ?? data["text"];
                                              final uri =
                                                  Uri.tryParse(raw.toString());
                                              if (uri == null) return;
                                              await launchUrl(
                                                uri,
                                                mode: LaunchMode
                                                    .externalApplication,
                                              );
                                            },
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(Icons.link,
                                                    size: 18),
                                                const SizedBox(width: 6),
                                                Flexible(
                                                  child: Text(
                                                    (data["url"] ??
                                                            data["text"])
                                                        .toString(),
                                                    style: const TextStyle(
                                                      decoration: TextDecoration
                                                          .underline,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        const SizedBox(height: 4),
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(time,
                                                style: const TextStyle(
                                                    fontSize: 10)),
                                            const SizedBox(width: 4),
                                            if (isMe)
                                              Icon(Icons.done_all,
                                                  size: 16,
                                                  color: isRead
                                                      ? AppColors.greenDark
                                                      : Colors.grey),
                                          ],
                                        ),
                                      ],
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
                  SafeArea(
                    child: Container(
                      color: AppColors.navy,
                      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                      child: Row(
                        children: [
                          IconButton.filled(
                            style: IconButton.styleFrom(
                              backgroundColor: AppColors.green,
                              foregroundColor: Colors.white,
                            ),
                            icon: const Icon(Icons.add),
                            onPressed: showAttachmentMenu,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: controller,
                              onChanged: handleTypingChanged,
                              decoration: const InputDecoration(
                                hintText: "Type a message",
                                filled: true,
                                fillColor: Colors.white,
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                              ),
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              isRecording ? Icons.stop_circle : Icons.mic,
                              color: isRecording ? Colors.red : Colors.white,
                            ),
                            onPressed: toggleRecording,
                          ),
                          IconButton.filled(
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.white70,
                              foregroundColor: AppColors.navy,
                            ),
                            icon: const Icon(Icons.send),
                            onPressed: sendMessage,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
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
