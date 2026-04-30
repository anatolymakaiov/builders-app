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
  bool uploading = false;

  String get userId => FirebaseAuth.instance.currentUser!.uid;

  Future<void> pickImages() async {
    if (uploading) return;

    try {
      final picked = await picker.pickMultiImage();
      if (picked.isEmpty) return;

      setState(() => uploading = true);

      final batch = FirebaseFirestore.instance.batch();
      final flatPortfolioRef = FirebaseFirestore.instance.collection(
        "portfolio",
      );
      final userPortfolioRef = FirebaseFirestore.instance
          .collection("users")
          .doc(userId)
          .collection("portfolio");

      for (final image in picked) {
        final ref = FirebaseStorage.instance.ref().child(
            "portfolio/$userId/${DateTime.now().millisecondsSinceEpoch}_${image.name}");

        await ref.putFile(File(image.path));

        final url = await ref.getDownloadURL();
        final data = {
          "userId": userId,
          "image": url,
          "imageUrl": url,
          "createdAt": FieldValue.serverTimestamp(),
        };

        batch.set(flatPortfolioRef.doc(), data);
        batch.set(userPortfolioRef.doc(), data);
      }

      await batch.commit();
    } catch (e) {
      debugPrint("PORTFOLIO UPLOAD ERROR: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not upload portfolio photos")),
      );
    } finally {
      if (mounted) setState(() => uploading = false);
    }
  }

  Stream<List<String>> portfolioStream() {
    return FirebaseFirestore.instance
        .collection("users")
        .doc(userId)
        .collection("portfolio")
        .snapshots()
        .asyncMap((nestedSnapshot) async {
      final urls = <String>[];

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
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("My Work Gallery"),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: uploading ? null : pickImages,
        child: const Icon(Icons.add_a_photo),
      ),
      body: StroykaScreenBody(
        child: Stack(
          children: [
            StreamBuilder<List<String>>(
              stream: portfolioStream(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final photos = snapshot.data!;

                if (photos.isEmpty) {
                  return const Center(
                    child: Text("No portfolio yet"),
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
                    final url = photos[index];

                    return ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(
                        url,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: Colors.grey.shade200,
                          alignment: Alignment.center,
                          child: const Icon(Icons.broken_image_outlined),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
            if (uploading) const LinearProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
