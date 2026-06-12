import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import 'chat_screen.dart';
import '../services/chat_profile_navigation_service.dart';
import '../services/chat_service.dart';
import '../theme/app_theme.dart';
import '../theme/stroyka_background.dart';

class MyChatsScreen extends StatefulWidget {
  const MyChatsScreen({super.key});

  @override
  State<MyChatsScreen> createState() => _MyChatsScreenState();
}

class _MyChatsScreenState extends State<MyChatsScreen> {
  final searchController = TextEditingController();
  Timer? searchDebounce;
  bool searchOpen = false;
  bool searching = false;
  List<_ChatSearchResult> searchResults = [];

  @override
  void dispose() {
    searchDebounce?.cancel();
    searchController.dispose();
    super.dispose();
  }

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

  bool chatBelongsToUser(Map<String, dynamic> data, String uid) {
    final hiddenForUsers = data["hiddenForUsers"];
    if (hiddenForUsers is List && hiddenForUsers.contains(uid)) {
      return false;
    }

    bool containsId(dynamic value) {
      return value is List &&
          value.map((item) => item.toString()).contains(uid);
    }

    return data["workerId"]?.toString() == uid ||
        data["employerId"]?.toString() == uid ||
        containsId(data["participants"]) ||
        containsId(data["members"]);
  }

  String? otherParticipantId(Map<String, dynamic> data, String uid) {
    final targetProfileId = data["targetProfileId"]?.toString();
    if (targetProfileId != null &&
        targetProfileId.isNotEmpty &&
        targetProfileId != uid) {
      return targetProfileId;
    }

    for (final key in const ["participantIds", "participants", "members"]) {
      for (final id in idsFrom(data[key])) {
        if (id != uid) return id;
      }
    }

    return null;
  }

  Widget chatAvatar({
    required String? avatarUrl,
    required bool isOnline,
    required IconData fallbackIcon,
  }) {
    final fallback = Icon(
      fallbackIcon,
      color: AppColors.greenDark,
      size: 28,
    );

    return Stack(
      children: [
        CircleAvatar(
          radius: 26,
          backgroundColor: AppColors.surfaceAlt,
          child: ClipOval(
            child: avatarUrl != null
                ? Image.network(
                    avatarUrl,
                    width: 52,
                    height: 52,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return fallback;
                    },
                    errorBuilder: (context, error, stackTrace) => fallback,
                  )
                : fallback,
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

  Future<bool> confirmDeleteItem(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Delete item"),
        content: const Text("Are you sure you want to delete this item?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text("Delete"),
          ),
        ],
      ),
    );
    return result == true;
  }

  Widget deleteBackground() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: AppColors.danger,
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.centerRight,
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Icon(Icons.delete_outline, color: Colors.white),
          SizedBox(width: 8),
          Text(
            "Delete",
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Future<bool> hideChatForCurrentUser(
    BuildContext context,
    QueryDocumentSnapshot chat,
    String uid,
  ) async {
    final confirmed = await confirmDeleteItem(context);
    if (!confirmed) return false;
    await chat.reference.set({
      "hiddenForUsers": FieldValue.arrayUnion([uid]),
      "unreadFor": FieldValue.arrayRemove([uid]),
      "deletedAtForUser.$uid": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return true;
  }

  void toggleSearch() {
    setState(() {
      searchOpen = !searchOpen;
      if (!searchOpen) {
        searchController.clear();
        searchResults = [];
        searching = false;
      }
    });
  }

  void onSearchChanged(String value, String uid) {
    searchDebounce?.cancel();
    searchDebounce = Timer(const Duration(milliseconds: 350), () {
      runSearch(value, uid);
    });
  }

  Future<void> runSearch(String value, String uid) async {
    final query = value.trim();
    if (query.isEmpty) {
      if (!mounted) return;
      setState(() {
        searchResults = [];
        searching = false;
      });
      return;
    }

    setState(() => searching = true);

    try {
      final currentUserSnap =
          await FirebaseFirestore.instance.collection("users").doc(uid).get();
      final currentRole =
          currentUserSnap.data()?["role"]?.toString().toLowerCase() ?? "";

      final users = await searchUsers(query, uid);
      final teams = await searchTeams(query, uid, currentRole);
      final combined = [...users, ...teams].take(25).toList();

      final enriched = <_ChatSearchResult>[];
      for (final result in combined) {
        final existingChatId = await findExistingChat(
          uid: uid,
          result: result,
        );
        enriched.add(result.copyWith(existingChatId: existingChatId));
      }

      if (!mounted) return;
      setState(() {
        searchResults = enriched;
        searching = false;
      });
    } catch (error) {
      debugPrint("CHAT SEARCH ERROR: $error");
      if (!mounted) return;
      setState(() => searching = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not search chats.")),
      );
    }
  }

  Future<List<_ChatSearchResult>> searchUsers(String query, String uid) async {
    final normalizedQuery = normalizeSearch(query);
    final phoneQuery = normalizePhoneForSearch(query);
    final snap =
        await FirebaseFirestore.instance.collection("users").limit(250).get();

    final results = <_ChatSearchResult>[];
    for (final doc in snap.docs) {
      if (doc.id == uid) continue;
      final data = doc.data();
      if (isInactive(data)) continue;

      final role = data["role"]?.toString().toLowerCase() ?? "worker";
      if (role == "admin") continue;

      final firstName = text(data["firstName"]);
      final lastName = text(data["lastName"]);
      final displayName = text(data["displayName"]);
      final name = role == "employer"
          ? firstNonEmpty([
              data["companyName"],
              data["name"],
              displayName,
              "$firstName $lastName",
            ], fallback: "Company")
          : firstNonEmpty([
              data["name"],
              displayName,
              "$firstName $lastName",
              data["nickname"],
            ], fallback: "Worker");
      final phone = firstNonEmpty([data["phone"], data["billingPhone"]]);
      final normalizedPhone = firstNonEmpty([
        data["normalizedPhone"],
        normalizePhoneForSearch(phone),
      ]);
      final haystack = normalizeSearch([
        doc.id,
        firstName,
        lastName,
        displayName,
        data["nickname"],
        data["companyName"],
        data["name"],
        phone,
        normalizedPhone,
      ].whereType<Object>().join(" "));
      final phoneMatches = phoneQuery.isNotEmpty &&
          normalizePhoneForSearch(haystack).contains(phoneQuery);

      if (!haystack.contains(normalizedQuery) && !phoneMatches) continue;

      results.add(
        _ChatSearchResult(
          id: doc.id,
          type: role == "employer" ? "Employer" : "Worker",
          role: role,
          name: name,
          phone: phone,
          avatarUrl: firstNonEmpty([
            data["avatarUrl"],
            data["profilePhotoUrl"],
            data["photo"],
            data["companyLogo"],
          ]),
        ),
      );
    }

    return results;
  }

  Future<List<_ChatSearchResult>> searchTeams(
    String query,
    String uid,
    String currentRole,
  ) async {
    final normalizedQuery = normalizeSearch(query);
    final snap =
        await FirebaseFirestore.instance.collection("teams").limit(150).get();

    final results = <_ChatSearchResult>[];
    for (final doc in snap.docs) {
      final data = doc.data();
      if (isInactive(data)) continue;
      final members = idsFrom(data["members"]);
      if (currentRole == "worker" && !members.contains(uid)) continue;

      final name =
          firstNonEmpty([data["name"], data["teamName"]], fallback: "Team");
      final haystack = normalizeSearch([
        doc.id,
        name,
        data["description"],
        data["trade"],
      ].whereType<Object>().join(" "));

      if (!haystack.contains(normalizedQuery)) continue;

      results.add(
        _ChatSearchResult(
          id: doc.id,
          type: "Team",
          role: "team",
          name: name,
          avatarUrl: firstNonEmpty([
            data["avatarUrl"],
            data["photo"],
            data["teamLogo"],
          ]),
          memberIds: members,
        ),
      );
    }

    return results;
  }

  Future<String?> findExistingChat({
    required String uid,
    required _ChatSearchResult result,
  }) async {
    final snap = await FirebaseFirestore.instance
        .collection("chats")
        .where("participants", arrayContains: uid)
        .limit(100)
        .get();

    for (final doc in snap.docs) {
      final data = doc.data();
      if (result.role == "team") {
        if (data["teamId"]?.toString() == result.id) return doc.id;
        continue;
      }

      final participants =
          idsFrom(data["participants"]) + idsFrom(data["members"]);
      if (participants.contains(result.id) ||
          data["workerId"]?.toString() == result.id ||
          data["employerId"]?.toString() == result.id) {
        return doc.id;
      }
    }

    return null;
  }

  Future<void> openOrStartChat(_ChatSearchResult result, String uid) async {
    try {
      final currentUserSnap =
          await FirebaseFirestore.instance.collection("users").doc(uid).get();
      final currentRole =
          currentUserSnap.data()?["role"]?.toString().toLowerCase() ?? "worker";

      final existingChatId = result.existingChatId ??
          await findExistingChat(
            uid: uid,
            result: result,
          );

      final chatId = existingChatId ??
          await createSearchChat(
            uid: uid,
            currentRole: currentRole,
            result: result,
          );

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ChatScreen(chatId: chatId)),
      );
    } catch (error) {
      debugPrint("CHAT SEARCH OPEN ERROR: $error");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not open chat.")),
      );
    }
  }

  Future<String> createSearchChat({
    required String uid,
    required String currentRole,
    required _ChatSearchResult result,
  }) async {
    if (result.role == "team") {
      if (currentRole == "employer") {
        return ChatService.getOrCreateTeamChat(
          teamId: result.id,
          employerId: uid,
          jobId: "",
          members: result.memberIds,
        );
      }
      return ChatService.getOrCreateInternalTeamChat(
        teamId: result.id,
        teamName: result.name,
        members: result.memberIds.contains(uid) ? result.memberIds : [uid],
      );
    }

    final isCurrentEmployer = currentRole == "employer";
    return ChatService.getOrCreateChat(
      workerId: isCurrentEmployer ? result.id : uid,
      employerId: isCurrentEmployer ? uid : result.id,
      jobId: "",
      jobTitle: "General",
    );
  }

  Widget buildSearchPanel(String uid) {
    final hasQuery = searchController.text.trim().isNotEmpty;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: TextField(
            controller: searchController,
            autofocus: true,
            onChanged: (value) => onSearchChanged(value, uid),
            decoration: InputDecoration(
              hintText: "Search users or teams",
              prefixIcon: const Icon(Icons.search),
              suffixIcon: hasQuery
                  ? IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        searchController.clear();
                        runSearch("", uid);
                      },
                    )
                  : null,
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.92),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
        if (searching)
          const Padding(
            padding: EdgeInsets.all(18),
            child: CircularProgressIndicator(),
          )
        else if (hasQuery && searchResults.isEmpty)
          const Padding(
            padding: EdgeInsets.all(18),
            child: Text("No users found."),
          )
        else if (hasQuery)
          Expanded(
            child: ListView.builder(
              itemCount: searchResults.length,
              itemBuilder: (context, index) {
                final result = searchResults[index];
                return StroykaSurface(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      chatAvatar(
                        avatarUrl: result.avatarUrl,
                        isOnline: false,
                        fallbackIcon:
                            result.role == "team" ? Icons.group : Icons.person,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              result.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                              ),
                            ),
                            Text(result.type),
                            if (result.phone.isNotEmpty)
                              Text(
                                result.phone,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.grey),
                              ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () => openOrStartChat(result, uid),
                        child: Text(
                          result.existingChatId == null
                              ? "Start chat"
                              : "Open chat",
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Future<void> openChatProfile(
    BuildContext context,
    Map<String, dynamic> data,
    String uid, {
    required bool preferTeamTarget,
  }) {
    return ChatProfileNavigationService.openFromChat(
      context,
      chatData: data,
      currentUserId: uid,
      preferTeamTarget: preferTeamTarget,
    );
  }

  bool isInactive(Map<String, dynamic> data) {
    final status = text(data["status"]).toLowerCase();
    final active = data["active"];
    return data["deleted"] == true ||
        data["accountDeleted"] == true ||
        data["anonymised"] == true ||
        data["companyDeleted"] == true ||
        status == "deleted" ||
        status == "inactive" ||
        active == false;
  }

  List<String> idsFrom(dynamic value) {
    if (value is! List) return const [];
    return value
        .map((item) => item.toString())
        .where((id) => id.isNotEmpty)
        .toList();
  }

  String normalizeSearch(String value) => value.toLowerCase().trim();

  String normalizePhoneForSearch(String value) {
    final digits = value.replaceAll(RegExp(r"[^0-9+]"), "");
    if (digits.startsWith("+44")) return "0${digits.substring(3)}";
    if (digits.startsWith("44") && digits.length > 10) {
      return "0${digits.substring(2)}";
    }
    return digits;
  }

  String text(dynamic value) => value?.toString().trim() ?? "";

  String firstNonEmpty(List<dynamic> values, {String fallback = ""}) {
    for (final value in values) {
      final str = value?.toString().trim() ?? "";
      if (str.isNotEmpty) return str;
    }
    return fallback;
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
        actions: [
          IconButton(
            tooltip: searchOpen ? "Close search" : "Search chats",
            icon: Icon(searchOpen ? Icons.close : Icons.search),
            onPressed: toggleSearch,
          ),
        ],
      ),
      body: StroykaScreenBody(
        child: Column(
          children: [
            if (searchOpen) Expanded(child: buildSearchPanel(uid)),
            if (!searchOpen)
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection("chats")
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                      return const Center(child: Text("No chats yet"));
                    }

                    final chats = snapshot.data!.docs.where((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      return chatBelongsToUser(data, uid);
                    }).toList();

                    if (chats.isEmpty) {
                      return const Center(child: Text("No chats yet"));
                    }

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
                        final isInternalTeamChat =
                            data["type"] == "internal_team";
                        final isTeamChat =
                            data["type"] == "team" || data["teamId"] != null;
                        final showTeamAvatar = isInternalTeamChat ||
                            (isTeamChat && uid == employerId);

                        final isWorker = uid == workerId;

                        final unreadFor =
                            List<String>.from(data["unreadFor"] ?? []);
                        final unread = unreadFor.contains(uid) ? 1 : 0;

                        final otherUserId = isTeamChat
                            ? employerId
                            : (isWorker
                                ? employerId
                                : workerId ?? otherParticipantId(data, uid));
                        final displayCollection =
                            showTeamAvatar ? "teams" : "users";
                        final displayId =
                            showTeamAvatar ? data["teamId"] : otherUserId;

                        if (displayId == null) {
                          return const SizedBox();
                        }

                        final updatedAt = data["updatedAt"] as Timestamp?;
                        final jobId = data["jobId"]?.toString();

                        final typingWorker = data["typing_worker"] ?? false;
                        final typingEmployer = data["typing_employer"] ?? false;

                        final otherTyping =
                            isWorker ? typingEmployer : typingWorker;

                        final lastMessage = data["lastMessage"] ?? "";
                        final lastMessageType =
                            data["lastMessageType"] ?? "text";

                        return StreamBuilder<DocumentSnapshot>(
                          stream: FirebaseFirestore.instance
                              .collection(displayCollection)
                              .doc(displayId)
                              .snapshots(),
                          builder: (context, displaySnap) {
                            final displayData = displaySnap.data?.data()
                                as Map<String, dynamic>?;

                            final isOnline = showTeamAvatar
                                ? false
                                : displayData?["isOnline"] ?? false;
                            final avatarUrl = avatarFrom(displayData);
                            final isTyping = otherTyping && isOnline;

                            return StreamBuilder<DocumentSnapshot>(
                              stream: jobId == null || jobId.isEmpty
                                  ? null
                                  : FirebaseFirestore.instance
                                      .collection("jobs")
                                      .doc(jobId)
                                      .snapshots(),
                              builder: (context, jobSnap) {
                                final jobData = jobSnap.data?.data()
                                    as Map<String, dynamic>?;
                                final isGenericDirectChat = !isTeamChat &&
                                    data["workerId"] == null &&
                                    data["employerId"] == null;
                                final chatName = isGenericDirectChat
                                    ? "${ChatService.firstText(
                                        displayData,
                                        ["companyName", "name", "displayName"],
                                        fallback: "User",
                                      )}_${ChatService.jobTitle(data, jobData)}"
                                    : ChatService.chatDisplayName(
                                        chatData: data,
                                        participantData: displayData,
                                        jobData: jobData,
                                        currentUserIsWorker: isWorker,
                                        isInternalTeamChat: isInternalTeamChat,
                                        showTeamAvatar: showTeamAvatar,
                                      );

                                return Dismissible(
                                  key: ValueKey("chat-${chat.id}"),
                                  direction: DismissDirection.endToStart,
                                  background: deleteBackground(),
                                  confirmDismiss: (_) => hideChatForCurrentUser(
                                    context,
                                    chat,
                                    uid,
                                  ),
                                  child: StroykaSurface(
                                    margin: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 8),
                                    padding: EdgeInsets.zero,
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(14),
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
                                            horizontal: 12, vertical: 12),
                                        child: Row(
                                          children: [
                                            GestureDetector(
                                              onTap: () => openChatProfile(
                                                context,
                                                data,
                                                uid,
                                                preferTeamTarget:
                                                    showTeamAvatar,
                                              ),
                                              child: chatAvatar(
                                                avatarUrl: avatarUrl,
                                                isOnline: isOnline,
                                                fallbackIcon: showTeamAvatar
                                                    ? Icons.group
                                                    : Icons.person,
                                              ),
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
                                                        MainAxisAlignment
                                                            .spaceBetween,
                                                    children: [
                                                      Expanded(
                                                        child: InkWell(
                                                          onTap: () =>
                                                              openChatProfile(
                                                            context,
                                                            data,
                                                            uid,
                                                            preferTeamTarget:
                                                                showTeamAvatar,
                                                          ),
                                                          child: Text(
                                                            chatName,
                                                            style: TextStyle(
                                                              fontWeight: unread >
                                                                      0
                                                                  ? FontWeight
                                                                      .bold
                                                                  : FontWeight
                                                                      .w500,
                                                              fontSize: 16,
                                                            ),
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                          ),
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
                                                          lastMessageType !=
                                                              "text")
                                                        const Padding(
                                                          padding:
                                                              EdgeInsets.only(
                                                                  right: 4),
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
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style: TextStyle(
                                                            fontSize: 14,
                                                            color: isTyping
                                                                ? Colors.green
                                                                : Colors
                                                                    .grey[700],
                                                            fontStyle: isTyping
                                                                ? FontStyle
                                                                    .italic
                                                                : FontStyle
                                                                    .normal,
                                                            fontWeight:
                                                                unread > 0
                                                                    ? FontWeight
                                                                        .w600
                                                                    : FontWeight
                                                                        .normal,
                                                          ),
                                                        ),
                                                      ),
                                                      if (unread > 0)
                                                        Container(
                                                          margin:
                                                              const EdgeInsets
                                                                  .only(
                                                                  left: 8),
                                                          padding:
                                                              const EdgeInsets
                                                                  .all(6),
                                                          decoration:
                                                              const BoxDecoration(
                                                            color:
                                                                AppColors.green,
                                                            shape:
                                                                BoxShape.circle,
                                                          ),
                                                          child: Text(
                                                            unread > 9
                                                                ? "9+"
                                                                : unread
                                                                    .toString(),
                                                            style:
                                                                const TextStyle(
                                                              color:
                                                                  Colors.white,
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
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        );
                      },
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ChatSearchResult {
  final String id;
  final String type;
  final String role;
  final String name;
  final String phone;
  final String? avatarUrl;
  final List<String> memberIds;
  final String? existingChatId;

  const _ChatSearchResult({
    required this.id,
    required this.type,
    required this.role,
    required this.name,
    this.phone = "",
    this.avatarUrl,
    this.memberIds = const [],
    this.existingChatId,
  });

  _ChatSearchResult copyWith({String? existingChatId}) {
    return _ChatSearchResult(
      id: id,
      type: type,
      role: role,
      name: name,
      phone: phone,
      avatarUrl: avatarUrl,
      memberIds: memberIds,
      existingChatId: existingChatId ?? this.existingChatId,
    );
  }
}
