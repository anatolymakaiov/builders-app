import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/job.dart';
import 'job_details_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'edit_profile_screen.dart';
import '../widgets/phone_link.dart';
import '../theme/app_theme.dart';
import '../theme/stroyka_background.dart';

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
                  builder: (_) => const ProfileScreen(),
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
          final headerImage =
              (data["profileHeaderImage"] ?? data["headerImage"])?.toString();
          final photos = List<String>.from(data["companyPhotos"] ?? []);

          return DefaultTabController(
            length: 4,
            child: StroykaScreenBody(
              child: Column(
                children: [
                  StroykaSurface(
                    margin: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                    padding: EdgeInsets.zero,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        decoration: BoxDecoration(
                          image: headerImage != null && headerImage.isNotEmpty
                              ? DecorationImage(
                                  image: NetworkImage(headerImage),
                                  fit: BoxFit.cover,
                                  opacity: 0.30,
                                )
                              : null,
                        ),
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                          color: Colors.white.withValues(
                            alpha: headerImage != null && headerImage.isNotEmpty
                                ? 0.58
                                : 0,
                          ),
                          child: Column(
                            children: [
                              CircleAvatar(
                                radius: 42,
                                backgroundColor: Colors.grey.shade300,
                                backgroundImage:
                                    logo is String ? NetworkImage(logo) : null,
                                child: logo == null
                                    ? const Icon(Icons.business, size: 34)
                                    : null,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                name,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 25,
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.ink,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  StroykaSurface(
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                    padding: const EdgeInsets.all(4),
                    borderRadius: BorderRadius.circular(999),
                    child: const TabBar(
                      dividerColor: Colors.transparent,
                      indicator: BoxDecoration(
                        color: AppColors.green,
                        borderRadius: BorderRadius.all(Radius.circular(999)),
                      ),
                      indicatorSize: TabBarIndicatorSize.tab,
                      labelColor: Colors.white,
                      unselectedLabelColor: AppColors.ink,
                      labelStyle: TextStyle(fontWeight: FontWeight.w800),
                      tabs: [
                        Tab(text: "Info"),
                        Tab(text: "Contacts"),
                        Tab(text: "Vacancies"),
                        Tab(text: "Photos"),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: TabBarView(
                      children: [
                        ListView(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
                          children: [
                            StroykaSurface(
                              padding: const EdgeInsets.all(18),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    "About company",
                                    style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    description.isEmpty
                                        ? "No company description yet"
                                        : description,
                                  ),
                                  if (address.isNotEmpty) ...[
                                    const SizedBox(height: 18),
                                    Row(
                                      children: [
                                        const Icon(Icons.location_on),
                                        const SizedBox(width: 8),
                                        Expanded(child: Text(address)),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                        ListView(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
                          children: [
                            StroykaSurface(
                              padding: const EdgeInsets.all(18),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (phone.isNotEmpty) ...[
                                    PhoneLink(phone: phone),
                                    const SizedBox(height: 16),
                                  ],
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
                                  if (extraPhones.isNotEmpty) ...[
                                    ...extraPhones.map(
                                      (p) => Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 8),
                                        child:
                                            PhoneLink(phone: p, compact: true),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                  ],
                                  if (email.isNotEmpty) ...[
                                    Row(
                                      children: [
                                        const Icon(Icons.email),
                                        const SizedBox(width: 8),
                                        Expanded(child: Text(email)),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                  ],
                                  if (website.isNotEmpty) ...[
                                    Row(
                                      children: [
                                        const Icon(Icons.language),
                                        const SizedBox(width: 8),
                                        Expanded(child: Text(website)),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                  ],
                                  if (contacts.isEmpty &&
                                      phone.isEmpty &&
                                      email.isEmpty &&
                                      website.isEmpty)
                                    const Text("No contacts yet"),
                                  if (contacts.isNotEmpty) ...[
                                    const Text(
                                      "Team contacts",
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(height: 6),
                                    ...contacts.map(
                                      (c) => ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        title: Text(c["name"] ?? ""),
                                        subtitle: PhoneLink(
                                          phone: c["phone"]?.toString(),
                                          compact: true,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
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
                              return const Center(child: Text("No jobs yet"));
                            }

                            return ListView.builder(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
                              itemCount: jobs.length,
                              itemBuilder: (context, index) {
                                final job = jobs[index];

                                return StroykaSurface(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  padding: const EdgeInsets.all(14),
                                  child: InkWell(
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              JobDetailScreen(job: job),
                                        ),
                                      );
                                    },
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        if (job.photos.isNotEmpty)
                                          ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(8),
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
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: const Icon(Icons.work),
                                          ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                job.title,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 16,
                                                ),
                                              ),
                                              if (job.trade.isNotEmpty)
                                                Text(
                                                  job.trade,
                                                  style: const TextStyle(
                                                    color: Colors.grey,
                                                  ),
                                                ),
                                              Text(
                                                job.city,
                                                style: const TextStyle(
                                                  color: Colors.grey,
                                                ),
                                              ),
                                              if (job.duration.isNotEmpty)
                                                Text(
                                                  job.duration,
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.grey,
                                                  ),
                                                ),
                                              const SizedBox(height: 6),
                                              Wrap(
                                                spacing: 8,
                                                runSpacing: 6,
                                                children: [
                                                  Text(
                                                    job.workFormatText,
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                  if (job
                                                      .listRateText.isNotEmpty)
                                                    Text(
                                                      job.listRateText,
                                                      style: const TextStyle(
                                                        color:
                                                            AppColors.greenDark,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        const Icon(
                                          Icons.arrow_forward_ios,
                                          size: 16,
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                        ListView(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
                          children: [
                            if (photos.isEmpty)
                              const StroykaSurface(
                                padding: EdgeInsets.all(18),
                                child: Text("No company photos yet"),
                              )
                            else
                              StroykaSurface(
                                padding: const EdgeInsets.all(18),
                                child: GridView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: photos.length,
                                  gridDelegate:
                                      const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 2,
                                    crossAxisSpacing: 10,
                                    mainAxisSpacing: 10,
                                  ),
                                  itemBuilder: (_, i) => ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: Image.network(
                                      photos[i],
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
