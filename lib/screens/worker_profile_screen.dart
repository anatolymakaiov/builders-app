import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'team_details_screen.dart';

import 'edit_profile_screen.dart';
import '../services/chat_service.dart';
import 'chat_screen.dart';

class WorkerProfileScreen extends StatelessWidget {
  final String userId;
  final String? jobId;
  final String? employerId;

  const WorkerProfileScreen({
    super.key,
    required this.userId,
    this.jobId,
    this.employerId,
  });

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    final isMyProfile = currentUser?.uid == userId;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Worker Profile"),
        actions: [
          if (isMyProfile) ...[
            /// ✏️ EDIT
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ProfileScreen(),
                  ),
                );
              },
            ),

            /// 🚪 LOGOUT
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () async {
                await FirebaseAuth.instance.signOut();
              },
            ),
          ],
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: () async {
          final userSnap = await FirebaseFirestore.instance
              .collection("users")
              .doc(userId)
              .get();

          final userData = userSnap.data() as Map<String, dynamic>;

          String? applicationId;
          String status = "pending";

          if (jobId != null && employerId != null) {
            final appQuery = await FirebaseFirestore.instance
                .collection("applications")
                .where("jobId", isEqualTo: jobId)
                .where("workerId", isEqualTo: userId)
                .limit(1)
                .get();

            if (appQuery.docs.isNotEmpty) {
              final appDoc = appQuery.docs.first;
              applicationId = appDoc.id;
              status = appDoc["status"] ?? "pending";
            }
          }

          return {
            "user": userData,
            "applicationId": applicationId,
            "status": status,
          };
        }(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final result = snapshot.data!;
          final data = result["user"] as Map<String, dynamic>;
          final String? applicationId = result["applicationId"];
          final String status = result["status"];
          final offerRate = result["offerRate"];
          final offerNote = result["offerNote"];
          final name = data["name"] ?? "Worker";
          final trade = data["trade"] ?? "";
          final rate = data["rate"];
          final bio = data["bio"] ?? "";
          final location = data["location"] ?? "";
          final photo = data["photo"];

          final rating = (data["rating"] ?? 0).toDouble();
          final reviews = data["reviewsCount"] ?? 0;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                /// 🔥 HEADER
                Center(
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 50,
                        backgroundColor: Colors.grey.shade300,
                        backgroundImage:
                            photo != null ? NetworkImage(photo) : null,
                        child: photo == null
                            ? const Icon(Icons.person, size: 40)
                            : null,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (trade.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          trade,
                          style: const TextStyle(color: Colors.grey),
                        ),
                      ],
                      if (rate != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          "£${rate.toString()}/hour",
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                      ],

                      /// ⭐ RATING
                      if (rating > 0) ...[
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.star, color: Colors.amber),
                            const SizedBox(width: 4),
                            Text("$rating ($reviews reviews)"),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 30),

                /// 📍 LOCATION
                if (location.isNotEmpty) ...[
                  const Text(
                    "Location",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(location),
                  const SizedBox(height: 20),
                ],

                /// 📝 ABOUT
                if (bio.isNotEmpty) ...[
                  const Text(
                    "About",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(bio),
                  const SizedBox(height: 20),
                ],

                /// 🔥 PORTFOLIO
                FutureBuilder<QuerySnapshot>(
                  future: FirebaseFirestore.instance
                      .collection("users")
                      .doc(userId)
                      .collection("portfolio")
                      .get(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                      return const SizedBox();
                    }

                    final items = snapshot.data!.docs;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Portfolio",
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 110,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: items.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 10),
                            itemBuilder: (_, index) {
                              final img = items[index]["imageUrl"];

                              return ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Image.network(
                                  img,
                                  width: 110,
                                  height: 110,
                                  fit: BoxFit.cover,
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 30),
                      ],
                    );
                  },
                ),
                if (status == "offer_sent") ...[
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: Colors.green.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Offer",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Colors.green,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (offerRate != null) Text("Rate: £$offerRate/hour"),
                        if (offerNote != null &&
                            offerNote.toString().isNotEmpty)
                          Text("Note: $offerNote"),
                        const SizedBox(height: 12),
                        if (!isMyProfile)
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: () async {
                                await FirebaseFirestore.instance
                                    .collection("applications")
                                    .doc(applicationId)
                                    .update({
                                  "status": "offer_accepted",
                                });

                                if (!context.mounted) return;

                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text("Offer accepted")),
                                );
                              },
                              child: const Text("Accept offer"),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],

                /// 💬 MESSAGE
                if (employerId != null && jobId != null)
                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton(
                      onPressed: () async {
                        final chatId = await ChatService.getOrCreateChat(
                          workerId: userId,
                          employerId: employerId!,
                          jobId: jobId!,
                        );

                        if (!context.mounted) return;

                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ChatScreen(chatId: chatId),
                          ),
                        );
                      },
                      child: const Text(
                        "Message worker",
                        style: TextStyle(fontSize: 18),
                      ),
                    ),
                  ),
                if (applicationId != null) ...[
                  const SizedBox(height: 12),

                  /// ACTIONS
                  Row(
                    children: [
                      /// ❌ REJECT (всегда кроме accepted)
                      if (status != "offer_accepted")
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () async {
                              await FirebaseFirestore.instance
                                  .collection("applications")
                                  .doc(applicationId)
                                  .update({"status": "rejected"});
                            },
                            child: const Text("Reject"),
                          ),
                        ),

                      if (status != "offer_accepted") const SizedBox(width: 10),

                      /// 💬 NEGOTIATION (только из pending)
                      if (status == "pending")
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () async {
                              await FirebaseFirestore.instance
                                  .collection("applications")
                                  .doc(applicationId)
                                  .update({"status": "negotiation"});
                            },
                            child: const Text("Negotiation"),
                          ),
                        ),

                      if (status == "pending") const SizedBox(width: 10),

                      /// 💰 OFFER (pending + negotiation)
                      if (status == "pending" || status == "negotiation")
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () async {
                              final rateController = TextEditingController();
                              final noteController = TextEditingController();

                              final result = await showDialog<bool>(
                                context: context,
                                builder: (_) => AlertDialog(
                                  title: const Text("Send Offer"),
                                  content: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      TextField(
                                        controller: rateController,
                                        keyboardType: TextInputType.number,
                                        decoration: const InputDecoration(
                                          labelText: "Rate (£/hour)",
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      TextField(
                                        controller: noteController,
                                        decoration: const InputDecoration(
                                          labelText: "Message (optional)",
                                        ),
                                      ),
                                    ],
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, false),
                                      child: const Text("Cancel"),
                                    ),
                                    ElevatedButton(
                                      onPressed: () =>
                                          Navigator.pop(context, true),
                                      child: const Text("Send"),
                                    ),
                                  ],
                                ),
                              );

                              if (result != true) return;

                              final rate =
                                  double.tryParse(rateController.text.trim());

                              await FirebaseFirestore.instance
                                  .collection("applications")
                                  .doc(applicationId)
                                  .update({
                                "status": "offer_sent",
                                "offerRate": rate,
                                "offerNote": noteController.text.trim(),
                                "offerCreatedAt": FieldValue.serverTimestamp(),
                              });
                            },
                            child: const Text("Offer"),
                          ),
                        ),

                      /// ✅ HIRED (только после оффера)
                      if (status == "offer_sent")
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () async {
                              await FirebaseFirestore.instance
                                  .collection("applications")
                                  .doc(applicationId)
                                  .update({"status": "offer_accepted"});
                            },
                            child: const Text("Hire"),
                          ),
                        ),
                    ],
                  ),
                ],

                /// 🔥 CREATE TEAM
                if (isMyProfile) ...[
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        await showCreateTeamDialog(context, userId);
                      },
                      icon: const Icon(Icons.group),
                      label: const Text(
                        "Create team",
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                  ),

                  /// 🔥 MY TEAMS
                  const SizedBox(height: 20),
                  const Text(
                    "My teams",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 10),

                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection("teams")
                        .where("members", arrayContains: userId)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final docs = snapshot.data!.docs;

                      if (docs.isEmpty) {
                        return const Text("No teams yet");
                      }

                      return Column(
                        children: docs.map((doc) {
                          final data = doc.data() as Map<String, dynamic>;

                          final name = data["name"] ?? "Team";
                          final members = (data["members"] as List?) ?? [];

                          return GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => TeamDetailsScreen(
                                    teamId: doc.id,
                                    teamData:
                                        doc.data() as Map<String, dynamic>,
                                  ),
                                ),
                              );
                            },
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.group),
                                  const SizedBox(width: 10),

                                  /// NAME
                                  Expanded(
                                    child: Text(
                                      name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),

                                  /// COUNT
                                  Text("${members.length} members"),

                                  const SizedBox(width: 6),
                                  const Icon(Icons.arrow_forward_ios, size: 14),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      );
                    },
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

/// 🔥 CREATE TEAM DIALOG
Future<void> showCreateTeamDialog(
  BuildContext context,
  String userId,
) async {
  final controller = TextEditingController();

  await showDialog(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text("Create team"),
      content: TextField(
        controller: controller,
        decoration: const InputDecoration(
          labelText: "Team name",
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Cancel"),
        ),
        ElevatedButton(
          onPressed: () async {
            final name = controller.text.trim();
            if (name.isEmpty) return;

            await FirebaseFirestore.instance.collection("teams").add({
              "name": name,
              "ownerId": userId,
              "members": [userId],
              "createdAt": FieldValue.serverTimestamp(),
            });

            Navigator.pop(context);

            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Team created")),
            );
          },
          child: const Text("Create"),
        ),
      ],
    ),
  );
}
