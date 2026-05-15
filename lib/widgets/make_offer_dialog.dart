import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class MakeOfferDialog extends StatefulWidget {
  final Map<String, String> physicalAddressFields;

  const MakeOfferDialog({
    super.key,
    required this.physicalAddressFields,
  });

  @override
  State<MakeOfferDialog> createState() => _MakeOfferDialogState();
}

class _MakeOfferDialogState extends State<MakeOfferDialog> {
  String jobType = "hourly";
  late final TextEditingController rateController;
  late final TextEditingController workPeriodController;
  late final TextEditingController weeklyHoursController;
  late final TextEditingController scheduleController;
  late final TextEditingController startDateTimeController;
  late final TextEditingController siteAddressController;
  late final TextEditingController firstDayRequirementsController;
  late final TextEditingController descriptionController;
  late final TextEditingController validUntilController;

  @override
  void initState() {
    super.initState();
    rateController = TextEditingController();
    workPeriodController = TextEditingController();
    weeklyHoursController = TextEditingController();
    scheduleController = TextEditingController();
    startDateTimeController = TextEditingController();
    siteAddressController = TextEditingController(
      text: widget.physicalAddressFields["siteAddress"] ?? "",
    );
    firstDayRequirementsController = TextEditingController();
    descriptionController = TextEditingController();
    validUntilController = TextEditingController();
  }

  @override
  void dispose() {
    rateController.dispose();
    workPeriodController.dispose();
    weeklyHoursController.dispose();
    scheduleController.dispose();
    startDateTimeController.dispose();
    siteAddressController.dispose();
    firstDayRequirementsController.dispose();
    descriptionController.dispose();
    validUntilController.dispose();
    super.dispose();
  }

  Widget offerTextField({
    required TextEditingController controller,
    required String label,
    String? hint,
    TextInputType? keyboardType,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const StroykaInputBorder(),
      ),
    );
  }

  void submit() {
    if (startDateTimeController.text.trim().isEmpty ||
        siteAddressController.text.trim().isEmpty) {
      return;
    }

    Navigator.of(context).pop({
      "jobType": jobType,
      "rate": rateController.text.trim(),
      "workPeriod": workPeriodController.text.trim(),
      "weeklyHours": weeklyHoursController.text.trim(),
      "schedule": scheduleController.text.trim(),
      "startDateTime": startDateTimeController.text.trim(),
      "siteAddress": siteAddressController.text.trim(),
      "firstDayRequirements": firstDayRequirementsController.text.trim(),
      "description": descriptionController.text.trim(),
      "validUntil": validUntilController.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Make offer"),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: jobType,
                decoration: const InputDecoration(
                  labelText: "Work format",
                  hintText: "Daywork, price, negotiable",
                  border: StroykaInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: "hourly",
                    child: Text("Daywork"),
                  ),
                  DropdownMenuItem(
                    value: "price",
                    child: Text("Price"),
                  ),
                  DropdownMenuItem(
                    value: "negotiable",
                    child: Text("Negotiable"),
                  ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => jobType = value);
                },
              ),
              const SizedBox(height: 12),
              offerTextField(
                controller: rateController,
                label: jobType == "price" ? "Price (£)" : "Rate (£)",
                hint: jobType == "price"
                    ? "Total project price"
                    : "Hourly or day rate",
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              offerTextField(
                controller: workPeriodController,
                label: "Work period",
                hint: "2 weeks, 3 months, ongoing",
              ),
              const SizedBox(height: 12),
              offerTextField(
                controller: weeklyHoursController,
                label: "Hours per week",
                hint: "40",
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              offerTextField(
                controller: scheduleController,
                label: "Work schedule",
                hint: "7:00-17:00, 1 hour break",
              ),
              const SizedBox(height: 12),
              offerTextField(
                controller: startDateTimeController,
                label: "Start date and time",
                hint: "Monday 12 May, 7:00",
              ),
              const SizedBox(height: 12),
              offerTextField(
                controller: siteAddressController,
                label: "Site address",
                hint: "Full construction site address",
              ),
              const SizedBox(height: 12),
              offerTextField(
                controller: firstDayRequirementsController,
                label: "Required on first day",
                hint: "Documents, certifications, tools, PPE, etc.",
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              offerTextField(
                controller: descriptionController,
                label: "Offer description",
                hint: "Additional conditions, notes, or expectations",
                maxLines: 3,
              ),
              const SizedBox(height: 12),
              offerTextField(
                controller: validUntilController,
                label: "Offer valid until",
                hint: "Friday 16 May, 18:00",
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text("Cancel"),
        ),
        ElevatedButton(
          onPressed: submit,
          child: const Text("Send offer"),
        ),
      ],
    );
  }
}
