import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'team_details_screen.dart';

import 'edit_profile_screen.dart';
import '../services/chat_service.dart';
import 'chat_screen.dart';
import '../widgets/phone_link.dart';
import '../theme/app_theme.dart';
import '../theme/stroyka_background.dart';

class WorkerProfileScreen extends StatelessWidget {
  final String userId;
  final String? jobId;
  final String? employerId;

  const WorkerProfileScreen({
    super.key,
    required this.userId,
    this.jobId,
    this.employerId,
  });

  Widget buildInfoSection(String title, dynamic value) {
    final text = value?.toString().trim() ?? "";
    if (text.isEmpty) return const SizedBox();

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(text),
        ],
      ),
    );
  }

  Widget buildPhoneSection(dynamic value) {
    final phone = value?.toString().trim() ?? "";
    if (phone.isEmpty) return const SizedBox();

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Phone",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          PhoneLink(phone: phone),
        ],
      ),
    );
  }

  String textFromListOrString(dynamic value) {
    if (value == null) return "";
    if (value is List) {
      return value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .join("\n");
    }
    return value.toString();
  }

  String experienceDurationText(Map<String, dynamic> data) {
    final years = int.tryParse(data["experienceYears"]?.toString() ?? "") ?? 0;
    final months =
        int.tryParse(data["experienceMonths"]?.toString() ?? "") ?? 0;
    final parts = <String>[];

    if (years > 0) {
      parts.add("$years ${years == 1 ? "year" : "years"}");
    }
    if (months > 0) {
      parts.add("$months ${months == 1 ? "month" : "months"}");
    }

    return parts.join(" ");
  }

  List<Map<String, dynamic>> parseReferences(dynamic value) {
    if (value is! List) return [];

    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .where((item) => item.values.any(
              (field) => field != null && field.toString().trim().isNotEmpty,
            ))
        .toList();
  }

  List<String> teamMemberIds(dynamic value) {
    if (value is! List) return [];

    return value
        .map((item) {
          if (item is String) return item;
          if (item is Map) return item["userId"]?.toString();
          return null;
        })
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
  }

  Widget buildReferencesSection(dynamic value) {
    final references = parseReferences(value);
    if (references.isEmpty) return const SizedBox();

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "References",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ...references.map((reference) {
            final name = reference["name"]?.toString().trim() ?? "";
            final company = reference["company"]?.toString().trim() ?? "";
            final phone = reference["phone"]?.toString().trim() ?? "";
            final email = reference["email"]?.toString().trim() ?? "";

            return Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (name.isNotEmpty)
                    Text(
                      name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  if (company.isNotEmpty) Text(company),
                  if (phone.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    PhoneLink(phone: phone),
                  ],
                  if (email.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(email),
                  ],
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Future<List<String>> loadPortfolioUrls() async {
    final urls = <String>[];

    final nestedSnapshot = await FirebaseFirestore.instance
        .collection("users")
        .doc(userId)
        .collection("portfolio")
        .get();

    for (final doc in nestedSnapshot.docs) {
      final data = doc.data();
      final url = data["imageUrl"] ?? data["image"];
      if (url != null) urls.add(url.toString());
    }

    final flatSnapshot = await FirebaseFirestore.instance
        .collection("portfolio")
        .where("userId", isEqualTo: userId)
        .get();

    for (final doc in flatSnapshot.docs) {
      final data = doc.data();
      final url = data["imageUrl"] ?? data["image"];
      if (url != null && !urls.contains(url.toString())) {
        urls.add(url.toString());
      }
    }

    return urls;
  }

  Widget buildPortfolioGallery() {
    return FutureBuilder<List<String>>(
      future: loadPortfolioUrls(),
      builder: (context, snapshot) {
        final items = snapshot.data ?? [];
        if (items.isEmpty) return const SizedBox();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Work gallery",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 110,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final img = items[index];

                  return GestureDetector(
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (_) => Dialog(
                          child: Image.network(img, fit: BoxFit.contain),
                        ),
                      );
                    },
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(
                        img,
                        width: 110,
                        height: 110,
                        fit: BoxFit.cover,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 30),
          ],
        );
      },
    );
  }

  Future<void> leaveReview(BuildContext context) async {
    final employer = FirebaseAuth.instance.currentUser;
    if (employer == null) return;

    int rating = 5;
    final reviewController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text("Leave review"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (index) {
                      return IconButton(
                        icon: Icon(
                          Icons.star,
                          color: index < rating ? Colors.orange : Colors.grey,
                        ),
                        onPressed: () {
                          setDialogState(() {
                            rating = index + 1;
                          });
                        },
                      );
                    }),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: reviewController,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: "Review",
                      hintText: "Quality of work, reliability, communication",
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text("Submit"),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != true) {
      reviewController.dispose();
      return;
    }

    final employerSnap = await FirebaseFirestore.instance
        .collection("users")
        .doc(employer.uid)
        .get();
    final employerData = employerSnap.data();

    await FirebaseFirestore.instance
        .collection("users")
        .doc(userId)
        .collection("reviews")
        .add({
      "employerId": employer.uid,
      "employerName": employerData?["companyName"] ??
          employerData?["name"] ??
          employer.email ??
          "Employer",
      "rating": rating,
      "review": reviewController.text.trim(),
      "createdAt": FieldValue.serverTimestamp(),
      if (jobId != null) "jobId": jobId,
    });

    final reviewsSnapshot = await FirebaseFirestore.instance
        .collection("users")
        .doc(userId)
        .collection("reviews")
        .get();
    var total = 0.0;
    for (final doc in reviewsSnapshot.docs) {
      total += (doc.data()["rating"] ?? 0).toDouble();
    }

    final count = reviewsSnapshot.docs.length;
    await FirebaseFirestore.instance.collection("users").doc(userId).set({
      "rating": count == 0 ? 0 : total / count,
      "reviewsCount": count,
    }, SetOptions(merge: true));

    reviewController.dispose();

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Review saved")),
    );
  }

  Widget buildReviewsSection(bool canReview) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection("users")
          .doc(userId)
          .collection("reviews")
          .orderBy("createdAt", descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? [];

        return Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      "Employer reviews",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  if (canReview)
                    TextButton.icon(
                      onPressed: () => leaveReview(context),
                      icon: const Icon(Icons.rate_review),
                      label: const Text("Add review"),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (!snapshot.hasData)
                const LinearProgressIndicator()
              else if (docs.isEmpty)
                const Text("No reviews yet")
              else
                ...docs.map((doc) {
                  final review = doc.data() as Map<String, dynamic>;
                  final rating = review["rating"] ?? 0;
                  final text = review["review"]?.toString().trim() ?? "";
                  final employerName =
                      review["employerName"]?.toString() ?? "Employer";

                  return Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              employerName,
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(width: 8),
                            const Icon(Icons.star,
                                color: Colors.orange, size: 18),
                            Text(rating.toString()),
                          ],
                        ),
                        if (text.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(text),
                        ],
                      ],
                    ),
                  );
                }),
            ],
          ),
        );
      },
    );
  }

  Widget buildWorkerTeamsSection(BuildContext context, bool isMyProfile) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection("teams").snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data!.docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return teamMemberIds(data["members"]).contains(userId) ||
              data["ownerId"] == userId;
        }).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isMyProfile) ...[
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 55,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await showCreateTeamDialog(context, userId);
                  },
                  icon: const Icon(Icons.group_add),
                  label: const Text(
                    "Create team",
                    style: TextStyle(fontSize: 16),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 20),
            const Text(
              "Worker Teams",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 10),
            if (docs.isEmpty)
              const Text("No worker teams yet")
            else
              ...docs.map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final name = data["name"] ?? "Team";
                final members = teamMemberIds(data["members"]);
                final avatarUrl = data["avatarUrl"] ?? data["photo"];
                final description = data["description"]?.toString().trim();

                return GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => TeamDetailsScreen(
                          teamId: doc.id,
                          teamData: data,
                        ),
                      ),
                    );
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: Colors.grey.shade300,
                          backgroundImage: avatarUrl is String
                              ? NetworkImage(avatarUrl)
                              : null,
                          child: avatarUrl is String
                              ? null
                              : const Icon(Icons.groups),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name.toString(),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (description != null && description.isNotEmpty)
                                Text(
                                  description,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                        ),
                        Text("${members.length} members"),
                        const SizedBox(width: 6),
                        const Icon(Icons.arrow_forward_ios, size: 14),
                      ],
                    ),
                  ),
                );
              }),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    final isMyProfile = currentUser?.uid == userId;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Worker Profile"),
        actions: [
          if (isMyProfile) ...[
            /// ✏️ EDIT
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

            /// 🚪 LOGOUT
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () async {
                await FirebaseAuth.instance.signOut();
              },
            ),
          ],
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: () async {
          final userSnap = await FirebaseFirestore.instance
              .collection("users")
              .doc(userId)
              .get();

          final userData = userSnap.data() as Map<String, dynamic>;

          String? applicationId;
          String status = "pending";

          if (jobId != null && employerId != null) {
            final appQuery = await FirebaseFirestore.instance
                .collection("applications")
                .where("jobId", isEqualTo: jobId)
                .where("workerId", isEqualTo: userId)
                .limit(1)
                .get();

            if (appQuery.docs.isNotEmpty) {
              final appDoc = appQuery.docs.first;
              applicationId = appDoc.id;
              status = appDoc["status"] ?? "pending";
            }
          }

          String? currentRole;
          if (currentUser != null && !isMyProfile) {
            final currentSnap = await FirebaseFirestore.instance
                .collection("users")
                .doc(currentUser.uid)
                .get();
            currentRole = currentSnap.data()?["role"]?.toString();
          }

          return {
            "user": userData,
            "applicationId": applicationId,
            "status": status,
            "currentRole": currentRole,
          };
        }(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final result = snapshot.data!;
          final data = result["user"] as Map<String, dynamic>;
          final String? applicationId = result["applicationId"];
          final String status = result["status"];
          final String? currentRole = result["currentRole"];
          final offerRate = result["offerRate"];
          final offerNote = result["offerNote"];
          final name = data["name"] ?? "Worker";
          final trade = data["trade"] ?? "";
          final bio = data["bio"] ?? "";
          final location = data["location"] ?? "";
          final photo = data["photo"];
          final headerImage =
              (data["profileHeaderImage"] ?? data["headerImage"])?.toString();
          final phone = data["phone"];
          final experience = data["experience"];
          final experienceDuration = experienceDurationText(data);
          final permits = data["permits"];
          final qualifications = data["qualifications"];
          final certifications = textFromListOrString(
              data["certificationsText"] ?? data["certifications"]);
          final education = data["education"];
          final previousWork = data["previousWork"];
          final references = data["references"];

          final rating = (data["rating"] ?? 0).toDouble();
          final reviews = data["reviewsCount"] ?? 0;

          return DefaultTabController(
            length: 3,
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
                                backgroundImage: photo is String
                                    ? NetworkImage(photo)
                                    : null,
                                child: photo == null
                                    ? const Icon(Icons.person, size: 34)
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
                              if (trade.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 3),
                                  child: Text(
                                    trade,
                                    style: const TextStyle(
                                      color: AppColors.muted,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              if (rating > 0)
                                Padding(
                                  padding: const EdgeInsets.only(top: 5),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.star,
                                          color: Colors.amber, size: 20),
                                      const SizedBox(width: 4),
                                      Text("$rating ($reviews reviews)"),
                                    ],
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
                                  buildInfoSection("Location", location),
                                  buildInfoSection("About", bio),
                                  buildInfoSection(
                                      "Work experience", experienceDuration),
                                  buildInfoSection(
                                      "Experience details", experience),
                                  buildInfoSection(
                                      "Permits / licences", permits),
                                  buildInfoSection(
                                      "Qualifications", qualifications),
                                  buildInfoSection(
                                      "Certifications", certifications),
                                  buildInfoSection(
                                      "Education (optional)", education),
                                  buildInfoSection(
                                      "Previous work", previousWork),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            StroykaSurface(
                              padding: const EdgeInsets.all(18),
                              child: buildReviewsSection(
                                  !isMyProfile && currentRole == "employer"),
                            ),
                            const SizedBox(height: 12),
                            StroykaSurface(
                              padding: const EdgeInsets.all(18),
                              child:
                                  buildWorkerTeamsSection(context, isMyProfile),
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
                                  buildPhoneSection(phone),
                                  buildReferencesSection(references),
                                  if (employerId != null && jobId != null)
                                    SizedBox(
                                      width: double.infinity,
                                      height: 55,
                                      child: ElevatedButton(
                                        onPressed: () async {
                                          final chatId =
                                              await ChatService.getOrCreateChat(
                                            workerId: userId,
                                            employerId: employerId!,
                                            jobId: jobId!,
                                          );

                                          if (!context.mounted) return;

                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  ChatScreen(chatId: chatId),
                                            ),
                                          );
                                        },
                                        child: const Text("Message worker"),
                                      ),
                                    ),
                                  if (status == "offer_sent") ...[
                                    const SizedBox(height: 12),
                                    Container(
                                      padding: const EdgeInsets.all(14),
                                      decoration: BoxDecoration(
                                        color: AppColors.green
                                            .withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            "Offer",
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          if (offerRate != null)
                                            Text("Rate: £$offerRate/hour"),
                                          if (offerNote != null &&
                                              offerNote.toString().isNotEmpty)
                                            Text("Note: $offerNote"),
                                          if (!isMyProfile) ...[
                                            const SizedBox(height: 12),
                                            SizedBox(
                                              width: double.infinity,
                                              child: ElevatedButton(
                                                onPressed: () async {
                                                  await FirebaseFirestore
                                                      .instance
                                                      .collection(
                                                          "applications")
                                                      .doc(applicationId)
                                                      .update({
                                                    "status": "offer_accepted",
                                                  });

                                                  if (!context.mounted) return;

                                                  ScaffoldMessenger.of(context)
                                                      .showSnackBar(
                                                    const SnackBar(
                                                      content: Text(
                                                          "Offer accepted"),
                                                    ),
                                                  );
                                                },
                                                child:
                                                    const Text("Accept offer"),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ],
                                  if (applicationId != null) ...[
                                    const SizedBox(height: 12),
                                    if (status == "offer_accepted") ...[
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: AppColors.green.withValues(
                                            alpha: 0.14,
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        child: const Text(
                                          "Worker hired",
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: AppColors.greenDark,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                    ],
                                    Row(
                                      children: [
                                        if (status != "offer_accepted")
                                          Expanded(
                                            child: OutlinedButton(
                                              onPressed: () async {
                                                await FirebaseFirestore.instance
                                                    .collection("applications")
                                                    .doc(applicationId)
                                                    .update({
                                                  "status": "rejected",
                                                });
                                              },
                                              child: const Text("Reject"),
                                            ),
                                          ),
                                        if (status != "offer_accepted")
                                          const SizedBox(width: 10),
                                        if (status == "pending")
                                          Expanded(
                                            child: OutlinedButton(
                                              onPressed: () async {
                                                await FirebaseFirestore.instance
                                                    .collection("applications")
                                                    .doc(applicationId)
                                                    .update({
                                                  "status": "negotiation",
                                                });
                                              },
                                              child: const Text("Negotiation"),
                                            ),
                                          ),
                                        if (status == "pending")
                                          const SizedBox(width: 10),
                                        if (status == "pending" ||
                                            status == "negotiation")
                                          Expanded(
                                            child: ElevatedButton(
                                              onPressed: () async {
                                                final rateController =
                                                    TextEditingController();
                                                final noteController =
                                                    TextEditingController();

                                                final result =
                                                    await showDialog<bool>(
                                                  context: context,
                                                  builder: (_) => AlertDialog(
                                                    title: const Text(
                                                        "Send Offer"),
                                                    content: Column(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        TextField(
                                                          controller:
                                                              rateController,
                                                          keyboardType:
                                                              TextInputType
                                                                  .number,
                                                          decoration:
                                                              const InputDecoration(
                                                            labelText:
                                                                "Rate (£/hour)",
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                            height: 10),
                                                        TextField(
                                                          controller:
                                                              noteController,
                                                          decoration:
                                                              const InputDecoration(
                                                            labelText:
                                                                "Message (optional)",
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    actions: [
                                                      TextButton(
                                                        onPressed: () =>
                                                            Navigator.pop(
                                                                context, false),
                                                        child: const Text(
                                                            "Cancel"),
                                                      ),
                                                      ElevatedButton(
                                                        onPressed: () =>
                                                            Navigator.pop(
                                                                context, true),
                                                        child:
                                                            const Text("Send"),
                                                      ),
                                                    ],
                                                  ),
                                                );

                                                if (result != true) return;

                                                final rate = double.tryParse(
                                                  rateController.text.trim(),
                                                );

                                                await FirebaseFirestore.instance
                                                    .collection("applications")
                                                    .doc(applicationId)
                                                    .update({
                                                  "status": "offer_sent",
                                                  "offerRate": rate,
                                                  "offerNote": noteController
                                                      .text
                                                      .trim(),
                                                  "offerCreatedAt": FieldValue
                                                      .serverTimestamp(),
                                                });
                                              },
                                              child: const Text("Offer"),
                                            ),
                                          ),
                                        if (status == "offer_sent")
                                          Expanded(
                                            child: ElevatedButton(
                                              onPressed: () async {
                                                await FirebaseFirestore.instance
                                                    .collection("applications")
                                                    .doc(applicationId)
                                                    .update({
                                                  "status": "offer_accepted",
                                                });
                                              },
                                              child: const Text("Hire"),
                                            ),
                                          ),
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
                              child: buildPortfolioGallery(),
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

/// 🔥 CREATE TEAM DIALOG
Future<void> showCreateTeamDialog(
  BuildContext context,
  String userId,
) async {
  final controller = TextEditingController();
  final descriptionController = TextEditingController();
  final picker = ImagePicker();
  XFile? pickedAvatar;
  String? previewPath;

  await showDialog(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (context, setDialogState) {
        return AlertDialog(
          title: const Text("Create team"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: () async {
                  final picked =
                      await picker.pickImage(source: ImageSource.gallery);
                  if (picked == null) return;

                  setDialogState(() {
                    pickedAvatar = picked;
                    previewPath = picked.path;
                  });
                },
                child: CircleAvatar(
                  radius: 38,
                  backgroundColor: Colors.grey.shade300,
                  backgroundImage: previewPath != null
                      ? FileImage(File(previewPath!))
                      : null,
                  child: previewPath == null
                      ? const Icon(Icons.add_a_photo, size: 28)
                      : null,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: "Team name",
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descriptionController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: "Team description",
                  hintText: "Trades, skills, availability, typical projects",
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = controller.text.trim();
                if (name.isEmpty) return;

                String? avatarUrl;

                if (pickedAvatar != null) {
                  final ref = FirebaseStorage.instance.ref().child(
                      "team_avatars/${userId}_${DateTime.now().millisecondsSinceEpoch}.jpg");

                  await ref.putFile(File(pickedAvatar!.path));
                  avatarUrl = await ref.getDownloadURL();
                }

                await FirebaseFirestore.instance.collection("teams").add({
                  "name": name,
                  "description": descriptionController.text.trim(),
                  "ownerId": userId,
                  "members": [userId],
                  "memberStatuses": {userId: "active"},
                  if (avatarUrl != null) "avatarUrl": avatarUrl,
                  if (avatarUrl != null) "photo": avatarUrl,
                  "createdAt": FieldValue.serverTimestamp(),
                  "updatedAt": FieldValue.serverTimestamp(),
                });

                if (!context.mounted) return;

                Navigator.pop(context);

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Team created")),
                );
              },
              child: const Text("Create"),
            ),
          ],
        );
      },
    ),
  );

  controller.dispose();
  descriptionController.dispose();
}
