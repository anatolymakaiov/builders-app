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
  final AddressLookupService? lookupService;
  final String postcodeLabel;
  final String addressLine1Label;
  final ValueChanged<PostalAddress>? onLookupResult;

  const UkPostalAddressForm({
    super.key,
    required this.controllers,
    this.lookupService,
    this.postcodeLabel = "Postcode",
    this.addressLine1Label = "Address Line 1",
    this.onLookupResult,
  });

  @override
  State<UkPostalAddressForm> createState() => _UkPostalAddressFormState();
}

class _UkPostalAddressFormState extends State<UkPostalAddressForm> {
  late final AddressLookupService lookupService;
  bool lookingUp = false;
  String statusText = "";

  @override
  void initState() {
    super.initState();
    lookupService =
        widget.lookupService ?? IdealPostcodesAddressLookupService();
  }

  void populateAddress(PostalAddress address) {
    widget.controllers.postcode.text = address.postcode;
    widget.controllers.addressLine1.text = address.addressLine1;
    widget.controllers.addressLine2.text = address.addressLine2;
    widget.controllers.addressLine3.text = address.addressLine3;
    widget.controllers.townCity.text = address.townCity;
    widget.controllers.county.text = address.county;
    widget.controllers.country.text =
        address.country.isNotEmpty ? address.country : "United Kingdom";
    widget.onLookupResult?.call(address);
  }

  Future<PostalAddress?> chooseAddress(List<PostalAddress> addresses) {
    return showModalBottomSheet<PostalAddress>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetContext).size.height * 0.72,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    "Select address",
                    style: Theme.of(sheetContext).textTheme.titleMedium,
                  ),
                ),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: addresses.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final address = addresses[index];
                      return ListTile(
                        title: Text(address.addressLine1.isNotEmpty
                            ? address.addressLine1
                            : address.selectionLabel),
                        subtitle: Text(address.selectionLabel),
                        onTap: () => Navigator.pop(sheetContext, address),
                      );
                    },
                  ),
                ),
                const Divider(height: 1),
                TextButton.icon(
                  onPressed: () => Navigator.pop(sheetContext),
                  icon: const Icon(Icons.edit_location_alt_outlined),
                  label: const Text("Enter address manually"),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> lookupPostcode() async {
    if (lookingUp) return;
    FocusManager.instance.primaryFocus?.unfocus();

    final normalized = lookupService.normalizePostcode(
      widget.controllers.postcode.text,
    );
    widget.controllers.postcode.text = normalized;

    if (!lookupService.isValidPostcode(normalized)) {
      setState(() => statusText = "Invalid postcode. Enter address manually.");
      return;
    }

    setState(() {
      lookingUp = true;
      statusText = "";
    });

    List<PostalAddress> addresses;
    try {
      addresses = await lookupService.lookupAddresses(normalized);
    } catch (_) {
      addresses = const [];
    }
    if (!mounted) return;

    if (addresses.isEmpty) {
      setState(() {
        lookingUp = false;
        statusText = "No address found. Enter address manually.";
      });
      return;
    }

    setState(() => lookingUp = false);
    final selected = await chooseAddress(addresses);
    if (!mounted) return;

    if (selected == null) {
      setState(() {
        statusText = "Enter address manually.";
      });
      return;
    }

    setState(() {
      populateAddress(selected);
      statusText = "Address selected.";
    });
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
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                statusText,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              TextButton.icon(
                onPressed: lookingUp
                    ? null
                    : () => setState(() {
                          statusText = "Enter address manually.";
                        }),
                icon: const Icon(Icons.edit_location_alt_outlined),
                label: const Text("Enter address manually"),
              ),
            ],
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
