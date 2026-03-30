import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/chat_service.dart';
import 'chat_screen.dart';
import 'worker_profile_screen.dart';
import 'team_details_screen.dart';

class ApplicantsScreen extends StatelessWidget {
  final String jobId;

  const ApplicantsScreen({
    super.key,
    required this.jobId,
  });

  Color getStatusColor(String status) {
    switch (status) {
      case "accepted":
        return Colors.green;

      case "offer_sent": // 👈 ВОТ ЭТА СТРОКА НОВАЯ
        return Colors.purple;

      case "rejected":
        return Colors.red;

      default:
        return Colors.orange;
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    Future<void> openTeam(BuildContext context, String? teamId) async {
      if (teamId == null) return;

      final navigator = Navigator.of(context);
      final scaffold = ScaffoldMessenger.of(context);

      final teamSnap = await FirebaseFirestore.instance
          .collection("teams")
          .doc(teamId)
          .get();

      if (!teamSnap.exists) {
        scaffold.showSnackBar(
          const SnackBar(content: Text("Team not found")),
        );
        return;
      }

      final teamData = teamSnap.data() as Map<String, dynamic>;

      navigator.push(
        MaterialPageRoute(
          builder: (_) => TeamDetailsScreen(
            teamId: teamId,
            teamData: teamData,
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Applicants"),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection("applications")
            .where("jobId", isEqualTo: jobId)
            .orderBy("createdAt", descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final applications = (snapshot.data?.docs ?? []).where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final status = data["status"] ?? "pending";

            return status == "pending" ||
                status == "accepted" ||
                status == "negotiation" ||
                status == "offer_sent";
          }).toList()
            ..sort((a, b) {
              final aStatus =
                  (a.data() as Map<String, dynamic>)["status"] ?? "pending";
              final bStatus =
                  (b.data() as Map<String, dynamic>)["status"] ?? "pending";

              /// 🟡 pending выше
              if (aStatus == "pending" && bStatus != "pending") return -1;
              if (aStatus != "pending" && bStatus == "pending") return 1;

              /// одинаковые — по дате
              final aDate =
                  (a.data() as Map<String, dynamic>)["createdAt"] as Timestamp?;
              final bDate =
                  (b.data() as Map<String, dynamic>)["createdAt"] as Timestamp?;

              if (aDate == null && bDate == null) return 0;
              if (aDate == null) return 1;
              if (bDate == null) return -1;

              return bDate.compareTo(aDate);
            });

          if (applications.isEmpty) {
            return const Center(child: Text("No applicants yet"));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: applications.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final doc = applications[index];
              final data = doc.data() as Map<String, dynamic>;
              final hasMembers = data["members"] != null;
              final status = data["status"] ?? "pending";
              final Timestamp? createdAt = data["createdAt"];
              final dateText = createdAt != null
                  ? DateTime.fromMillisecondsSinceEpoch(
                          createdAt.millisecondsSinceEpoch)
                      .toString()
                      .substring(0, 16)
                  : "";

              if (hasMembers) {
                final members = List<String>.from(data["members"] ?? []);
                final String? teamId = data["teamId"] as String?;

                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      )
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      /// STATUS
                      Align(
                        alignment: Alignment.topRight,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color:
                                getStatusColor(status).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            status.toUpperCase(),
                            style: TextStyle(
                              color: getStatusColor(status),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 8),

                      /// 🔥 HEADER (ТОЛЬКО ОН КЛИКАБЕЛЕН)
                      GestureDetector(
                        onTap: () => openTeam(context, teamId),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Team application • ${members.length} ${members.length == 1 ? 'member' : 'members'}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  if (dateText.isNotEmpty)
                                    Text(
                                      dateText,
                                      style: const TextStyle(
                                          fontSize: 12, color: Colors.grey),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 10),

                      /// 👇 MEMBERS (кликаются отдельно)
                      ...members.map((memberId) {
                        return FutureBuilder<DocumentSnapshot>(
                          future: FirebaseFirestore.instance
                              .collection("users")
                              .doc(memberId)
                              .get(),
                          builder: (context, snapshot) {
                            if (!snapshot.hasData) {
                              return const Text("Loading...");
                            }

                            final user =
                                snapshot.data!.data() as Map<String, dynamic>?;

                            final membersStatus = data["membersStatus"]
                                    as Map<String, dynamic>? ??
                                {};

                            final memberStatus =
                                membersStatus[memberId] ?? "pending";

                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(user?["name"] ?? "User"),
                              subtitle: Text(memberStatus.toUpperCase()),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (memberStatus == "pending") ...[
                                    IconButton(
                                      icon: const Icon(Icons.check,
                                          color: Colors.green),
                                      onPressed: () async {
                                        try {
                                          await updateMemberStatus(
                                              doc.id, memberId, "accepted");
                                        } catch (e) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            const SnackBar(
                                                content: Text("No spots left")),
                                          );
                                        }
                                      },
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.close,
                                          color: Colors.red),
                                      onPressed: () async {
                                        await updateMemberStatus(
                                            doc.id, memberId, "rejected");
                                      },
                                    ),
                                  ],
                                  if (memberStatus == "accepted")
                                    IconButton(
                                      icon: const Icon(Icons.undo,
                                          color: Colors.orange),
                                      onPressed: () async {
                                        await undoMemberStatus(
                                            doc.id, memberId);
                                      },
                                    ),
                                ],
                              ),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => WorkerProfileScreen(
                                      userId: memberId,
                                      jobId: jobId,
                                      employerId: currentUser?.uid,
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        );
                      }),

                      /// 👇 ВОТ ЭТО ДОБАВЬ
                      const SizedBox(height: 12),

                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: () async {
                            if (currentUser == null) return;
                            if (teamId == null) return;

                            final chatId =
                                await ChatService.getOrCreateTeamChat(
                              teamId: teamId,
                              employerId: currentUser.uid,
                              jobId: jobId,
                              members: members,
                            );

                            if (!context.mounted) return;

                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ChatScreen(chatId: chatId),
                              ),
                            );
                          },
                          child: const Text("Message team"),
                        ),
                      ),

                      const SizedBox(height: 8),

                      /// 🔥 НОВАЯ КНОПКА — ПЕРЕГОВОРЫ
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: () async {
                            if (currentUser == null) return;
                            if (teamId == null) return;

                            /// меняем статус
                            await updateStatus(doc.id, "negotiation");

                            final chatId =
                                await ChatService.getOrCreateTeamChat(
                              teamId: teamId,
                              employerId: currentUser.uid,
                              jobId: jobId,
                              members: members,
                            );

                            if (!context.mounted) return;

                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ChatScreen(chatId: chatId),
                              ),
                            );
                          },
                          child: const Text("Negotiation"),
                        ),
                      ),
                      const SizedBox(height: 8),

                      /// 🔥 SEND OFFER ДЛЯ TEAM
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: status == "negotiation"
                              ? () {
                                  showOfferDialog(context, doc.id);
                                }
                              : null,
                          child: const Text("Send offer"),
                        ),
                      ),
                    ],
                  ),
                );
              }

              /// SINGLE
              final String? workerId = data["workerId"];

              if (workerId == null || workerId.isEmpty) {
                return const SizedBox();
              }

              return FutureBuilder<DocumentSnapshot>(
                future: FirebaseFirestore.instance
                    .collection("users")
                    .doc(workerId)
                    .get(),
                builder: (context, userSnapshot) {
                  if (!userSnapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final userData =
                      userSnapshot.data!.data() as Map<String, dynamic>?;

                  final name = userData?["name"] ?? "Worker";
                  final trade = userData?["trade"] ?? "";
                  final rate = userData?["rate"];
                  final photo = userData?["photo"];

                  return InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => WorkerProfileScreen(
                            userId: workerId,
                            jobId: jobId,
                            employerId: currentUser?.uid,
                          ),
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          )
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          /// STATUS
                          Align(
                            alignment: Alignment.topRight,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: getStatusColor(status)
                                    .withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                status.toUpperCase(),
                                style: TextStyle(
                                  color: getStatusColor(status),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),

                          /// HEADER
                          Row(
                            children: [
                              /// AVATAR
                              CircleAvatar(
                                radius: 24,
                                backgroundColor: Colors.grey.shade300,
                                backgroundImage:
                                    photo != null ? NetworkImage(photo) : null,
                                child: photo == null
                                    ? const Icon(Icons.person)
                                    : null,
                              ),

                              const SizedBox(width: 12),

                              /// INFO
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    if (trade.isNotEmpty)
                                      Text(
                                        trade,
                                        style:
                                            const TextStyle(color: Colors.grey),
                                      ),
                                    if (rate != null)
                                      Text("£${rate.toString()}/h"),
                                    if (dateText.isNotEmpty)
                                      Text(
                                        dateText,
                                        style: const TextStyle(
                                            fontSize: 12, color: Colors.grey),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 14),

                          /// ACTIONS
                          /// ACTIONS
                          const SizedBox(height: 10),

                          /// MESSAGE
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton(
                              onPressed: () async {
                                if (currentUser == null) return;

                                final chatId =
                                    await ChatService.getOrCreateChat(
                                  workerId: workerId,
                                  employerId: currentUser.uid,
                                  jobId: jobId,
                                );

                                if (!context.mounted) return;

                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ChatScreen(chatId: chatId),
                                  ),
                                );
                              },
                              child: const Text("Message"),
                            ),
                          ),

                          const SizedBox(height: 10),

                          if (status == "pending" ||
                              status == "negotiation" ||
                              status == "offer_sent")
                            Column(
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: ElevatedButton(
                                        onPressed: () {
                                          acceptApplication(
                                              doc.id, data, context);
                                        },
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.green,
                                        ),
                                        child: const Text("Accept"),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: OutlinedButton(
                                        onPressed: () {
                                          updateStatus(doc.id, "rejected");
                                        },
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: Colors.red,
                                          side: const BorderSide(
                                              color: Colors.red),
                                        ),
                                        child: const Text("Reject"),
                                      ),
                                    ),
                                  ],
                                ),

                                const SizedBox(height: 8),

                                /// 🔥 NEGOTIATION
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton(
                                    onPressed: () async {
                                      await updateStatus(doc.id, "negotiation");

                                      if (currentUser == null) return;

                                      final chatId =
                                          await ChatService.getOrCreateChat(
                                        workerId: workerId,
                                        employerId: currentUser.uid,
                                        jobId: jobId,
                                      );

                                      if (!context.mounted) return;

                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              ChatScreen(chatId: chatId),
                                        ),
                                      );
                                    },
                                    child: const Text("Negotiation"),
                                  ),
                                ),

                                const SizedBox(height: 8),

                                /// 🔥 SEND OFFER
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton(
                                    onPressed: status == "negotiation"
                                        ? () {
                                            showOfferDialog(context, doc.id);
                                          }
                                        : null,
                                    child: const Text("Send offer"),
                                  ),
                                ),
                                if (status == "offer_sent") ...[
                                  const SizedBox(height: 8),
                                  SizedBox(
                                    width: double.infinity,
                                    child: ElevatedButton(
                                      onPressed: () {
                                        updateStatus(doc.id, "accepted");
                                      },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.green,
                                      ),
                                      child: const Text("Confirm hire"),
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 10),
                              ],
                            ),
                          const SizedBox(height: 10),
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

  Future<void> acceptApplication(
    String applicationId,
    Map<String, dynamic> data,
    BuildContext context,
  ) async {
    try {
      /// 🔥 ОБНОВЛЯЕМ APPLICATION
      await FirebaseFirestore.instance
          .collection("applications")
          .doc(applicationId)
          .update({
        "status": "accepted",
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Application accepted")),
      );
    } catch (e) {
      final message = e.toString();

      if (message.contains("NOT_ENOUGH_SPOTS")) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Not enough spots")),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Something went wrong")),
        );
      }
    }
  }

  Future<void> updateMemberStatus(
    String applicationId,
    String userId,
    String status,
  ) async {
    final appRef = FirebaseFirestore.instance
        .collection("applications")
        .doc(applicationId);

    final jobRef = FirebaseFirestore.instance.collection("jobs").doc(jobId);

    /// 🔥 1. обновляем статус участника
    await appRef.update({
      "membersStatus.$userId": status,
    });

    /// 🔥 2. получаем свежие данные
    final appSnap = await appRef.get();
    final appData = appSnap.data() as Map<String, dynamic>;

    final membersStatus =
        Map<String, dynamic>.from(appData["membersStatus"] ?? {});

    final values = membersStatus.values.toList();

    /// 🔥 4. обновляем job (позиции)
    if (status == "accepted") {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final jobSnap = await transaction.get(jobRef);

        final jobData = jobSnap.data() as Map<String, dynamic>;

        final filled = jobData["filledPositions"] ?? 0;
        final positions = jobData["positions"] ?? 1;

        if (filled >= positions) {
          throw Exception("NO_SPOTS_LEFT");
        }

        transaction.update(jobRef, {
          "filledPositions": filled + 1,
        });
      });
    }

    /// 🔥 5. пересчёт общего статуса заявки
    String newStatus = "pending";

    if (values.every((s) => s == "accepted")) {
      newStatus = "accepted";
    } else if (values.every((s) => s == "rejected")) {
      newStatus = "rejected";
    }

    await appRef.update({
      "status": newStatus,
    });
  }

  Future<void> undoMemberStatus(
    String applicationId,
    String userId,
  ) async {
    final appRef = FirebaseFirestore.instance
        .collection("applications")
        .doc(applicationId);

    final jobRef = FirebaseFirestore.instance.collection("jobs").doc(jobId);

    /// 1. получаем текущие данные
    final appSnap = await appRef.get();
    final appData = appSnap.data() as Map<String, dynamic>;

    final membersStatus =
        Map<String, dynamic>.from(appData["membersStatus"] ?? {});

    final currentStatus = membersStatus[userId];

    /// ❗ если не accepted — ничего не делаем
    if (currentStatus != "accepted") return;

    /// 2. откатываем статус участника
    await appRef.update({
      "membersStatus.$userId": "pending",
    });

    /// 3. уменьшаем позиции
    await FirebaseFirestore.instance.runTransaction((transaction) async {
      final jobSnap = await transaction.get(jobRef);

      final jobData = jobSnap.data() as Map<String, dynamic>;

      final filled = jobData["filledPositions"] ?? 0;

      if (filled > 0) {
        transaction.update(jobRef, {
          "filledPositions": filled - 1,
        });
      }
    });

    /// 4. пересчитываем статус заявки
    final updatedSnap = await appRef.get();
    final updatedData = updatedSnap.data() as Map<String, dynamic>;

    final updatedStatuses =
        Map<String, dynamic>.from(updatedData["membersStatus"] ?? {});

    final values = updatedStatuses.values.toList();

    String newStatus = "pending";

    if (values.every((s) => s == "accepted")) {
      newStatus = "accepted";
    } else if (values.every((s) => s == "rejected")) {
      newStatus = "rejected";
    }

    await appRef.update({
      "status": newStatus,
    });
  }

  Future<void> updateStatus(
    String applicationId,
    String status,
  ) async {
    await FirebaseFirestore.instance
        .collection("applications")
        .doc(applicationId)
        .update({
      "status": status,
    });
  }
}

Future<void> showOfferDialog(BuildContext context, String applicationId) async {
  final rateController = TextEditingController();
  final dateController = TextEditingController();
  final messageController = TextEditingController();

  await showDialog(
    context: context,
    builder: (_) {
      return AlertDialog(
        title: const Text("Send Offer"),
        content: SingleChildScrollView(
          child: Column(
            children: [
              TextField(
                controller: rateController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: "Rate (£/h)"),
              ),
              TextField(
                controller: dateController,
                decoration: const InputDecoration(labelText: "Start date"),
              ),
              TextField(
                controller: messageController,
                decoration: const InputDecoration(labelText: "Message"),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              await sendOffer(
                applicationId,
                rateController.text,
                dateController.text,
                messageController.text,
              );

              Navigator.pop(context);
            },
            child: const Text("Send"),
          ),
        ],
      );
    },
  );
}

Future<void> sendOffer(
  String applicationId,
  String rate,
  String date,
  String message,
) async {
  await FirebaseFirestore.instance
      .collection("applications")
      .doc(applicationId)
      .update({
    "status": "offer_sent",
    "offer": {
      "rate": rate,
      "startDate": date,
      "message": message,
      "createdAt": FieldValue.serverTimestamp(),
    }
  });
}
