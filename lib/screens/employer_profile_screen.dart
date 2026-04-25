import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/job.dart';
import 'job_details_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'edit_profile_screen.dart';

class EmployerProfileScreen extends StatelessWidget {
  final String userId;

  const EmployerProfileScreen({
    super.key,
    required this.userId,
  });

  Stream<List<Job>> getJobs() {
    return FirebaseFirestore.instance
        .collection("jobs")
        .where("ownerId", isEqualTo: userId)
        .orderBy("createdAt", descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        return Job.fromFirestore(doc.id, doc.data());
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Company Profile"),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ProfileScreen(),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
            },
          ),
        ],
      ),
      body: FutureBuilder<DocumentSnapshot>(
        future:
            FirebaseFirestore.instance.collection("users").doc(userId).get(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.data!.exists) {
            return const Center(child: Text("Company not found"));
          }

          final data = snapshot.data!.data() as Map<String, dynamic>;

          final name = data["companyName"] ?? "Company";
          final description = data["bio"] ?? "";
          final address = data["location"] ?? "";
          final phone = data["phone"] ?? "";
          final contactPerson = data["contactPerson"] ?? "";
          final extraPhones = List<String>.from(data["phones"] ?? []);
          final website = data["website"] ?? "";
          final email = data["email"] ?? "";

          final contacts = (data["contacts"] as List<dynamic>? ?? [])
              .map((e) => Map<String, dynamic>.from(e))
              .toList();

          final logo = data["photo"];
          final photos = List<String>.from(data["companyPhotos"] ?? []);

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                /// 🔥 HEADER
                Center(
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 50,
                        backgroundColor: Colors.grey.shade300,
                        backgroundImage:
                            logo is String ? NetworkImage(logo) : null,
                        child: logo == null
                            ? const Icon(Icons.business, size: 40)
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
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                /// 📝 DESCRIPTION
                if (description.isNotEmpty) ...[
                  const Text(
                    "About company",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(description),
                  const SizedBox(height: 16),
                ],

                /// 📍 ADDRESS
                if (address.isNotEmpty) ...[
                  Row(
                    children: [
                      const Icon(Icons.location_on),
                      const SizedBox(width: 8),
                      Expanded(child: Text(address)),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],

                /// 📞 PHONE
                if (phone.isNotEmpty) ...[
                  Row(
                    children: [
                      const Icon(Icons.phone),
                      const SizedBox(width: 8),
                      Text(phone),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
                if (phone.isNotEmpty)

                  /// 👤 CONTACT PERSON
                  if (contactPerson.isNotEmpty) ...[
                    Row(
                      children: [
                        const Icon(Icons.person),
                        const SizedBox(width: 8),
                        Text(contactPerson),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],

                /// 📞 EXTRA PHONES
                if (extraPhones.isNotEmpty) ...[
                  ...extraPhones.map((p) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            const Icon(Icons.phone, size: 16),
                            const SizedBox(width: 6),
                            Text(p),
                          ],
                        ),
                      )),
                  const SizedBox(height: 16),
                ],

                /// ✉️ EMAIL
                if (email.isNotEmpty) ...[
                  Row(
                    children: [
                      const Icon(Icons.email),
                      const SizedBox(width: 8),
                      Text(email),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],

                /// 🌐 WEBSITE
                if (website.isNotEmpty) ...[
                  Row(
                    children: [
                      const Icon(Icons.language),
                      const SizedBox(width: 8),
                      Text(website),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],

                /// 👥 CONTACTS
                if (contacts.isNotEmpty) ...[
                  const Text(
                    "Contacts",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  ...contacts.map((c) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(c["name"] ?? ""),
                        subtitle: Text(c["phone"] ?? ""),
                      )),
                  const SizedBox(height: 16),
                ],

                /// 🖼 PHOTOS
                if (photos.isNotEmpty) ...[
                  const Text(
                    "Gallery",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 120,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: photos.length,
                      itemBuilder: (_, i) => Container(
                        margin: const EdgeInsets.only(right: 8),
                        width: 120,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          image: DecorationImage(
                            image: NetworkImage(photos[i]),
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                const SizedBox(height: 30),

                /// 🔥 JOBS
                const Text(
                  "Jobs from this company",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 12),

                StreamBuilder<List<Job>>(
                  stream: getJobs(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(
                        child: CircularProgressIndicator(),
                      );
                    }

                    final jobs = snapshot.data!;

                    if (jobs.isEmpty) {
                      return const Text("No jobs yet");
                    }

                    return Column(
                      children: jobs.map((job) {
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
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                /// 📸 PHOTO
                                if (job.photos.isNotEmpty)
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.network(
                                      job.photos.first,
                                      width: 70,
                                      height: 70,
                                      fit: BoxFit.cover,
                                    ),
                                  )
                                else
                                  Container(
                                    width: 70,
                                    height: 70,
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade300,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(Icons.work),
                                  ),

                                const SizedBox(width: 12),

                                /// 🧾 INFO
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      /// TITLE
                                      Text(
                                        job.title,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),

                                      const SizedBox(height: 4),

                                      /// TRADE
                                      if (job.trade.isNotEmpty)
                                        Text(
                                          job.trade,
                                          style: const TextStyle(
                                            color: Colors.grey,
                                          ),
                                        ),

                                      const SizedBox(height: 4),

                                      /// LOCATION
                                      Text(
                                        "${job.city}",
                                        style: const TextStyle(
                                          color: Colors.grey,
                                        ),
                                      ),

                                      const SizedBox(height: 6),

                                      /// 🔥 DURATION
                                      if (job.duration.isNotEmpty)
                                        Text(
                                          "⏱ ${job.duration}",
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey,
                                          ),
                                        ),

                                      const SizedBox(height: 6),

                                      /// RATE
                                      Text(
                                        job.rateText,
                                        style: const TextStyle(
                                          color: Colors.green,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                const Icon(Icons.arrow_forward_ios, size: 16),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),

                const SizedBox(height: 30),
              ],
            ),
          );
        },
      ),
    );
  }
}
