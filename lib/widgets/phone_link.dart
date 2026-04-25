import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class PhoneLink extends StatelessWidget {
  final String? phone;
  final String? label;
  final TextStyle? style;
  final bool compact;

  const PhoneLink({
    super.key,
    required this.phone,
    this.label,
    this.style,
    this.compact = false,
  });

  static String cleanPhone(String phone) {
    return phone.replaceAll(RegExp(r'[^0-9+]'), "");
  }

  static Future<void> call(BuildContext context, String? phone) async {
    final raw = phone?.trim() ?? "";
    final clean = cleanPhone(raw);
    if (clean.isEmpty) return;

    final uri = Uri(scheme: "tel", path: clean);
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);

    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not start phone call")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final raw = phone?.trim() ?? "";
    if (raw.isEmpty) return const SizedBox();

    final text = label == null || label!.trim().isEmpty ? raw : label!.trim();

    return InkWell(
      onTap: () => call(context, raw),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 0 : 2,
          vertical: compact ? 0 : 4,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.phone,
              size: compact ? 16 : 18,
              color: Colors.blue,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                text,
                style: style ??
                    const TextStyle(
                      color: Colors.blue,
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.underline,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
