import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:io';

import '../theme/stroyka_background.dart';

class PortfolioScreen extends StatefulWidget {
  const PortfolioScreen({super.key});

  @override
  State<PortfolioScreen> createState() => _PortfolioScreenState();
}

class _PortfolioScreenState extends State<PortfolioScreen> {
  final picker = ImagePicker();
  File? image;

  String get userId => FirebaseAuth.instance.currentUser!.uid;

  Future<void> pickImage() async {
    final picked = await picker.pickImage(source: ImageSource.gallery);

    if (picked == null) return;

    image = File(picked.path);

    uploadImage();
  }

  Future<void> uploadImage() async {
    if (image == null) return;

    final ref = FirebaseStorage.instance.ref().child(
        "portfolio/$userId/${DateTime.now().millisecondsSinceEpoch}.jpg");

    await ref.putFile(image!);

    final url = await ref.getDownloadURL();

    await FirebaseFirestore.instance.collection("portfolio").add({
      "userId": userId,
      "image": url,
      "imageUrl": url,
      "createdAt": FieldValue.serverTimestamp()
    });

    await FirebaseFirestore.instance
        .collection("users")
        .doc(userId)
        .collection("portfolio")
        .add({
      "image": url,
      "imageUrl": url,
      "createdAt": FieldValue.serverTimestamp(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("My Work Gallery"),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: pickImage,
        child: const Icon(Icons.add_a_photo),
      ),
      body: StroykaScreenBody(
        child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection("portfolio")
              .where("userId", isEqualTo: userId)
              .snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final photos = snapshot.data!.docs;

            if (photos.isEmpty) {
              return const Center(
                child: Text("No work photos yet"),
              );
            }

            return GridView.builder(
              padding: const EdgeInsets.all(10),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemCount: photos.length,
              itemBuilder: (context, index) {
                final data = photos[index].data() as Map<String, dynamic>;
                final url = data["imageUrl"] ?? data["image"];

                return Image.network(url, fit: BoxFit.cover);
              },
            );
          },
        ),
      ),
    );
  }
}
