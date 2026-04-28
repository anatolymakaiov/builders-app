import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/job.dart';
import '../theme/stroyka_background.dart';

class ReviewWorkerScreen extends StatefulWidget {
  final Job job;

  const ReviewWorkerScreen({
    super.key,
    required this.job,
  });

  @override
  State<ReviewWorkerScreen> createState() => _ReviewWorkerScreenState();
}

class _ReviewWorkerScreenState extends State<ReviewWorkerScreen> {
  int rating = 5;

  final reviewController = TextEditingController();

  Future<void> submitReview() async {
    final text = reviewController.text.trim();

    await FirebaseFirestore.instance.collection("reviews").add({
      "jobId": widget.job.id,
      "rating": rating,
      "review": text,
      "createdAt": FieldValue.serverTimestamp(),
    });

    if (mounted) {
      Navigator.pop(context);
    }
  }

  Widget buildStars() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(5, (index) {
        return IconButton(
          icon: Icon(
            Icons.star,
            color: index < rating ? Colors.orange : Colors.grey,
          ),
          onPressed: () {
            setState(() {
              rating = index + 1;
            });
          },
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Review Worker"),
      ),
      body: StroykaScreenBody(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const Text(
                "Rate the worker",
                style: TextStyle(fontSize: 20),
              ),
              const SizedBox(height: 20),
              buildStars(),
              const SizedBox(height: 20),
              TextField(
                controller: reviewController,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: "Leave a review",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: submitReview,
                  child: const Text("Submit review"),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}
