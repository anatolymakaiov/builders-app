import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/job.dart';
import 'job_details_screen.dart';

class EmployerDashboardScreen extends StatefulWidget {
  const EmployerDashboardScreen({super.key});

  @override
  State<EmployerDashboardScreen> createState() =>
      _EmployerDashboardScreenState();
}

class _EmployerDashboardScreenState extends State<EmployerDashboardScreen> {
  String selectedTrade = "All";
  String selectedSite = "All";

  List<String> trades = ["All"];
  List<String> sites = ["All"];
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
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
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

                final tradeSet = <String>{};
                final siteSet = <String>{};

                for (var job in jobs) {
                  if (job.trade.isNotEmpty) tradeSet.add(job.trade);
                  if (job.site.isNotEmpty) siteSet.add(job.site);
                }

                final tradeList = ["All", ...tradeSet];
                final siteList = ["All", ...siteSet];

                final filteredJobs = jobs.where((job) {
                  if (selectedTrade != "All" &&
                      job.trade.toLowerCase().trim() !=
                          selectedTrade.toLowerCase().trim()) {
                    return false;
                  }

                  if (selectedSite != "All" &&
                      job.site.toLowerCase().trim() !=
                          selectedSite.toLowerCase().trim()) {
                    return false;
                  }

                  return true;
                }).toList();

                return Column(
                  children: [
                    /// FILTERS
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Expanded(
                            child: DropdownButton<String>(
                              value: tradeList.contains(selectedTrade)
                                  ? selectedTrade
                                  : "All",
                              isExpanded: true,
                              items: tradeList.map((trade) {
                                return DropdownMenuItem(
                                  value: trade,
                                  child: Text(trade),
                                );
                              }).toList(),
                              onChanged: (value) {
                                setState(() {
                                  selectedTrade = value!;
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: DropdownButton<String>(
                              value: siteList.contains(selectedSite)
                                  ? selectedSite
                                  : "All",
                              isExpanded: true,
                              items: siteList.map((site) {
                                return DropdownMenuItem(
                                  value: site,
                                  child: Text(site),
                                );
                              }).toList(),
                              onChanged: (value) {
                                setState(() {
                                  selectedSite = value!;
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                    ),

                    /// LIST
                    Expanded(
                      child: ListView.builder(
                        itemCount: filteredJobs.length,
                        itemBuilder: (context, index) {
                          final job = filteredJobs[index];

                          return GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => JobDetailScreen(job: job),
                                ),
                              );
                            },
                            child: Container(
                              margin: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.05),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  )
                                ],
                              ),
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
                                    style: const TextStyle(
                                      color: Colors.grey,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text("${job.city} ${job.postcode}"),
                                  const SizedBox(height: 12),
                                  StreamBuilder<QuerySnapshot>(
                                    stream: FirebaseFirestore.instance
                                        .collection("applications")
                                        .where("jobId", isEqualTo: job.id)
                                        .snapshots(),
                                    builder: (context, snapshot) {
                                      if (!snapshot.hasData) {
                                        return const Text("Applications: ...");
                                      }

                                      final docs = snapshot.data!.docs;

                                      int pending = 0;
                                      int negotiation = 0;
                                      int offer = 0;
                                      int hired = 0;

                                      for (var doc in docs) {
                                        final status = (doc.data() as Map<
                                                String, dynamic>)["status"] ??
                                            "pending";

                                        if (status == "pending") pending++;
                                        if (status == "negotiation")
                                          negotiation++;
                                        if (status == "offer_sent") offer++;
                                        if (status == "offer_accepted") hired++;
                                      }

                                      return Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            "Applications: ${docs.length}",
                                            style: const TextStyle(
                                                fontWeight: FontWeight.bold),
                                          ),
                                          const SizedBox(height: 4),
                                          Text("New: $pending"),
                                          Text("Negotiation: $negotiation"),
                                          Text("Offer: $offer"),
                                          Text("Hired: $hired"),
                                        ],
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
