import 'package:flutter/material.dart';

import '../../services/vacancy_import_service.dart';
import '../theme/web_theme.dart';
import 'web_design_components.dart';

class WebVacancyImportDialog extends StatefulWidget {
  const WebVacancyImportDialog({
    super.key,
    required this.parsedVacancy,
  });

  final ParsedVacancy parsedVacancy;

  @override
  State<WebVacancyImportDialog> createState() => _WebVacancyImportDialogState();
}

class _WebVacancyImportDialogState extends State<WebVacancyImportDialog> {
  late final TextEditingController description;
  late final TextEditingController responsibilities;
  late final TextEditingController requirements;
  late final TextEditingController documents;
  late final TextEditingController additional;

  @override
  void initState() {
    super.initState();
    final parsed = widget.parsedVacancy;
    description = TextEditingController(text: parsed.jobDescription);
    responsibilities = TextEditingController(text: parsed.responsibilities);
    requirements = TextEditingController(text: parsed.requirements);
    documents = TextEditingController(
      text: parsed.requiredDocumentsAndCertifications,
    );
    additional = TextEditingController(text: parsed.additionalInformation);
  }

  @override
  void dispose() {
    description.dispose();
    responsibilities.dispose();
    requirements.dispose();
    documents.dispose();
    additional.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final parsed = widget.parsedVacancy;
    return AlertDialog(
      title: const Text('Review imported vacancy'),
      content: WebDialogScrollArea(
        preferredWidth: 680,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              parsed.sourceFileName,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            const Text(
              'Review and edit the extracted text before applying it to the form.',
              style: TextStyle(color: WebTheme.muted),
            ),
            if (parsed.suggestedRole?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: WebStatusChip(
                  label: 'Suggested role: ${parsed.suggestedRole}',
                ),
              ),
            ],
            const SizedBox(height: 16),
            _field('Job Description', description, 4),
            _field('Responsibilities', responsibilities, 3),
            _field('Candidate requirements', requirements, 3),
            _field('Required documents / certifications', documents, 3),
            _field('Additional information', additional, 3),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            parsed.copyWith(
              jobDescription: description.text.trim(),
              responsibilities: responsibilities.text.trim(),
              requirements: requirements.text.trim(),
              requiredDocumentsAndCertifications: documents.text.trim(),
              additionalInformation: additional.text.trim(),
            ),
          ),
          child: const Text('Apply parsed text'),
        ),
      ],
    );
  }

  Widget _field(
    String label,
    TextEditingController controller,
    int lines,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        minLines: lines,
        maxLines: 8,
        decoration: InputDecoration(
          labelText: label,
          alignLabelWithHint: true,
        ),
      ),
    );
  }
}
