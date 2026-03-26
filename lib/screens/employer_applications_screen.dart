import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'application_details_screen.dart';

class EmployerApplicationsScreen extends StatelessWidget {
  const EmployerApplicationsScreen({super.key});

  Color getStatusColor(String status) {
    switch (status) {
      case "accepted":
        return Colors.green;
      case "rejected":
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Scaffold(
        body: Center(child: Text("Not logged in")),
      );
    }

    final employerId = user.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Applications"),
      ),

      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection("applications")
            .where("employerId", isEqualTo: employerId)
            .orderBy("createdAt", descending: true) // ✅ вернули сортировку
            .snapshots(),

        builder: (context, snapshot) {

          /// 🔄 LOADING
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          /// ❌ ERROR
          if (snapshot.hasError) {
            return Center(
              child: Text("Error: ${snapshot.error}"),
            );
          }

          final apps = snapshot.data?.docs ?? [];

          /// 📭 EMPTY
          if (apps.isEmpty) {
            return const Center(
              child: Text("No applications yet"),
            );
          }

          return ListView.builder(
            itemCount: apps.length,
            itemBuilder: (context, index) {

              final doc = apps[index];
              final data = doc.data() as Map<String, dynamic>;

              final status = data["status"] ?? "pending";
              final color = getStatusColor(status);

              /// ✅ НОРМАЛЬНЫЕ ДАННЫЕ (если есть)
              final workerName = data["workerName"];
              final jobTitle = data["jobTitle"];

              /// fallback (если старые данные)
              final workerId = data["workerId"] ?? "Unknown";
              final jobId = data["jobId"] ?? "";

              return Card(
                margin: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 8),
                child: ListTile(

                  /// 🔥 ИМЯ
                  title: Text(
                    workerName ?? "Worker: $workerId",
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  /// 🔥 JOB
                  subtitle: Text(
                    jobTitle ?? "Job ID: $jobId",
                  ),

                  /// 🔥 STATUS
                  trailing: Text(
                    status.toUpperCase(),
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ApplicationDetailsScreen(
                          applicationId: doc.id,
                          data: data,
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}