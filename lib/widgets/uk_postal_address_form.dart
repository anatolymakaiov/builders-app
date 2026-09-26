import 'dart:async';

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
  final bool autoLookup;
  final bool showManualEntryShortcut;

  const UkPostalAddressForm({
    super.key,
    required this.controllers,
    this.lookupService,
    this.postcodeLabel = "Postcode",
    this.addressLine1Label = "Address Line 1",
    this.onLookupResult,
    this.autoLookup = false,
    this.showManualEntryShortcut = false,
  });

  @override
  State<UkPostalAddressForm> createState() => _UkPostalAddressFormState();
}

class _UkPostalAddressFormState extends State<UkPostalAddressForm> {
  late AddressLookupService lookupService;
  final addressLine1Focus = FocusNode();
  Timer? lookupDebounce;
  int lookupRevision = 0;
  int? activeRevision;
  String? activePostcode;
  bool settingPostcode = false;
  bool lookingUp = false;
  String statusText = "";
  bool statusIsError = false;
  bool manualEntrySuggested = false;

  @override
  void initState() {
    super.initState();
    lookupService =
        widget.lookupService ?? IdealPostcodesAddressLookupService();
    manualEntrySuggested = widget.showManualEntryShortcut;
    widget.controllers.postcode.addListener(onPostcodeChanged);
  }

  @override
  void didUpdateWidget(covariant UkPostalAddressForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lookupService != widget.lookupService) {
      lookupService =
          widget.lookupService ?? IdealPostcodesAddressLookupService();
      lookupRevision++;
      lookupDebounce?.cancel();
      lookingUp = false;
    }
    if (oldWidget.controllers.postcode != widget.controllers.postcode) {
      oldWidget.controllers.postcode.removeListener(onPostcodeChanged);
      widget.controllers.postcode.addListener(onPostcodeChanged);
      lookupRevision++;
      lookupDebounce?.cancel();
      lookingUp = false;
      statusText = '';
      manualEntrySuggested = widget.showManualEntryShortcut;
    }
  }

  @override
  void dispose() {
    lookupDebounce?.cancel();
    widget.controllers.postcode.removeListener(onPostcodeChanged);
    addressLine1Focus.dispose();
    super.dispose();
  }

  void onPostcodeChanged() {
    if (settingPostcode) return;
    lookupRevision++;
    lookupDebounce?.cancel();
    setState(() {
      lookingUp = false;
      statusText = '';
      statusIsError = false;
      manualEntrySuggested = widget.showManualEntryShortcut;
    });
    if (widget.autoLookup &&
        lookupService.isValidPostcode(widget.controllers.postcode.text)) {
      lookupDebounce = Timer(
        const Duration(milliseconds: 500),
        lookupPostcode,
      );
    }
  }

  void populateAddress(PostalAddress address) {
    settingPostcode = true;
    widget.controllers.postcode.text = address.postcode;
    settingPostcode = false;
    if (address.addressLine1.isNotEmpty) {
      widget.controllers.addressLine1.text = address.addressLine1;
      widget.controllers.addressLine2.text = address.addressLine2;
      widget.controllers.addressLine3.text = address.addressLine3;
    }
    if (address.townCity.isNotEmpty) {
      widget.controllers.townCity.text = address.townCity;
    }
    if (address.county.isNotEmpty) {
      widget.controllers.county.text = address.county;
    }
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
    lookupDebounce?.cancel();
    FocusManager.instance.primaryFocus?.unfocus();

    final normalized = lookupService.normalizePostcode(
      widget.controllers.postcode.text,
    );
    settingPostcode = true;
    widget.controllers.postcode.text = normalized;
    settingPostcode = false;

    if (!lookupService.isValidPostcode(normalized)) {
      setState(() {
        statusText = 'Invalid UK postcode. Check it or enter address manually.';
        statusIsError = true;
      });
      return;
    }

    if (activePostcode == normalized && activeRevision == lookupRevision) {
      return;
    }

    final revision = ++lookupRevision;
    activeRevision = revision;
    activePostcode = normalized;
    setState(() {
      lookingUp = true;
      statusText = "";
      statusIsError = false;
    });

    List<PostalAddress> addresses = const [];
    String? failure;
    try {
      addresses = await lookupService.lookupAddresses(normalized);
    } on AddressLookupException catch (error) {
      failure = error.message;
    } catch (_) {
      failure = 'Address lookup is unavailable. Enter address manually.';
    }
    if (activeRevision == revision) {
      activeRevision = null;
      activePostcode = null;
    }
    if (!mounted || lookupRevision != revision) return;

    if (failure != null) {
      setState(() {
        lookingUp = false;
        statusText = failure!;
        statusIsError = true;
        manualEntrySuggested = true;
      });
      return;
    }

    if (addresses.isEmpty) {
      setState(() {
        lookingUp = false;
        statusText = "No address found. Enter address manually.";
        statusIsError = true;
        manualEntrySuggested = true;
      });
      return;
    }

    setState(() => lookingUp = false);
    final selected = await chooseAddress(addresses);
    if (!mounted) return;

    if (selected == null) {
      setState(() {
        statusText = "Enter address manually.";
        manualEntrySuggested = true;
      });
      return;
    }

    setState(() {
      populateAddress(selected);
      manualEntrySuggested = selected.addressLine1.isEmpty;
      statusText = manualEntrySuggested
          ? 'Postcode found. Enter Address Line 1 and confirm town/city.'
          : 'Address selected.';
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
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => lookupPostcode(),
                decoration: InputDecoration(labelText: widget.postcodeLabel),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: "Search postcode",
              onPressed: lookupPostcode,
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
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: statusIsError
                      ? Theme.of(context).colorScheme.error
                      : null,
                ),
          ),
        ],
        if (manualEntrySuggested)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () {
                lookupDebounce?.cancel();
                lookupRevision++;
                setState(() {
                  lookingUp = false;
                  statusText = 'Enter address manually.';
                  statusIsError = false;
                });
                addressLine1Focus.requestFocus();
              },
              icon: const Icon(Icons.edit_location_alt_outlined),
              label: const Text('Enter address manually'),
            ),
          ),
        const SizedBox(height: 12),
        TextField(
          controller: widget.controllers.addressLine1,
          focusNode: addressLine1Focus,
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
