import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'chat_screen.dart';

class MyChatsScreen extends StatelessWidget {
  const MyChatsScreen({super.key});

  String formatTime(Timestamp? ts) {
    if (ts == null) return "";

    final dt = ts.toDate();
    final now = DateTime.now();

    final diff = now.difference(dt).inDays;

    if (diff == 0) {
      return "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
    }

    if (diff == 1) return "Yesterday";

    return "${dt.day}/${dt.month}";
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Scaffold(
        body: Center(child: Text("Not logged in")),
      );
    }

    final uid = user.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text("My Chats"),
      ),

      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection("chats")
            .where("participants", arrayContains: uid)
            .snapshots(),
        builder: (context, snapshot) {

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text("No chats yet"));
          }

          final chats = snapshot.data!.docs;

          /// 🔥 SORT
          chats.sort((a, b) {
            final aData = a.data() as Map<String, dynamic>;
            final bData = b.data() as Map<String, dynamic>;

            final aTime = aData["updatedAt"] as Timestamp?;
            final bTime = bData["updatedAt"] as Timestamp?;

            if (aTime == null && bTime == null) return 0;
            if (aTime == null) return 1;
            if (bTime == null) return -1;

            return bTime.compareTo(aTime);
          });

          return ListView.builder(
            itemCount: chats.length,
            itemBuilder: (context, index) {

              final chat = chats[index];
              final data = chat.data() as Map<String, dynamic>;

              final workerId = data["workerId"];
              final employerId = data["employerId"];

              final isWorker = uid == workerId;

              final unread = isWorker
                  ? (data["unreadCount_worker"] ?? 0)
                  : (data["unreadCount_employer"] ?? 0);

              final chatName = isWorker
                  ? (data["employerName"] ?? "Employer")
                  : (data["workerName"] ?? "Worker");

              final otherUserId =
                  isWorker ? employerId : workerId;

              final updatedAt = data["updatedAt"] as Timestamp?;

              final typingWorker = data["typing_worker"] ?? false;
              final typingEmployer = data["typing_employer"] ?? false;

              final isTyping =
                  isWorker ? typingEmployer : typingWorker;

              final lastMessage = data["lastMessage"] ?? "";
              final lastMessageType = data["lastMessageType"] ?? "text";

              return StreamBuilder<DocumentSnapshot>(
                stream: FirebaseFirestore.instance
                    .collection("users")
                    .doc(otherUserId)
                    .snapshots(),
                builder: (context, userSnap) {

                  final userData =
                      userSnap.data?.data() as Map<String, dynamic>?;

                  final isOnline = userData?["isOnline"] ?? false;
                  final avatarUrl = userData?["avatarUrl"];

                  return InkWell(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              ChatScreen(chatId: chat.id),
                        ),
                      );
                    },

                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      child: Row(
                        children: [

                          /// 👤 AVATAR (🔥 CACHE)
                          Stack(
                            children: [
                              CircleAvatar(
                                radius: 26,
                                backgroundColor: Colors.grey.shade200,
                                child: ClipOval(
                                  child: avatarUrl != null
                                      ? CachedNetworkImage(
                                          imageUrl: avatarUrl,
                                          width: 52,
                                          height: 52,
                                          fit: BoxFit.cover,

                                          placeholder: (context, url) =>
                                              const CircularProgressIndicator(strokeWidth: 2),

                                          errorWidget: (context, url, error) =>
                                              const Icon(Icons.person),
                                        )
                                      : const Icon(Icons.person),
                                ),
                              ),

                              if (isOnline)
                                Positioned(
                                  right: 0,
                                  bottom: 0,
                                  child: Container(
                                    width: 12,
                                    height: 12,
                                    decoration: const BoxDecoration(
                                      color: Colors.green,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                            ],
                          ),

                          const SizedBox(width: 12),

                          /// 💬 TEXT
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [

                                /// NAME + TIME
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        chatName,
                                        style: TextStyle(
                                          fontWeight: unread > 0
                                              ? FontWeight.bold
                                              : FontWeight.w500,
                                          fontSize: 16,
                                        ),
                                        overflow:
                                            TextOverflow.ellipsis,
                                      ),
                                    ),

                                    Text(
                                      formatTime(updatedAt),
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),

                                const SizedBox(height: 4),

                                /// MESSAGE
                                Row(
                                  children: [

                                    if (!isTyping && lastMessageType == "image")
                                      const Padding(
                                        padding: EdgeInsets.only(right: 4),
                                        child: Icon(
                                          Icons.photo,
                                          size: 16,
                                          color: Colors.grey,
                                        ),
                                      ),

                                    Expanded(
                                      child: Text(
                                        isTyping
                                            ? "typing..."
                                            : (lastMessageType == "image"
                                                ? "Photo"
                                                : (lastMessage.isEmpty
                                                    ? "Open chat"
                                                    : lastMessage)),
                                        maxLines: 1,
                                        overflow:
                                            TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: isTyping
                                              ? Colors.green
                                              : Colors.grey[700],
                                          fontStyle: isTyping
                                              ? FontStyle.italic
                                              : FontStyle.normal,
                                          fontWeight: unread > 0
                                              ? FontWeight.w600
                                              : FontWeight.normal,
                                        ),
                                      ),
                                    ),

                                    if (unread > 0)
                                      Container(
                                        margin:
                                            const EdgeInsets.only(left: 8),
                                        padding:
                                            const EdgeInsets.all(6),
                                        decoration:
                                            const BoxDecoration(
                                          color: Colors.orange,
                                          shape: BoxShape.circle,
                                        ),
                                        child: Text(
                                          unread > 9
                                              ? "9+"
                                              : unread.toString(),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}