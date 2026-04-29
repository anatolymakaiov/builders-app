import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';

import '../models/job.dart';
import '../services/billing_service.dart';
import '../theme/stroyka_background.dart';
import 'employer_profile_screen.dart';

class PostJobScreen extends StatefulWidget {
  final Function(dynamic) onJobCreated;

  /// 🔥 NEW: edit mode
  final Job? existingJob;

  const PostJobScreen({
    super.key,
    required this.onJobCreated,
    this.existingJob,
  });

  @override
  State<PostJobScreen> createState() => _PostJobScreenState();
}

class _PostJobScreenState extends State<PostJobScreen> {
  final titleController = TextEditingController();
  final positionsController = TextEditingController();
  final durationController = TextEditingController();
  final weeklyHoursController = TextEditingController();
  final streetController = TextEditingController();
  final cityController = TextEditingController();
  final postcodeController = TextEditingController();
  final rateController = TextEditingController();
  final companyController = TextEditingController();
  final descriptionController = TextEditingController();
  final candidateRequirementsController = TextEditingController();
  final requiredDocumentsController = TextEditingController();
  final siteController = TextEditingController();

  bool loading = false;
  String postcodeStatus = "";

  String jobType = "hourly";
  String selectedTrade = "Bricklayer";

  File? companyLogo;
  List<File> jobPhotos = [];
  List<String> existingPhotos = [];

  final picker = ImagePicker();

  final trades = [
    "Bricklayer",
    "Dryliner",
    "Carpenter",
    "Joiner",
    "Painter",
    "Decorator",
    "Plasterer",
    "Tiler",
    "Floor layer",
    "Groundworker",
    "Steel fixer",
    "Concrete finisher",
    "Scaffolder",
    "Roofer",
    "Window fitter",
    "Door installer",
    "Electrician",
    "Electrical mate",
    "Plumber",
    "Pipe fitter",
    "Gas engineer",
    "HVAC engineer",
    "Fire alarm engineer",
    "Security engineer",
    "Data engineer",
    "Kitchen fitter",
    "Bathroom fitter",
    "Handyman",
    "Snagger",
    "Cleaner",
    "Labourer"
  ];

  @override
  void initState() {
    super.initState();

    /// 🔥 ЕСЛИ EDIT MODE
    if (widget.existingJob != null) {
      final job = widget.existingJob!;

      titleController.text = job.title;
      positionsController.text = job.positions.toString();
      siteController.text = job.site;
      durationController.text = job.duration;
      weeklyHoursController.text = job.weeklyHours;
      streetController.text = job.street;
      cityController.text = job.city;
      postcodeController.text = job.postcode;
      rateController.text = job.rate.toString();

      companyController.text = job.companyName;
      descriptionController.text = job.description;
      candidateRequirementsController.text = job.candidateRequirements;
      requiredDocumentsController.text = job.requiredDocuments;

      selectedTrade = job.trade;
      jobType = job.jobType;

      existingPhotos = job.photos;
    }
  }

  /// IMAGE PICKERS

  Future<void> pickCompanyLogo() async {
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() => companyLogo = File(picked.path));
    }
  }

  Future<void> pickJobPhotos() async {
    final picked = await picker.pickMultiImage();
    if (picked.isNotEmpty) {
      setState(() {
        jobPhotos.addAll(picked.map((e) => File(e.path)));
      });
    }
  }

  Future<String?> uploadFile(File file, String folder) async {
    try {
      final name =
          "${DateTime.now().millisecondsSinceEpoch}_${file.path.split('/').last}";

      final ref = FirebaseStorage.instance.ref("$folder/$name");

      await ref.putFile(file);

      return await ref.getDownloadURL();
    } catch (e) {
      debugPrint("Upload error: $e");
      return null;
    }
  }

  /// POSTCODE

  String normalizeUKPostcode(String postcode) {
    final clean =
        postcode.replaceAll(RegExp(r'[^A-Za-z0-9]'), "").trim().toUpperCase();

    if (clean.length <= 3) return clean;

    return "${clean.substring(0, clean.length - 3)} "
        "${clean.substring(clean.length - 3)}";
  }

  bool isValidUKPostcode(String postcode) {
    final normalized = normalizeUKPostcode(postcode);
    final regex = RegExp(
      r'^[A-Z]{1,2}[0-9][0-9A-Z]?\s?[0-9][A-Z]{2}$',
      caseSensitive: false,
    );
    return regex.hasMatch(normalized);
  }

  Future<Map<String, dynamic>?> lookupPostcode(String postcode) async {
    try {
      final clean = postcode.replaceAll(" ", "").toUpperCase();
      final res = await http
          .get(Uri.parse("https://api.postcodes.io/postcodes/$clean"));

      if (res.statusCode != 200) return null;

      final data = json.decode(res.body);
      return data["status"] == 200 ? data["result"] : null;
    } catch (_) {
      return null;
    }
  }

  void checkPostcode() async {
    final postcode = normalizeUKPostcode(postcodeController.text);

    if (!isValidUKPostcode(postcode)) {
      setState(() => postcodeStatus = "Invalid postcode");
      return;
    }

    setState(() => postcodeStatus = "Checking...");

    final result = await lookupPostcode(postcode);

    if (!mounted) return;

    if (result == null) {
      setState(() => postcodeStatus = "Not found");
      return;
    }

    setState(() {
      cityController.text = result["admin_district"] ?? "";
      postcodeStatus = "OK";
    });
  }

  /// 🔥 CREATE / UPDATE JOB

  void showValidationMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> showBillingLimitMessage(
      String message, String employerId) async {
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Billing required"),
        content: Text(message),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Open Billing"),
          ),
        ],
      ),
    );

    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EmployerProfileScreen(
          userId: employerId,
          initialTab: 4,
        ),
      ),
    );
  }

  Future<void> saveJob() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final typedTitle = titleController.text.trim();
    final title = typedTitle.isNotEmpty ? typedTitle : selectedTrade.trim();
    final postcode = normalizeUKPostcode(postcodeController.text);

    if (title.isEmpty) {
      showValidationMessage("Enter a job title or choose a trade.");
      return;
    }

    if (postcode.isEmpty) {
      showValidationMessage("Enter a site postcode.");
      return;
    }

    if (!isValidUKPostcode(postcode)) {
      showValidationMessage(
        "Enter a full UK postcode, for example SW1A 1AA.",
      );
      return;
    }

    postcodeController.text = postcode;

    setState(() => loading = true);

    final result = await lookupPostcode(postcode);

    double lat = 0;
    double lng = 0;

    if (result != null) {
      lat = (result["latitude"] as num?)?.toDouble() ?? 0;
      lng = (result["longitude"] as num?)?.toDouble() ?? 0;
    }

    if (widget.existingJob == null) {
      try {
        await BillingService().assertEmployerCanPost(user.uid);
      } on BillingLimitException catch (e) {
        if (mounted) {
          setState(() => loading = false);
          await showBillingLimitMessage(e.message, user.uid);
        }
        return;
      }
    }

    /// upload photos
    List<String> photoUrls = [...existingPhotos];

    for (var file in jobPhotos) {
      final url = await uploadFile(file, "job_photos");
      if (url != null) photoUrls.add(url);
    }

    final data = {
      "ownerId": user.uid,
      "title": title,
      "site": siteController.text.trim(),
      "trade": selectedTrade,
      "duration": durationController.text.trim(),
      "weeklyHours": weeklyHoursController.text.trim(),
      "positions": int.tryParse(positionsController.text) ?? 1,
      "filledPositions": widget.existingJob?.filledPositions ?? 0,
      "street": streetController.text.trim(),
      "city": cityController.text.trim(),
      "postcode": postcode,
      "location": "${streetController.text}, ${cityController.text} $postcode",
      "rate": jobType == "negotiable"
          ? 0
          : double.tryParse(rateController.text) ?? 0,
      "jobType": jobType,
      "companyName": companyController.text.trim(),
      "description": descriptionController.text.trim(),
      "candidateRequirements": candidateRequirementsController.text.trim(),
      "requiredDocuments": requiredDocumentsController.text.trim(),
      "photos": photoUrls,
      "lat": lat,
      "lng": lng,
      if (widget.existingJob == null) "moderationStatus": "pending_review",
      if (widget.existingJob == null) "moderationReason": "",
      "updatedAt": FieldValue.serverTimestamp(),
    };

    try {
      /// 🔥 EDIT
      if (widget.existingJob != null) {
        await FirebaseFirestore.instance
            .collection('jobs')
            .doc(widget.existingJob!.id)
            .update(data);
      }

      /// 🔥 CREATE
      else {
        await BillingService().createJobWithBillingLimit(
          employerId: user.uid,
          jobData: data,
        );
      }

      widget.onJobCreated(true);

      if (mounted) Navigator.pop(context);
    } on BillingLimitException catch (e) {
      debugPrint("Billing limit: ${e.message}");
      if (mounted) {
        setState(() => loading = false);
        await showBillingLimitMessage(e.message, user.uid);
      }
    } catch (e) {
      debugPrint("Save error: $e");
      if (mounted) {
        setState(() => loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Could not save job")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existingJob != null ? "Edit Job" : "Post Job"),
      ),
      body: StroykaScreenBody(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          child: StroykaSurface(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                TextField(
                  controller: companyController,
                  decoration: const InputDecoration(labelText: "Company name"),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: selectedTrade,
                  items: trades
                      .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                      .toList(),
                  onChanged: (v) => setState(() => selectedTrade = v!),
                  decoration: const InputDecoration(labelText: "Trade"),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(labelText: "Job title"),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: siteController,
                  decoration: const InputDecoration(labelText: "Site"),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: durationController,
                  decoration: const InputDecoration(
                    labelText: "Duration (e.g. 2 weeks)",
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: weeklyHoursController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: "Hours per week",
                    hintText: "40",
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: positionsController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: "Workers needed",
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: jobType,
                  items: const [
                    DropdownMenuItem(value: "hourly", child: Text("Daywork")),
                    DropdownMenuItem(value: "price", child: Text("Price")),
                    DropdownMenuItem(
                        value: "negotiable", child: Text("Negotiable")),
                  ],
                  onChanged: (v) => setState(() => jobType = v!),
                  decoration: const InputDecoration(
                    labelText: "Work format",
                    hintText: "Daywork, price, negotiable",
                  ),
                ),
                if (jobType != "negotiable")
                  TextField(
                    controller: rateController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: "Rate (£)"),
                  ),
                const SizedBox(height: 12),
                TextField(
                  controller: postcodeController,
                  decoration: const InputDecoration(labelText: "Postcode"),
                  onChanged: (_) => checkPostcode(),
                ),
                const SizedBox(height: 6),
                Text(postcodeStatus),
                const SizedBox(height: 12),
                TextField(
                  controller: streetController,
                  decoration: const InputDecoration(labelText: "Street"),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: cityController,
                  decoration: const InputDecoration(labelText: "City"),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descriptionController,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: "Description"),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: candidateRequirementsController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: "Candidate requirements",
                    hintText: "Experience, skills, right to work, references",
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: requiredDocumentsController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: "Required documents / certifications",
                    hintText: "CSCS, PPE, certifications, tools, documents",
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: pickJobPhotos,
                  child: const Text("Add photos"),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: loading ? null : saveJob,
                    child: loading
                        ? const CircularProgressIndicator()
                        : Text(widget.existingJob != null
                            ? "Update Job"
                            : "Create Job"),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
