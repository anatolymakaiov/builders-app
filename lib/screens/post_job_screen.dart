import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';

class PostJobScreen extends StatefulWidget {

  final Function(dynamic) onJobCreated;

  const PostJobScreen({
    super.key,
    required this.onJobCreated,
  });

  @override
  State<PostJobScreen> createState() => _PostJobScreenState();
}

class _PostJobScreenState extends State<PostJobScreen> {

  final titleController = TextEditingController();
  final streetController = TextEditingController();
  final cityController = TextEditingController();
  final postcodeController = TextEditingController();
  final rateController = TextEditingController();
  final companyController = TextEditingController();
  final descriptionController = TextEditingController();

  bool loading = false;
  String postcodeStatus = "";

  String jobType = "hourly";
  String selectedTrade = "Bricklayer";

  File? companyLogo;
  List<File> jobPhotos = [];

  final ImagePicker picker = ImagePicker();

  final trades = [
    "Bricklayer","Dryliner","Carpenter","Joiner","Painter","Decorator",
    "Plasterer","Tiler","Floor layer","Groundworker","Steel fixer",
    "Concrete finisher","Scaffolder","Roofer","Window fitter",
    "Door installer","Electrician","Electrical mate","Plumber",
    "Pipe fitter","Gas engineer","HVAC engineer","Fire alarm engineer",
    "Security engineer","Data engineer","Kitchen fitter",
    "Bathroom fitter","Handyman","Snagger","Cleaner","Labourer"
  ];

  /// PICK LOGO

  Future<void> pickCompanyLogo() async {

    final picked = await picker.pickImage(source: ImageSource.gallery);

    if (picked == null) return;

    setState(() {
      companyLogo = File(picked.path);
    });

  }

  /// PICK JOB PHOTOS

  Future<void> pickJobPhotos() async {

    final picked = await picker.pickMultiImage();

    if (picked.isEmpty) return;

    setState(() {

      for (var img in picked) {
        jobPhotos.add(File(img.path));
      }

    });

  }

  /// UPLOAD FILE

  Future<String?> uploadFile(File file, String folder) async {

    try {

      final fileName =
          "${DateTime.now().millisecondsSinceEpoch}_${file.path.split('/').last}";

      final ref = FirebaseStorage.instance
          .ref()
          .child("$folder/$fileName");

      await ref.putFile(file);

      return await ref.getDownloadURL();

    } catch (e) {

      debugPrint("Upload error $e");
      return null;

    }

  }

  bool isValidUKPostcode(String postcode) {

    final regex = RegExp(
      r'^[A-Z]{1,2}[0-9][0-9A-Z]?\s?[0-9][A-Z]{2}$',
      caseSensitive: false,
    );

    return regex.hasMatch(postcode.trim());
  }

  Future<Map<String, dynamic>?> lookupPostcode(String postcode) async {

    try {

      final cleanPostcode = postcode.replaceAll(" ", "").toUpperCase();
      final url = "https://api.postcodes.io/postcodes/$cleanPostcode";

      final response = await http.get(Uri.parse(url));

      if (response.statusCode != 200) return null;

      final data = json.decode(response.body);

      if (data["status"] == 200) {
        return data["result"];
      }

      return null;

    } catch (e) {

      debugPrint("Postcode lookup error: $e");
      return null;

    }
  }

  void checkPostcode() async {

    final postcode = postcodeController.text.trim();

    if (!isValidUKPostcode(postcode)) {

      setState(() {
        postcodeStatus = "Invalid postcode";
      });

      return;
    }

    setState(() {
      postcodeStatus = "Checking postcode...";
    });

    final result = await lookupPostcode(postcode);

    if (!mounted) return;

    if (result == null) {

      setState(() {
        postcodeStatus = "Postcode not found";
      });

      return;
    }

    setState(() {

      cityController.text = result["admin_district"] ?? "";
      postcodeStatus = "Location found";

    });
  }

  /// CREATE JOB

  Future<void> createJob() async {

    final user = FirebaseAuth.instance.currentUser;

    if (user == null) return;

    final ownerId = user.uid;

    final title = titleController.text.trim();
    final street = streetController.text.trim();
    final city = cityController.text.trim();
    final postcode = postcodeController.text.trim();
    final rate = double.tryParse(rateController.text) ?? 0;
    final companyName = companyController.text.trim();
    final description = descriptionController.text.trim();

    if (title.isEmpty || !isValidUKPostcode(postcode)) {

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Enter job title and valid postcode")),
      );

      return;
    }

    setState(() {
      loading = true;
    });

    final result = await lookupPostcode(postcode);

    double lat = 0;
    double lng = 0;

    if (result != null) {

      lat = (result["latitude"] as num?)?.toDouble() ?? 0;
      lng = (result["longitude"] as num?)?.toDouble() ?? 0;

    }

    final location = "$street, $city $postcode";

    /// UPLOAD LOGO

    String? logoUrl;

    if (companyLogo != null) {

      logoUrl = await uploadFile(
        companyLogo!,
        "company_logos",
      );

    }

    /// UPLOAD PHOTOS

    List<String> photoUrls = [];

    for (var photo in jobPhotos) {

      final url = await uploadFile(
        photo,
        "job_photos",
      );

      if (url != null) photoUrls.add(url);

    }

    try {

      await FirebaseFirestore.instance.collection('jobs').add({

        "ownerId": ownerId,

        "title": title,
        "trade": selectedTrade,

        "street": street,
        "city": city,
        "postcode": postcode,
        "location": location,

        "rate": jobType == "negotiable" ? 0 : rate,
        "jobType": jobType,

        "companyName": companyName,
        "companyLogo": logoUrl,

        "description": description,

        "photos": photoUrls,

        "lat": lat,
        "lng": lng,

        "createdAt": FieldValue.serverTimestamp()

      });

      widget.onJobCreated(true);

      if (mounted) Navigator.pop(context);

    } catch (e) {

      debugPrint("Firestore error: $e");

      setState(() {
        loading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Error creating job")),
      );

    }

  }

  @override
  Widget build(BuildContext context) {

    final postcodeValid = isValidUKPostcode(postcodeController.text);

    return Scaffold(

      appBar: AppBar(
        title: const Text("Post Job"),
      ),

      body: SingleChildScrollView(

        padding: const EdgeInsets.all(20),

        child: Column(
          children: [

            TextField(
              controller: companyController,
              decoration: const InputDecoration(
                labelText: "Company name",
              ),
            ),

            const SizedBox(height: 12),

            Row(
              children: [

                companyLogo != null
                    ? CircleAvatar(
                        radius: 28,
                        backgroundImage: FileImage(companyLogo!),
                      )
                    : const CircleAvatar(
                        radius: 28,
                        child: Icon(Icons.business),
                      ),

                const SizedBox(width: 12),

                TextButton(
                  onPressed: pickCompanyLogo,
                  child: const Text("Upload company logo"),
                )

              ],
            ),

            const SizedBox(height: 12),

            DropdownButtonFormField<String>(

              value: selectedTrade,

              items: trades.map((trade) {

                return DropdownMenuItem(
                  value: trade,
                  child: Text(trade),
                );

              }).toList(),

              onChanged: (value) {

                setState(() {
                  selectedTrade = value!;
                });

              },

              decoration: const InputDecoration(
                labelText: "Trade",
              ),

            ),

            const SizedBox(height: 12),

            TextField(
              controller: titleController,
              decoration: const InputDecoration(
                labelText: "Job title",
              ),
            ),

            const SizedBox(height: 12),

            DropdownButtonFormField<String>(

              value: jobType,

              items: const [

                DropdownMenuItem(
                  value: "hourly",
                  child: Text("Hourly rate"),
                ),

                DropdownMenuItem(
                  value: "price",
                  child: Text("Price work"),
                ),

                DropdownMenuItem(
                  value: "negotiable",
                  child: Text("Price negotiable"),
                ),

              ],

              onChanged: (value) {

                setState(() {
                  jobType = value!;
                });

              },

              decoration: const InputDecoration(
                labelText: "Job type",
              ),

            ),

            const SizedBox(height: 12),

            if (jobType != "negotiable")
              TextField(
                controller: rateController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: "Rate (£)",
                ),
              ),

            const SizedBox(height: 12),

            TextField(
              controller: postcodeController,
              decoration: const InputDecoration(
                labelText: "Postcode",
              ),
              onChanged: (_) {

                if (postcodeController.text.length > 4) {
                  checkPostcode();
                }

              },
            ),

            const SizedBox(height: 6),

            Text(
              postcodeStatus,
              style: const TextStyle(fontSize: 12),
            ),

            const SizedBox(height: 12),

            TextField(
              controller: streetController,
              decoration: const InputDecoration(
                labelText: "Street",
              ),
            ),

            const SizedBox(height: 12),

            TextField(
              controller: cityController,
              decoration: const InputDecoration(
                labelText: "City",
              ),
            ),

            const SizedBox(height: 12),

            TextField(
              controller: descriptionController,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: "Job description",
                alignLabelWithHint: true,
              ),
            ),

            const SizedBox(height: 20),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [

                const Text(
                  "Job photos",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),

                TextButton(
                  onPressed: pickJobPhotos,
                  child: const Text("Add photos"),
                )

              ],
            ),

            if (jobPhotos.isNotEmpty)
              SizedBox(
                height: 90,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: jobPhotos.length,
                  itemBuilder: (context, index) {

                    return Container(
                      margin: const EdgeInsets.only(right: 10),
                      width: 90,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        image: DecorationImage(
                          image: FileImage(jobPhotos[index]),
                          fit: BoxFit.cover,
                        ),
                      ),
                    );

                  },
                ),
              ),

            const SizedBox(height: 30),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: loading || !postcodeValid ? null : createJob,
                child: loading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text("Create Job"),
              ),
            )

          ],
        ),
      ),
    );
  }
}