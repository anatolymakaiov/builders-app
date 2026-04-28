import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/job.dart';
import 'job_details_screen.dart';
import '../theme/app_theme.dart';
import '../theme/stroyka_background.dart';

class SavedJobsScreen extends StatelessWidget {
  const SavedJobsScreen({super.key});

  String? get userId => FirebaseAuth.instance.currentUser?.uid;

  @override
  Widget build(BuildContext context) {
    if (userId == null) {
      return const Scaffold(
        body: Center(child: Text("Not logged in")),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Saved Jobs"),
      ),
      body: StroykaScreenBody(
        child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection("saved_jobs")
              .doc(userId)
              .collection("jobs")
              .snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final savedDocs = snapshot.data!.docs;

            if (savedDocs.isEmpty) {
              return const Center(
                child: Text("No saved jobs yet"),
              );
            }

            final jobIds = savedDocs.map((doc) => doc.id).toList();

            return FutureBuilder<List<Job?>>(
              future: Future.wait(
                jobIds.map((id) async {
                  final doc = await FirebaseFirestore.instance
                      .collection("jobs")
                      .doc(id)
                      .get();

                  if (!doc.exists) return null;

                  final data = doc.data() as Map<String, dynamic>;
                  return Job.fromFirestore(doc.id, data);
                }),
              ),
              builder: (context, jobsSnapshot) {
                if (!jobsSnapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final jobs = jobsSnapshot.data!
                    .where((job) => job != null)
                    .cast<Job>()
                    .toList();

                if (jobs.isEmpty) {
                  return const Center(
                    child: Text("No saved jobs found"),
                  );
                }

                return ListView.builder(
                  itemCount: jobs.length,
                  itemBuilder: (context, index) {
                    final job = jobs[index];

                    return Container(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 8,
                        ),
                        title: Text(
                          job.title,
                          style: const TextStyle(
                            color: AppColors.ink,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        subtitle: Text("${job.city} • ${job.rateText}"),
                        trailing: const Icon(Icons.favorite, color: Colors.red),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => JobDetailScreen(job: job),
                            ),
                          );
                        },
                      ),
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}
