import 'package:flutter/material.dart';

import '../../services/web_applications_data_service.dart';
import '../../services/web_data_state.dart';
import '../../theme/web_breakpoints.dart';
import '../../theme/web_theme.dart';
import '../../widgets/web_page_container.dart';
import '../../widgets/web_panel.dart';
import '../../widgets/web_remote_image.dart';

class WebApplicationsPage extends StatefulWidget {
  const WebApplicationsPage({
    super.key,
    required this.userId,
    required this.role,
  });

  final String userId;
  final String role;

  @override
  State<WebApplicationsPage> createState() => _WebApplicationsPageState();
}

class _WebApplicationsPageState extends State<WebApplicationsPage> {
  final service = WebApplicationsDataService();
  late Stream<WebDataState<List<WebApplicationSummary>>> applicationsStream;
  String? selectedApplicationId;
  bool showTeamApplications = false;

  bool get isWorker => widget.role == 'worker';

  @override
  void initState() {
    super.initState();
    applicationsStream = service.applications(
      uid: widget.userId,
      role: widget.role,
    );
  }

  @override
  void didUpdateWidget(covariant WebApplicationsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId || oldWidget.role != widget.role) {
      applicationsStream = service.applications(
        uid: widget.userId,
        role: widget.role,
      );
      selectedApplicationId = null;
      showTeamApplications = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<WebDataState<List<WebApplicationSummary>>>(
      stream: applicationsStream,
      builder: (context, snapshot) {
        final state = snapshot.data;
        if (state == null || state.loading) {
          return const Center(child: CircularProgressIndicator());
        }
        final loadedApplications =
            state.data ?? const <WebApplicationSummary>[];
        final applications = isWorker
            ? loadedApplications
                .where((item) => item.isTeam == showTeamApplications)
                .toList()
            : loadedApplications;
        if (selectedApplicationId == null && applications.isNotEmpty) {
          selectedApplicationId = applications.first.id;
        }
        if (selectedApplicationId != null &&
            applications.every((item) => item.id != selectedApplicationId)) {
          selectedApplicationId =
              applications.isEmpty ? null : applications.first.id;
        }
        WebApplicationSummary? selected;
        for (final application in applications) {
          if (application.id == selectedApplicationId) {
            selected = application;
            break;
          }
        }

        return WebPageContainer(
          child: Column(
            children: [
              if (state.error != null)
                _ErrorBanner(
                  message: 'Could not refresh applications: ${state.error}',
                ),
              if (isWorker) ...[
                _WorkerApplicationToggle(
                  showTeamApplications: showTeamApplications,
                  singleCount:
                      loadedApplications.where((item) => !item.isTeam).length,
                  teamCount:
                      loadedApplications.where((item) => item.isTeam).length,
                  onChanged: (value) {
                    setState(() {
                      showTeamApplications = value;
                      selectedApplicationId = null;
                    });
                  },
                ),
                const SizedBox(height: 14),
              ],
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final compact =
                        constraints.maxWidth < WebBreakpoints.compactWidth;
                    final list = WebPanel(
                      padding: EdgeInsets.zero,
                      child: _ApplicationList(
                        applications: applications,
                        selectedId: selectedApplicationId,
                        onSelected: (id) {
                          setState(() => selectedApplicationId = id);
                        },
                      ),
                    );
                    final detail = WebPanel(
                      child: _ApplicationDetail(application: selected),
                    );
                    if (compact) {
                      return Column(
                        children: [
                          SizedBox(height: 360, child: list),
                          const SizedBox(height: 18),
                          SizedBox(height: 620, child: detail),
                        ],
                      );
                    }
                    return Row(
                      children: [
                        SizedBox(width: 390, child: list),
                        const SizedBox(width: 22),
                        Expanded(child: detail),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _WorkerApplicationToggle extends StatelessWidget {
  const _WorkerApplicationToggle({
    required this.showTeamApplications,
    required this.singleCount,
    required this.teamCount,
    required this.onChanged,
  });

  final bool showTeamApplications;
  final int singleCount;
  final int teamCount;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: SegmentedButton<bool>(
        segments: [
          ButtonSegment(
            value: false,
            label: Text('Single ($singleCount)'),
            icon: const Icon(Icons.person_outline),
          ),
          ButtonSegment(
            value: true,
            label: Text('Team ($teamCount)'),
            icon: const Icon(Icons.groups_2_outlined),
          ),
        ],
        selected: {showTeamApplications},
        onSelectionChanged: (value) => onChanged(value.first),
      ),
    );
  }
}

class _ApplicationList extends StatelessWidget {
  const _ApplicationList({
    required this.applications,
    required this.selectedId,
    required this.onSelected,
  });

  final List<WebApplicationSummary> applications;
  final String? selectedId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    if (applications.isEmpty) {
      return const Center(child: Text('No applications yet.'));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(14),
      itemCount: applications.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final application = applications[index];
        final selected = application.id == selectedId;
        return InkWell(
          onTap: () => onSelected(application.id),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: selected ? const Color(0xFFFFF6E9) : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? WebTheme.green : WebTheme.border,
              ),
            ),
            child: Row(
              children: [
                WebCircleImage(
                  url: application.avatarUrl,
                  size: 44,
                  fallbackIcon: application.isTeam
                      ? Icons.groups_2_outlined
                      : Icons.person_outline,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        application.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        application.jobTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: WebTheme.muted),
                      ),
                    ],
                  ),
                ),
                _StatusChip(status: application.status),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ApplicationDetail extends StatelessWidget {
  const _ApplicationDetail({required this.application});

  final WebApplicationSummary? application;

  @override
  Widget build(BuildContext context) {
    final item = application;
    if (item == null) {
      return const Center(child: Text('Select an application.'));
    }
    final fields = <MapEntry<String, String>>[
      MapEntry('Vacancy', item.jobTitle),
      MapEntry('Company', item.companyName),
      MapEntry('Applicant', item.title),
      MapEntry('Type', item.isTeam ? 'Team' : 'Single'),
      MapEntry('Status', item.status),
      MapEntry('Application ID', item.id),
    ];
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              WebCircleImage(
                url: item.avatarUrl,
                size: 64,
                fallbackIcon: item.isTeam
                    ? Icons.groups_2_outlined
                    : Icons.person_outline,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      item.jobTitle,
                      style: const TextStyle(color: WebTheme.muted),
                    ),
                  ],
                ),
              ),
              _StatusChip(status: item.status),
            ],
          ),
          const SizedBox(height: 24),
          for (final field in fields) ...[
            Text(
              field.key,
              style: const TextStyle(
                color: WebTheme.muted,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(field.value, style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF6EF),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status.replaceAll('_', ' '),
        style: const TextStyle(
          color: Color(0xFF217A42),
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(message),
    );
  }
}
