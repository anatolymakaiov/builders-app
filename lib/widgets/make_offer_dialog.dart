import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'stroyka_date_time_field.dart';
import 'uk_postal_address_form.dart';

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
  late final TextEditingController siteAddressController;
  late final TextEditingController siteAddressLine2Controller;
  late final TextEditingController siteAddressLine3Controller;
  late final TextEditingController siteCityController;
  late final TextEditingController siteCountyController;
  late final TextEditingController sitePostcodeController;
  late final TextEditingController siteCountryController;
  late final TextEditingController firstDayRequirementsController;
  late final TextEditingController descriptionController;
  StroykaDateTimeValue startDateTime = const StroykaDateTimeValue();
  StroykaDateTimeValue validUntil = const StroykaDateTimeValue();

  @override
  void initState() {
    super.initState();
    rateController = TextEditingController();
    workPeriodController = TextEditingController();
    weeklyHoursController = TextEditingController();
    scheduleController = TextEditingController();
    siteAddressController = TextEditingController(
      text: widget.physicalAddressFields["siteStreet"] ??
          widget.physicalAddressFields["siteAddress"] ??
          "",
    );
    siteAddressLine2Controller = TextEditingController(
      text: widget.physicalAddressFields["siteAddressLine2"] ?? "",
    );
    siteAddressLine3Controller = TextEditingController(
      text: widget.physicalAddressFields["siteAddressLine3"] ?? "",
    );
    siteCityController = TextEditingController(
      text: widget.physicalAddressFields["siteCity"] ?? "",
    );
    siteCountyController = TextEditingController(
      text: widget.physicalAddressFields["siteCounty"] ?? "",
    );
    sitePostcodeController = TextEditingController(
      text: widget.physicalAddressFields["sitePostcode"] ?? "",
    );
    siteCountryController = TextEditingController(
      text: widget.physicalAddressFields["siteCountry"] ?? "United Kingdom",
    );
    firstDayRequirementsController = TextEditingController();
    descriptionController = TextEditingController();
  }

  @override
  void dispose() {
    rateController.dispose();
    workPeriodController.dispose();
    weeklyHoursController.dispose();
    scheduleController.dispose();
    siteAddressController.dispose();
    siteAddressLine2Controller.dispose();
    siteAddressLine3Controller.dispose();
    siteCityController.dispose();
    siteCountyController.dispose();
    sitePostcodeController.dispose();
    siteCountryController.dispose();
    firstDayRequirementsController.dispose();
    descriptionController.dispose();
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
    if (startDateTime.dateTime == null ||
        startDateTime.time == null ||
        siteAddressController.text.trim().isEmpty ||
        siteCityController.text.trim().isEmpty ||
        siteCountryController.text.trim().isEmpty) {
      return;
    }
    final siteAddress = UkPostalAddressControllers(
      postcode: sitePostcodeController,
      addressLine1: siteAddressController,
      addressLine2: siteAddressLine2Controller,
      addressLine3: siteAddressLine3Controller,
      townCity: siteCityController,
      county: siteCountyController,
      country: siteCountryController,
    ).value();

    Navigator.of(context).pop({
      "jobType": jobType,
      "rate": rateController.text.trim(),
      "workPeriod": workPeriodController.text.trim(),
      "weeklyHours": weeklyHoursController.text.trim(),
      "schedule": scheduleController.text.trim(),
      "startDateTime": startDateTime.displayText,
      "startDateTimestamp": startDateTime.dateTime,
      "siteStreet": siteAddress.addressLine1,
      "siteAddressLine1": siteAddress.addressLine1,
      "siteAddressLine2": siteAddress.addressLine2,
      "siteAddressLine3": siteAddress.addressLine3,
      "siteCity": siteAddress.townCity,
      "sitePostcode": siteAddress.postcode,
      "siteCounty": siteAddress.county,
      "siteCountry": siteAddress.country,
      "siteAddress": siteAddress.singleLine,
      "firstDayRequirements": firstDayRequirementsController.text.trim(),
      "description": descriptionController.text.trim(),
      "validUntil": validUntil.displayText,
      if (validUntil.dateTime != null)
        "validUntilTimestamp": validUntil.dateTime,
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
              StroykaDateTimeField(
                label: "Start date and time",
                value: startDateTime,
                firstDate: DateTime.now(),
                onChanged: (value) => setState(() => startDateTime = value),
              ),
              const SizedBox(height: 12),
              UkPostalAddressForm(
                controllers: UkPostalAddressControllers(
                  postcode: sitePostcodeController,
                  addressLine1: siteAddressController,
                  addressLine2: siteAddressLine2Controller,
                  addressLine3: siteAddressLine3Controller,
                  townCity: siteCityController,
                  county: siteCountyController,
                  country: siteCountryController,
                ),
                postcodeLabel: "Site postcode",
                addressLine1Label: "Site Address Line 1",
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
              StroykaDateTimeField(
                label: "Offer valid until",
                value: validUntil,
                firstDate: DateTime.now(),
                onChanged: (value) => setState(() => validUntil = value),
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
