import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/job.dart';
import '../theme/stroyka_background.dart';
import '../widgets/job_card.dart';

class SavedJobsScreen extends StatelessWidget {
  const SavedJobsScreen({super.key});

  String? get userId => FirebaseAuth.instance.currentUser?.uid;

  Future<List<Job>> loadSavedJobs(List<QueryDocumentSnapshot> savedDocs) async {
    final jobs = <Job>[];

    for (final savedDoc in savedDocs) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection("jobs")
            .doc(savedDoc.id)
            .get();

        if (!doc.exists) continue;

        final data = doc.data();
        if (data == null) continue;

        final job = Job.fromFirestore(doc.id, data);
        if (!job.isPubliclyVisible) continue;

        jobs.add(job);
      } on FirebaseException catch (error) {
        debugPrint(
          "SAVED JOB LOAD SKIPPED jobId=${savedDoc.id} error=${error.code}",
        );
      } catch (error) {
        debugPrint(
          "SAVED JOB LOAD SKIPPED jobId=${savedDoc.id} error=$error",
        );
      }
    }

    return jobs;
  }

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
            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              debugPrint("SAVED JOBS STREAM ERROR=${snapshot.error}");
              return const Center(
                child: Text("Could not load saved jobs"),
              );
            }

            final savedDocs = snapshot.data!.docs;

            if (savedDocs.isEmpty) {
              return const Center(
                child: Text("No saved jobs yet"),
              );
            }

            return FutureBuilder<List<Job>>(
              future: loadSavedJobs(savedDocs),
              builder: (context, jobsSnapshot) {
                if (jobsSnapshot.connectionState == ConnectionState.waiting &&
                    !jobsSnapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (jobsSnapshot.hasError) {
                  debugPrint("SAVED JOBS LOAD ERROR=${jobsSnapshot.error}");
                  return const Center(
                    child: Text("Could not load saved jobs"),
                  );
                }

                final jobs = jobsSnapshot.data ?? const <Job>[];

                if (jobs.isEmpty) {
                  return const Center(
                    child: Text("You have no saved jobs yet."),
                  );
                }

                return ListView.builder(
                  itemCount: jobs.length,
                  itemBuilder: (context, index) {
                    final job = jobs[index];

                    return JobCard(
                      job: job,
                      trailingAction: const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Icon(Icons.favorite, color: Colors.red),
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
