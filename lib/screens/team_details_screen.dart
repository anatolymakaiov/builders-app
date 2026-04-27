import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/chat_service.dart';
import '../widgets/phone_link.dart';
import 'chat_screen.dart';
import 'worker_profile_screen.dart';

class TeamDetailsScreen extends StatefulWidget {
  final String teamId;
  final Map<String, dynamic> teamData;

  const TeamDetailsScreen({
    super.key,
    required this.teamId,
    required this.teamData,
  });

  @override
  State<TeamDetailsScreen> createState() => _TeamDetailsScreenState();
}

class _TeamDetailsScreenState extends State<TeamDetailsScreen> {
  final picker = ImagePicker();

  String get currentUserId => FirebaseAuth.instance.currentUser!.uid;

  List<String> memberIdsFrom(dynamic value) {
    if (value is! List) return [];

    return value
        .map((item) {
          if (item is String) return item;
          if (item is Map) return item["userId"]?.toString();
          return null;
        })
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
  }

  bool canEditTeam(Map<String, dynamic> team, List<String> members) {
    return team["ownerId"] == currentUserId || members.contains(currentUserId);
  }

  Future<void> updateTeamDescription(String currentDescription) async {
    final controller = TextEditingController(text: currentDescription);

    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Team description"),
          content: TextField(
            controller: controller,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: "Description",
              hintText: "Team skills, trades, availability, typical projects",
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text("Save"),
            ),
          ],
        );
      },
    );

    controller.dispose();
    if (result == null) return;

    await FirebaseFirestore.instance
        .collection("teams")
        .doc(widget.teamId)
        .set({"description": result}, SetOptions(merge: true));
  }

  Future<void> updateTeamAvatar() async {
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    final ref = FirebaseStorage.instance.ref().child(
        "team_avatars/${widget.teamId}_${DateTime.now().millisecondsSinceEpoch}.jpg");

    await ref.putFile(File(picked.path));
    final url = await ref.getDownloadURL();

    await FirebaseFirestore.instance
        .collection("teams")
        .doc(widget.teamId)
        .set({
      "avatarUrl": url,
      "photo": url,
    }, SetOptions(merge: true));
  }

  Future<void> addTeamPortfolioImage() async {
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    final ref = FirebaseStorage.instance.ref().child(
        "team_portfolio/${widget.teamId}/${DateTime.now().millisecondsSinceEpoch}.jpg");

    await ref.putFile(File(picked.path));
    final url = await ref.getDownloadURL();

    await FirebaseFirestore.instance
        .collection("teams")
        .doc(widget.teamId)
        .collection("portfolio")
        .add({
      "image": url,
      "imageUrl": url,
      "createdAt": FieldValue.serverTimestamp(),
    });
  }

  Future<Map<String, dynamic>?> findWorker(String query) async {
    final text = query.trim();
    if (text.isEmpty) return null;

    Future<Map<String, dynamic>?> byField(String field) async {
      final snap = await FirebaseFirestore.instance
          .collection("users")
          .where(field, isEqualTo: text)
          .limit(1)
          .get();

      if (snap.docs.isEmpty) return null;
      return {
        "id": snap.docs.first.id,
        "data": snap.docs.first.data(),
      };
    }

    return await byField("phone") ??
        await byField("nickname") ??
        await byField("nickName") ??
        await byField("username");
  }

  Future<void> addMember(List<String> currentMembers) async {
    final controller = TextEditingController();

    final query = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Add team member"),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: "Nickname or phone",
              hintText: "Worker nickname or phone number",
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text("Add"),
            ),
          ],
        );
      },
    );

    controller.dispose();
    if (query == null || query.isEmpty) return;

    final worker = await findWorker(query);
    if (!mounted) return;

    if (worker == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Worker not found")),
      );
      return;
    }

    final workerId = worker["id"] as String;
    final workerData = worker["data"] as Map<String, dynamic>;
    if (workerData["role"] != "worker") {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Only workers can be added")),
      );
      return;
    }

    if (currentMembers.contains(workerId)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Worker is already in this team")),
      );
      return;
    }

    await FirebaseFirestore.instance
        .collection("teams")
        .doc(widget.teamId)
        .set({
      "members": [...currentMembers, workerId],
      "memberStatuses.$workerId": "active",
      "updatedAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> removeMember(String userId) async {
    final teamRef =
        FirebaseFirestore.instance.collection("teams").doc(widget.teamId);
    final snap = await teamRef.get();
    final data = snap.data();
    final members = memberIdsFrom(data?["members"])
      ..removeWhere((memberId) => memberId == userId);

    await teamRef.set({
      "members": members,
      "updatedAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> openInternalChat(
    String teamName,
    List<String> members,
  ) async {
    final chatId = await ChatService.getOrCreateInternalTeamChat(
      teamId: widget.teamId,
      teamName: teamName,
      members: members,
    );

    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(chatId: chatId),
      ),
    );
  }

  Widget buildTeamPortfolio(bool canEdit) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection("teams")
          .doc(widget.teamId)
          .collection("portfolio")
          .orderBy("createdAt", descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        final photos = snapshot.data?.docs ?? [];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    "Team portfolio",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                if (canEdit)
                  IconButton(
                    tooltip: "Add photo",
                    icon: const Icon(Icons.add_a_photo),
                    onPressed: addTeamPortfolioImage,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (!snapshot.hasData)
              const LinearProgressIndicator()
            else if (photos.isEmpty)
              const Text("No team portfolio yet")
            else
              SizedBox(
                height: 110,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: photos.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    final data = photos[index].data() as Map<String, dynamic>;
                    final image = data["imageUrl"] ?? data["image"];
                    if (image == null) return const SizedBox();

                    return GestureDetector(
                      onTap: () {
                        showDialog(
                          context: context,
                          builder: (_) => Dialog(
                            child: Image.network(
                              image.toString(),
                              fit: BoxFit.contain,
                            ),
                          ),
                        );
                      },
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.network(
                          image.toString(),
                          width: 110,
                          height: 110,
                          fit: BoxFit.cover,
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }

  Widget buildMemberCard(
    BuildContext context,
    String memberId,
    bool canRemove,
  ) {
    return FutureBuilder<DocumentSnapshot>(
      future:
          FirebaseFirestore.instance.collection("users").doc(memberId).get(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const ListTile(title: Text("Loading..."));
        }

        final user = snapshot.data!.data() as Map<String, dynamic>?;
        final userName = user?["name"] ?? "User";
        final trade = user?["trade"] ?? "";
        final photo = user?["photo"];
        final phone = user?["phone"]?.toString();

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 6,
                offset: const Offset(0, 2),
              )
            ],
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundImage: photo != null ? NetworkImage(photo) : null,
              child: photo == null ? const Icon(Icons.person) : null,
            ),
            title: Text(userName),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (trade.toString().isNotEmpty) Text(trade.toString()),
                if (phone != null && phone.isNotEmpty)
                  PhoneLink(
                    phone: phone,
                    compact: true,
                  ),
              ],
            ),
            trailing: canRemove
                ? IconButton(
                    tooltip: "Remove member",
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => removeMember(memberId),
                  )
                : null,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => WorkerProfileScreen(userId: memberId),
                ),
              );
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection("teams")
          .doc(widget.teamId)
          .snapshots(),
      builder: (context, snapshot) {
        final liveData = snapshot.data?.data() as Map<String, dynamic>?;
        final team = liveData ?? widget.teamData;
        final members = memberIdsFrom(team["members"]);
        final name = team["name"]?.toString() ?? "Team";
        final description =
            (team["description"] ?? team["bio"])?.toString().trim() ?? "";
        final avatar = team["avatarUrl"] ?? team["photo"] ?? team["logo"];
        final canEdit = canEditTeam(team, members);
        final canRemove = team["ownerId"] == currentUserId;

        return Scaffold(
          appBar: AppBar(
            title: const Text("Team"),
            actions: [
              if (canEdit)
                IconButton(
                  tooltip: "Add member",
                  icon: const Icon(Icons.person_add_alt),
                  onPressed: () => addMember(members),
                ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Center(
                child: Column(
                  children: [
                    GestureDetector(
                      onTap: canEdit ? updateTeamAvatar : null,
                      child: CircleAvatar(
                        radius: 46,
                        backgroundColor: Colors.grey.shade300,
                        backgroundImage: avatar == null
                            ? null
                            : NetworkImage(avatar.toString()),
                        child: avatar == null
                            ? const Icon(Icons.groups, size: 40)
                            : null,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "${members.length} members",
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: members.isEmpty
                      ? null
                      : () => openInternalChat(name, members),
                  icon: const Icon(Icons.forum),
                  label: const Text("Team chat"),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      "Team description",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  if (canEdit)
                    IconButton(
                      tooltip: "Edit description",
                      icon: const Icon(Icons.edit),
                      onPressed: () => updateTeamDescription(description),
                    ),
                ],
              ),
              if (description.isEmpty)
                const Text("No team description yet")
              else
                Text(description),
              const SizedBox(height: 24),
              buildTeamPortfolio(canEdit),
              const SizedBox(height: 24),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      "Team members",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  if (canEdit)
                    TextButton.icon(
                      onPressed: () => addMember(members),
                      icon: const Icon(Icons.person_add_alt),
                      label: const Text("Add"),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              if (members.isEmpty)
                const Text("No members yet")
              else
                ...members.map((memberId) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: buildMemberCard(
                      context,
                      memberId,
                      canRemove && memberId != currentUserId,
                    ),
                  );
                }),
            ],
          ),
        );
      },
    );
  }
}
