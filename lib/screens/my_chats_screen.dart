import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'chat_screen.dart';
import '../theme/app_theme.dart';
import '../theme/stroyka_background.dart';

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

  String lastMessagePreview(String type, String text) {
    switch (type) {
      case "image":
        return "Photo";
      case "video":
        return "Video";
      case "audio":
        return "Voice message";
      case "link":
        return text.isEmpty ? "Link" : text;
      default:
        return text.isEmpty ? "Open chat" : text;
    }
  }

  String? avatarFrom(Map<String, dynamic>? data) {
    final value = data?["avatarUrl"] ?? data?["photo"] ?? data?["companyLogo"];
    return value is String && value.isNotEmpty ? value : null;
  }

  Widget chatAvatar({
    required String? avatarUrl,
    required bool isOnline,
    required IconData fallbackIcon,
  }) {
    return Stack(
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
                    errorWidget: (context, url, error) => Icon(fallbackIcon),
                  )
                : Icon(fallbackIcon),
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
    );
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
      body: StroykaScreenBody(
        child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection("chats")
              .where("members", arrayContains: uid)
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
                final isInternalTeamChat = data["type"] == "internal_team";
                final isTeamChat =
                    data["type"] == "team" || data["teamId"] != null;
                final showTeamAvatar =
                    isInternalTeamChat || (isTeamChat && uid == employerId);

                final isWorker = uid == workerId;

                final unread = isWorker
                    ? (data["unreadCount_worker"] ?? 0)
                    : (data["unreadCount_employer"] ?? 0);

                final otherUserId = isTeamChat
                    ? employerId
                    : (isWorker ? employerId : workerId);
                final displayCollection = showTeamAvatar ? "teams" : "users";
                final displayId = showTeamAvatar ? data["teamId"] : otherUserId;

                if (displayId == null) {
                  return const SizedBox();
                }

                final updatedAt = data["updatedAt"] as Timestamp?;

                final typingWorker = data["typing_worker"] ?? false;
                final typingEmployer = data["typing_employer"] ?? false;

                final otherTyping = isWorker ? typingEmployer : typingWorker;

                final lastMessage = data["lastMessage"] ?? "";
                final lastMessageType = data["lastMessageType"] ?? "text";

                return StreamBuilder<DocumentSnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection(displayCollection)
                      .doc(displayId)
                      .snapshots(),
                  builder: (context, displaySnap) {
                    final displayData =
                        displaySnap.data?.data() as Map<String, dynamic>?;

                    final isOnline = showTeamAvatar
                        ? false
                        : displayData?["isOnline"] ?? false;
                    final avatarUrl = avatarFrom(displayData);
                    final chatName = showTeamAvatar
                        ? (displayData?["name"] ?? data["teamName"] ?? "Team")
                        : isWorker
                            ? (displayData?["companyName"] ??
                                displayData?["name"] ??
                                data["employerName"] ??
                                "Employer")
                            : (displayData?["name"] ??
                                data["workerName"] ??
                                "Worker");
                    final isTyping = otherTyping && isOnline;

                    return InkWell(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ChatScreen(chatId: chat.id),
                          ),
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        child: Row(
                          children: [
                            chatAvatar(
                              avatarUrl: avatarUrl,
                              isOnline: isOnline,
                              fallbackIcon:
                                  showTeamAvatar ? Icons.group : Icons.person,
                            ),

                            const SizedBox(width: 12),

                            /// 💬 TEXT
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
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
                                          overflow: TextOverflow.ellipsis,
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
                                      if (!isTyping &&
                                          lastMessageType != "text")
                                        const Padding(
                                          padding: EdgeInsets.only(right: 4),
                                          child: Icon(
                                            Icons.attach_file,
                                            size: 16,
                                            color: Colors.grey,
                                          ),
                                        ),
                                      Expanded(
                                        child: Text(
                                          isTyping
                                              ? "typing..."
                                              : lastMessagePreview(
                                                  lastMessageType,
                                                  lastMessage,
                                                ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
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
                                          padding: const EdgeInsets.all(6),
                                          decoration: const BoxDecoration(
                                            color: AppColors.green,
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
      ),
    );
  }
}
