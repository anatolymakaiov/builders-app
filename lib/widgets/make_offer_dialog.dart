import 'package:flutter/material.dart';

import '../services/address_lookup_service.dart';
import '../services/offer_prefill_service.dart';
import '../theme/app_theme.dart';
import 'mobile_numeric_time_picker.dart';
import 'stroyka_date_time_field.dart';
import 'uk_postal_address_form.dart';

class MakeOfferDialog extends StatefulWidget {
  final OfferPrefill prefill;
  final AddressLookupService? addressLookupService;

  const MakeOfferDialog({
    super.key,
    required this.prefill,
    this.addressLookupService,
  });

  @override
  State<MakeOfferDialog> createState() => _MakeOfferDialogState();
}

class _MakeOfferDialogState extends State<MakeOfferDialog> {
  late String jobType;
  late final TextEditingController tradeController;
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
  TimeOfDay? workStart;
  TimeOfDay? workEnd;
  String? validationError;

  @override
  void initState() {
    super.initState();
    final prefill = widget.prefill;
    final address = prefill.address;
    jobType = prefill.jobType;
    tradeController = TextEditingController(text: prefill.trade);
    rateController = TextEditingController(text: prefill.rate);
    workPeriodController = TextEditingController(text: prefill.workPeriod);
    weeklyHoursController = TextEditingController(text: prefill.weeklyHours);
    scheduleController = TextEditingController(text: prefill.schedule);
    workStart = prefill.workStart;
    workEnd = prefill.workEnd;
    startDateTime = StroykaDateTimeValue(
      date: prefill.startDate,
      time: prefill.workStart,
    );
    siteAddressController = TextEditingController(
      text: address["siteStreet"] ?? address["siteAddress"] ?? "",
    );
    siteAddressLine2Controller = TextEditingController(
      text: address["siteAddressLine2"] ?? "",
    );
    siteAddressLine3Controller = TextEditingController(
      text: address["siteAddressLine3"] ?? "",
    );
    siteCityController = TextEditingController(
      text: address["siteCity"] ?? "",
    );
    siteCountyController = TextEditingController(
      text: address["siteCounty"] ?? "",
    );
    sitePostcodeController = TextEditingController(
      text: address["sitePostcode"] ?? "",
    );
    siteCountryController = TextEditingController(
      text: address["siteCountry"]?.isNotEmpty == true
          ? address["siteCountry"]
          : "United Kingdom",
    );
    firstDayRequirementsController =
        TextEditingController(text: prefill.firstDayRequirements);
    descriptionController = TextEditingController();
  }

  @override
  void dispose() {
    tradeController.dispose();
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
      setState(() => validationError =
          'Add a start date and time and complete the site address.');
      return;
    }
    if (workStart != null &&
        workEnd != null &&
        workEnd!.hour * 60 + workEnd!.minute <=
            workStart!.hour * 60 + workStart!.minute) {
      setState(() => validationError = 'Work end must be after work start.');
      return;
    }
    if (validUntil.dateTime != null &&
        !validUntil.dateTime!.isAfter(DateTime.now())) {
      setState(() => validationError = 'Offer deadline must be in the future.');
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
      "trade": tradeController.text.trim(),
      "jobType": jobType,
      "rate": rateController.text.trim(),
      "workPeriod": workPeriodController.text.trim(),
      "weeklyHours": weeklyHoursController.text.trim(),
      "schedule": scheduleController.text.trim(),
      "workStartTime":
          workStart == null ? "" : StroykaDateTimeFormat.formatTime(workStart!),
      "workEndTime":
          workEnd == null ? "" : StroykaDateTimeFormat.formatTime(workEnd!),
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

  Future<void> pickWorkTime({required bool start}) async {
    final picked = await showMobileNumericTimePicker(
      context: context,
      initialTime:
          (start ? workStart : workEnd) ?? const TimeOfDay(hour: 7, minute: 0),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (start) {
        workStart = picked;
      } else {
        workEnd = picked;
      }
      validationError = null;
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
              offerTextField(
                  controller: tradeController, label: 'Trade / role'),
              const SizedBox(height: 12),
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
              ListTile(
                title: const Text('Work starts'),
                subtitle: Text(workStart == null
                    ? 'Select time'
                    : StroykaDateTimeFormat.formatTime(workStart!)),
                trailing: const Icon(Icons.schedule_outlined),
                onTap: () => pickWorkTime(start: true),
              ),
              ListTile(
                title: const Text('Work ends'),
                subtitle: Text(workEnd == null
                    ? 'Select time'
                    : StroykaDateTimeFormat.formatTime(workEnd!)),
                trailing: const Icon(Icons.schedule_outlined),
                onTap: () => pickWorkTime(start: false),
              ),
              const SizedBox(height: 12),
              StroykaDateTimeField(
                label: "Start date and time",
                value: startDateTime,
                firstDate: prefillStartDateOrNow,
                onChanged: (value) => setState(() => startDateTime = value),
              ),
              if (validationError != null)
                Text(validationError!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 12),
              UkPostalAddressForm(
                lookupService: widget.addressLookupService,
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

  DateTime get prefillStartDateOrNow {
    final now = DateTime.now();
    final prefilled = widget.prefill.startDate;
    return prefilled != null && prefilled.isBefore(now) ? prefilled : now;
  }
}
