import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'worker_profile_screen.dart';
import '../widgets/phone_link.dart';

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
    final rawMembers = (teamData["members"] as List?) ?? [];

    final members = rawMembers.map((m) {
      if (m is String) {
        return {
          "userId": m,
          "status": "pending",
        };
      }
      return Map<String, dynamic>.from(m);
    }).toList();
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
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final member = members[index];
                  final memberId = member["userId"];
                  final status = member["status"] ?? "pending";

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
                            backgroundImage:
                                photo != null ? NetworkImage(photo) : null,
                            child:
                                photo == null ? const Icon(Icons.person) : null,
                          ),
                          title: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(userName),
                              Text(
                                status,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                              if (phone != null && phone.isNotEmpty)
                                PhoneLink(
                                  phone: phone,
                                  compact: true,
                                ),
                            ],
                          ),

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
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (status != "offer_accepted") ...[
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    /// NEGOTIATE
                                    IconButton(
                                      icon: const Icon(Icons.chat, size: 18),
                                      onPressed: () async {
                                        await updateMemberStatus(
                                            memberId, "negotiation");
                                      },
                                    ),

                                    /// OFFER
                                    IconButton(
                                      icon: const Icon(Icons.local_offer,
                                          size: 18),
                                      onPressed: () async {
                                        await updateMemberStatus(
                                            memberId, "offer_sent");
                                      },
                                    ),

                                    /// REJECT
                                    IconButton(
                                      icon: const Icon(Icons.close,
                                          size: 18, color: Colors.red),
                                      onPressed: () async {
                                        await updateMemberStatus(
                                            memberId, "rejected");
                                      },
                                    ),
                                  ],
                                ),
                              ],

                              /// ACCEPT (HIRE)
                              if (status == "offer_sent")
                                IconButton(
                                  icon: const Icon(Icons.check_circle,
                                      color: Colors.green),
                                  onPressed: () async {
                                    await updateMemberStatus(
                                        memberId, "offer_accepted");
                                  },
                                ),
                            ],
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
    final ref = FirebaseFirestore.instance.collection("teams").doc(teamId);

    final snap = await ref.get();

    if (!snap.exists) return;

    final data = snap.data() as Map<String, dynamic>;

    final members = List<Map<String, dynamic>>.from(
      (data["members"] ?? []).map((e) {
        if (e is String) {
          return {
            "userId": e,
            "status": "pending",
          };
        }
        return Map<String, dynamic>.from(e);
      }),
    );

    members.removeWhere((m) => m["userId"] == userId);

    await ref.update({
      "members": members,
    });
  }

  Future<void> updateMemberStatus(
    String userId,
    String newStatus,
  ) async {
    /// 🔥 1. UPDATE TEAM
    final teamRef = FirebaseFirestore.instance.collection("teams").doc(teamId);

    final teamSnap = await teamRef.get();

    if (!teamSnap.exists) return;

    final teamData = teamSnap.data() as Map<String, dynamic>;

    final members = List<Map<String, dynamic>>.from(
      (teamData["members"] ?? []).map((e) {
        if (e is String) {
          return {
            "userId": e,
            "status": "pending",
          };
        }
        return Map<String, dynamic>.from(e);
      }),
    );

    for (var m in members) {
      if (m["userId"] == userId) {
        m["status"] = newStatus;
      }
    }

    await teamRef.update({
      "members": members,
    });

    /// 🔥 2. UPDATE APPLICATION (ВАЖНО)
    final appQuery = await FirebaseFirestore.instance
        .collection("applications")
        .where("teamId", isEqualTo: teamId)
        .limit(1)
        .get();

    if (appQuery.docs.isNotEmpty) {
      final appDoc = appQuery.docs.first;

      /// если хотя бы один принят → hired
      final hasAccepted = members.any(
        (m) => m["status"] == "offer_accepted",
      );

      await appDoc.reference.update({
        "status": hasAccepted ? "offer_accepted" : "negotiation",
      });
    }
  }
}
