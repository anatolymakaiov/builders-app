import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../models/job.dart';
import '../../services/web_data_state.dart';
import '../../services/web_profile_data_service.dart';
import '../../services/web_profile_edit_service.dart';
import '../../theme/web_breakpoints.dart';
import '../../theme/web_theme.dart';
import '../../widgets/web_page_container.dart';
import '../../widgets/web_panel.dart';
import '../../widgets/web_remote_image.dart';
import 'web_profile_gallery.dart';

class WebProfilePage extends StatefulWidget {
  const WebProfilePage({
    super.key,
    required this.user,
    required this.role,
    required this.profile,
    this.viewedUserId,
    this.viewedRole,
    this.onClose,
  });

  final User user;
  final String role;
  final Map<String, dynamic> profile;
  final String? viewedUserId;
  final String? viewedRole;
  final VoidCallback? onClose;

  @override
  State<WebProfilePage> createState() => _WebProfilePageState();
}

class _WebProfilePageState extends State<WebProfilePage> {
  final service = WebProfileDataService();
  final editService = WebProfileEditService();
  late Stream<WebDataState<WebProfileData?>> profileStream;
  late String viewedUserId;
  late String viewedRole;
  List<WebPortfolioItem> portfolio = const <WebPortfolioItem>[];
  List<WebTeamData> teams = const <WebTeamData>[];
  List<Job> companyJobs = const <Job>[];
  bool loadingDetails = false;
  Object? detailsError;

  bool get ownProfile => widget.user.uid == viewedUserId;
  bool get isEmployer => viewedRole == 'employer';
  bool get isWorker => viewedRole == 'worker';

  @override
  void initState() {
    super.initState();
    viewedUserId = widget.viewedUserId ?? widget.user.uid;
    viewedRole = widget.viewedRole ?? widget.role;
    profileStream = service.profile(viewedUserId);
    _loadDetails();
  }

  @override
  void didUpdateWidget(covariant WebProfilePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextId = widget.viewedUserId ?? widget.user.uid;
    final nextRole = widget.viewedRole ?? widget.role;
    if (nextId != viewedUserId || nextRole != viewedRole) {
      viewedUserId = nextId;
      viewedRole = nextRole;
      profileStream = service.profile(viewedUserId);
      portfolio = const <WebPortfolioItem>[];
      teams = const <WebTeamData>[];
      companyJobs = const <Job>[];
      _loadDetails();
    }
  }

  Future<void> _loadDetails() async {
    setState(() {
      loadingDetails = true;
      detailsError = null;
    });
    try {
      if (isWorker) {
        final loadedPortfolio = await service.loadWorkerPortfolio(viewedUserId);
        final loadedTeams = await service.loadWorkerTeams(viewedUserId);
        if (!mounted) return;
        setState(() {
          portfolio = loadedPortfolio;
          teams = loadedTeams;
        });
      } else {
        final jobs = await service.loadCompanyJobs(
          ownerId: viewedUserId,
          ownProfile: ownProfile,
        );
        if (!mounted) return;
        setState(() => companyJobs = jobs);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => detailsError = error);
    } finally {
      if (mounted) setState(() => loadingDetails = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<WebDataState<WebProfileData?>>(
      stream: profileStream,
      builder: (context, snapshot) {
        final state = snapshot.data;
        final fallback = viewedUserId == widget.user.uid
            ? widget.profile
            : const <String, dynamic>{};
        final current =
            state?.data ?? WebProfileData(id: viewedUserId, data: fallback);
        if ((state == null || state.loading) && state?.data == null) {
          return const Center(child: CircularProgressIndicator());
        }

        return WebPageContainer(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ProfileHeader(
                  profile: current,
                  role: viewedRole,
                  ownProfile: ownProfile,
                  onBack: widget.onClose,
                  onEdit: ownProfile ? () => _openEditProfile(current) : null,
                  onChangeAvatar: ownProfile ? _changeAvatar : null,
                  onChangeHeader: ownProfile ? _changeHeader : null,
                ),
                if (state?.error != null)
                  _ErrorBanner(
                    message: 'Could not refresh profile: ${state!.error}',
                  ),
                if (detailsError != null)
                  _ErrorBanner(
                    message: 'Could not refresh profile details: $detailsError',
                  ),
                const SizedBox(height: 22),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final compact =
                        constraints.maxWidth < WebBreakpoints.compactWidth;
                    final main = isEmployer
                        ? _EmployerProfileBody(
                            profile: current,
                            jobs: companyJobs,
                            loading: loadingDetails,
                            ownProfile: ownProfile,
                            onAddCompanyPhotos:
                                ownProfile ? _addCompanyPhotos : null,
                            onRemoveCompanyPhoto:
                                ownProfile ? _removeCompanyPhoto : null,
                          )
                        : _WorkerProfileBody(
                            profile: current,
                            portfolio:
                                portfolio.map((item) => item.url).toList(),
                            teams: teams,
                            loading: loadingDetails,
                            ownProfile: ownProfile,
                            onAddPortfolio: ownProfile ? _addPortfolio : null,
                            onRemovePortfolio:
                                ownProfile ? _removePortfolioPhoto : null,
                            onCreateTeam: ownProfile ? _openCreateTeam : null,
                            onEditTeam: ownProfile ? _openEditTeam : null,
                          );
                    final contact = _ContactPanel(profile: current);
                    if (compact) {
                      return Column(
                        children: [
                          main,
                          const SizedBox(height: 18),
                          contact,
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 7, child: main),
                        const SizedBox(width: 22),
                        Expanded(flex: 3, child: contact),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openEditProfile(WebProfileData profile) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _EditProfileDialog(
        role: viewedRole,
        profile: profile,
        onSave: (updates) => editService.saveUserProfile(
          uid: viewedUserId,
          updates: updates,
        ),
      ),
    );
    if (saved == true) _loadDetails();
  }

  Future<void> _changeAvatar() async {
    await editService.pickAndUploadProfileImage(
      uid: viewedUserId,
      isEmployer: isEmployer,
    );
    await _loadDetails();
  }

  Future<void> _changeHeader() async {
    await editService.pickAndUploadHeaderImage(viewedUserId);
    await _loadDetails();
  }

  Future<void> _addCompanyPhotos() async {
    await editService.pickAndAddCompanyPhotos(viewedUserId);
    await _loadDetails();
  }

  Future<void> _removeCompanyPhoto(String url) async {
    await editService.removeCompanyPhoto(uid: viewedUserId, url: url);
    await _loadDetails();
  }

  Future<void> _addPortfolio() async {
    await editService.pickAndAddWorkerPortfolio(viewedUserId);
    await _loadDetails();
  }

  Future<void> _removePortfolioPhoto(String url) async {
    await editService.removePortfolioPhoto(uid: viewedUserId, url: url);
    await _loadDetails();
  }

  Future<void> _openCreateTeam() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _TeamDialog(
        title: 'Create team',
        onSave: (values) async {
          await editService.createTeam(
            ownerId: viewedUserId,
            name: values['name'] ?? '',
            description: values['description'] ?? '',
            trade: values['trade'] ?? '',
          );
        },
      ),
    );
    if (saved == true) _loadDetails();
  }

  Future<void> _openEditTeam(WebTeamData team) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _TeamDialog(
        title: 'Edit team',
        team: team,
        onSave: (values) => editService.saveTeam(
          teamId: team.id,
          updates: values,
        ),
        onChangeAvatar: () => editService.pickAndUploadTeamImage(
          teamId: team.id,
          header: false,
        ),
        onChangeHeader: () => editService.pickAndUploadTeamImage(
          teamId: team.id,
          header: true,
        ),
      ),
    );
    if (saved == true) _loadDetails();
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.profile,
    required this.role,
    required this.ownProfile,
    this.onBack,
    this.onEdit,
    this.onChangeAvatar,
    this.onChangeHeader,
  });

  final WebProfileData profile;
  final String role;
  final bool ownProfile;
  final VoidCallback? onBack;
  final VoidCallback? onEdit;
  final VoidCallback? onChangeAvatar;
  final VoidCallback? onChangeHeader;

  @override
  Widget build(BuildContext context) {
    return WebPanel(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          height: 320,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (profile.headerUrl.isNotEmpty)
                WebRemoteImage(
                  url: profile.headerUrl,
                  fit: BoxFit.cover,
                  fallbackIcon: Icons.image_outlined,
                )
              else
                _HeaderFallback(role: role),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      WebTheme.deep.withValues(alpha: 0.1),
                      WebTheme.deep.withValues(alpha: 0.72),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 22,
                top: 22,
                child: onBack == null
                    ? const SizedBox.shrink()
                    : IconButton.filledTonal(
                        tooltip: 'Back',
                        onPressed: onBack,
                        icon: const Icon(Icons.arrow_back),
                      ),
              ),
              Positioned(
                right: 22,
                top: 22,
                child: Wrap(
                  spacing: 10,
                  children: [
                    if (onChangeHeader != null)
                      FilledButton.tonalIcon(
                        onPressed: onChangeHeader,
                        icon: const Icon(
                          Icons.photo_size_select_actual_outlined,
                        ),
                        label: const Text('Header'),
                      ),
                    if (onEdit != null)
                      FilledButton.icon(
                        onPressed: onEdit,
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Edit profile'),
                      ),
                  ],
                ),
              ),
              Positioned(
                left: 30,
                right: 30,
                bottom: 28,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Stack(
                      children: [
                        WebCircleImage(
                          url: profile.avatarUrl,
                          size: 150,
                          fallbackIcon: role == 'employer'
                              ? Icons.business_outlined
                              : Icons.person_outline,
                        ),
                        if (onChangeAvatar != null)
                          Positioned(
                            right: 4,
                            bottom: 4,
                            child: IconButton.filled(
                              tooltip: role == 'employer'
                                  ? 'Change logo'
                                  : 'Change avatar',
                              onPressed: onChangeAvatar,
                              icon: const Icon(Icons.photo_camera_outlined),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            profile.displayName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 34,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _roleLabel(role, ownProfile),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WorkerProfileBody extends StatelessWidget {
  const _WorkerProfileBody({
    required this.profile,
    required this.portfolio,
    required this.teams,
    required this.loading,
    required this.ownProfile,
    this.onAddPortfolio,
    this.onRemovePortfolio,
    this.onCreateTeam,
    this.onEditTeam,
  });

  final WebProfileData profile;
  final List<String> portfolio;
  final List<WebTeamData> teams;
  final bool loading;
  final bool ownProfile;
  final VoidCallback? onAddPortfolio;
  final ValueChanged<String>? onRemovePortfolio;
  final VoidCallback? onCreateTeam;
  final ValueChanged<WebTeamData>? onEditTeam;

  @override
  Widget build(BuildContext context) {
    final cvItems = <MapEntry<String, String>>[
      MapEntry('Trade / position', profile.trade),
      MapEntry('Experience', profile.experience),
      MapEntry(
        'Qualifications',
        profile.listField(const ['qualifications']).join(', '),
      ),
      MapEntry(
        'Certifications',
        profile.listField(const ['certificationsText', 'certifications']).join(
            ', '),
      ),
    ].where((item) => item.value.trim().isNotEmpty).toList();

    return Column(
      children: [
        WebPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Worker CV', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 14),
              if (profile.bio.isNotEmpty) ...[
                Text(profile.bio, style: const TextStyle(height: 1.45)),
                const SizedBox(height: 16),
              ],
              if (cvItems.isEmpty)
                const Text(
                  'No CV details yet.',
                  style: TextStyle(color: WebTheme.muted),
                )
              else
                Wrap(
                  spacing: 14,
                  runSpacing: 14,
                  children: cvItems
                      .map((item) =>
                          _FieldTile(label: item.key, value: item.value))
                      .toList(),
                ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _SectionPanel(
          title: 'Portfolio',
          action: onAddPortfolio == null
              ? null
              : FilledButton.icon(
                  onPressed: onAddPortfolio,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: const Text('Add photos'),
                ),
          child: loading
              ? const LinearProgressIndicator()
              : WebProfileGallery(
                  urls: portfolio,
                  onRemove: ownProfile ? onRemovePortfolio : null,
                ),
        ),
        const SizedBox(height: 18),
        _SectionPanel(
          title: 'Teams',
          action: onCreateTeam == null
              ? null
              : FilledButton.icon(
                  onPressed: onCreateTeam,
                  icon: const Icon(Icons.group_add_outlined),
                  label: const Text('Create team'),
                ),
          child: loading
              ? const LinearProgressIndicator()
              : _TeamsList(
                  teams: teams,
                  ownProfile: ownProfile,
                  onEditTeam: onEditTeam,
                ),
        ),
      ],
    );
  }
}

class _EmployerProfileBody extends StatelessWidget {
  const _EmployerProfileBody({
    required this.profile,
    required this.jobs,
    required this.loading,
    required this.ownProfile,
    this.onAddCompanyPhotos,
    this.onRemoveCompanyPhoto,
  });

  final WebProfileData profile;
  final List<Job> jobs;
  final bool loading;
  final bool ownProfile;
  final VoidCallback? onAddCompanyPhotos;
  final ValueChanged<String>? onRemoveCompanyPhoto;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        WebPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Company information',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 14),
              Text(
                profile.bio.isEmpty
                    ? 'No company description has been added yet.'
                    : profile.bio,
                style: TextStyle(
                  color: profile.bio.isEmpty ? WebTheme.muted : WebTheme.ink,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  if (profile.website.isNotEmpty)
                    _FieldTile(label: 'Website', value: profile.website),
                  if (profile.trade.isNotEmpty)
                    _FieldTile(label: 'Speciality', value: profile.trade),
                  if (profile.location.isNotEmpty)
                    _FieldTile(label: 'Location', value: profile.location),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _SectionPanel(
          title: 'Company photos',
          action: onAddCompanyPhotos == null
              ? null
              : FilledButton.icon(
                  onPressed: onAddCompanyPhotos,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: const Text('Add photos'),
                ),
          child: WebProfileGallery(
            urls: profile.companyPhotos,
            onRemove: ownProfile ? onRemoveCompanyPhoto : null,
          ),
        ),
        const SizedBox(height: 18),
        _SectionPanel(
          title: ownProfile ? 'Your vacancies' : 'Vacancies',
          child: loading
              ? const LinearProgressIndicator()
              : _CompanyJobsList(jobs: jobs, ownProfile: ownProfile),
        ),
      ],
    );
  }
}

class _ContactPanel extends StatelessWidget {
  const _ContactPanel({required this.profile});

  final WebProfileData profile;

  @override
  Widget build(BuildContext context) {
    final address = [
      profile.addressLine1,
      profile.addressLine2,
      profile.addressLine3,
      profile.city,
      profile.county,
      profile.postcode,
      profile.country,
    ].where((part) => part.trim().isNotEmpty).join(', ');
    final fields = <MapEntry<String, String>>[
      MapEntry('Email', profile.email),
      MapEntry('Phone', profile.phone),
      MapEntry('Address', address.isNotEmpty ? address : profile.location),
      MapEntry('Postcode', profile.postcode),
    ].where((item) => item.value.trim().isNotEmpty).toList();

    return WebPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Contacts', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 14),
          if (fields.isEmpty)
            const Text(
              'No contact details available.',
              style: TextStyle(color: WebTheme.muted),
            )
          else
            for (final field in fields) ...[
              _FieldTile(label: field.key, value: field.value, fullWidth: true),
              const SizedBox(height: 12),
            ],
        ],
      ),
    );
  }
}

class _TeamsList extends StatelessWidget {
  const _TeamsList({
    required this.teams,
    required this.ownProfile,
    this.onEditTeam,
  });

  final List<WebTeamData> teams;
  final bool ownProfile;
  final ValueChanged<WebTeamData>? onEditTeam;

  @override
  Widget build(BuildContext context) {
    if (teams.isEmpty) {
      return const Text('No teams yet.',
          style: TextStyle(color: WebTheme.muted));
    }
    return Column(
      children: teams.map((team) {
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: WebTheme.surfaceAlt,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: WebTheme.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  WebCircleImage(
                    url: team.avatarUrl,
                    size: 54,
                    fallbackIcon: Icons.groups_2_outlined,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          team.name,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        if (team.trade.isNotEmpty)
                          Text(
                            team.trade,
                            style: const TextStyle(color: WebTheme.muted),
                          ),
                        Text(
                          '${team.memberCount} member${team.memberCount == 1 ? '' : 's'}',
                          style: const TextStyle(color: WebTheme.muted),
                        ),
                      ],
                    ),
                  ),
                  if (ownProfile && onEditTeam != null)
                    IconButton(
                      tooltip: 'Edit team',
                      onPressed: () => onEditTeam!(team),
                      icon: const Icon(Icons.more_horiz),
                    ),
                ],
              ),
              if (team.description.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(team.description),
              ],
              if (team.members.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: team.members
                      .map(
                        (member) => Chip(
                          avatar: WebCircleImage(
                            url: member.avatarUrl,
                            size: 24,
                            fallbackIcon: Icons.person_outline,
                          ),
                          label: Text(member.displayName),
                        ),
                      )
                      .toList(),
                ),
              ],
              if (team.portfolio.isNotEmpty) ...[
                const SizedBox(height: 14),
                WebProfileGallery(urls: team.portfolio),
              ],
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _CompanyJobsList extends StatelessWidget {
  const _CompanyJobsList({
    required this.jobs,
    required this.ownProfile,
  });

  final List<Job> jobs;
  final bool ownProfile;

  @override
  Widget build(BuildContext context) {
    if (jobs.isEmpty) {
      return Text(
        ownProfile
            ? 'You have not created any vacancies yet.'
            : 'No vacancies to display.',
        style: const TextStyle(color: WebTheme.muted),
      );
    }
    return Column(
      children: jobs.map((job) {
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: WebTheme.surfaceAlt,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: WebTheme.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      job.displayTitle,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      job.fullAddress.isEmpty ? job.site : job.fullAddress,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: WebTheme.muted),
                    ),
                  ],
                ),
              ),
              _StatusBadge(
                  label: ownProfile ? job.moderationLabel : job.status),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _SectionPanel extends StatelessWidget {
  const _SectionPanel({
    required this.title,
    required this.child,
    this.action,
  });

  final String title;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return WebPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child:
                    Text(title, style: Theme.of(context).textTheme.titleLarge),
              ),
              if (action != null) action!,
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _EditProfileDialog extends StatefulWidget {
  const _EditProfileDialog({
    required this.role,
    required this.profile,
    required this.onSave,
  });

  final String role;
  final WebProfileData profile;
  final Future<void> Function(Map<String, dynamic> updates) onSave;

  @override
  State<_EditProfileDialog> createState() => _EditProfileDialogState();
}

class _EditProfileDialogState extends State<_EditProfileDialog> {
  late final TextEditingController name;
  late final TextEditingController email;
  late final TextEditingController phone;
  late final TextEditingController trade;
  late final TextEditingController bio;
  late final TextEditingController addressLine1;
  late final TextEditingController addressLine2;
  late final TextEditingController addressLine3;
  late final TextEditingController city;
  late final TextEditingController county;
  late final TextEditingController postcode;
  late final TextEditingController country;
  late final TextEditingController website;
  late final TextEditingController experience;
  late final TextEditingController qualifications;
  late final TextEditingController certifications;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    final profile = widget.profile;
    name = TextEditingController(text: profile.displayName);
    email = TextEditingController(text: profile.email);
    phone = TextEditingController(text: profile.phone);
    trade = TextEditingController(text: profile.trade);
    bio = TextEditingController(text: profile.bio);
    addressLine1 = TextEditingController(text: profile.addressLine1);
    addressLine2 = TextEditingController(text: profile.addressLine2);
    addressLine3 = TextEditingController(text: profile.addressLine3);
    city = TextEditingController(text: profile.city);
    county = TextEditingController(text: profile.county);
    postcode = TextEditingController(text: profile.postcode);
    country = TextEditingController(text: profile.country);
    website = TextEditingController(text: profile.website);
    experience = TextEditingController(text: profile.experience);
    qualifications = TextEditingController(
      text: profile.listField(const ['qualifications']).join(', '),
    );
    certifications = TextEditingController(
      text: profile
          .listField(const ['certificationsText', 'certifications']).join(', '),
    );
  }

  @override
  void dispose() {
    for (final controller in [
      name,
      email,
      phone,
      trade,
      bio,
      addressLine1,
      addressLine2,
      addressLine3,
      city,
      county,
      postcode,
      country,
      website,
      experience,
      qualifications,
      certifications,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEmployer = widget.role == 'employer';
    return AlertDialog(
      title: Text(isEmployer ? 'Edit company profile' : 'Edit worker profile'),
      content: SizedBox(
        width: 720,
        child: SingleChildScrollView(
          child: Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              _input(name, isEmployer ? 'Company name' : 'Name'),
              _input(email, 'Email'),
              _input(phone, 'Phone'),
              _input(trade, isEmployer ? 'Speciality' : 'Trade / position'),
              _input(bio, isEmployer ? 'Company description' : 'Bio', lines: 3),
              if (!isEmployer) _input(experience, 'Experience'),
              if (!isEmployer) _input(qualifications, 'Qualifications'),
              if (!isEmployer) _input(certifications, 'Certifications'),
              if (isEmployer) _input(website, 'Website'),
              _input(addressLine1, 'Address Line 1'),
              _input(addressLine2, 'Address Line 2'),
              _input(addressLine3, 'Address Line 3'),
              _input(city, 'Town / City'),
              _input(county, 'County'),
              _input(postcode, 'Postcode'),
              _input(country, 'Country'),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: saving ? null : _save,
          child: saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }

  Widget _input(TextEditingController controller, String label,
      {int lines = 1}) {
    return SizedBox(
      width: lines > 1 ? 680 : 330,
      child: TextField(
        controller: controller,
        maxLines: lines,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  Future<void> _save() async {
    setState(() => saving = true);
    final isEmployer = widget.role == 'employer';
    final updates = <String, dynamic>{
      if (isEmployer) 'companyName': name.text.trim(),
      if (!isEmployer) 'name': name.text.trim(),
      'displayName': name.text.trim(),
      'email': email.text.trim(),
      'phone': phone.text.trim(),
      if (isEmployer) 'description': bio.text.trim(),
      if (!isEmployer) 'bio': bio.text.trim(),
      'trade': trade.text.trim(),
      'addressLine1': addressLine1.text.trim(),
      'addressLine2': addressLine2.text.trim(),
      'addressLine3': addressLine3.text.trim(),
      'city': city.text.trim(),
      'town': city.text.trim(),
      'county': county.text.trim(),
      'postcode': postcode.text.trim(),
      'country': country.text.trim(),
      if (isEmployer) 'website': website.text.trim(),
      if (!isEmployer) 'experience': experience.text.trim(),
      if (!isEmployer) 'qualifications': _splitList(qualifications.text),
      if (!isEmployer) 'certificationsText': certifications.text.trim(),
    };
    try {
      await widget.onSave(updates);
      if (mounted) Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }
}

class _TeamDialog extends StatefulWidget {
  const _TeamDialog({
    required this.title,
    required this.onSave,
    this.team,
    this.onChangeAvatar,
    this.onChangeHeader,
  });

  final String title;
  final WebTeamData? team;
  final Future<void> Function(Map<String, String> values) onSave;
  final Future<String?> Function()? onChangeAvatar;
  final Future<String?> Function()? onChangeHeader;

  @override
  State<_TeamDialog> createState() => _TeamDialogState();
}

class _TeamDialogState extends State<_TeamDialog> {
  late final TextEditingController name;
  late final TextEditingController description;
  late final TextEditingController trade;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    name = TextEditingController(text: widget.team?.name ?? '');
    description = TextEditingController(text: widget.team?.description ?? '');
    trade = TextEditingController(text: widget.team?.trade ?? '');
  }

  @override
  void dispose() {
    name.dispose();
    description.dispose();
    trade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(
                labelText: 'Team name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: trade,
              decoration: const InputDecoration(
                labelText: 'Trade / specialization',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: description,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Description',
                border: OutlineInputBorder(),
              ),
            ),
            if (widget.team != null) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: widget.onChangeAvatar,
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: const Text('Avatar'),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    onPressed: widget.onChangeHeader,
                    icon: const Icon(Icons.image_outlined),
                    label: const Text('Header'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: saving ? null : _save,
          child: const Text('Save'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    setState(() => saving = true);
    try {
      await widget.onSave({
        'name': name.text.trim(),
        'teamName': name.text.trim(),
        'description': description.text.trim(),
        'trade': trade.text.trim(),
      });
      if (mounted) Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }
}

class _FieldTile extends StatelessWidget {
  const _FieldTile({
    required this.label,
    required this.value,
    this.fullWidth = false,
  });

  final String label;
  final String value;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: fullWidth ? double.infinity : 270,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: WebTheme.muted,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          Text(value, style: const TextStyle(fontSize: 15, height: 1.35)),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF6EF),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label.replaceAll('_', ' '),
        style: const TextStyle(
          color: Color(0xFF217A42),
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _HeaderFallback extends StatelessWidget {
  const _HeaderFallback({required this.role});

  final String role;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: role == 'employer'
          ? const Color(0xFF253044)
          : const Color(0xFF2E3A4F),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(message),
    );
  }
}

String _roleLabel(String role, bool ownProfile) {
  if (role == 'employer') {
    return ownProfile ? 'Your company profile' : 'Company profile';
  }
  return ownProfile ? 'Your worker profile' : 'Worker profile';
}

List<String> _splitList(String value) {
  return value
      .split(',')
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList();
}
