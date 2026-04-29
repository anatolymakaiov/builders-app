import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';

import 'portfolio_screen.dart';
import '../theme/stroyka_background.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final nameController = TextEditingController();
  final phoneController = TextEditingController();
  final nicknameController = TextEditingController();

  final tradeController = TextEditingController();
  final companyController = TextEditingController();

  final bioController = TextEditingController();
  final experienceController = TextEditingController();
  final experienceYearsController = TextEditingController();
  final experienceMonthsController = TextEditingController();
  final permitsController = TextEditingController();
  final qualificationsController = TextEditingController();
  final certificationsController = TextEditingController();
  final educationController = TextEditingController();
  final previousWorkController = TextEditingController();
  final rateController = TextEditingController();
  final locationController = TextEditingController();

  /// 🔥 NEW
  final websiteController = TextEditingController();
  final contactPersonController = TextEditingController();
  final companyGoalsController = TextEditingController();
  final companyAdvantagesController = TextEditingController();
  final companyClientsController = TextEditingController();
  final companyWhoWeAreController = TextEditingController();
  final companyHistoryController = TextEditingController();
  List<String> extraPhones = [];
  List<Map<String, String>> references = [];
  final picker = ImagePicker();

  String role = "worker";
  bool loading = false;

  double rating = 0;
  int reviewsCount = 0;

  String? photoUrl;
  String? headerImageUrl;
  File? headerImageFile;
  List<String> portfolio = [];

  String get userId => FirebaseAuth.instance.currentUser!.uid;

  @override
  void initState() {
    super.initState();
    loadProfile();
  }

  /// LOAD PROFILE
  Future<void> loadProfile() async {
    final userDoc =
        await FirebaseFirestore.instance.collection("users").doc(userId).get();

    if (!userDoc.exists) return;

    final data = userDoc.data()!;

    final portfolioUrls = await loadPortfolioUrls(userId);

    setState(() {
      role = data["role"] ?? "worker";

      nameController.text = data["name"] ?? "";
      phoneController.text = data["phone"] ?? "";
      nicknameController.text =
          data["nickname"] ?? data["username"] ?? data["nickName"] ?? "";

      tradeController.text = data["trade"] ?? "";
      companyController.text = data["companyName"] ?? "";

      bioController.text = data["bio"] ?? "";
      experienceController.text = data["experience"] ?? "";
      experienceYearsController.text =
          data["experienceYears"]?.toString() ?? "";
      experienceMonthsController.text =
          data["experienceMonths"]?.toString() ?? "";
      permitsController.text = data["permits"] ?? "";
      qualificationsController.text = data["qualifications"] ?? "";
      certificationsController.text = textFromListOrString(
        data["certificationsText"] ?? data["certifications"],
      );
      educationController.text = data["education"] ?? "";
      previousWorkController.text = data["previousWork"] ?? "";
      rateController.text = "";
      locationController.text = data["location"] ?? "";

      websiteController.text = data["website"] ?? "";
      contactPersonController.text = data["contactPerson"] ?? "";
      companyGoalsController.text = data["companyGoals"] ?? "";
      companyAdvantagesController.text = data["companyAdvantages"] ?? "";
      companyClientsController.text = data["companyClients"] ?? "";
      companyWhoWeAreController.text = data["companyWhoWeAre"] ?? "";
      companyHistoryController.text = data["companyHistory"] ?? "";
      extraPhones = List<String>.from(data["phones"] ?? []);
      references = parseReferences(data["references"]);
      rating = (data["rating"] ?? 0).toDouble();
      reviewsCount = data["reviewsCount"] ?? 0;

      photoUrl = data["photo"];
      headerImageUrl =
          (data["profileHeaderImage"] ?? data["headerImage"])?.toString();
      portfolio = portfolioUrls;
    });
  }

  Future<List<String>> loadPortfolioUrls(String userId) async {
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

  List<String> splitLines(String text) {
    return text
        .split(RegExp(r"[\n,]"))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  List<Map<String, String>> parseReferences(dynamic value) {
    if (value is List) {
      return value.map((item) {
        if (item is Map) {
          return {
            "name": item["name"]?.toString() ?? "",
            "company": item["company"]?.toString() ?? "",
            "phone": item["phone"]?.toString() ?? "",
            "email": item["email"]?.toString() ?? "",
          };
        }
        return {
          "name": item.toString(),
          "company": "",
          "phone": "",
          "email": "",
        };
      }).toList();
    }

    if (value is String && value.trim().isNotEmpty) {
      return [
        {
          "name": value.trim(),
          "company": "",
          "phone": "",
          "email": "",
        }
      ];
    }

    return [];
  }

  List<Map<String, String>> cleanedReferences() {
    return references
        .map((reference) => {
              "name": (reference["name"] ?? "").trim(),
              "company": (reference["company"] ?? "").trim(),
              "phone": (reference["phone"] ?? "").trim(),
              "email": (reference["email"] ?? "").trim(),
            })
        .where((reference) => reference.values.any((value) => value.isNotEmpty))
        .toList();
  }

  /// AVATAR
  Future<void> pickAndUploadAvatar() async {
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    final file = File(picked.path);

    final ref =
        FirebaseStorage.instance.ref().child("profile_photos/$userId.jpg");

    await ref.putFile(file);
    final url = await ref.getDownloadURL();

    await FirebaseFirestore.instance
        .collection("users")
        .doc(userId)
        .set({"photo": url}, SetOptions(merge: true));

    setState(() => photoUrl = url);
  }

  Future<void> pickHeaderImage() async {
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    setState(() => headerImageFile = File(picked.path));
  }

  /// SAVE PROFILE
  Future<void> saveProfile() async {
    final name = nameController.text.trim();
    final phone = phoneController.text.trim();
    final companyName = companyController.text.trim();
    final certificationsText = certificationsController.text.trim();

    if (role == "worker" && name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Enter your name")),
      );
      return;
    }

    if (role == "employer" && companyName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Enter company name")),
      );
      return;
    }

    setState(() => loading = true);

    try {
      var savedHeaderImageUrl = headerImageUrl;
      if (headerImageFile != null) {
        final ref =
            FirebaseStorage.instance.ref().child("profile_headers/$userId.jpg");
        await ref.putFile(headerImageFile!);
        savedHeaderImageUrl = await ref.getDownloadURL();
      }

      final cleanedPhones = extraPhones
          .map((phone) => phone.trim())
          .where((phone) => phone.isNotEmpty)
          .toList();

      final profileData = <String, dynamic>{
        "role": role,
        "phone": phone,
        "bio": bioController.text.trim(),
        "location": locationController.text.trim(),
        "updatedAt": FieldValue.serverTimestamp(),
      };

      if (role == "worker") {
        profileData.addAll({
          "name": name,
          "nickname": nicknameController.text.trim(),
          "username": nicknameController.text.trim(),
          "trade": tradeController.text.trim(),
          "experience": experienceController.text.trim(),
          "experienceYears":
              int.tryParse(experienceYearsController.text.trim()),
          "experienceMonths":
              int.tryParse(experienceMonthsController.text.trim()),
          "permits": permitsController.text.trim(),
          "qualifications": qualificationsController.text.trim(),
          "certificationsText": certificationsText,
          "certifications": splitLines(certificationsText),
          "education": educationController.text.trim(),
          "previousWork": previousWorkController.text.trim(),
          "references": cleanedReferences(),
          "rate": FieldValue.delete(),
        });
      }

      if (role == "employer") {
        profileData.addAll({
          "companyName": companyName,
          "website": websiteController.text.trim(),
          "contactPerson": contactPersonController.text.trim(),
          "phones": cleanedPhones,
          "companyGoals": companyGoalsController.text.trim(),
          "companyAdvantages": companyAdvantagesController.text.trim(),
          "companyClients": companyClientsController.text.trim(),
          "companyWhoWeAre": companyWhoWeAreController.text.trim(),
          "companyHistory": companyHistoryController.text.trim(),
        });
      }

      if (savedHeaderImageUrl != null && savedHeaderImageUrl.isNotEmpty) {
        profileData["profileHeaderImage"] = savedHeaderImageUrl;
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .set(profileData, SetOptions(merge: true));

      if (!mounted) return;

      setState(() {
        loading = false;
        headerImageUrl = savedHeaderImageUrl;
        headerImageFile = null;
        extraPhones = cleanedPhones;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Profile saved")),
      );
    } catch (e) {
      debugPrint("Save profile error: $e");
      if (!mounted) return;
      setState(() => loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not save profile")),
      );
    }
  }

  Widget buildHeaderBackgroundPicker() {
    final hasHeaderImage = headerImageFile != null ||
        (headerImageUrl != null && headerImageUrl!.isNotEmpty);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        const Text(
          "Profile header background",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Container(
            height: 118,
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              image: hasHeaderImage
                  ? DecorationImage(
                      image: headerImageFile != null
                          ? FileImage(headerImageFile!) as ImageProvider
                          : NetworkImage(headerImageUrl!),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: Container(
              alignment: Alignment.center,
              color: Colors.black.withValues(alpha: hasHeaderImage ? 0.20 : 0),
              child: OutlinedButton.icon(
                onPressed: pickHeaderImage,
                icon: const Icon(Icons.image_outlined),
                label: Text(
                    hasHeaderImage ? "Change background" : "Choose background"),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> logout() async {
    await FirebaseAuth.instance.signOut();
  }

  Widget buildAvatar() {
    return GestureDetector(
      onTap: pickAndUploadAvatar,
      child: CircleAvatar(
        radius: 50,
        backgroundColor: Colors.grey.shade300,
        backgroundImage: photoUrl != null ? NetworkImage(photoUrl!) : null,
        child: photoUrl == null ? const Icon(Icons.camera_alt, size: 30) : null,
      ),
    );
  }

  /// PORTFOLIO
  Widget buildPortfolioPreview() {
    if (role != "worker") return const SizedBox();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              "Work gallery",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            TextButton(
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const PortfolioScreen(),
                  ),
                );
                await loadProfile();
              },
              child: const Text("Edit"),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (portfolio.isEmpty) const Text("No work photos yet"),
        if (portfolio.isNotEmpty)
          SizedBox(
            height: 90,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: portfolio.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, index) {
                return ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    portfolio[index],
                    width: 90,
                    height: 90,
                    fit: BoxFit.cover,
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget buildForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        buildAvatar(),
        buildHeaderBackgroundPicker(),
        const SizedBox(height: 20),

        DropdownButtonFormField<String>(
          initialValue: role,
          decoration: const InputDecoration(
            labelText: "Account type",
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(value: "worker", child: Text("Worker")),
            DropdownMenuItem(value: "employer", child: Text("Employer")),
          ],
          onChanged: (value) => setState(() => role = value!),
        ),

        const SizedBox(height: 20),

        if (role == "worker") ...[
          TextField(
            controller: nameController,
            decoration: const InputDecoration(labelText: "Name"),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: phoneController,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: "Phone"),
          ),
          const SizedBox(height: 12),
        ],

        /// 🔥 WORKER
        if (role == "worker") ...[
          TextField(
            controller: nicknameController,
            decoration: const InputDecoration(
              labelText: "Nickname",
              hintText: "Used by teammates to add you to a team",
            ),
          ),
          const SizedBox(height: 12),
          TextField(
              controller: tradeController,
              decoration: const InputDecoration(labelText: "Trade")),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: experienceYearsController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: "Experience years",
                    hintText: "Years",
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: experienceMonthsController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: "Months",
                    hintText: "Months",
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
              controller: experienceController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: "Experience details",
                hintText: "Main skills, project types, responsibilities",
              )),
          const SizedBox(height: 12),
          TextField(
            controller: permitsController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: "Permits / licences",
              hintText: "CSCS, right to work, driving licence, permits",
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: qualificationsController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: "Qualifications",
              hintText: "NVQ, trade qualifications, specialist skills",
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: certificationsController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: "Certifications",
              hintText: "CSCS, IPAF, PASMA, First Aid, asbestos awareness",
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: educationController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: "Education (optional)",
              hintText: "Courses, college, training",
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: previousWorkController,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: "Previous work",
              hintText: "Previous projects, employers, responsibilities",
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            "References (optional)",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ...references.asMap().entries.map((entry) {
            final index = entry.key;
            final reference = entry.value;

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  TextField(
                    controller:
                        TextEditingController(text: reference["name"] ?? ""),
                    decoration: const InputDecoration(
                      labelText: "Referee name",
                      hintText: "Name",
                    ),
                    onChanged: (value) => references[index]["name"] = value,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller:
                        TextEditingController(text: reference["company"] ?? ""),
                    decoration: const InputDecoration(
                      labelText: "Company / role",
                      hintText: "Company, site manager, supervisor",
                    ),
                    onChanged: (value) => references[index]["company"] = value,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller:
                        TextEditingController(text: reference["phone"] ?? ""),
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: "Phone",
                      hintText: "Contact phone",
                    ),
                    onChanged: (value) => references[index]["phone"] = value,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: TextEditingController(
                              text: reference["email"] ?? ""),
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: "Email",
                            hintText: "Contact email",
                          ),
                          onChanged: (value) =>
                              references[index]["email"] = value,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete),
                        onPressed: () {
                          references.removeAt(index);
                          setState(() {});
                        },
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),
          OutlinedButton.icon(
            onPressed: () {
              references.add({
                "name": "",
                "company": "",
                "phone": "",
                "email": "",
              });
              setState(() {});
            },
            icon: const Icon(Icons.add),
            label: const Text("Add reference"),
          ),
        ],

        /// 🔥 EMPLOYER
        if (role == "employer") ...[
          TextField(
            controller: companyController,
            decoration: const InputDecoration(labelText: "Company name"),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: websiteController,
            decoration: const InputDecoration(labelText: "Website"),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: contactPersonController,
            decoration: const InputDecoration(labelText: "Contact person"),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: phoneController,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: "Main phone"),
          ),
          const SizedBox(height: 12),
          const Text("Additional phones"),
          const SizedBox(height: 8),
          ...extraPhones.asMap().entries.map((entry) {
            final index = entry.key;

            return Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(labelText: "Phone"),
                    onChanged: (value) => extraPhones[index] = value,
                    controller: TextEditingController(text: extraPhones[index]),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete),
                  onPressed: () {
                    extraPhones.removeAt(index);
                    setState(() {});
                  },
                )
              ],
            );
          }),
          TextButton(
            onPressed: () {
              extraPhones.add("");
              setState(() {});
            },
            child: const Text("Add phone"),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: locationController,
            maxLines: 2,
            decoration: const InputDecoration(labelText: "Location / address"),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: bioController,
            maxLines: 3,
            decoration: const InputDecoration(labelText: "About"),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: companyGoalsController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: "Our goals and objectives",
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: companyAdvantagesController,
            maxLines: 3,
            decoration: const InputDecoration(labelText: "Our advantages"),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: companyClientsController,
            maxLines: 3,
            decoration: const InputDecoration(labelText: "Our clients"),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: companyWhoWeAreController,
            maxLines: 3,
            decoration: const InputDecoration(labelText: "Who we are"),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: companyHistoryController,
            maxLines: 4,
            decoration: const InputDecoration(labelText: "Our history"),
          ),
        ],

        if (role == "worker") ...[
          const SizedBox(height: 12),
          TextField(
            controller: locationController,
            decoration: const InputDecoration(labelText: "Location"),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: bioController,
            maxLines: 3,
            decoration: const InputDecoration(labelText: "About"),
          ),
        ],

        buildPortfolioPreview(),

        const SizedBox(height: 100),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Profile"),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: logout,
          )
        ],
      ),
      body: StroykaScreenBody(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 110),
          child: StroykaSurface(
            padding: const EdgeInsets.all(18),
            child: buildForm(),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            height: 55,
            child: ElevatedButton(
              onPressed: loading ? null : saveProfile,
              child: loading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text("Save profile"),
            ),
          ),
        ),
      ),
    );
  }
}
