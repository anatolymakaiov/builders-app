import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'employer_profile_screen.dart';
import 'team_details_screen.dart';

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

    final workerId = data["workerId"] ?? data["userId"];
    final employerId = data["employerId"];
    final jobId = data["jobId"];

    if (workerId == null || employerId == null || jobId == null) return;

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
        if (status == "accepted") {
          transaction.update(jobRef, {
            "filledPositions": filled + workersCount,
          });
        }
      });

      if (!context.mounted) return;

      Navigator.pop(context);
    } catch (e) {
      debugPrint("UPDATE STATUS ERROR: $e");

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Not enough positions")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final workerId = data["workerId"] ?? data["userId"];

    if (workerId == null) {
      return const Scaffold(
        body: Center(child: Text("Invalid application")),
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

                const SizedBox(height: 40),

                /// 🔥 BUTTONS
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => updateStatus(context, "accepted"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text("Accept"),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => updateStatus(context, "rejected"),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text("Reject"),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
