import 'package:flutter/material.dart';

import '../../widgets/web_page_container.dart';
import '../../widgets/web_panel.dart';

class WebApplicationsPage extends StatelessWidget {
  const WebApplicationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const WebPageContainer(
      child: WebPanel(
        child: _SectionScaffold(
          title: 'Applications',
          body:
              'The dedicated desktop applications workspace will be built here.',
          icon: Icons.assignment_outlined,
        ),
      ),
    );
  }
}

class _SectionScaffold extends StatelessWidget {
  const _SectionScaffold({
    required this.title,
    required this.body,
    required this.icon,
  });

  final String title;
  final String body;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 42),
          const SizedBox(height: 16),
          Text(title, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          Text(body, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
