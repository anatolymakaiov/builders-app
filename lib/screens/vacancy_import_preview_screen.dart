import 'package:flutter/material.dart';

import '../services/vacancy_import_service.dart';
import '../theme/app_theme.dart';
import '../theme/stroyka_background.dart';

class VacancyImportPreviewScreen extends StatefulWidget {
  final ParsedVacancy parsedVacancy;

  const VacancyImportPreviewScreen({
    super.key,
    required this.parsedVacancy,
  });

  @override
  State<VacancyImportPreviewScreen> createState() =>
      _VacancyImportPreviewScreenState();
}

class _VacancyImportPreviewScreenState
    extends State<VacancyImportPreviewScreen> {
  late final TextEditingController descriptionController;
  late final TextEditingController responsibilitiesController;
  late final TextEditingController requirementsController;
  late final TextEditingController documentsController;
  late final TextEditingController additionalController;

  @override
  void initState() {
    super.initState();
    final parsed = widget.parsedVacancy;
    descriptionController = TextEditingController(text: parsed.jobDescription);
    responsibilitiesController =
        TextEditingController(text: parsed.responsibilities);
    requirementsController = TextEditingController(text: parsed.requirements);
    documentsController = TextEditingController(
      text: parsed.requiredDocumentsAndCertifications,
    );
    additionalController =
        TextEditingController(text: parsed.additionalInformation);
  }

  @override
  void dispose() {
    descriptionController.dispose();
    responsibilitiesController.dispose();
    requirementsController.dispose();
    documentsController.dispose();
    additionalController.dispose();
    super.dispose();
  }

  ParsedVacancy currentValue() {
    return widget.parsedVacancy.copyWith(
      jobDescription: descriptionController.text.trim(),
      responsibilities: responsibilitiesController.text.trim(),
      requirements: requirementsController.text.trim(),
      requiredDocumentsAndCertifications: documentsController.text.trim(),
      additionalInformation: additionalController.text.trim(),
    );
  }

  Widget parsedField({
    required String label,
    required TextEditingController controller,
    int minLines = 3,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        minLines: minLines,
        maxLines: 8,
        decoration: InputDecoration(
          labelText: label,
          alignLabelWithHint: true,
        ),
      ),
    );
  }

  Widget missingFieldsNotice() {
    const fields = [
      "Profession / canonical role",
      "Salary / rate",
      "Work format",
      "Workers needed",
      "Hours per week",
      "Duration",
      "Site, address, postcode and coordinates",
      "Start / end dates",
    ];

    return StroykaSurface(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Manual fields still required",
            style: TextStyle(
              color: AppColors.ink,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          ...fields.map(
            (field) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 16,
                    color: AppColors.warning,
                  ),
                  const SizedBox(width: 6),
                  Expanded(child: Text(field)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final suggestedRole = widget.parsedVacancy.suggestedRole;

    return Scaffold(
      appBar: AppBar(title: const Text("Preview Parsed Vacancy")),
      body: StroykaScreenBody(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
          children: [
            StroykaSurface(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.parsedVacancy.sourceFileName,
                    style: const TextStyle(
                      color: AppColors.ink,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    "English-only parser. Imported content is plain text and can be edited before publishing.",
                  ),
                  if (suggestedRole != null &&
                      suggestedRole.trim().isNotEmpty) ...[
                    const SizedBox(height: 10),
                    AppChip.status(
                      "Suggested role: $suggestedRole",
                      color: AppColors.greenDark,
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      "The role is not selected automatically. Please confirm it manually on the job form.",
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            missingFieldsNotice(),
            const SizedBox(height: 12),
            StroykaSurface(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  parsedField(
                    label: "Job Description",
                    controller: descriptionController,
                  ),
                  parsedField(
                    label: "Responsibilities",
                    controller: responsibilitiesController,
                  ),
                  parsedField(
                    label: "Requirements",
                    controller: requirementsController,
                  ),
                  parsedField(
                    label: "Required documents / certifications",
                    controller: documentsController,
                  ),
                  parsedField(
                    label: "Additional Information",
                    controller: additionalController,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context, currentValue()),
              child: const Text("Apply Parsed Text"),
            ),
          ),
        ),
      ),
    );
  }
}
