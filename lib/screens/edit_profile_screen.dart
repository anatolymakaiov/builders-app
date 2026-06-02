import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:async';
import 'dart:io';

import 'portfolio_screen.dart';
import '../theme/app_theme.dart';
import '../theme/stroyka_background.dart';
import '../services/registration_validation_service.dart';
import '../widgets/legal_documents.dart';

class ProfileScreen extends StatefulWidget {
  final VoidCallback? onProfileSaved;

  const ProfileScreen({
    super.key,
    this.onProfileSaved,
  });

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
  final billingEmailController = TextEditingController();
  final invoiceLegalCompanyNameController = TextEditingController();
  final invoiceTradingNameController = TextEditingController();
  final invoiceCompanyNumberController = TextEditingController();
  final invoiceRegisteredOfficeController = TextEditingController();
  final invoiceBillingAddressController = TextEditingController();
  final invoiceBillingContactNameController = TextEditingController();
  final invoiceVatNumberController = TextEditingController();
  final invoicePurchaseOrderController = TextEditingController();
  final invoicePaymentPhoneController = TextEditingController();
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
  List<String> companyPhotos = [];
  bool uploadingAvatar = false;
  bool uploadingCompanyPhotos = false;
  bool firstProfileCreation = false;
  bool legalAcceptedForCurrentVersion = false;
  bool billingEmailVerified = false;
  bool emailVerified = false;
  bool phoneVerified = false;
  bool sendingEmailVerification = false;
  String loadedBillingEmail = "";

  String get userId => FirebaseAuth.instance.currentUser!.uid;

  @override
  void initState() {
    super.initState();
    loadProfile();
  }

  @override
  void dispose() {
    nameController.dispose();
    phoneController.dispose();
    nicknameController.dispose();
    tradeController.dispose();
    companyController.dispose();
    bioController.dispose();
    experienceController.dispose();
    experienceYearsController.dispose();
    experienceMonthsController.dispose();
    permitsController.dispose();
    qualificationsController.dispose();
    certificationsController.dispose();
    educationController.dispose();
    previousWorkController.dispose();
    rateController.dispose();
    locationController.dispose();
    websiteController.dispose();
    billingEmailController.dispose();
    invoiceLegalCompanyNameController.dispose();
    invoiceTradingNameController.dispose();
    invoiceCompanyNumberController.dispose();
    invoiceRegisteredOfficeController.dispose();
    invoiceBillingAddressController.dispose();
    invoiceBillingContactNameController.dispose();
    invoiceVatNumberController.dispose();
    invoicePurchaseOrderController.dispose();
    invoicePaymentPhoneController.dispose();
    contactPersonController.dispose();
    companyGoalsController.dispose();
    companyAdvantagesController.dispose();
    companyClientsController.dispose();
    companyWhoWeAreController.dispose();
    companyHistoryController.dispose();
    super.dispose();
  }

  /// LOAD PROFILE
  Future<void> loadProfile() async {
    final userDoc =
        await FirebaseFirestore.instance.collection("users").doc(userId).get();

    if (!userDoc.exists) return;

    final data = userDoc.data()!;

    final portfolioUrls = await loadPortfolioUrls(userId);

    final existingRole = data["role"]?.toString() ?? "worker";
    final hasWorkerProfile = (data["name"]?.toString().trim() ?? "").isNotEmpty;
    final hasEmployerProfile =
        (data["companyName"]?.toString().trim() ?? "").isNotEmpty;
    final acceptedCurrentVersion =
        LegalDocuments.hasAcceptedCurrentVersion(data, existingRole);

    setState(() {
      role = existingRole;
      firstProfileCreation = !hasWorkerProfile && !hasEmployerProfile;
      legalAcceptedForCurrentVersion = acceptedCurrentVersion;

      final registrationName = data["registrationName"]?.toString() ?? "";
      nameController.text = data["name"]?.toString().trim().isNotEmpty == true
          ? data["name"].toString()
          : registrationName;
      phoneController.text = data["phone"] ?? "";
      nicknameController.text =
          data["nickname"] ?? data["username"] ?? data["nickName"] ?? "";

      tradeController.text = (data["trade"] ??
              data["position"] ??
              data["registrationPosition"] ??
              "")
          .toString();
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
      final billing = data["billing"] is Map
          ? Map<String, dynamic>.from(data["billing"] as Map)
          : <String, dynamic>{};
      final invoiceDetails = billing["invoiceDetails"] is Map
          ? Map<String, dynamic>.from(billing["invoiceDetails"] as Map)
          : data["invoiceDetails"] is Map
              ? Map<String, dynamic>.from(data["invoiceDetails"] as Map)
              : <String, dynamic>{};
      loadedBillingEmail = (data["billingEmail"] ??
              billing["billingEmail"] ??
              data["email"] ??
              FirebaseAuth.instance.currentUser?.email ??
              "")
          .toString();
      billingEmailController.text = loadedBillingEmail;
      emailVerified = data["emailVerified"] == true ||
          FirebaseAuth.instance.currentUser?.emailVerified == true;
      phoneVerified = data["phoneVerified"] == true;
      billingEmailVerified = data["billingEmailVerified"] == true ||
          billing["billingEmailVerified"] == true;
      invoiceLegalCompanyNameController.text =
          invoiceDetails["legalCompanyName"]?.toString() ??
              data["companyName"]?.toString() ??
              "";
      invoiceTradingNameController.text =
          invoiceDetails["tradingName"]?.toString() ?? "";
      invoiceCompanyNumberController.text =
          invoiceDetails["companyRegistrationNumber"]?.toString() ?? "";
      invoiceRegisteredOfficeController.text =
          invoiceDetails["registeredOfficeAddress"]?.toString() ?? "";
      invoiceBillingAddressController.text =
          invoiceDetails["billingAddress"]?.toString() ??
              data["location"]?.toString() ??
              "";
      invoiceBillingContactNameController.text =
          invoiceDetails["billingContactName"]?.toString().trim().isNotEmpty ==
                  true
              ? invoiceDetails["billingContactName"].toString()
              : registrationName;
      invoiceVatNumberController.text =
          invoiceDetails["vatNumber"]?.toString() ?? "";
      invoicePurchaseOrderController.text =
          invoiceDetails["purchaseOrderReference"]?.toString() ?? "";
      invoicePaymentPhoneController.text =
          invoiceDetails["paymentContactPhone"]?.toString() ??
              data["phone"]?.toString() ??
              "";
      contactPersonController.text =
          data["contactPerson"]?.toString().trim().isNotEmpty == true
              ? data["contactPerson"].toString()
              : registrationName;
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
      companyPhotos = List<String>.from(data["companyPhotos"] ?? []);
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

  Stream<List<String>> portfolioUrlsStream(String userId) {
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
    if (uploadingAvatar) return;

    try {
      final picked = await picker.pickImage(source: ImageSource.gallery);
      if (picked == null) return;

      setState(() => uploadingAvatar = true);

      final url = await uploadProfileImage(
        picked,
        folder: "profile_photos",
        fileName: "$userId.jpg",
      );

      await FirebaseFirestore.instance.collection("users").doc(userId).set({
        "photo": url,
        "avatarUrl": url,
        "updatedAt": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      setState(() => photoUrl = url);
    } catch (e) {
      debugPrint("Profile photo upload error: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(photoUploadMessage(e))),
      );
    } finally {
      if (mounted) setState(() => uploadingAvatar = false);
    }
  }

  Future<String> uploadProfileImage(
    XFile image, {
    required String folder,
    required String fileName,
  }) async {
    final extension = image.name.split(".").last.toLowerCase();
    final supportedExtensions = {"jpg", "jpeg", "png", "heic", "heif", "webp"};
    if (!supportedExtensions.contains(extension)) {
      throw const FormatException("unsupported-image-format");
    }

    final size = await image.length();
    const maxSize = 15 * 1024 * 1024;
    if (size > maxSize) {
      throw const FormatException("image-too-large");
    }

    final contentType = switch (extension) {
      "png" => "image/png",
      "webp" => "image/webp",
      "heic" || "heif" => "image/heic",
      _ => "image/jpeg",
    };
    final safeName = fileName.replaceAll(RegExp(r"[^A-Za-z0-9._-]"), "_");
    final ref = FirebaseStorage.instance.ref().child("$folder/$safeName");
    await ref.putFile(
      File(image.path),
      SettableMetadata(contentType: contentType),
    );
    return ref.getDownloadURL();
  }

  String photoUploadMessage(Object error) {
    if (error is FormatException) {
      if (error.message == "unsupported-image-format") {
        return "Unsupported image format.";
      }
      if (error.message == "image-too-large") {
        return "Image is too large.";
      }
    }
    if (error is PlatformException) {
      final code = error.code.toLowerCase();
      if (code.contains("denied") || code.contains("permission")) {
        return "Permission denied.";
      }
    }
    if (error is FirebaseException) {
      final code = error.code.toLowerCase();
      if (code.contains("denied") || code.contains("unauthorized")) {
        return "Permission denied.";
      }
      if (code.contains("network") || code.contains("unavailable")) {
        return "No internet connection.";
      }
    }
    return "Photo upload failed. Please try again.";
  }

  Future<void> sendEmailVerification() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || sendingEmailVerification) return;

    setState(() => sendingEmailVerification = true);
    try {
      await user.reload();
      final refreshed = FirebaseAuth.instance.currentUser ?? user;
      if (refreshed.emailVerified) {
        await FirebaseFirestore.instance.collection("users").doc(userId).set({
          "emailVerified": true,
          "emailVerifiedAt": FieldValue.serverTimestamp(),
          if (role == "employer" &&
              refreshed.email?.toLowerCase() ==
                  billingEmailController.text.trim().toLowerCase()) ...{
            "billingEmailVerified": true,
            "billingEmailVerifiedAt": FieldValue.serverTimestamp(),
            "billing": {
              "billingEmailVerified": true,
              "billingEmailVerifiedAt": FieldValue.serverTimestamp(),
              "updatedAt": FieldValue.serverTimestamp(),
            },
          },
        }, SetOptions(merge: true));
        if (!mounted) return;
        setState(() {
          emailVerified = true;
          billingEmailVerified = role == "employer"
              ? refreshed.email?.toLowerCase() ==
                  billingEmailController.text.trim().toLowerCase()
              : billingEmailVerified;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Email verified")),
        );
        return;
      }

      await refreshed.sendEmailVerification();
      await FirebaseFirestore.instance.collection("users").doc(userId).set({
        "emailVerificationSentAt": FieldValue.serverTimestamp(),
        "authPreferences": {
          "email": refreshed.email,
          "emailVerified": false,
          "emailVerificationSentAt": FieldValue.serverTimestamp(),
          "updatedAt": FieldValue.serverTimestamp(),
        },
      }, SetOptions(merge: true));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Verification email sent")),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message ?? "Could not send verification email"),
        ),
      );
    } finally {
      if (mounted) setState(() => sendingEmailVerification = false);
    }
  }

  Future<void> refreshEmailVerification() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await user.reload();
    final refreshed = FirebaseAuth.instance.currentUser ?? user;
    final verified = refreshed.emailVerified;
    final billingMatches = refreshed.email?.toLowerCase() ==
        billingEmailController.text.trim().toLowerCase();

    await FirebaseFirestore.instance.collection("users").doc(userId).set({
      "emailVerified": verified,
      if (verified) "emailVerifiedAt": FieldValue.serverTimestamp(),
      "authPreferences": {
        "email": refreshed.email,
        "emailVerified": verified,
        "updatedAt": FieldValue.serverTimestamp(),
      },
      if (role == "employer" && billingMatches) ...{
        "billingEmailVerified": verified,
        if (verified) "billingEmailVerifiedAt": FieldValue.serverTimestamp(),
        "billing": {
          "billingEmailVerified": verified,
          if (verified) "billingEmailVerifiedAt": FieldValue.serverTimestamp(),
          "updatedAt": FieldValue.serverTimestamp(),
        },
      },
    }, SetOptions(merge: true));

    if (!mounted) return;
    setState(() {
      if (role == "employer" && billingMatches) {
        billingEmailVerified = verified;
      }
      emailVerified = verified;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content:
              Text(verified ? "Email verified" : "Email not verified yet")),
    );
  }

  Widget buildInlineVerificationStatus({
    required bool verified,
    required String verifiedText,
    required String unverifiedText,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Icon(
            verified ? Icons.verified : Icons.info_outline,
            size: 18,
            color: verified ? AppColors.success : AppColors.warning,
          ),
          const SizedBox(width: 6),
          Text(
            verified ? verifiedText : unverifiedText,
            style: TextStyle(
              color: verified ? AppColors.success : AppColors.warning,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> verifyEmailFromDialog() async {
    final email = (FirebaseAuth.instance.currentUser?.email ??
            billingEmailController.text.trim())
        .trim();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Verify email"),
        content: Text("Send verification email to $email?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text("Send"),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await sendEmailVerification();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Check your email"),
        content: const Text(
          "Open the verification link from Firebase, then return to the app and tap Refresh.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text("Close"),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              await refreshEmailVerification();
            },
            child: const Text("Refresh"),
          ),
        ],
      ),
    );
  }

  Future<void> verifyPhoneFromDialog() async {
    final phone = phoneController.text.trim();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Verify phone"),
        content: Text("Send SMS verification code to $phone?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text("Send SMS"),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    const allowDevVerification = kDebugMode;
    final verified = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("SMS verification"),
        content: const Text(
          allowDevVerification
              ? "SMS verification backend is not configured yet. Development verification can mark this phone as verified for testing."
              : "SMS verification backend is not configured yet. Phone cannot be marked as verified until SMS provider is connected.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text("Cancel"),
          ),
          if (allowDevVerification)
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text("Use development verification"),
            ),
        ],
      ),
    );
    if (verified != true) return;

    await FirebaseFirestore.instance.collection("users").doc(userId).set({
      "phoneVerified": true,
      "phoneVerifiedAt": FieldValue.serverTimestamp(),
      "updatedAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    if (!mounted) return;
    setState(() => phoneVerified = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Phone verified")),
    );
  }

  Future<void> showVerificationRequiredDialog({
    required bool requireEmail,
    required bool requirePhone,
  }) async {
    final message = requireEmail && requirePhone
        ? "Your email address and phone number are not verified. Please choose what you would like to verify."
        : requireEmail
            ? "Your email address is not verified. Please verify it before continuing."
            : "Your phone number is not verified. Please verify it before continuing.";
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Verification required"),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text("Cancel"),
          ),
          if (requireEmail)
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                unawaited(verifyEmailFromDialog());
              },
              child: const Text("Verify email"),
            ),
          if (requirePhone)
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                unawaited(verifyPhoneFromDialog());
              },
              child: const Text("Verify phone"),
            ),
        ],
      ),
    );
  }

  Future<void> pickHeaderImage() async {
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    setState(() => headerImageFile = File(picked.path));
  }

  Future<void> pickAndUploadCompanyPhotos() async {
    if (role != "employer" || uploadingCompanyPhotos) return;

    try {
      final picked = await picker.pickMultiImage();
      if (picked.isEmpty) return;

      setState(() => uploadingCompanyPhotos = true);

      final uploadedUrls = <String>[];
      for (final image in picked) {
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final url = await uploadProfileImage(
          image,
          folder: "company_photos/$userId",
          fileName: "${timestamp}_${image.name}",
        );
        uploadedUrls.add(url);
      }

      if (uploadedUrls.isEmpty) return;

      await FirebaseFirestore.instance.collection("users").doc(userId).set({
        "companyPhotos": FieldValue.arrayUnion(uploadedUrls),
        "updatedAt": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      setState(() {
        companyPhotos = [...companyPhotos, ...uploadedUrls];
      });
    } catch (e) {
      debugPrint("Company gallery upload error: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(photoUploadMessage(e))),
      );
    } finally {
      if (mounted) setState(() => uploadingCompanyPhotos = false);
    }
  }

  Future<void> removeCompanyPhoto(String photo) async {
    if (role != "employer" || uploadingCompanyPhotos) return;

    try {
      setState(() {
        companyPhotos.remove(photo);
      });

      await FirebaseFirestore.instance.collection("users").doc(userId).set({
        "companyPhotos": FieldValue.arrayRemove([photo]),
        "updatedAt": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint("Company gallery remove error: $e");
      if (!mounted) return;
      setState(() {
        if (!companyPhotos.contains(photo)) {
          companyPhotos.add(photo);
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not remove company photo")),
      );
    }
  }

  /// SAVE PROFILE
  Future<void> saveProfile() async {
    final name = nameController.text.trim();
    final phone = phoneController.text.trim();
    final normalizedPhone = RegistrationValidationService.normalizePhone(phone);
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

    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Enter phone number")),
      );
      return;
    }

    final billingEmail = billingEmailController.text.trim();
    final validBillingEmail =
        RegExp(r"^[^\s@]+@[^\s@]+\.[^\s@]+$").hasMatch(billingEmail);
    if (role == "employer" && !validBillingEmail) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Enter a valid billing email")),
      );
      return;
    }

    final shouldRequestLegalAcceptance =
        firstProfileCreation && !legalAcceptedForCurrentVersion;

    if (shouldRequestLegalAcceptance) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please accept required legal documents first."),
        ),
      );
      return;
    }

    final authUser = FirebaseAuth.instance.currentUser;
    final billingEmailMatchesAuth =
        authUser?.email?.toLowerCase() == billingEmail.toLowerCase();
    final emailIsVerified = role == "employer"
        ? billingEmailVerified ||
            (billingEmailMatchesAuth && authUser?.emailVerified == true)
        : emailVerified || authUser?.emailVerified == true;
    if (firstProfileCreation && (!emailIsVerified || !phoneVerified)) {
      await showVerificationRequiredDialog(
        requireEmail: !emailIsVerified,
        requirePhone: !phoneVerified,
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
        "normalizedPhone": normalizedPhone,
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
        final verifiedByAuth =
            authUser?.email?.toLowerCase() == billingEmail.toLowerCase() &&
                authUser?.emailVerified == true;
        final nextBillingEmailVerified = verifiedByAuth ||
            (billingEmailVerified &&
                billingEmail.toLowerCase() == loadedBillingEmail.toLowerCase());
        final invoiceDetails = {
          "legalCompanyName": invoiceLegalCompanyNameController.text.trim(),
          "tradingName": invoiceTradingNameController.text.trim(),
          "companyRegistrationNumber":
              invoiceCompanyNumberController.text.trim(),
          "registeredOfficeAddress":
              invoiceRegisteredOfficeController.text.trim(),
          "billingAddress": invoiceBillingAddressController.text.trim(),
          "billingContactName": invoiceBillingContactNameController.text.trim(),
          "billingEmail": billingEmail,
          "vatNumber": invoiceVatNumberController.text.trim(),
          "purchaseOrderReference": invoicePurchaseOrderController.text.trim(),
          "paymentContactPhone": invoicePaymentPhoneController.text.trim(),
        };
        profileData.addAll({
          "companyName": companyName,
          "email": billingEmail,
          "billingEmail": billingEmail,
          "billingEmailProvided": true,
          "billingEmailVerified": nextBillingEmailVerified,
          if (nextBillingEmailVerified)
            "billingEmailVerifiedAt": FieldValue.serverTimestamp(),
          "billing": {
            "billingEmail": billingEmail,
            "billingEmailVerified": nextBillingEmailVerified,
            if (nextBillingEmailVerified)
              "billingEmailVerifiedAt": FieldValue.serverTimestamp(),
            "invoiceDetails": invoiceDetails,
            "updatedAt": FieldValue.serverTimestamp(),
          },
          "invoiceDetails": invoiceDetails,
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

      if (firstProfileCreation) {
        profileData.addAll({
          "profileCreated": true,
          "profileComplete": true,
          "onboardingComplete": true,
          "onboardingTourPending": true,
          "onboardingTourCompleted": false,
          if (shouldRequestLegalAcceptance || legalAcceptedForCurrentVersion)
            "legalAccepted": true,
          if (shouldRequestLegalAcceptance || legalAcceptedForCurrentVersion)
            "legalAcceptedAt": FieldValue.serverTimestamp(),
          if (shouldRequestLegalAcceptance || legalAcceptedForCurrentVersion)
            "acceptedPolicyVersion": LegalDocuments.policyVersion,
          if (shouldRequestLegalAcceptance || legalAcceptedForCurrentVersion)
            "acceptedDocuments": LegalDocuments.acceptedMapForRole(role),
          if (shouldRequestLegalAcceptance || legalAcceptedForCurrentVersion)
            "acceptedDocumentIds": LegalDocuments.acceptedIdsForRole(role),
          if (shouldRequestLegalAcceptance || legalAcceptedForCurrentVersion)
            "legalVersion": LegalDocuments.policyVersion,
          if (shouldRequestLegalAcceptance || legalAcceptedForCurrentVersion)
            "onboardingLegalStepComplete": true,
        });
      } else {
        profileData.addAll({
          "profileComplete": true,
          "onboardingComplete": true,
        });
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
        firstProfileCreation = false;
        billingEmailVerified = (FirebaseAuth.instance.currentUser?.email
                        ?.toLowerCase() ==
                    billingEmail.toLowerCase() &&
                FirebaseAuth.instance.currentUser?.emailVerified == true) ||
            (billingEmailVerified &&
                billingEmail.toLowerCase() == loadedBillingEmail.toLowerCase());
        loadedBillingEmail = billingEmail;
        if (shouldRequestLegalAcceptance || legalAcceptedForCurrentVersion) {
          legalAcceptedForCurrentVersion = true;
        }
      });

      if (widget.onProfileSaved != null) {
        widget.onProfileSaved!.call();
      } else {
        Navigator.pop(context, true);
      }
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
      onTap: uploadingAvatar ? null : pickAndUploadAvatar,
      child: CircleAvatar(
        radius: 50,
        backgroundColor: Colors.grey.shade300,
        backgroundImage: photoUrl != null ? NetworkImage(photoUrl!) : null,
        child: uploadingAvatar
            ? const CircularProgressIndicator()
            : photoUrl == null
                ? const Icon(Icons.camera_alt, size: 30)
                : null,
      ),
    );
  }

  ImageProvider? profileHeaderImageProvider() {
    if (headerImageFile != null) return FileImage(headerImageFile!);
    final url = headerImageUrl?.trim();
    if (url != null && url.isNotEmpty) return NetworkImage(url);
    return null;
  }

  Widget buildProfileCreationHeader() {
    final title = role == "employer"
        ? (companyController.text.trim().isNotEmpty
            ? companyController.text.trim()
            : contactPersonController.text.trim().isNotEmpty
                ? contactPersonController.text.trim()
                : "Company profile")
        : (nameController.text.trim().isNotEmpty
            ? nameController.text.trim()
            : "Worker profile");
    final subtitle = role == "employer"
        ? (contactPersonController.text.trim().isNotEmpty
            ? contactPersonController.text.trim()
            : "Company account")
        : (tradeController.text.trim().isNotEmpty
            ? tradeController.text.trim()
            : "Worker account");
    final headerImage = profileHeaderImageProvider();
    final hasHeaderImage = headerImage != null;

    return AppCard(
      margin: const EdgeInsets.fromLTRB(0, 0, 0, 16),
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          height: 210,
          child: DecoratedBox(
            decoration: BoxDecoration(
              image: hasHeaderImage
                  ? DecorationImage(
                      image: headerImage,
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: hasHeaderImage ? 0.10 : 0),
                    Colors.black.withValues(alpha: hasHeaderImage ? 0.20 : 0),
                  ],
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: CustomPaint(
                  painter: BlueprintDecorationPainter(
                    fillColor: Colors.white.withValues(alpha: 0.82),
                    lineColor: AppColors.blueprintLine.withValues(alpha: 0.55),
                    gridColor: AppColors.blueprintLine.withValues(alpha: 0.20),
                    radius: 12,
                    subtle: true,
                  ),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              GestureDetector(
                                onTap: uploadingAvatar
                                    ? null
                                    : pickAndUploadAvatar,
                                child: Stack(
                                  clipBehavior: Clip.none,
                                  alignment: Alignment.center,
                                  children: [
                                    StroykaAvatar(
                                      imageUrl: photoUrl,
                                      fallbackIcon: role == "employer"
                                          ? Icons.business
                                          : Icons.person,
                                      size: 88,
                                    ),
                                    Positioned(
                                      right: -8,
                                      bottom: -8,
                                      child: Material(
                                        color: AppColors.navy
                                            .withValues(alpha: 0.90),
                                        shape: const CircleBorder(),
                                        child: SizedBox(
                                          width: 34,
                                          height: 34,
                                          child: uploadingAvatar
                                              ? const Padding(
                                                  padding: EdgeInsets.all(8),
                                                  child:
                                                      CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                    color: Colors.white,
                                                  ),
                                                )
                                              : const Icon(
                                                  Icons.photo_camera_outlined,
                                                  color: Colors.white,
                                                  size: 18,
                                                ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                title,
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.ink,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                subtitle,
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.muted,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Tooltip(
                            message: "Choose background",
                            child: Material(
                              color: AppColors.navy.withValues(alpha: 0.90),
                              shape: const CircleBorder(),
                              child: IconButton(
                                onPressed: pickHeaderImage,
                                icon: const Icon(
                                  Icons.photo_camera_outlined,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
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
              },
              child: const Text("Edit"),
            ),
          ],
        ),
        const SizedBox(height: 10),
        StreamBuilder<List<String>>(
          stream: portfolioUrlsStream(userId),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const LinearProgressIndicator();
            }

            final photos = snapshot.data!;
            if (photos.isEmpty) return const Text("No work photos yet");

            return SizedBox(
              height: 90,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: photos.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, index) {
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(
                      photos[index],
                      width: 90,
                      height: 90,
                      fit: BoxFit.cover,
                    ),
                  );
                },
              ),
            );
          },
        ),
      ],
    );
  }

  Widget buildCompanyGalleryEditor() {
    if (role != "employer") return const SizedBox();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 20),
        Row(
          children: [
            const Expanded(
              child: Text(
                "Company gallery",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            OutlinedButton.icon(
              onPressed:
                  uploadingCompanyPhotos ? null : pickAndUploadCompanyPhotos,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: Text(uploadingCompanyPhotos ? "Uploading..." : "Add"),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (uploadingCompanyPhotos) ...[
          const LinearProgressIndicator(),
          const SizedBox(height: 12),
        ],
        if (companyPhotos.isEmpty)
          const Text("No company photos yet")
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: companyPhotos.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemBuilder: (context, index) {
              final photo = companyPhotos[index];

              return ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.network(
                      photo,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: Colors.grey.shade200,
                        alignment: Alignment.center,
                        child: const Icon(Icons.broken_image_outlined),
                      ),
                    ),
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Material(
                        color: Colors.black.withValues(alpha: 0.55),
                        shape: const CircleBorder(),
                        child: IconButton(
                          tooltip: "Remove photo",
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: uploadingCompanyPhotos
                              ? null
                              : () => removeCompanyPhoto(photo),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }

  Widget buildVerificationPanel() {
    final authUser = FirebaseAuth.instance.currentUser;
    final emailVerified = authUser?.emailVerified == true;
    return StroykaSurface(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            "Verification",
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                emailVerified ? Icons.verified : Icons.mark_email_unread,
                color: emailVerified ? AppColors.success : AppColors.warning,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  emailVerified ? "Email verified" : "Email not verified",
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              TextButton(
                onPressed: sendingEmailVerification
                    ? null
                    : (emailVerified
                        ? refreshEmailVerification
                        : sendEmailVerification),
                child: Text(emailVerified ? "Refresh" : "Send link"),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Row(
            children: [
              Icon(
                Icons.sms_failed_outlined,
                color: AppColors.warning,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  "Phone verification prepared. SMS provider is not configured yet.",
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget buildInvoiceDetailsForm() {
    if (role != "employer") return const SizedBox();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 18),
        const Text(
          "Manual invoice company details",
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        const Text(
          "Used for UK-style invoices if you choose Manual Invoice billing.",
          style: TextStyle(color: AppColors.muted),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: invoiceLegalCompanyNameController,
          decoration: const InputDecoration(labelText: "Legal company name"),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: invoiceTradingNameController,
          decoration: const InputDecoration(
            labelText: "Trading name if different",
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: invoiceCompanyNumberController,
          decoration: const InputDecoration(
            labelText: "Company registration number if Ltd",
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: invoiceRegisteredOfficeController,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: "Registered office address",
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: invoiceBillingAddressController,
          maxLines: 2,
          decoration: const InputDecoration(labelText: "Billing address"),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: invoiceBillingContactNameController,
          decoration: const InputDecoration(labelText: "Billing contact name"),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: invoiceVatNumberController,
          decoration: const InputDecoration(
            labelText: "VAT number if VAT registered",
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: invoicePurchaseOrderController,
          decoration: const InputDecoration(
            labelText: "Purchase order / reference if applicable",
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: invoicePaymentPhoneController,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: "Payment contact phone",
          ),
        ),
      ],
    );
  }

  Widget buildForm() {
    final accountEmail = (FirebaseAuth.instance.currentUser?.email ??
            billingEmailController.text.trim())
        .trim();
    final inlineEmailVerified = emailVerified ||
        FirebaseAuth.instance.currentUser?.emailVerified == true;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        buildProfileCreationHeader(),
        const SizedBox(height: 20),

        DropdownButtonFormField<String>(
          initialValue: role,
          decoration: const InputDecoration(
            labelText: "Account type",
            border: StroykaInputBorder(),
          ),
          items: const [
            DropdownMenuItem(value: "worker", child: Text("Worker")),
            DropdownMenuItem(value: "employer", child: Text("Employer")),
          ],
          onChanged: (value) => setState(() {
            role = value!;
            if (firstProfileCreation) {
              legalAcceptedForCurrentVersion = false;
            }
          }),
        ),

        const SizedBox(height: 20),

        if (role == "worker") ...[
          TextField(
            controller: nameController,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: "Name"),
          ),
          const SizedBox(height: 12),
          TextFormField(
            initialValue: accountEmail,
            readOnly: true,
            decoration: const InputDecoration(labelText: "Email"),
          ),
          buildInlineVerificationStatus(
            verified: inlineEmailVerified,
            verifiedText: "Verified",
            unverifiedText: "Not verified",
          ),
          const SizedBox(height: 12),
          TextField(
            controller: phoneController,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: "Phone"),
          ),
          buildInlineVerificationStatus(
            verified: phoneVerified,
            verifiedText: "Verified",
            unverifiedText: "Not verified",
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
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: "Trade"),
          ),
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
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: "Company name"),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: billingEmailController,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            decoration: const InputDecoration(
              labelText: "Company billing email *",
              helperText: "Invoices and billing notices will use this email.",
            ),
          ),
          buildInlineVerificationStatus(
            verified: billingEmailVerified ||
                (FirebaseAuth.instance.currentUser?.email?.toLowerCase() ==
                        billingEmailController.text.trim().toLowerCase() &&
                    FirebaseAuth.instance.currentUser?.emailVerified == true),
            verifiedText: "Verified",
            unverifiedText: "Not verified",
          ),
          buildInvoiceDetailsForm(),
          const SizedBox(height: 12),
          TextField(
            controller: websiteController,
            decoration: const InputDecoration(labelText: "Website"),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: contactPersonController,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: "Contact person"),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: phoneController,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: "Main phone"),
          ),
          buildInlineVerificationStatus(
            verified: phoneVerified,
            verifiedText: "Verified",
            unverifiedText: "Not verified",
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
          buildCompanyGalleryEditor(),
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
