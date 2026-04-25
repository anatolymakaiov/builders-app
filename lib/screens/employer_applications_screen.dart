import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'employer_profile_screen.dart';
import 'team_details_screen.dart';
import 'applicants_screen.dart';
import 'application_details_screen.dart';

class EmployerApplicationsScreen extends StatefulWidget {
  const EmployerApplicationsScreen({super.key});

  @override
  State<EmployerApplicationsScreen> createState() =>
      _EmployerApplicationsScreenState();
}

class _EmployerApplicationsScreenState
    extends State<EmployerApplicationsScreen> {
  String selectedStatus = "all";
  Set<String> trades = {"all"};
  Set<String> sites = {"all"};
  String selectedTrade = "all";
  String selectedSite = "all";
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

  Future<void> updateStatus(String id, String status) async {
    await FirebaseFirestore.instance
        .collection("applications")
        .doc(id)
        .update({"status": status});
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
      appBar: AppBar(title: const Text("Applications")),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                /// STATUS
                Expanded(
                  child: DropdownButton<String>(
                    value: selectedStatus,
                    isExpanded: true,
                    items: [
                      "all",
                      "pending",
                      "negotiation",
                      "offer_sent",
                      "rejected",
                      "offer_accepted"
                    ]
                        .map((e) => DropdownMenuItem(
                              value: e,
                              child: Text(e.toUpperCase()),
                            ))
                        .toList(),
                    onChanged: (value) {
                      setState(() {
                        selectedStatus = value!;
                      });
                    },
                  ),
                ),

                const SizedBox(width: 8),

                /// TRADE
                Expanded(
                  child: DropdownButton<String>(
                    value: selectedTrade,
                    isExpanded: true,
                    items: trades
                        .map((e) => DropdownMenuItem(
                              value: e,
                              child: Text(e),
                            ))
                        .toList(),
                    onChanged: (value) {
                      setState(() {
                        selectedTrade = value!;
                      });
                    },
                  ),
                ),

                const SizedBox(width: 8),

                /// SITE
                Expanded(
                  child: DropdownButton<String>(
                    value: selectedSite,
                    isExpanded: true,
                    items: sites
                        .map((e) => DropdownMenuItem(
                              value: e,
                              child: Text(e),
                            ))
                        .toList(),
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
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection("applications")
                  .where("employerId", isEqualTo: employerId)
                  .orderBy("createdAt", descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final allApps = snapshot.data!.docs;

                trades = {"all"};
                sites = {"all"};

                for (var doc in allApps) {
                  final data = doc.data() as Map<String, dynamic>;

                  final trade = (data["jobTrade"] ?? "").toString().trim();
                  final site = (data["jobSite"] ?? "").toString().trim();

                  if (trade.isNotEmpty) {
                    trades.add(trade);
                  }

                  if (site.isNotEmpty) {
                    sites.add(site);
                  }
                }
                final apps = allApps.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;

                  final status = data["status"] ?? "pending";
                  final trade = (data["jobTrade"] ?? "").toString().trim();
                  final site = (data["jobSite"] ?? "").toString().trim();

                  if (selectedStatus != "all" && status != selectedStatus) {
                    return false;
                  }

                  if (selectedTrade != "all" && trade != selectedTrade) {
                    return false;
                  }

                  if (selectedSite != "all" && site != selectedSite) {
                    return false;
                  }

                  return true;
                }).toList();
                if (apps.isEmpty) {
                  return const Center(child: Text("No applications yet"));
                }

                return ListView.builder(
                  itemCount: apps.length,
                  itemBuilder: (context, index) {
                    final doc = apps[index];
                    final data = doc.data() as Map<String, dynamic>;

                    final type = data["type"] ?? "single";
                    final workerName = data["workerName"] ?? "Worker";
                    final members = List<String>.from(data["members"] ?? []);
                    final jobTitle = data["jobTitle"] ?? "Job";
                    final status = data["status"] ?? "pending";
                    final Timestamp? createdAt = data["createdAt"];

                    final dateText = createdAt != null
                        ? DateTime.fromMillisecondsSinceEpoch(
                                createdAt.millisecondsSinceEpoch)
                            .toString()
                            .substring(0, 16)
                        : "";

                    return GestureDetector(
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
                      child: Container(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
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
                            Row(
                              children: [
                                CircleAvatar(
                                  child: Icon(
                                    type == "team"
                                        ? Icons.groups
                                        : Icons.person,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        type == "team"
                                            ? "Team application"
                                            : workerName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                      if (type == "team")
                                        Text(
                                          "${members.length} members",
                                          style: const TextStyle(
                                              color: Colors.grey),
                                        ),
                                    ],
                                  ),
                                ),
                                Text(
                                  status.toUpperCase(),
                                  style: TextStyle(
                                    color: getStatusColor(status),
                                    fontWeight: FontWeight.bold,
                                  ),
                                )
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(jobTitle),
                            if (dateText.isNotEmpty)
                              Text(
                                dateText,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
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
    );
  }
}
