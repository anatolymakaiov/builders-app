import 'package:flutter/material.dart';

import '../../services/job_taxonomy_service.dart';
import '../services/web_admin_profile_service.dart';
import '../services/web_profile_data_service.dart';
import '../theme/web_theme.dart';
import '../widgets/web_remote_image.dart';
import 'admin_directory_service.dart';

class AdminDirectoryPage extends StatefulWidget {
  const AdminDirectoryPage(
      {super.key,
      required this.role,
      required this.onOpenRecord,
      this.service});

  final String role;
  final Future<void> Function(WebAdminRecord) onOpenRecord;
  final AdminDirectoryService? service;

  @override
  State<AdminDirectoryPage> createState() => _AdminDirectoryPageState();
}

class _AdminDirectoryPageState extends State<AdminDirectoryPage> {
  late final AdminDirectoryService service =
      widget.service ?? AdminDirectoryService();
  final search = TextEditingController();
  final location = TextEditingController();
  final profession = TextEditingController();
  final selectedRoles = <ConstructionRole>[];
  final entries = <AdminDirectoryEntry>[];
  String? nextCursor;
  String status = 'all';
  int? radiusKm;
  bool loading = false;
  bool loaded = false;
  String? error;
  int generation = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    search.dispose();
    location.dispose();
    profession.dispose();
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    if (loading && more) return;
    if (radiusKm != null && location.text.trim().isEmpty) {
      setState(() => error = 'Enter a town, city or postcode to use a radius.');
      return;
    }
    final request = ++generation;
    setState(() {
      loading = true;
      error = null;
      if (!more) {
        entries.clear();
        nextCursor = null;
        loaded = false;
      }
    });
    try {
      final page = await service.load(
        role: widget.role,
        search: search.text,
        location: location.text,
        radiusKm: radiusKm,
        status: status,
        professions: selectedRoles,
        cursor: more ? nextCursor : null,
      );
      if (!mounted || request != generation) return;
      setState(() {
        entries.addAll(page.entries);
        nextCursor = page.nextCursor;
        if (radiusKm != null && location.text.trim().isNotEmpty) {
          entries.sort((a, b) => (a.distanceKm ?? double.infinity)
              .compareTo(b.distanceKm ?? double.infinity));
        }
        loaded = true;
      });
    } catch (failure) {
      if (mounted && request == generation) {
        setState(() => error = 'Could not load directory: $failure');
      }
    } finally {
      if (mounted && request == generation) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final workers = widget.role == 'worker';
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(workers ? 'Workers' : 'Employers',
              style: WebTypography.panelTitle),
          const SizedBox(height: 12),
          Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.end,
              children: [
                SizedBox(
                    width: 245,
                    child: TextField(
                        controller: search,
                        decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.search),
                            labelText: workers
                                ? 'Name, email or phone'
                                : 'Company, name, email or phone'),
                        onSubmitted: (_) => _load())),
                if (workers)
                  SizedBox(
                      width: 230,
                      child: Autocomplete<ConstructionRole>(
                          displayStringForOption: (role) => role.canonical,
                          optionsBuilder: (value) => value.text.trim().isEmpty
                              ? JobTaxonomyService.roles
                              : JobTaxonomyService.suggestions(value.text,
                                  limit: 12),
                          onSelected: (role) {
                            if (!selectedRoles.any(
                                (item) => item.canonical == role.canonical)) {
                              setState(() => selectedRoles.add(role));
                            }
                            _load();
                          },
                          fieldViewBuilder:
                              (context, controller, focusNode, onSubmit) =>
                                  TextField(
                                    controller: controller,
                                    focusNode: focusNode,
                                    decoration: const InputDecoration(
                                        labelText: 'Profession',
                                        prefixIcon: Icon(Icons.work_outline)),
                                  ))),
                SizedBox(
                    width: 210,
                    child: TextField(
                        controller: location,
                        decoration: const InputDecoration(
                            labelText: 'Town, city or postcode',
                            prefixIcon: Icon(Icons.location_on_outlined)),
                        onSubmitted: (_) => _load())),
                SizedBox(
                    width: 145,
                    child: DropdownButtonFormField<int?>(
                      isExpanded: true,
                      initialValue: radiusKm,
                      decoration: const InputDecoration(labelText: 'Radius'),
                      items: [
                        const DropdownMenuItem<int?>(
                            value: null, child: Text('Any')),
                        for (final km in const [5, 10, 20, 30, 50, 100])
                          DropdownMenuItem<int?>(
                              value: km, child: Text('$km km'))
                      ],
                      onChanged: (value) => setState(() => radiusKm = value),
                    )),
                SizedBox(
                    width: 155,
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: status,
                      decoration: const InputDecoration(labelText: 'Status'),
                      items: const [
                        DropdownMenuItem(value: 'all', child: Text('All')),
                        DropdownMenuItem(
                            value: 'active', child: Text('Active')),
                        DropdownMenuItem(
                            value: 'blocked', child: Text('Blocked')),
                      ],
                      onChanged: (value) =>
                          setState(() => status = value ?? 'all'),
                    )),
                FilledButton.icon(
                    onPressed: loading ? null : () => _load(),
                    icon: const Icon(Icons.tune),
                    label: const Text('Apply')),
              ]),
          if (selectedRoles.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Wrap(spacing: 6, children: [
                for (final role in selectedRoles)
                  InputChip(
                      label: Text(role.canonical),
                      onDeleted: () {
                        setState(() => selectedRoles.remove(role));
                        _load();
                      }),
              ]),
            ),
        ]),
      ),
      if (loading) const LinearProgressIndicator(),
      Expanded(
          child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        children: [
          if (error != null)
            ListTile(
                title: Text(error!),
                trailing: TextButton(
                    onPressed: () => _load(more: entries.isNotEmpty),
                    child: const Text('Retry'))),
          if (loaded && entries.isEmpty && error == null)
            const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                    'No matching profiles yet. Load more to continue searching if available.')),
          for (final entry in entries) _row(entry),
          if (nextCursor != null)
            Center(
                child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: OutlinedButton.icon(
                        onPressed: loading ? null : () => _load(more: true),
                        icon: const Icon(Icons.expand_more),
                        label: const Text('Load more')))),
        ],
      )),
    ]);
  }

  Widget _row(AdminDirectoryEntry entry) {
    final profile =
        WebProfileData(id: entry.record.id, data: entry.record.data);
    final trade = profile.trade;
    final place = [profile.city, profile.postcode]
        .where((value) => value.isNotEmpty)
        .join(' · ');
    final blocked = entry.record.data['moderationHold'] == true ||
        entry.record.data['profileSuspended'] == true ||
        const ['suspended', 'on_hold'].contains(entry.record.data['status']);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
          color: WebTheme.surface,
          border: Border.all(color: WebTheme.border),
          borderRadius: BorderRadius.circular(6)),
      child: ListTile(
        leading: WebCircleImage(
            url: profile.avatarUrl,
            size: 44,
            fallbackIcon: widget.role == 'worker'
                ? Icons.person_outline
                : Icons.business_outlined),
        title: Text(profile.displayName),
        subtitle: Text(
            [
              if (widget.role == 'worker' && trade.isNotEmpty) trade,
              if (place.isNotEmpty) place,
              if (entry.distanceKm != null)
                '${entry.distanceKm!.toStringAsFixed(1)} km away'
            ].join(' · '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          if (blocked)
            const Tooltip(
                message: 'Blocked',
                child: Icon(Icons.block, color: Colors.red)),
          const Icon(Icons.chevron_right),
        ]),
        onTap: () async {
          await widget.onOpenRecord(entry.record);
          if (mounted) _load();
        },
      ),
    );
  }
}
