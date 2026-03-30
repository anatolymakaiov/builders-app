import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'worker_profile_screen.dart';

class TeamDetailsScreen extends StatelessWidget {
  final String teamId;
  final Map<String, dynamic> teamData;

  const TeamDetailsScreen({
    super.key,
    required this.teamId,
    required this.teamData,
  });

  @override
  Widget build(BuildContext context) {
    final members = List<String>.from(teamData["members"] ?? []);
    final name = teamData["name"] ?? "Team";

    return Scaffold(
      appBar: AppBar(
        title: const Text("Team"),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            /// 🔥 HEADER
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

            const SizedBox(height: 20),

            /// 🔥 MEMBERS LIST
            Expanded(
              child: ListView.separated(
                itemCount: members.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final memberId = members[index];

                  return FutureBuilder<DocumentSnapshot>(
                    future: FirebaseFirestore.instance
                        .collection("users")
                        .doc(memberId)
                        .get(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const ListTile(
                          title: Text("Loading..."),
                        );
                      }

                      final user =
                          snapshot.data!.data() as Map<String, dynamic>?;

                      final userName = user?["name"] ?? "User";
                      final photo = user?["photo"];

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
                            backgroundImage: photo != null
                                ? NetworkImage(photo)
                                : null,
                            child: photo == null
                                ? const Icon(Icons.person)
                                : null,
                          ),
                          title: Text(userName),

                          /// 🔥 ПРОФИЛЬ
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => WorkerProfileScreen(
                                  userId: memberId,
                                ),
                              ),
                            );
                          },

                          /// 🔥 REMOVE (пока оставим)
                          trailing: IconButton(
                            icon: const Icon(Icons.remove_circle,
                                color: Colors.red),
                            onPressed: () async {
                              await removeMember(memberId);
                            },
                          ),
                        ),
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

  Future<void> removeMember(String userId) async {
    final ref =
        FirebaseFirestore.instance.collection("teams").doc(teamId);

    final snap = await ref.get();

    if (!snap.exists) return;

    final data = snap.data() as Map<String, dynamic>;

    final members = List<String>.from(data["members"] ?? []);

    members.remove(userId);

    await ref.update({
      "members": members,
    });
  }
}