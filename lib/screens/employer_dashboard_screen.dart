import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/job.dart';
import 'job_details_screen.dart';
import 'applicants_screen.dart';
import 'review_worker_screen.dart';

class EmployerDashboardScreen extends StatelessWidget {
  const EmployerDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Scaffold(
        body: Center(child: Text("User not logged in")),
      );
    }

    final ownerId = user.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text("My Jobs"),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
            },
          )
        ],
      ),

      /// ❌ УБРАЛИ FAB ОТСЮДА

      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection("jobs")
            .where("ownerId", isEqualTo: ownerId)
            .orderBy("createdAt", descending: true)
            .snapshots(),
        builder: (context, snapshot) {

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData) {
            return const Center(child: Text("Error loading jobs"));
          }

          final jobs = snapshot.data!.docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return Job.fromFirestore(doc.id, data);
          }).toList();

          if (jobs.isEmpty) {
            return const Center(child: Text("You have no jobs yet"));
          }

          return ListView.builder(
            itemCount: jobs.length,
            itemBuilder: (context, index) {
              final job = jobs[index];

              return Card(
                margin: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [

                      Text(
                        job.title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 6),

                      Text(
                        job.trade,
                        style: const TextStyle(color: Colors.grey),
                      ),

                      const SizedBox(height: 6),

                      Text("${job.city} ${job.postcode}"),

                      const SizedBox(height: 12),

                      /// APPLICATION COUNT
                      StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection("applications")
                            .where("jobId", isEqualTo: job.id)
                            .snapshots(),
                        builder: (context, snapshot) {

                          if (!snapshot.hasData) {
                            return const Text("Applications: ...");
                          }

                          final count = snapshot.data!.docs.length;

                          return Text(
                            "Applications: $count",
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          );
                        },
                      ),

                      const SizedBox(height: 14),

                      /// 🔥 FIX OVERFLOW
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.end,
                        children: [

                          TextButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      ApplicantsScreen(jobId: job.id),
                                ),
                              );
                            },
                            child: const Text("Applicants"),
                          ),

                          ElevatedButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      JobDetailScreen(job: job),
                                ),
                              );
                            },
                            child: const Text("View job"),
                          ),

                          OutlinedButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      ReviewWorkerScreen(job: job),
                                ),
                              );
                            },
                            child: const Text("Complete"),
                          ),
                        ],
                      )

                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}