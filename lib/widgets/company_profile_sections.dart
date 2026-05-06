import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/stroyka_background.dart';
import 'phone_link.dart';

class CompanyInfoWidget extends StatelessWidget {
  final String description;
  final String address;
  final String companyGoals;
  final String companyAdvantages;
  final String companyClients;
  final String companyWhoWeAre;
  final String companyHistory;

  const CompanyInfoWidget({
    super.key,
    required this.description,
    required this.address,
    required this.companyGoals,
    required this.companyAdvantages,
    required this.companyClients,
    required this.companyWhoWeAre,
    required this.companyHistory,
  });

  @override
  Widget build(BuildContext context) {
    return StroykaSurface(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "About company",
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            description.trim().isEmpty
                ? "No company description yet"
                : description,
          ),
          _CompanyInfoBlock(
            title: "Our goals and objectives",
            text: companyGoals,
          ),
          _CompanyInfoBlock(
            title: "Our advantages",
            text: companyAdvantages,
          ),
          _CompanyInfoBlock(
            title: "Our clients",
            text: companyClients,
          ),
          _CompanyInfoBlock(
            title: "Who we are",
            text: companyWhoWeAre,
          ),
          _CompanyInfoBlock(
            title: "Our history",
            text: companyHistory,
          ),
          if (address.trim().isNotEmpty) ...[
            const SizedBox(height: 18),
            Row(
              children: [
                const Icon(Icons.location_on),
                const SizedBox(width: 8),
                Expanded(child: Text(address)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class CompanyContactsWidget extends StatelessWidget {
  final String phone;
  final String contactPerson;
  final List<String> extraPhones;
  final String email;
  final String website;
  final List<Map<String, dynamic>> contacts;

  const CompanyContactsWidget({
    super.key,
    required this.phone,
    required this.contactPerson,
    required this.extraPhones,
    required this.email,
    required this.website,
    required this.contacts,
  });

  @override
  Widget build(BuildContext context) {
    final hasDirectContacts = phone.trim().isNotEmpty ||
        contactPerson.trim().isNotEmpty ||
        extraPhones.isNotEmpty ||
        email.trim().isNotEmpty ||
        website.trim().isNotEmpty;

    return StroykaSurface(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (phone.trim().isNotEmpty) ...[
            PhoneLink(phone: phone),
            const SizedBox(height: 16),
          ],
          if (contactPerson.trim().isNotEmpty) ...[
            Row(
              children: [
                const Icon(Icons.person),
                const SizedBox(width: 8),
                Expanded(child: Text(contactPerson)),
              ],
            ),
            const SizedBox(height: 16),
          ],
          if (extraPhones.isNotEmpty) ...[
            ...extraPhones.map(
              (p) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: PhoneLink(phone: p, compact: true),
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (email.trim().isNotEmpty) ...[
            Row(
              children: [
                const Icon(Icons.email),
                const SizedBox(width: 8),
                Expanded(child: Text(email)),
              ],
            ),
            const SizedBox(height: 16),
          ],
          if (website.trim().isNotEmpty) ...[
            Row(
              children: [
                const Icon(Icons.language),
                const SizedBox(width: 8),
                Expanded(child: Text(website)),
              ],
            ),
            const SizedBox(height: 16),
          ],
          if (!hasDirectContacts && contacts.isEmpty)
            const Text("No contacts yet"),
          if (contacts.isNotEmpty) ...[
            const Text(
              "Team contacts",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            ...contacts.map(
              (c) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(c["name"]?.toString() ?? ""),
                subtitle: PhoneLink(
                  phone: c["phone"]?.toString(),
                  compact: true,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CompanyInfoBlock extends StatelessWidget {
  final String title;
  final String text;

  const _CompanyInfoBlock({
    required this.title,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    final cleanText = text.trim();
    if (cleanText.isEmpty) return const SizedBox();

    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.ink,
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 6),
          Text(cleanText),
        ],
      ),
    );
  }
}
