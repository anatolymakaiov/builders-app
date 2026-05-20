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
    final userRef = FirebaseFirestore.instance.collection("users").doc(userId);
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

  const LegalAcceptanceScreen({
    super.key,
    required this.role,
  });

  @override
  State<LegalAcceptanceScreen> createState() => _LegalAcceptanceScreenState();
}

class _LegalAcceptanceScreenState extends State<LegalAcceptanceScreen> {
  late final List<LegalDocument> documents;
  late final Map<String, bool> accepted;
  String language = LegalDocuments.defaultLanguage;

  @override
  void initState() {
    super.initState();
    documents = LegalDocuments.requiredForRole(widget.role);
    accepted = {
      for (final doc in documents) doc.key: false,
    };
  }

  bool get allAccepted => accepted.values.every((value) => value);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Legal documents")),
      body: StroykaScreenBody(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 110),
          children: [
            StroykaSurface(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Step 1: choose language",
                    style: TextStyle(
                      color: AppColors.ink,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: "en", label: Text("English")),
                      ButtonSegment(
                        value: "ru",
                        label: Text("Russian / Coming soon"),
                      ),
                    ],
                    selected: {language},
                    onSelectionChanged: (value) {
                      final next = value.first;
                      if (next != "en") {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text("Russian documents are coming soon"),
                          ),
                        );
                        return;
                      }
                      setState(() => language = next);
                    },
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    "Step 2: review and accept required documents",
                    style: TextStyle(
                      color: AppColors.ink,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    "Company: Stroyka UK Ltd\nVersion: ${LegalDocuments.policyVersion}\n${LegalDocuments.templateNotice}",
                    style: TextStyle(
                      color: AppColors.muted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ...documents.map((doc) {
                    return _LegalAcceptanceTile(
                      document: doc,
                      accepted: accepted[doc.key] ?? false,
                      onChanged: (value) {
                        setState(() => accepted[doc.key] = value ?? false);
                      },
                    );
                  }),
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
              onPressed: allAccepted
                  ? () => Navigator.pop(
                        context,
                        LegalAcceptanceResult(language: language),
                      )
                  : null,
              child: const Text("Continue"),
            ),
          ),
        ),
      ),
    );
  }
}

class _LegalAcceptanceTile extends StatelessWidget {
  final LegalDocument document;
  final bool accepted;
  final ValueChanged<bool?> onChanged;

  const _LegalAcceptanceTile({
    required this.document,
    required this.accepted,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.68),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: CheckboxListTile(
        value: accepted,
        onChanged: onChanged,
        controlAffinity: ListTileControlAffinity.leading,
        title: Text(
          document.title,
          style: const TextStyle(
            color: AppColors.ink,
            fontWeight: FontWeight.w900,
          ),
        ),
        subtitle: TextButton.icon(
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            alignment: Alignment.centerLeft,
          ),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => LegalDocumentScreen(document: document),
              ),
            );
          },
          icon: const Icon(Icons.description_outlined, size: 18),
          label: const Text("Open and read full document"),
        ),
        secondary: const Icon(Icons.check_circle_outline),
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
