import 'package:flutter/material.dart';

import '../../../models/job.dart';
import '../../services/web_data_state.dart';
import '../../services/web_jobs_data_service.dart';
import '../../theme/web_theme.dart';
import '../../widgets/web_page_container.dart';
import '../../widgets/web_panel.dart';

class WebMapPage extends StatelessWidget {
  const WebMapPage({
    super.key,
    required this.userId,
    required this.role,
  });

  final String userId;
  final String role;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<WebDataState<List<Job>>>(
      stream: WebJobsDataService().jobs(userId: userId, role: role),
      builder: (context, snapshot) {
        final state = snapshot.data;
        final count = state?.data?.length ?? 0;
        return WebPageContainer(
          child: WebPanel(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.map_outlined, size: 42),
                  const SizedBox(height: 16),
                  const Text(
                    'Map',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  if (state == null || state.loading)
                    const CircularProgressIndicator()
                  else ...[
                    Text(
                      count == 1
                          ? '1 visible vacancy is ready for the Web map.'
                          : '$count visible vacancies are ready for the Web map.',
                      textAlign: TextAlign.center,
                    ),
                    if (state.error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Could not refresh map jobs: ${state.error}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: WebTheme.muted),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
