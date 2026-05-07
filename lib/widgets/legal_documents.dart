import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../theme/stroyka_background.dart';

class LegalDocument {
  final String key;
  final String title;
  final String assetPath;

  const LegalDocument({
    required this.key,
    required this.title,
    required this.assetPath,
  });
}

class LegalDocuments {
  static const policyVersion = "2026-05-07";

  static const privacyPolicy = LegalDocument(
    key: "privacyPolicy",
    title: "Privacy Policy",
    assetPath: "assets/legal/privacy_policy.md",
  );
  static const termsOfUse = LegalDocument(
    key: "termsOfUse",
    title: "Terms of Use",
    assetPath: "assets/legal/terms_of_use.md",
  );
  static const codeOfConduct = LegalDocument(
    key: "codeOfConduct",
    title: "Code of Conduct",
    assetPath: "assets/legal/code_of_conduct.md",
  );
  static const workerTerms = LegalDocument(
    key: "workerTerms",
    title: "Worker Terms",
    assetPath: "assets/legal/worker_terms.md",
  );
  static const employerPostingPolicy = LegalDocument(
    key: "employerPostingPolicy",
    title: "Employer Posting Policy",
    assetPath: "assets/legal/employer_posting_policy.md",
  );
  static const refundPolicy = LegalDocument(
    key: "refundPolicy",
    title: "Refund Policy",
    assetPath: "assets/legal/refund_policy.md",
  );
  static const complaintsPolicy = LegalDocument(
    key: "complaintsPolicy",
    title: "Complaints Policy",
    assetPath: "assets/legal/complaints_policy.md",
  );
  static const cookiePolicy = LegalDocument(
    key: "cookiePolicy",
    title: "Cookie Policy",
    assetPath: "assets/legal/cookie_policy.md",
  );
  static const dataRetentionPolicy = LegalDocument(
    key: "dataRetentionPolicy",
    title: "Data Retention Policy",
    assetPath: "assets/legal/data_retention_policy.md",
  );
  static const ukPrivacyNotice = LegalDocument(
    key: "ukPrivacyNotice",
    title: "UK Privacy Notice",
    assetPath: "assets/legal/uk_privacy_notice.md",
  );
  static const companyInformation = LegalDocument(
    key: "companyInformation",
    title: "Company Information",
    assetPath: "assets/legal/company_information.md",
  );

  static const commonRequired = [
    privacyPolicy,
    termsOfUse,
    codeOfConduct,
    dataRetentionPolicy,
    ukPrivacyNotice,
    complaintsPolicy,
    cookiePolicy,
  ];

  static const all = [
    privacyPolicy,
    termsOfUse,
    codeOfConduct,
    workerTerms,
    employerPostingPolicy,
    refundPolicy,
    complaintsPolicy,
    cookiePolicy,
    dataRetentionPolicy,
    ukPrivacyNotice,
    companyInformation,
  ];

  static List<LegalDocument> requiredForRole(String role) {
    if (role == "employer") {
      return [
        ...commonRequired,
        employerPostingPolicy,
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
                            value: metadata["Version"] ?? "Draft",
                          ),
                          _LegalMetaChip(
                            label: "Updated",
                            value: metadata["UpdatedAt"] ?? "",
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
                    "Please read and accept the required documents",
                    style: TextStyle(
                      color: AppColors.ink,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    "You only need to do this during first profile creation, or when the policy version changes.",
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
              onPressed:
                  allAccepted ? () => Navigator.pop(context, true) : null,
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
