import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';

import 'portfolio_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {

  final nameController = TextEditingController();
  final phoneController = TextEditingController();

  final tradeController = TextEditingController();
  final companyController = TextEditingController();

  final bioController = TextEditingController();
  final experienceController = TextEditingController();
  final rateController = TextEditingController();
  final locationController = TextEditingController();

  /// 🔥 NEW
  final websiteController = TextEditingController();

  final picker = ImagePicker();

  String role = "worker";
  bool loading = false;

  double rating = 0;
  int reviewsCount = 0;

  String? photoUrl;
  List<String> portfolio = [];

  String get userId => FirebaseAuth.instance.currentUser!.uid;

  @override
  void initState() {
    super.initState();
    loadProfile();
  }

  /// LOAD PROFILE
  Future<void> loadProfile() async {

    final userDoc = await FirebaseFirestore.instance
        .collection("users")
        .doc(userId)
        .get();

    if (!userDoc.exists) return;

    final data = userDoc.data()!;

    final portfolioSnapshot = await FirebaseFirestore.instance
        .collection("users")
        .doc(userId)
        .collection("portfolio")
        .get();

    final portfolioUrls = portfolioSnapshot.docs
        .map((doc) => doc["imageUrl"] as String)
        .toList();

    setState(() {

      role = data["role"] ?? "worker";

      nameController.text = data["name"] ?? "";
      phoneController.text = data["phone"] ?? "";

      tradeController.text = data["trade"] ?? "";
      companyController.text = data["companyName"] ?? "";

      bioController.text = data["bio"] ?? "";
      experienceController.text = data["experience"] ?? "";
      rateController.text = data["rate"]?.toString() ?? "";
      locationController.text = data["location"] ?? "";

      websiteController.text = data["website"] ?? "";

      rating = (data["rating"] ?? 0).toDouble();
      reviewsCount = data["reviewsCount"] ?? 0;

      photoUrl = data["photo"];
      portfolio = portfolioUrls;
    });
  }

  /// AVATAR
  Future<void> pickAndUploadAvatar() async {

    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    final file = File(picked.path);

    final ref = FirebaseStorage.instance
        .ref()
        .child("profile_photos/$userId.jpg");

    await ref.putFile(file);
    final url = await ref.getDownloadURL();

    await FirebaseFirestore.instance
        .collection("users")
        .doc(userId)
        .set({"photo": url}, SetOptions(merge: true));

    setState(() => photoUrl = url);
  }

  /// SAVE PROFILE
  Future<void> saveProfile() async {

    final name = nameController.text.trim();
    final phone = phoneController.text.trim();

    if (name.isEmpty || phone.isEmpty) return;

    setState(() => loading = true);

    await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .set({

      "role": role,
      "name": name,
      "phone": phone,

      /// 🔥 WORKER
      "trade": role == "worker" ? tradeController.text.trim() : null,
      "experience": role == "worker" ? experienceController.text.trim() : null,
      "rate": role == "worker"
          ? double.tryParse(rateController.text.trim())
          : null,

      /// 🔥 EMPLOYER
      "companyName": role == "employer"
          ? companyController.text.trim()
          : null,
      "website": role == "employer"
          ? websiteController.text.trim()
          : null,

      /// 🔥 COMMON
      "bio": bioController.text.trim(),
      "location": locationController.text.trim(),

      "updatedAt": FieldValue.serverTimestamp(),

    }, SetOptions(merge: true));

    setState(() => loading = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Profile saved")),
      );
    }
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
        backgroundImage:
            photoUrl != null ? NetworkImage(photoUrl!) : null,
        child: photoUrl == null
            ? const Icon(Icons.camera_alt, size: 30)
            : null,
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
              "Portfolio",
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

        if (portfolio.isEmpty)
          const Text("No portfolio yet"),

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

        TextField(
          controller: nameController,
          decoration: const InputDecoration(labelText: "Name"),
        ),

        const SizedBox(height: 12),

        TextField(
          controller: phoneController,
          decoration: const InputDecoration(labelText: "Phone"),
        ),

        const SizedBox(height: 12),

        /// 🔥 WORKER
        if (role == "worker") ...[
          TextField(controller: tradeController, decoration: const InputDecoration(labelText: "Trade")),
          const SizedBox(height: 12),
          TextField(controller: rateController, decoration: const InputDecoration(labelText: "Rate (£/hour)")),
          const SizedBox(height: 12),
          TextField(controller: experienceController, decoration: const InputDecoration(labelText: "Experience")),
        ],

        /// 🔥 EMPLOYER
        if (role == "employer") ...[
          TextField(controller: companyController, decoration: const InputDecoration(labelText: "Company name")),
          const SizedBox(height: 12),
          TextField(controller: websiteController, decoration: const InputDecoration(labelText: "Website")),
        ],

        const SizedBox(height: 12),

        TextField(controller: locationController, decoration: const InputDecoration(labelText: "Location")),
        const SizedBox(height: 12),

        TextField(
          controller: bioController,
          maxLines: 3,
          decoration: const InputDecoration(labelText: "About"),
        ),

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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: buildForm(),
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