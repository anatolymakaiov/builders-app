import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/chat_service.dart';
import '../services/profile_communication_service.dart';
import '../widgets/app_photo_grid_gallery.dart';
import '../widgets/phone_link.dart';
import '../theme/app_theme.dart';
import '../theme/stroyka_background.dart';
import 'chat_screen.dart';
import 'worker_profile_screen.dart';

class TeamDetailsScreen extends StatefulWidget {
  final String teamId;
  final Map<String, dynamic> teamData;
  final bool showInternalChat;

  const TeamDetailsScreen({
    super.key,
    required this.teamId,
    required this.teamData,
    this.showInternalChat = true,
  });

  @override
  State<TeamDetailsScreen> createState() => _TeamDetailsScreenState();
}

class _TeamDetailsScreenState extends State<TeamDetailsScreen> {
  final picker = ImagePicker();
  bool uploadingTeamPortfolio = false;
  bool addingMember = false;
  bool deletingTeam = false;
  bool teamDeletedLocally = false;
  String viewerRole = "worker";

  String? get currentUserId => FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    loadViewerRole();
  }

  Future<void> loadViewerRole() async {
    final uid = currentUserId;
    if (uid == null || uid.isEmpty) return;

    final snap =
        await FirebaseFirestore.instance.collection("users").doc(uid).get();
    if (!mounted) return;
    setState(() {
      viewerRole = snap.data()?["role"]?.toString().toLowerCase() ?? "worker";
    });
  }

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
    return isTeamLeader(team);
  }

  bool isTeamLeader(Map<String, dynamic> team) {
    final uid = currentUserId;
    if (uid == null || uid.isEmpty) return false;
    return team["ownerId"] == uid || team["createdBy"] == uid;
  }

  bool isTeamMember(List<String> members) {
    final uid = currentUserId;
    if (uid == null || uid.isEmpty) return false;
    return members.contains(uid);
  }

  Future<bool> confirmAction({
    required String title,
    required String message,
    required String confirmText,
    bool destructive = true,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: destructive
                ? ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  )
                : null,
            onPressed: () => Navigator.pop(context, true),
            child: Text(confirmText),
          ),
        ],
      ),
    );

    return result == true;
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
              border: StroykaInputBorder(),
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
    if (!mounted) return;

    final cropped = await showDialog<File>(
      context: context,
      barrierDismissible: false,
      builder: (_) => TeamAvatarCropDialog(imageFile: File(picked.path)),
    );
    if (cropped == null) return;

    final ref = FirebaseStorage.instance.ref().child(
        "team_avatars/${widget.teamId}_${DateTime.now().millisecondsSinceEpoch}.png");

    await ref.putFile(
      cropped,
      SettableMetadata(contentType: "image/png"),
    );
    final url = await ref.getDownloadURL();

    await FirebaseFirestore.instance
        .collection("teams")
        .doc(widget.teamId)
        .set({
      "avatarUrl": url,
      "photo": url,
    }, SetOptions(merge: true));
  }

  Future<void> updateTeamBackground() async {
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    final ref = FirebaseStorage.instance.ref().child(
        "team_headers/${widget.teamId}_${DateTime.now().millisecondsSinceEpoch}_${picked.name}");

    await ref.putFile(File(picked.path));
    final url = await ref.getDownloadURL();

    await FirebaseFirestore.instance
        .collection("teams")
        .doc(widget.teamId)
        .set({
      "headerImageUrl": url,
      "profileHeaderImage": url,
      "headerImage": url,
    }, SetOptions(merge: true));
  }

  Future<void> addTeamPortfolioImages() async {
    if (uploadingTeamPortfolio) return;

    try {
      final picked = await picker.pickMultiImage();
      if (picked.isEmpty) return;

      setState(() => uploadingTeamPortfolio = true);

      final batch = FirebaseFirestore.instance.batch();
      final portfolioRef = FirebaseFirestore.instance
          .collection("teams")
          .doc(widget.teamId)
          .collection("portfolio");

      for (final image in picked) {
        final ref = FirebaseStorage.instance.ref().child(
            "team_portfolio/${widget.teamId}/${DateTime.now().millisecondsSinceEpoch}_${image.name}");

        await ref.putFile(File(image.path));
        final url = await ref.getDownloadURL();
        batch.set(portfolioRef.doc(), {
          "image": url,
          "imageUrl": url,
          "createdAt": FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();
    } catch (e) {
      debugPrint("TEAM PORTFOLIO UPLOAD ERROR: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not upload team photos")),
      );
    } finally {
      if (mounted) setState(() => uploadingTeamPortfolio = false);
    }
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
    if (addingMember) return;
    if (!mounted) return;

    final query = await showDialog<String?>(
      context: context,
      builder: (_) => const _AddTeamMemberDialog(),
    );

    final searchText = query?.trim() ?? "";
    if (!mounted || searchText.isEmpty) return;

    setState(() => addingMember = true);

    try {
      final worker = await findWorker(searchText);
      if (!mounted) return;

      if (worker == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Worker not found")),
        );
        return;
      }

      final workerId = worker["id"]?.toString() ?? "";
      final workerData = worker["data"] as Map<String, dynamic>? ?? {};
      if (workerId.isEmpty || workerData["role"] != "worker") {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Only workers can be added")),
        );
        return;
      }

      final teamRef =
          FirebaseFirestore.instance.collection("teams").doc(widget.teamId);
      final teamSnap = await teamRef.get();
      if (!mounted) return;

      final latestMembers = teamSnap.exists
          ? memberIdsFrom(teamSnap.data()?["members"])
          : currentMembers;

      if (latestMembers.contains(workerId)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Worker is already in this team")),
        );
        return;
      }

      await teamRef.set({
        "members": [...latestMembers, workerId],
        "memberStatuses.$workerId": "active",
        "updatedAt": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint("ADD TEAM MEMBER ERROR: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not add team member")),
      );
    } finally {
      if (mounted) setState(() => addingMember = false);
    }
  }

  Future<void> messageMember(String userId) async {
    await ProfileCommunicationService.openDirectProfileChat(
      context: context,
      targetUserId: userId,
      targetRole: "worker",
    );
  }

  Future<void> removeMember(String userId, String userName) async {
    final uid = currentUserId;
    if (uid == null || uid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Sign in again to manage this team")),
      );
      return;
    }

    if (uid == userId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Team leader cannot remove themselves here."),
        ),
      );
      return;
    }

    final teamRef =
        FirebaseFirestore.instance.collection("teams").doc(widget.teamId);
    final snap = await teamRef.get();
    if (!mounted) return;

    if (!snap.exists) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Team is no longer available.")),
      );
      return;
    }

    final data = snap.data() ?? <String, dynamic>{};
    if (!isTeamLeader(data)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Only the team leader can manage team members."),
        ),
      );
      return;
    }

    final latestMembers = memberIdsFrom(data["members"]);
    if (!latestMembers.contains(userId)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("This worker is no longer in the team.")),
      );
      return;
    }

    final confirmed = await confirmAction(
      title: "Remove from team",
      message: "Are you sure you want to remove this worker from the team?",
      confirmText: "Yes",
    );
    if (!confirmed) return;
    if (!mounted) return;

    try {
      final members = latestMembers
        ..removeWhere((memberId) => memberId == userId);

      await teamRef.set({
        "members": members,
        "memberCount": members.length,
        "memberStatuses.$userId": FieldValue.delete(),
        "membersStatus.$userId": FieldValue.delete(),
        "updatedAt": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Worker removed from team.")),
      );
    } on FirebaseException catch (e) {
      if (!mounted) return;
      final message = e.code == "permission-denied"
          ? "Only the team leader can manage team members."
          : "Could not remove worker from team.";
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not remove worker from team.")),
      );
    }
  }

  Future<void> leaveTeam(
      Map<String, dynamic> team, List<String> members) async {
    final uid = currentUserId;
    if (uid == null || uid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Sign in again to manage this team")),
      );
      return;
    }

    if (isTeamLeader(team)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Team leader should delete the team instead"),
        ),
      );
      return;
    }

    final confirmed = await confirmAction(
      title: "Leave team",
      message: "Are you sure you want to leave this team?",
      confirmText: "Leave",
    );
    if (!confirmed) return;

    final updatedMembers = [...members]
      ..removeWhere((memberId) => memberId == uid);

    await FirebaseFirestore.instance
        .collection("teams")
        .doc(widget.teamId)
        .set({
      "members": updatedMembers,
      "memberStatuses.$uid": FieldValue.delete(),
      "updatedAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    messenger.showSnackBar(
      const SnackBar(content: Text("You left the team")),
    );
  }

  Future<void> deleteTeam() async {
    if (deletingTeam) return;

    final confirmed = await confirmAction(
      title: "Delete team",
      message:
          "Delete this team permanently? This cannot be undone, but existing applications and chats will not be automatically deleted.",
      confirmText: "Delete",
    );
    if (!confirmed) return;

    if (!mounted) return;
    setState(() => deletingTeam = true);

    try {
      final firestore = FirebaseFirestore.instance;
      final teamRef = firestore.collection("teams").doc(widget.teamId);
      final portfolio = await teamRef.collection("portfolio").get();
      final batch = firestore.batch();

      for (final doc in portfolio.docs) {
        batch.delete(doc.reference);
      }
      batch.delete(teamRef);

      await batch.commit();

      if (!mounted) return;
      setState(() => teamDeletedLocally = true);
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop(true);
      messenger.showSnackBar(
        const SnackBar(content: Text("Team deleted")),
      );
    } catch (e) {
      debugPrint("DELETE TEAM ERROR: $e");
      if (!mounted) return;
      setState(() => deletingTeam = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not delete team")),
      );
    }
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
                    onPressed:
                        uploadingTeamPortfolio ? null : addTeamPortfolioImages,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (uploadingTeamPortfolio)
              const LinearProgressIndicator()
            else if (!snapshot.hasData)
              const LinearProgressIndicator()
            else if (photos.isEmpty)
              const Text("No team portfolio yet")
            else
              AppPhotoGridGallery(
                imageUrls: photos
                    .map((doc) => doc.data() as Map<String, dynamic>)
                    .map((data) =>
                        (data["imageUrl"] ?? data["image"])?.toString() ?? "")
                    .toList(),
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
    bool isLeader,
  ) {
    return FutureBuilder<DocumentSnapshot>(
      future:
          FirebaseFirestore.instance.collection("users").doc(memberId).get(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const ListTile(title: Text("Loading..."));
        }

        final user = snapshot.data!.data() as Map<String, dynamic>?;
        final status = user?["status"]?.toString().trim().toLowerCase() ?? "";
        if (user == null ||
            user["deleted"] == true ||
            user["accountDeleted"] == true ||
            user["active"] == false ||
            status == "deleted") {
          return const SizedBox.shrink();
        }
        final userName = user["name"] ?? "User";
        final trade = user["trade"] ?? "";
        final photo = user["photo"];
        final phone = user["phone"]?.toString();

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
            leading: StroykaAvatar(
              imageUrl: photo?.toString(),
              fallbackIcon: Icons.person,
              size: 54,
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
                ? PopupMenuButton<String>(
                    tooltip: "Member actions",
                    icon: const Icon(Icons.more_vert),
                    onSelected: (value) {
                      if (value == "message") {
                        messageMember(memberId);
                      }
                      if (value == "remove") {
                        removeMember(memberId, userName.toString());
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: "message",
                        child: Row(
                          children: [
                            Icon(Icons.chat_bubble_outline),
                            SizedBox(width: 10),
                            Text("Message"),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: "remove",
                        child: Row(
                          children: [
                            Icon(Icons.person_remove_outlined),
                            SizedBox(width: 10),
                            Text("Remove from team"),
                          ],
                        ),
                      ),
                    ],
                  )
                : isLeader
                    ? const Chip(label: Text("Leader"))
                    : null,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => WorkerProfileScreen(
                    userId: memberId,
                    openedFrom: "team",
                    returnToTeamId: widget.teamId,
                  ),
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
        if (snapshot.hasData && !snapshot.data!.exists) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !teamDeletedLocally && Navigator.canPop(context)) {
              Navigator.pop(context, true);
            }
          });
          return const Scaffold(
            body: Center(child: Text("Team deleted")),
          );
        }

        final liveData = snapshot.data?.data() as Map<String, dynamic>?;
        final team = liveData ?? widget.teamData;
        final members = memberIdsFrom(team["members"]);
        final name = team["name"]?.toString() ?? "Team";
        final description =
            (team["description"] ?? team["bio"])?.toString().trim() ?? "";
        final avatar = team["avatarUrl"] ?? team["photo"] ?? team["logo"];
        final headerImage = team["profileHeaderImage"] ??
            team["headerImageUrl"] ??
            team["headerImage"] ??
            team["backgroundUrl"] ??
            team["backgroundImage"];
        final canEdit = canEditTeam(team, members);
        final isMember = isTeamMember(members);

        return StroykaBackground(
          asset: AppAssets.backgroundCranesYard,
          child: Scaffold(
            appBar: AppBar(
              title: const Text("Team"),
              actions: [
                if (canEdit)
                  IconButton(
                    tooltip: "Add member",
                    icon: const Icon(Icons.person_add_alt),
                    onPressed: addingMember ? null : () => addMember(members),
                  ),
                if (canEdit)
                  IconButton(
                    tooltip: "Delete team",
                    icon: const Icon(Icons.delete_outline),
                    onPressed: deletingTeam ? null : deleteTeam,
                  ),
              ],
            ),
            body: StroykaScreenBody(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      GestureDetector(
                        onTap: canEdit ? updateTeamBackground : null,
                        child: StroykaProfileHeader(
                          title: name,
                          subtitle: "${members.length} members",
                          avatarUrl: avatar?.toString(),
                          headerImageUrl: headerImage?.toString(),
                          fallbackIcon: Icons.groups,
                          margin: EdgeInsets.zero,
                          headerControls: canEdit
                              ? Row(
                                  children: [
                                    ProfileCommunicationService.circleAction(
                                      icon: Icons.image_outlined,
                                      tooltip: "Choose background",
                                      onPressed: updateTeamBackground,
                                    ),
                                    const Spacer(),
                                    ProfileCommunicationService.circleAction(
                                      icon: Icons.photo_camera_outlined,
                                      tooltip: "Choose avatar",
                                      onPressed: updateTeamAvatar,
                                    ),
                                  ],
                                )
                              : null,
                          leftBottomAction: viewerRole == "employer"
                              ? ProfileCommunicationService.circleAction(
                                  icon: Icons.phone,
                                  tooltip: "Call team",
                                  onPressed: () async {
                                    final phone =
                                        await ProfileCommunicationService
                                            .teamPhone(team);
                                    if (!context.mounted) return;
                                    await ProfileCommunicationService.callPhone(
                                      context,
                                      profileData: team,
                                      phone: phone,
                                    );
                                  },
                                )
                              : null,
                          rightBottomAction: currentUserId != null
                              ? ProfileCommunicationService.circleAction(
                                  icon: Icons.chat_bubble_outline,
                                  tooltip: "Message team",
                                  onPressed: () => ProfileCommunicationService
                                      .openTeamProfileChat(
                                    context: context,
                                    teamId: widget.teamId,
                                    teamName: name,
                                    memberIds: members,
                                  ),
                                )
                              : null,
                        ),
                      ),
                      if (canEdit)
                        Positioned(
                          top: 64,
                          child: GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onTap: updateTeamAvatar,
                            child: const SizedBox(
                              width: 104,
                              height: 104,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  if (widget.showInternalChat) ...[
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
                  ],
                  if (canEdit || isMember) ...[
                    StroykaSurface(
                      padding: const EdgeInsets.all(14),
                      child: SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red),
                          ),
                          onPressed: canEdit
                              ? (deletingTeam ? null : deleteTeam)
                              : () => leaveTeam(team, members),
                          icon: Icon(
                            canEdit ? Icons.delete_outline : Icons.logout,
                          ),
                          label: Text(canEdit ? "Delete team" : "Leave team"),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                  ],
                  StroykaSurface(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
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
                                onPressed: () =>
                                    updateTeamDescription(description),
                              ),
                          ],
                        ),
                        if (description.isEmpty)
                          const Text("No team description yet")
                        else
                          Text(description),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  StroykaSurface(
                    padding: const EdgeInsets.all(18),
                    child: buildTeamPortfolio(canEdit),
                  ),
                  const SizedBox(height: 24),
                  StroykaSurface(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      children: [
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
                                onPressed: addingMember
                                    ? null
                                    : () => addMember(members),
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
                                canEdit && memberId != currentUserId,
                                memberId == team["ownerId"] ||
                                    memberId == team["createdBy"],
                              ),
                            );
                          }),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AddTeamMemberDialog extends StatefulWidget {
  const _AddTeamMemberDialog();

  @override
  State<_AddTeamMemberDialog> createState() => _AddTeamMemberDialogState();
}

class _AddTeamMemberDialogState extends State<_AddTeamMemberDialog> {
  final controller = TextEditingController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void submit() {
    final value = controller.text.trim();
    Navigator.of(context).pop(value.isEmpty ? null : value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Add team member"),
      content: TextField(
        controller: controller,
        decoration: const InputDecoration(
          labelText: "Nickname or phone",
          hintText: "Worker nickname or phone number",
        ),
        autofocus: true,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text("Cancel"),
        ),
        ElevatedButton(
          onPressed: submit,
          child: const Text("Add"),
        ),
      ],
    );
  }
}

class TeamAvatarCropDialog extends StatefulWidget {
  final File imageFile;

  const TeamAvatarCropDialog({
    super.key,
    required this.imageFile,
  });

  @override
  State<TeamAvatarCropDialog> createState() => _TeamAvatarCropDialogState();
}

class _TeamAvatarCropDialogState extends State<TeamAvatarCropDialog> {
  final TransformationController controller = TransformationController();
  bool processing = false;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> confirmCrop(double cropSize) async {
    if (processing) return;
    setState(() => processing = true);
    try {
      final cropped = await _cropTeamAvatarFile(
        imageFile: widget.imageFile,
        matrix: controller.value,
        cropSize: cropSize,
      );
      if (!mounted) return;
      Navigator.pop(context, cropped);
    } catch (error) {
      debugPrint("Team avatar crop error: $error");
      if (!mounted) return;
      setState(() => processing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not crop avatar image")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final cropSize = math.min(screenWidth - 80, 300).toDouble();

    return AlertDialog(
      title: const Text("Position team avatar"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: cropSize,
            height: cropSize,
            child: Stack(
              children: [
                ClipOval(
                  child: SizedBox(
                    width: cropSize,
                    height: cropSize,
                    child: InteractiveViewer(
                      transformationController: controller,
                      minScale: 1,
                      maxScale: 4,
                      boundaryMargin: EdgeInsets.zero,
                      clipBehavior: Clip.none,
                      child: SizedBox(
                        width: cropSize,
                        height: cropSize,
                        child: Image.file(
                          widget.imageFile,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                ),
                IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.blueprintLine,
                        width: 3,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            "Drag to position. Pinch to zoom.",
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.muted,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: processing ? null : () => Navigator.pop(context),
          child: const Text("Cancel"),
        ),
        ElevatedButton(
          onPressed: processing ? null : () => confirmCrop(cropSize),
          child: processing
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text("Use avatar"),
        ),
      ],
    );
  }
}

Future<File> _cropTeamAvatarFile({
  required File imageFile,
  required Matrix4 matrix,
  required double cropSize,
}) async {
  final bytes = await imageFile.readAsBytes();
  final sourceImage = await _decodeTeamUiImage(bytes);
  final inverse = Matrix4.inverted(matrix);
  final topLeft = MatrixUtils.transformPoint(inverse, Offset.zero);
  final bottomRight = MatrixUtils.transformPoint(
    inverse,
    Offset(cropSize, cropSize),
  );

  final imageWidth = sourceImage.width.toDouble();
  final imageHeight = sourceImage.height.toDouble();
  final baseScale = math.max(cropSize / imageWidth, cropSize / imageHeight);
  final fittedWidth = imageWidth * baseScale;
  final fittedHeight = imageHeight * baseScale;
  final fittedLeft = (cropSize - fittedWidth) / 2;
  final fittedTop = (cropSize - fittedHeight) / 2;

  double sourceLeft = (topLeft.dx - fittedLeft) / baseScale;
  double sourceTop = (topLeft.dy - fittedTop) / baseScale;
  double sourceRight = (bottomRight.dx - fittedLeft) / baseScale;
  double sourceBottom = (bottomRight.dy - fittedTop) / baseScale;

  sourceLeft = sourceLeft.clamp(0, imageWidth - 1);
  sourceTop = sourceTop.clamp(0, imageHeight - 1);
  sourceRight = sourceRight.clamp(sourceLeft + 1, imageWidth);
  sourceBottom = sourceBottom.clamp(sourceTop + 1, imageHeight);

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  const outputSize = 512.0;
  final sourceRect = Rect.fromLTRB(
    sourceLeft,
    sourceTop,
    sourceRight,
    sourceBottom,
  );
  canvas.drawImageRect(
    sourceImage,
    sourceRect,
    const Rect.fromLTWH(0, 0, outputSize, outputSize),
    Paint()..filterQuality = FilterQuality.high,
  );

  final picture = recorder.endRecording();
  final croppedImage = await picture.toImage(
    outputSize.toInt(),
    outputSize.toInt(),
  );
  final pngBytes =
      await croppedImage.toByteData(format: ui.ImageByteFormat.png);
  if (pngBytes == null) {
    throw StateError("Could not encode cropped team avatar");
  }

  final outputFile = File(
    "${Directory.systemTemp.path}/stroyka_team_avatar_${DateTime.now().millisecondsSinceEpoch}.png",
  );
  await outputFile.writeAsBytes(pngBytes.buffer.asUint8List());
  return outputFile;
}

Future<ui.Image> _decodeTeamUiImage(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  return frame.image;
}
