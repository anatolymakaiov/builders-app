import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:io';
import 'image_viewer_screen.dart';

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

  String? workerId;
  String? employerId;
  bool _preloaded = false;

  @override
  void initState() {
    super.initState();
    initChat();
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

  /// 📷 IMAGE
  Future<void> sendImage() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    final file = File(picked.path);

    try {
      final ref = FirebaseStorage.instance.ref().child(
          "chat_images/${widget.chatId}/${DateTime.now().millisecondsSinceEpoch}");

      await ref.putFile(file);
      final url = await ref.getDownloadURL();

      final isWorker = user.uid == workerId;

      await FirebaseFirestore.instance
          .collection("chats")
          .doc(widget.chatId)
          .collection("messages")
          .add({
        "type": "image",
        "imageUrl": url,
        "senderId": user.uid,
        "createdAt": FieldValue.serverTimestamp(),
        "readBy": [user.uid],
      });

      await FirebaseFirestore.instance
          .collection("chats")
          .doc(widget.chatId)
          .update({
        "lastMessage": "📷 Photo",
        "lastMessageType": "image",
        "updatedAt": FieldValue.serverTimestamp(),
        if (isWorker)
          "unreadCount_employer": FieldValue.increment(1)
        else
          "unreadCount_worker": FieldValue.increment(1),
      });

      scrollToBottom();
    } catch (e) {
      print("IMAGE ERROR: $e");
    }
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

    final isWorker = user.uid == workerId;

    await FirebaseFirestore.instance
        .collection("chats")
        .doc(widget.chatId)
        .update({
      if (isWorker) "typing_worker": isTyping else "typing_employer": isTyping,
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

            final name = userData?["name"] ?? "User";
            final isOnline = userData?["isOnline"] ?? false;

            final lastSeenRaw = userData?["lastSeen"];
            final Timestamp? lastSeen =
                lastSeenRaw is Timestamp ? lastSeenRaw : null;

            final typingWorker = chatData["typing_worker"] ?? false;
            final typingEmployer = chatData["typing_employer"] ?? false;
            final isTyping = isWorker ? typingEmployer : typingWorker;

            return Scaffold(
              appBar: AppBar(
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name),
                    Text(
                      isOnline ? "Online" : formatLastSeen(lastSeen),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
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
                                          ? Colors.orange
                                          : Colors.grey.shade300,
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        if (type == "text")
                                          Text(data["text"] ?? ""),
                                        if (type == "image" &&
                                            data["imageUrl"] != null)
                                          GestureDetector(
                                            onTap: () {
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (_) =>
                                                      ImageViewerScreen(
                                                          imageUrl:
                                                              data["imageUrl"]),
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
                                                      ? Colors.blue
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
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.image),
                          onPressed: sendImage,
                        ),
                        Expanded(
                          child: TextField(
                            controller: controller,
                            onChanged: (v) => updateTyping(v.isNotEmpty),
                            decoration: const InputDecoration(
                              hintText: "Message...",
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.send),
                          onPressed: sendMessage,
                        ),
                      ],
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
