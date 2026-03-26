import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

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

  String role = "worker";

  bool loading = false;

  double rating = 0;
  int reviewsCount = 0;

  String? photoUrl;

  String get userId => FirebaseAuth.instance.currentUser!.uid;

  @override
  void initState() {
    super.initState();
    loadProfile();
  }

  /// LOAD PROFILE

  Future<void> loadProfile() async {

    final doc = await FirebaseFirestore.instance
        .collection("users")
        .doc(userId)
        .get();

    if (!doc.exists) return;

    final data = doc.data()!;

    setState(() {

      role = data["role"] ?? "worker";

      nameController.text = data["name"] ?? "";
      phoneController.text = data["phone"] ?? "";

      tradeController.text = data["trade"] ?? "";
      companyController.text = data["companyName"] ?? "";

      rating = (data["rating"] ?? 0).toDouble();
      reviewsCount = data["reviewsCount"] ?? 0;

      photoUrl = data["photo"];

    });

  }

  /// SAVE PROFILE

  Future<void> saveProfile() async {

    final name = nameController.text.trim();
    final phone = phoneController.text.trim();
    final trade = tradeController.text.trim();
    final company = companyController.text.trim();

    if (name.isEmpty || phone.isEmpty) {

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Enter name and phone")),
      );

      return;
    }

    setState(() {
      loading = true;
    });

    await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .set({

      "role": role,
      "name": name,
      "phone": phone,

      "trade": role == "worker" ? trade : null,
      "companyName": role == "employer" ? company : null,

      "updatedAt": FieldValue.serverTimestamp(),

    }, SetOptions(merge: true));

    setState(() {
      loading = false;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Profile saved")),
      );
    }

  }

  /// LOGOUT

  Future<void> logout() async {
    await FirebaseAuth.instance.signOut();
  }

  Widget buildAvatar() {

    ImageProvider? image;

    if (photoUrl != null) {
      image = NetworkImage(photoUrl!);
    }

    return CircleAvatar(
      radius: 50,
      backgroundColor: Colors.grey.shade300,
      backgroundImage: image,
      child: image == null
          ? const Icon(Icons.person, size: 40)
          : null,
    );

  }

  Widget buildRating() {

    if (role != "worker") return const SizedBox();

    return Column(
      children: [

        const SizedBox(height: 10),

        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [

            const Icon(Icons.star, color: Colors.orange),

            const SizedBox(width: 6),

            Text(
              rating.toStringAsFixed(1),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(width: 6),

            Text(
              "($reviewsCount reviews)",
              style: const TextStyle(color: Colors.grey),
            ),

          ],
        ),

      ],
    );

  }

  Widget buildPortfolioButton(BuildContext context) {

    if (role != "worker") return const SizedBox();

    return Column(
      children: [

        const SizedBox(height: 20),

        SizedBox(
          width: double.infinity,
          child: OutlinedButton(

            onPressed: () {

              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const PortfolioScreen(),
                ),
              );

            },

            child: const Text("My Portfolio"),

          ),
        ),

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

        child: Column(
          children: [

            buildAvatar(),

            buildRating(),

            const SizedBox(height: 20),

            DropdownButtonFormField<String>(

              value: role,

              decoration: const InputDecoration(
                labelText: "Account type",
                border: OutlineInputBorder(),
              ),

              items: const [

                DropdownMenuItem(
                  value: "worker",
                  child: Text("Worker"),
                ),

                DropdownMenuItem(
                  value: "employer",
                  child: Text("Employer"),
                ),

              ],

              onChanged: (value) {

                setState(() {
                  role = value!;
                });

              },

            ),

            const SizedBox(height: 20),

            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: "Name",
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 12),

            TextField(
              controller: phoneController,
              decoration: const InputDecoration(
                labelText: "Phone",
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 12),

            if (role == "worker")
              TextField(
                controller: tradeController,
                decoration: const InputDecoration(
                  labelText: "Trade",
                  border: OutlineInputBorder(),
                ),
              ),

            if (role == "employer")
              TextField(
                controller: companyController,
                decoration: const InputDecoration(
                  labelText: "Company name",
                  border: OutlineInputBorder(),
                ),
              ),

            const SizedBox(height: 20),

            buildPortfolioButton(context),

            const SizedBox(height: 30),

            SizedBox(
              width: double.infinity,
              height: 50,

              child: ElevatedButton(

                onPressed: loading ? null : saveProfile,

                child: loading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text("Save profile"),

              ),
            )

          ],
        ),
      ),
    );
  }
}