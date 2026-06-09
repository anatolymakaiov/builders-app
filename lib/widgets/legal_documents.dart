import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../theme/app_theme.dart';
import '../theme/stroyka_background.dart';

class LegalDocument {
  final String key;
  final String title;
  final String assetPath;
  final String version;
  final String effectiveDate;
  final List<String> requiredForRoles;

  const LegalDocument({
    required this.key,
    required this.title,
    required this.assetPath,
    required this.version,
    required this.effectiveDate,
    this.requiredForRoles = const ["worker", "employer"],
  });
}

class LegalDocuments {
  static const policyVersion = "2026-05-20";
  static const defaultLanguage = "en";
  static const templateNotice =
      "Template document — legal review required before public launch.";

  static const privacyPolicy = LegalDocument(
    key: "privacyPolicy",
    title: "Privacy Policy / Privacy Notice",
    assetPath: "assets/legal/privacy_policy.md",
    version: policyVersion,
    effectiveDate: "2026-05-20",
  );
  static const termsAndConditions = LegalDocument(
    key: "termsAndConditions",
    title: "Terms and Conditions",
    assetPath: "assets/legal/terms_of_use.md",
    version: policyVersion,
    effectiveDate: "2026-05-20",
  );
  static const dataProcessingConsentNotice = LegalDocument(
    key: "dataProcessingConsentNotice",
    title: "Data Processing & Consent Notice",
    assetPath: "assets/legal/data_processing_consent_notice.md",
    version: policyVersion,
    effectiveDate: "2026-05-20",
  );
  static const codeOfConduct = LegalDocument(
    key: "codeOfConduct",
    title: "Acceptable Use Policy / Code of Conduct",
    assetPath: "assets/legal/code_of_conduct.md",
    version: policyVersion,
    effectiveDate: "2026-05-20",
  );
  static const workerTerms = LegalDocument(
    key: "workerTerms",
    title: "Worker Terms",
    assetPath: "assets/legal/worker_terms.md",
    version: policyVersion,
    effectiveDate: "2026-05-20",
    requiredForRoles: ["worker"],
  );
  static const employerTerms = LegalDocument(
    key: "employerTerms",
    title: "Employer Terms",
    assetPath: "assets/legal/employer_terms.md",
    version: policyVersion,
    effectiveDate: "2026-05-20",
    requiredForRoles: ["employer"],
  );
  static const employerPostingPolicy = LegalDocument(
    key: "employerPostingPolicy",
    title: "Employer Posting Policy",
    assetPath: "assets/legal/employer_posting_policy.md",
    version: policyVersion,
    effectiveDate: "2026-05-20",
    requiredForRoles: ["employer"],
  );
  static const billingPaymentTerms = LegalDocument(
    key: "billingPaymentTerms",
    title: "Billing & Payment Terms",
    assetPath: "assets/legal/billing_payment_terms.md",
    version: policyVersion,
    effectiveDate: "2026-05-20",
    requiredForRoles: ["employer"],
  );
  static const refundPolicy = LegalDocument(
    key: "refundPolicy",
    title: "Refund Policy",
    assetPath: "assets/legal/refund_policy.md",
    version: policyVersion,
    effectiveDate: "2026-05-20",
    requiredForRoles: ["employer"],
  );
  static const complaintsPolicy = LegalDocument(
    key: "complaintsPolicy",
    title: "Complaints Policy",
    assetPath: "assets/legal/complaints_policy.md",
    version: policyVersion,
    effectiveDate: "2026-05-20",
  );
  static const cookiePolicy = LegalDocument(
    key: "cookiePolicy",
    title: "Cookie Policy placeholder for future web version",
    assetPath: "assets/legal/cookie_policy.md",
    version: policyVersion,
    effectiveDate: "2026-05-20",
  );
  static const dataRetentionPolicy = LegalDocument(
    key: "dataRetentionPolicy",
    title: "Data Retention Policy",
    assetPath: "assets/legal/data_retention_policy.md",
    version: policyVersion,
    effectiveDate: "2026-05-20",
  );
  static const accountDeletionPolicy = LegalDocument(
    key: "accountDeletionPolicy",
    title: "Account Deletion Notice",
    assetPath: "assets/legal/account_deletion_policy.md",
    version: policyVersion,
    effectiveDate: "2026-05-20",
  );
  static const safetyAbuseReportingPolicy = LegalDocument(
    key: "safetyAbuseReportingPolicy",
    title: "Safety & Abuse Reporting Policy",
    assetPath: "assets/legal/safety_abuse_reporting_policy.md",
    version: policyVersion,
    effectiveDate: "2026-05-20",
  );
  static const moderationPolicy = LegalDocument(
    key: "moderationPolicy",
    title: "Moderation Policy",
    assetPath: "assets/legal/moderation_policy.md",
    version: policyVersion,
    effectiveDate: "2026-05-20",
  );
  static const companyInformation = LegalDocument(
    key: "companyInformation",
    title: "Company Information",
    assetPath: "assets/legal/company_information.md",
    version: policyVersion,
    effectiveDate: "2026-05-20",
    requiredForRoles: [],
  );

  static const commonRequired = [
    privacyPolicy,
    termsAndConditions,
    dataProcessingConsentNotice,
    codeOfConduct,
    dataRetentionPolicy,
    accountDeletionPolicy,
    complaintsPolicy,
    cookiePolicy,
  ];

  static const all = [
    privacyPolicy,
    termsAndConditions,
    dataProcessingConsentNotice,
    codeOfConduct,
    workerTerms,
    employerTerms,
    employerPostingPolicy,
    billingPaymentTerms,
    refundPolicy,
    complaintsPolicy,
    safetyAbuseReportingPolicy,
    moderationPolicy,
    cookiePolicy,
    dataRetentionPolicy,
    accountDeletionPolicy,
    companyInformation,
  ];

  static List<LegalDocument> requiredForRole(String role) {
    if (role == "employer") {
      return [
        ...commonRequired,
        employerTerms,
        employerPostingPolicy,
        billingPaymentTerms,
        refundPolicy,
      ];
    }

    return [
      ...commonRequired,
      workerTerms,
    ];
  }

  static Map<String, bool> acceptedMapForRole(String role) {
    return {
      for (final doc in requiredForRole(role)) doc.key: true,
    };
  }

  static List<String> acceptedIdsForRole(String role) {
    return requiredForRole(role).map((doc) => doc.key).toList();
  }

  static bool hasAcceptedCurrentVersion(
    Map<String, dynamic>? data,
    String role,
  ) {
    if (data == null) return false;
    final acceptedDocuments =
        Map<String, dynamic>.from(data["acceptedDocuments"] ?? {});
    final acceptedIds = List<String>.from(data["acceptedDocumentIds"] ?? []);
    final acceptedVersion = data["acceptedPolicyVersion"] ??
        data["legalVersion"] ??
        data["policyVersion"];
    if (data["legalAccepted"] != true ||
        acceptedVersion != LegalDocuments.policyVersion) {
      return false;
    }
    return requiredForRole(role).every((doc) {
      return acceptedDocuments[doc.key] == true ||
          acceptedIds.contains(doc.key);
    });
  }

  static Future<void> saveAcceptances({
    required String userId,
    required String role,
    String language = defaultLanguage,
  }) async {
    final docs = requiredForRole(role);
    final firestore = FirebaseFirestore.instance;
    final activeUserRef = firestore.collection("users").doc(userId);
    final activeUserSnapshot = await activeUserRef.get();
    final userRef = activeUserSnapshot.exists
        ? activeUserRef
        : firestore.collection("pending_registrations").doc(userId);
    final batch = FirebaseFirestore.instance.batch();

    for (final doc in docs) {
      batch.set(
          userRef.collection("legalAcceptances").doc(doc.key),
          {
            "documentId": doc.key,
            "documentTitle": doc.title,
            "documentVersion": doc.version,
            "role": role,
            "language": language,
            "acceptedAt": FieldValue.serverTimestamp(),
            "required": true,
          },
          SetOptions(merge: true));
    }

    batch.set(
        userRef,
        {
          "legalAccepted": true,
          "legalAcceptedAt": FieldValue.serverTimestamp(),
          "legalVersion": policyVersion,
          "acceptedPolicyVersion": policyVersion,
          "acceptedLanguage": language,
          "acceptedDocuments": acceptedMapForRole(role),
          "acceptedDocumentIds": acceptedIdsForRole(role),
          "onboardingLegalStepComplete": true,
        },
        SetOptions(merge: true));

    await batch.commit();
  }
}

class LegalAcceptanceResult {
  final String language;

  const LegalAcceptanceResult({
    required this.language,
  });
}

class LegalDocumentScreen extends StatelessWidget {
  final LegalDocument document;

  const LegalDocumentScreen({
    super.key,
    required this.document,
  });

  Map<String, String> parseMetadata(String content) {
    final metadata = <String, String>{};
    for (final line in content.split("\n").take(3)) {
      final separatorIndex = line.indexOf(":");
      if (separatorIndex <= 0) continue;
      metadata[line.substring(0, separatorIndex).trim()] =
          line.substring(separatorIndex + 1).trim();
    }
    return metadata;
  }

  String bodyWithoutMetadata(String content) {
    final lines = content.split("\n");
    if (lines.length <= 4) return content;
    return lines.skip(4).join("\n").trim();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(document.title)),
      body: StroykaScreenBody(
        child: FutureBuilder<String>(
          future: rootBundle.loadString(document.assetPath),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Center(child: Text("Could not load document"));
            }

            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final content = snapshot.data!;
            final metadata = parseMetadata(content);
            final body = bodyWithoutMetadata(content);
            final effectiveDate =
                metadata["EffectiveDate"] ?? document.effectiveDate;

            return ListView(
              padding: const EdgeInsets.all(12),
              children: [
                StroykaSurface(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        metadata["Title"] ?? document.title,
                        style: const TextStyle(
                          color: AppColors.ink,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _LegalMetaChip(
                            label: "Version",
                            value: metadata["Version"] ?? document.version,
                          ),
                          _LegalMetaChip(
                            label: "Effective",
                            value: effectiveDate,
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      SelectableText(
                        body,
                        style: const TextStyle(
                          color: AppColors.ink,
                          height: 1.45,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class LegalAcceptanceScreen extends StatefulWidget {
  final String role;
  final String? userId;
  final Future<void> Function(LegalAcceptanceResult result)? onAccepted;

  const LegalAcceptanceScreen({
    super.key,
    required this.role,
    this.userId,
    this.onAccepted,
  });

  @override
  State<LegalAcceptanceScreen> createState() => _LegalAcceptanceScreenState();
}

class _LegalAcceptanceScreenState extends State<LegalAcceptanceScreen> {
  late final List<LegalDocument> documents;
  String language = LegalDocuments.defaultLanguage;
  bool validationAttempted = false;
  bool consentAccepted = false;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    documents = LegalDocuments.requiredForRole(widget.role);
  }

  Future<void> continueIfValid() async {
    if (!consentAccepted) {
      setState(() => validationAttempted = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "You must confirm that you have read and agree to the required documents before continuing.",
          ),
        ),
      );
      return;
    }

    final result = LegalAcceptanceResult(language: language);

    if (widget.userId != null || widget.onAccepted != null) {
      setState(() => saving = true);
      try {
        if (widget.userId != null) {
          await LegalDocuments.saveAcceptances(
            userId: widget.userId!,
            role: widget.role,
            language: result.language,
          );
        }
        await widget.onAccepted?.call(result);
      } catch (e) {
        debugPrint("Legal acceptance save error: $e");
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Could not save legal acceptance. Please try again."),
          ),
        );
      } finally {
        if (mounted) setState(() => saving = false);
      }
      return;
    }

    Navigator.pop(context, result);
  }

  List<LegalDocument> get compactDocuments {
    final keys = <String>{
      LegalDocuments.termsAndConditions.key,
      LegalDocuments.privacyPolicy.key,
      LegalDocuments.codeOfConduct.key,
      LegalDocuments.dataProcessingConsentNotice.key,
      if (widget.role == "employer") LegalDocuments.billingPaymentTerms.key,
    };

    return LegalDocuments.all.where((doc) => keys.contains(doc.key)).toList();
  }

  String documentShortTitle(LegalDocument document) {
    switch (document.key) {
      case "termsAndConditions":
        return "Terms & Conditions";
      case "privacyPolicy":
        return "Privacy Policy";
      case "codeOfConduct":
        return "Community Rules";
      case "dataProcessingConsentNotice":
        return "Data Consent";
      case "billingPaymentTerms":
        return "Billing & Subscription Terms";
      default:
        return document.title;
    }
  }

  void openDocument(LegalDocument document) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LegalDocumentScreen(document: document),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Create account")),
      body: StroykaScreenBody(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 110),
          children: [
            Center(
              child: Column(
                children: [
                  const StroykaAvatar(
                    fallbackIcon: Icons.construction_outlined,
                    size: 70,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    "STROYKA UK Ltd",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.role == "employer"
                        ? "Employer registration"
                        : "Worker registration",
                    style: const TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            StroykaSurface(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceAlt.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Container(
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: AppColors.greenDark,
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: const Text(
                              "Sign Up",
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Container(
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: const Text(
                              "Sign In",
                              style: TextStyle(
                                color: AppColors.muted,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    "Legal consent",
                    style: TextStyle(
                      color: AppColors.ink,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    "Please confirm you are over 18 and agree to the required platform documents before continuing.",
                    style: TextStyle(
                      color: AppColors.muted,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    decoration: BoxDecoration(
                      color: validationAttempted && !consentAccepted
                          ? AppColors.danger.withValues(alpha: 0.08)
                          : Colors.white.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: validationAttempted && !consentAccepted
                            ? AppColors.danger
                            : Colors.black.withValues(alpha: 0.08),
                      ),
                    ),
                    child: CheckboxListTile(
                      value: consentAccepted,
                      onChanged: (value) {
                        setState(() {
                          consentAccepted = value ?? false;
                          if (consentAccepted) validationAttempted = false;
                        });
                      },
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text(
                        "I confirm that I am over 18 years old and agree to the required legal documents.",
                        style: TextStyle(
                          color: AppColors.ink,
                          fontWeight: FontWeight.w800,
                          height: 1.25,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: compactDocuments.map((doc) {
                      return ActionChip(
                        avatar: const Icon(Icons.description_outlined),
                        label: Text(documentShortTitle(doc)),
                        onPressed: () => openDocument(doc),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    "Version ${LegalDocuments.policyVersion}. ${LegalDocuments.templateNotice}",
                    style: TextStyle(
                      color: AppColors.muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            StroykaSurface(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  const Icon(Icons.language, color: AppColors.greenDark),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      "Language",
                      style: TextStyle(
                        color: AppColors.ink,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: language,
                      items: const [
                        DropdownMenuItem(
                          value: "en",
                          child: Text("English"),
                        ),
                        DropdownMenuItem(
                          value: "ru",
                          enabled: false,
                          child: Text("Russian soon"),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => language = value);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            height: 50,
            child: ElevatedButton(
              onPressed: saving ? null : continueIfValid,
              child: saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text("Continue"),
            ),
          ),
        ),
      ),
    );
  }
}

class _LegalMetaChip extends StatelessWidget {
  final String label;
  final String value;

  const _LegalMetaChip({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    if (value.trim().isEmpty) return const SizedBox();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.green.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        "$label: $value",
        style: const TextStyle(
          color: AppColors.ink,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
