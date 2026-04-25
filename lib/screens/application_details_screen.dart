import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'employer_profile_screen.dart';
import 'team_details_screen.dart';
import 'chat_screen.dart';

class ApplicationDetailsScreen extends StatelessWidget {
  final String applicationId;
  final Map<String, dynamic> data;

  const ApplicationDetailsScreen({
    super.key,
    required this.applicationId,
    required this.data,
  });

  Future<void> updateStatus(BuildContext context, String status) async {
    final db = FirebaseFirestore.instance;

    final isTeam = (data["type"] ?? "single") == "team";

    final workerId = isTeam ? null : (data["workerId"] ?? data["userId"]);
    final employerId = data["employerId"];
    final jobId = data["jobId"];

    if (employerId == null || jobId == null) return;

    try {
      /// 🔥 получаем вакансию
      final jobRef = db.collection("jobs").doc(jobId);

      await db.runTransaction((transaction) async {
        final jobSnap = await transaction.get(jobRef);

        if (!jobSnap.exists) throw Exception("Job not found");

        final jobData = jobSnap.data() as Map<String, dynamic>;

        final positions = jobData["positions"] ?? 1;
        final filled = jobData["filledPositions"] ?? 0;

        /// 🔥 сколько людей в заявке
        final workersCount = data["workersCount"] ?? 1;

        /// ❌ если не хватает мест — стоп
        if (status == "accepted" && (filled + workersCount) > positions) {
          throw Exception("Not enough positions");
        }

        /// ✅ обновляем статус заявки
        transaction.update(
          db.collection("applications").doc(applicationId),
          {"status": status},
        );

        /// 🔥 если приняли — увеличиваем занятые места
        if (status == "offer_accepted") {
          transaction.update(jobRef, {
            "filledPositions": filled + workersCount,
          });
        }
      });

      if (!context.mounted) return;
    } catch (e) {
      debugPrint("UPDATE STATUS ERROR: $e");

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Not enough positions")),
      );
    }
  }

  Future<void> openChat(BuildContext context) async {
    final workerId = data["workerId"] ??
        data["userId"] ??
        (data["members"] != null && data["members"].isNotEmpty
            ? data["members"][0]
            : null);
    final employerId = data["employerId"];

    if (workerId == null || employerId == null) return;

    final existing = await FirebaseFirestore.instance
        .collection("chats")
        .where("workerId", isEqualTo: workerId)
        .where("employerId", isEqualTo: employerId)
        .limit(1)
        .get();

    String chatId;

    if (existing.docs.isNotEmpty) {
      chatId = existing.docs.first.id;
    } else {
      final doc = await FirebaseFirestore.instance.collection("chats").add({
        "workerId": workerId,
        "employerId": employerId,
        "participants": [workerId, employerId],
        "lastMessage": "",
        "lastMessageType": "text",
        "updatedAt": FieldValue.serverTimestamp(),
        "unreadCount_worker": 0,
        "unreadCount_employer": 0,
        "typing_worker": false,
        "typing_employer": false,
      });

      chatId = doc.id;
    }

    if (!context.mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(chatId: chatId),
      ),
    );
  }

  Future<void> openOfferDialog(BuildContext context) async {
    final rateController = TextEditingController();
    final dateController = TextEditingController();
    final messageController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Send Offer"),
          content: SingleChildScrollView(
            child: Column(
              children: [
                TextField(
                  controller: rateController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: "Rate (£/h)",
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: dateController,
                  decoration: const InputDecoration(
                    labelText: "Start date",
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: messageController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: "Message",
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () {
                if (rateController.text.isEmpty ||
                    dateController.text.isEmpty) {
                  return;
                }
                Navigator.pop(context, true);
              },
              child: const Text("Send"),
            ),
          ],
        );
      },
    );

    if (result != true) return;

    /// 🔥 СОХРАНЕНИЕ OFFER
    await FirebaseFirestore.instance
        .collection("applications")
        .doc(applicationId)
        .update({
      "status": "offer_sent",
      "offer": {
        "rate": rateController.text.trim(),
        "startDate": dateController.text.trim(),
        "message": messageController.text.trim(),
        "createdAt": FieldValue.serverTimestamp(),
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final Set<String> selectedMembers = {};
    final workerId = data["workerId"] ??
        data["userId"] ??
        (data["members"] != null && data["members"].isNotEmpty
            ? data["members"][0]
            : null);

    if (workerId == null) {
      return const Scaffold(
        body: Center(child: Text("No worker data")),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Application")),
      body: FutureBuilder<DocumentSnapshot>(
        future:
            FirebaseFirestore.instance.collection("users").doc(workerId).get(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.data!.exists) {
            return const Center(child: Text("User not found"));
          }

          final user = snapshot.data!.data() as Map<String, dynamic>;

          final name = user["name"] ?? "Worker";
          final trade = user["trade"] ?? "";
          final rate = user["rate"] != null ? "£${user["rate"]}/h" : "";
          final bio = user["bio"] ?? "";
          final location = user["location"] ?? "";
          final photo = user["photo"];

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                /// 👤 HEADER
                Center(
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 45,
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
                        Text(trade),
                      ],
                      if (rate.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          rate,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
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

                /// 📝 BIO
                if (bio.isNotEmpty) ...[
                  const Text(
                    "About worker",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(bio),
                  const SizedBox(height: 20),
                ],

                /// 🔍 VIEW PROFILE
                TextButton(
                  onPressed: () {
                    final type = data["type"] ?? "single";

                    if (type == "team") {
                      final teamId = data["teamId"];

                      if (teamId == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Team not found")),
                        );
                        return;
                      }

                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => TeamDetailsScreen(
                            teamId: teamId,
                            teamData: data,
                          ),
                        ),
                      );
                    } else {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              EmployerProfileScreen(userId: workerId),
                        ),
                      );
                    }
                  },
                  child: Text(
                    (data["type"] ?? "single") == "team"
                        ? "View team"
                        : "View full profile",
                  ),
                ),
                if ((data["type"] ?? "single") == "team" &&
                    data["members"] != null) ...[
                  const Text(
                    "Team members",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  ...List<String>.from(data["members"]).map((memberId) {
                    return FutureBuilder<DocumentSnapshot>(
                      future: FirebaseFirestore.instance
                          .collection("users")
                          .doc(memberId)
                          .get(),
                      builder: (context, snap) {
                        if (!snap.hasData) return const SizedBox();

                        final user = snap.data!.data() as Map<String, dynamic>;

                        return StatefulBuilder(
                          builder: (context, setLocalState) {
                            final isSelected =
                                selectedMembers.contains(memberId);

                            return ListTile(
                              leading: Checkbox(
                                value: isSelected,
                                onChanged: (v) {
                                  setLocalState(() {
                                    if (v == true) {
                                      selectedMembers.add(memberId);
                                    } else {
                                      selectedMembers.remove(memberId);
                                    }
                                  });
                                },
                              ),
                              title: Text(user["name"] ?? "Worker"),
                              subtitle: Text(user["trade"] ?? ""),
                            );
                          },
                        );
                      },
                    );
                  }).toList(),
                  const SizedBox(height: 20),
                ],
                const SizedBox(height: 40),

                /// 🔥 BUTTONS
                /// 🔥 ACTIONS (НОВАЯ ЛОГИКА)
                StreamBuilder<DocumentSnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection("applications")
                      .doc(applicationId)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return const SizedBox();

                    final liveData =
                        snapshot.data!.data() as Map<String, dynamic>;
                    final status = liveData["status"] ?? "pending";

                    final members =
                        List<String>.from(liveData["members"] ?? []);

                    return Column(
                      children: [
                        /// MESSAGE
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () => openChat(context),
                            child: const Text("Message worker"),
                          ),
                        ),

                        const SizedBox(height: 12),

                        /// =========================
                        /// PENDING
                        /// =========================
                        if (status == "pending") ...[
                          /// NEGOTIATION
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: () async {
                                if ((liveData["type"] ?? "single") == "team") {
                                  for (var memberId in selectedMembers) {
                                    await FirebaseFirestore.instance
                                        .collection("applications")
                                        .doc(applicationId)
                                        .update({
                                      "membersStatus.$memberId": "negotiation",
                                    });
                                  }
                                  await FirebaseFirestore.instance
                                      .collection("applications")
                                      .doc(applicationId)
                                      .update({
                                    "status": "negotiation",
                                  });
                                } else {
                                  await updateStatus(context, "negotiation");
                                }

                                final workerId = liveData["workerId"] ??
                                    (liveData["members"] != null
                                        ? liveData["members"][0]
                                        : null);

                                final employerId = liveData["employerId"];
                                final jobId = liveData["jobId"];

                                if (workerId == null ||
                                    employerId == null ||
                                    jobId == null) return;

                                final existing = await FirebaseFirestore
                                    .instance
                                    .collection("chats")
                                    .where("jobId", isEqualTo: jobId)
                                    .where("members", arrayContains: workerId)
                                    .get();

                                String chatId;

                                if (existing.docs.isNotEmpty) {
                                  chatId = existing.docs.first.id;
                                } else {
                                  final doc = await FirebaseFirestore.instance
                                      .collection("chats")
                                      .add({
                                    "jobId": jobId,
                                    "members": [workerId, employerId],
                                    "workerId": workerId,
                                    "employerId": employerId,
                                    "workerName": "Worker",
                                    "employerName": "Employer",
                                    "unreadCount_worker": 0,
                                    "unreadCount_employer": 0,
                                    "typing_worker": false,
                                    "typing_employer": false,
                                    "lastMessage": "",
                                    "lastMessageType": "text",
                                    "createdAt": FieldValue.serverTimestamp(),
                                    "updatedAt": FieldValue.serverTimestamp(),
                                  });

                                  chatId = doc.id;
                                }

                                if (context.mounted) {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          ChatScreen(chatId: chatId),
                                    ),
                                  );
                                }
                              },
                              child: const Text("Start negotiation"),
                            ),
                          ),

                          const SizedBox(height: 10),

                          /// MAKE OFFER
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: () => openOfferDialog(context),
                              child: const Text("Make offer"),
                            ),
                          ),

                          const SizedBox(height: 10),

                          /// REJECT
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton(
                              onPressed: () async {
                                if ((liveData["type"] ?? "single") == "team") {
                                  await FirebaseFirestore.instance
                                      .collection("applications")
                                      .doc(applicationId)
                                      .update({
                                    "status": "rejected",
                                  });
                                } else {
                                  await updateStatus(context, "rejected");
                                }
                              },
                              child: const Text("Reject"),
                            ),
                          ),
                        ],

                        /// =========================
                        /// NEGOTIATION
                        /// =========================
                        if (status == "negotiation") ...[
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: () => openOfferDialog(context),
                              child: const Text("Make offer"),
                            ),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton(
                              onPressed: () async {
                                if ((liveData["type"] ?? "single") == "team") {
                                  await FirebaseFirestore.instance
                                      .collection("applications")
                                      .doc(applicationId)
                                      .update({
                                    "status": "rejected",
                                  });
                                } else {
                                  await updateStatus(context, "rejected");
                                }
                              },
                              child: const Text("Reject"),
                            ),
                          ),
                        ],

                        /// =========================
                        /// OFFER SENT
                        /// =========================
                        if (status == "offer_sent") ...[
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton(
                              onPressed: () async {
                                await updateStatus(context, "negotiation");
                              },
                              child: const Text("Withdraw offer"),
                            ),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton(
                              onPressed: () async {
                                await FirebaseFirestore.instance
                                    .collection("applications")
                                    .doc(applicationId)
                                    .update({
                                  "status": "negotiation",
                                  "offer": FieldValue.delete(),
                                });
                              },
                              child: const Text("Reject"),
                            ),
                          ),
                        ],

                        /// =========================
                        /// HIRED
                        /// =========================
                        if (status == "offer_accepted") ...[
                          const SizedBox(height: 10),
                          const Text(
                            "Worker hired",
                            style: TextStyle(
                              color: Colors.green,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                )
              ],
            ),
          );
        },
      ),
    );
  }
}
