import 'package:flutter/material.dart';

import '../services/address_lookup_service.dart';

class UkPostalAddressControllers {
  final TextEditingController postcode;
  final TextEditingController addressLine1;
  final TextEditingController addressLine2;
  final TextEditingController addressLine3;
  final TextEditingController townCity;
  final TextEditingController county;
  final TextEditingController country;

  const UkPostalAddressControllers({
    required this.postcode,
    required this.addressLine1,
    required this.addressLine2,
    required this.addressLine3,
    required this.townCity,
    required this.county,
    required this.country,
  });

  PostalAddress value() {
    return PostalAddress(
      postcode: postcode.text.trim(),
      addressLine1: addressLine1.text.trim(),
      addressLine2: addressLine2.text.trim(),
      addressLine3: addressLine3.text.trim(),
      townCity: townCity.text.trim(),
      county: county.text.trim(),
      country: country.text.trim(),
    );
  }
}

class UkPostalAddressForm extends StatefulWidget {
  final UkPostalAddressControllers controllers;
  final AddressLookupService lookupService;
  final String postcodeLabel;
  final String addressLine1Label;
  final ValueChanged<PostalAddress>? onLookupResult;

  const UkPostalAddressForm({
    super.key,
    required this.controllers,
    this.lookupService = const _DefaultAddressLookupService(),
    this.postcodeLabel = "Postcode",
    this.addressLine1Label = "Address Line 1",
    this.onLookupResult,
  });

  @override
  State<UkPostalAddressForm> createState() => _UkPostalAddressFormState();
}

class _UkPostalAddressFormState extends State<UkPostalAddressForm> {
  bool lookingUp = false;
  String statusText = "";

  Future<void> lookupPostcode() async {
    if (lookingUp) return;
    FocusManager.instance.primaryFocus?.unfocus();

    final normalized = widget.lookupService
        .normalizePostcode(widget.controllers.postcode.text);
    widget.controllers.postcode.text = normalized;

    if (!widget.lookupService.isValidPostcode(normalized)) {
      setState(() => statusText = "Invalid postcode. Enter address manually.");
      return;
    }

    setState(() {
      lookingUp = true;
      statusText = "";
    });

    final result = await widget.lookupService.lookupPostcode(normalized);
    if (!mounted) return;

    if (result == null) {
      setState(() {
        lookingUp = false;
        statusText = "Postcode not found. Enter address manually.";
      });
      return;
    }

    setState(() {
      widget.controllers.postcode.text = result.postcode;
      if (result.townCity.isNotEmpty) {
        widget.controllers.townCity.text = result.townCity;
      }
      if (result.county.isNotEmpty) {
        widget.controllers.county.text = result.county;
      }
      if (result.country.isNotEmpty) {
        widget.controllers.country.text = result.country;
      }
      lookingUp = false;
      statusText = "Postcode found. Complete address manually if needed.";
    });
    widget.onLookupResult?.call(result);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: widget.controllers.postcode,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(labelText: widget.postcodeLabel),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: "Search postcode",
              onPressed: lookingUp ? null : lookupPostcode,
              icon: lookingUp
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.search),
            ),
          ],
        ),
        if (statusText.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            statusText,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: widget.controllers.addressLine1,
          decoration: InputDecoration(labelText: widget.addressLine1Label),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: widget.controllers.addressLine2,
          decoration: const InputDecoration(labelText: "Address Line 2"),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: widget.controllers.addressLine3,
          decoration: const InputDecoration(labelText: "Address Line 3"),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: widget.controllers.townCity,
          decoration: const InputDecoration(labelText: "Town / City"),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: widget.controllers.county,
          decoration: const InputDecoration(labelText: "County"),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: widget.controllers.country,
          decoration: const InputDecoration(labelText: "Country"),
        ),
      ],
    );
  }
}

class _DefaultAddressLookupService extends PostcodesIoAddressLookupService {
  const _DefaultAddressLookupService();
}
