import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../models/job.dart';
import '../../services/web_data_state.dart';
import '../../services/web_profile_data_service.dart';
import '../../services/web_profile_edit_service.dart';
import '../../services/web_profile_communication.dart';
import '../../../services/moderation_hold_service.dart';
import '../../../services/multi_account_service.dart';
import '../../../widgets/account_switcher.dart';
import '../../widgets/web_report_dialog.dart';
import '../../theme/web_breakpoints.dart';
import '../../theme/web_theme.dart';
import '../../widgets/web_page_container.dart';
import '../../widgets/web_panel.dart';
import '../../widgets/web_logo_crop_dialog.dart';
import '../../widgets/web_remote_image.dart';
import '../../widgets/web_design_components.dart';
import 'web_profile_gallery.dart';
import 'web_worker_reviews.dart';

class WebProfilePage extends StatefulWidget {
  const WebProfilePage({
    super.key,
    required this.user,
    required this.role,
    required this.profile,
    this.viewedUserId,
    this.viewedRole,
    this.onClose,
    this.onOpenChat,
    this.onOpenProfile,
    this.onOpenJob,
    this.onAdminInbox,
    this.onOwnProfileChanged,
  });

  final User user;
  final String role;
  final Map<String, dynamic> profile;
  final String? viewedUserId;
  final String? viewedRole;
  final VoidCallback? onClose;
  final ValueChanged<String>? onOpenChat;
  final void Function(String, String)? onOpenProfile;
  final void Function(String jobId, bool ownerView)? onOpenJob;
  final VoidCallback? onAdminInbox;
  final ValueChanged<Map<String, dynamic>>? onOwnProfileChanged;

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
  bool mediaBusy = false;
  Object? detailsError;
  final localProfileUpdates = <String, dynamic>{};
  Map<String, dynamic> latestProfileData = const <String, dynamic>{};

  bool get ownProfile =>
      isAuthenticatedOwnProfile(widget.user.uid, viewedUserId);
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
      localProfileUpdates.clear();
      profileStream = service.profile(viewedUserId);
      portfolio = const <WebPortfolioItem>[];
      teams = const <WebTeamData>[];
      companyJobs = const <Job>[];
      _loadDetails();
    }
  }

  Future<void> _loadDetails() async {
    final requestedUserId = viewedUserId;
    final requestedRole = viewedRole;
    final requestedOwnProfile = ownProfile;
    setState(() {
      loadingDetails = true;
      detailsError = null;
    });
    try {
      if (requestedRole == 'worker') {
        final loadedPortfolio =
            await service.loadWorkerPortfolio(requestedUserId);
        final loadedTeams = await service.loadWorkerTeams(requestedUserId);
        if (!mounted || requestedUserId != viewedUserId) return;
        setState(() {
          portfolio = loadedPortfolio;
          teams = loadedTeams;
        });
      } else {
        final jobs = await service.loadCompanyJobs(
          ownerId: requestedUserId,
          ownProfile: requestedOwnProfile,
        );
        if (!mounted || requestedUserId != viewedUserId) return;
        setState(() => companyJobs = jobs);
      }
    } catch (error) {
      if (!mounted || requestedUserId != viewedUserId) return;
      setState(() => detailsError = error);
    } finally {
      if (mounted && requestedUserId == viewedUserId) {
        setState(() => loadingDetails = false);
      }
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
        final loaded = state?.data?.data ?? fallback;
        final current = WebProfileData(
          id: viewedUserId,
          data: {...loaded, ...localProfileUpdates},
        );
        latestProfileData = current.data;
        if ((state == null || state.loading) && state?.data == null) {
          return const Center(child: CircularProgressIndicator());
        }
        final held = ModerationHoldService.isProfileHeld(current.data);
        if (!ownProfile &&
            WebProfileCommunication.unavailable(
                current.data.isEmpty ? null : current.data)) {
          return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('This profile is no longer available.'),
            TextButton(onPressed: widget.onClose, child: const Text('Back')),
          ]));
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
                  onEdit: ownProfile && !held
                      ? () => _openEditProfile(current)
                      : null,
                  onChangeAvatar: ownProfile && !held ? _changeAvatar : null,
                  onChangeHeader: ownProfile && !held ? _changeHeader : null,
                  onSwitchAccount: ownProfile ? _showAccountSwitcher : null,
                  mediaBusy: mediaBusy,
                ),
                if (ownProfile && held)
                  MaterialBanner(
                    content: const Text(
                        'PROFILE TEMPORARILY SUSPENDED\nPlease contact Administrator.'),
                    actions: [
                      TextButton(
                          onPressed: widget.onAdminInbox,
                          child: const Text('View Administrator Message'))
                    ],
                  ),
                if (!ownProfile) const SizedBox(height: WebSpacing.md),
                if (!ownProfile)
                  Wrap(spacing: 10, children: [
                    OutlinedButton.icon(
                        onPressed: () async {
                          try {
                            final id = await WebProfileCommunication()
                                .message(viewedUserId);
                            if (mounted) widget.onOpenChat?.call(id);
                          } catch (error) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(error.toString())),
                              );
                            }
                          }
                        },
                        icon: const Icon(Icons.chat_outlined),
                        label: const Text('Message')),
                    if (widget.role == 'employer' &&
                        isWorker &&
                        current.phone.isNotEmpty)
                      IconButton(
                          tooltip: 'Call',
                          onPressed: () => launchUrl(
                              Uri(scheme: 'tel', path: current.phone)),
                          icon: const Icon(Icons.phone_outlined)),
                    OutlinedButton.icon(
                        onPressed: () => showWebReportDialog(context,
                            type: isEmployer ? 'employer' : 'worker',
                            againstUserId: viewedUserId),
                        icon: const Icon(Icons.flag_outlined),
                        label: const Text('Report')),
                  ]),
                if (state?.error != null)
                  _ErrorBanner(
                    message: 'Could not refresh profile: ${state!.error}',
                  ),
                if (detailsError != null)
                  _ErrorBanner(
                    message: 'Could not refresh profile details: $detailsError',
                  ),
                const SizedBox(height: 22),
                if (isWorker)
                  WebWorkerReviews(
                      workerId: viewedUserId, ownProfile: ownProfile),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final compact =
                        constraints.maxWidth < WebBreakpoints.compactWidth;
                    final contact = _ContactPanel(profile: current);
                    final main = isEmployer
                        ? _EmployerProfileBody(
                            profile: current,
                            jobs: companyJobs,
                            loading: loadingDetails,
                            mediaBusy: mediaBusy,
                            ownProfile: ownProfile,
                            onAddCompanyPhotos:
                                ownProfile ? _addCompanyPhotos : null,
                            onRemoveCompanyPhoto:
                                ownProfile ? _removeCompanyPhoto : null,
                            onOpenJob: widget.onOpenJob,
                            contactAfterInformation: compact ? contact : null,
                          )
                        : _WorkerProfileBody(
                            profile: current,
                            portfolio:
                                portfolio.map((item) => item.url).toList(),
                            teams: teams,
                            loading: loadingDetails,
                            mediaBusy: mediaBusy,
                            ownProfile: ownProfile,
                            onAddPortfolio: ownProfile ? _addPortfolio : null,
                            onRemovePortfolio:
                                ownProfile ? _removePortfolioPhoto : null,
                            onCreateTeam:
                                ownProfile && !held ? _openCreateTeam : null,
                            onOpenProfile: widget.onOpenProfile,
                          );
                    if (compact) {
                      if (isEmployer) return main;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
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

  Future<void> _showAccountSwitcher() async {
    await showAccountSwitcher(
      context,
      web: true,
      onCreateNewAccount: () async {
        await MultiAccountService().prepareCreateNewAccount();
        await FirebaseAuth.instance.signOut();
      },
    );
  }

  Future<void> _changeAvatar() async {
    await _runMediaAction(() async {
      final picked = await editService.pickSingleImage();
      if (picked == null || !mounted) return;
      final selected = isEmployer
          ? await showDialog<WebPickedFile>(
              context: context,
              builder: (_) => WebLogoCropDialog(file: picked),
            )
          : picked;
      if (selected == null) return;
      final url = await editService.uploadProfileImage(
        uid: viewedUserId,
        isEmployer: isEmployer,
        image: selected,
      );
      _applyOwnProfileUpdates({
        'avatarUrl': url,
        'photo': url,
        'photoUrl': url,
        'profilePhotoUrl': url,
        if (isEmployer) 'companyLogo': url,
        if (isEmployer) 'companyLogoUrl': url,
        if (isEmployer) 'companyAvatarUrl': url,
      });
    });
  }

  Future<void> _changeHeader() async {
    await _runMediaAction(() async {
      final url = await editService.pickAndUploadHeaderImage(viewedUserId);
      if (url == null) return;
      _applyOwnProfileUpdates({
        'profileHeaderImage': url,
        'headerImage': url,
        'headerImageUrl': url,
        'backgroundImageUrl': url,
        'coverPhotoUrl': url,
      });
    });
  }

  void _applyOwnProfileUpdates(Map<String, dynamic> updates) {
    if (!mounted) return;
    setState(() => localProfileUpdates.addAll(updates));
    widget.onOwnProfileChanged?.call(updates);
  }

  Future<void> _addCompanyPhotos() async {
    await _runMediaAction(() async {
      final urls = await editService.pickAndAddCompanyPhotos(viewedUserId);
      if (urls.isEmpty) return;
      final existing = WebProfileData(
        id: viewedUserId,
        data: latestProfileData,
      ).companyPhotos;
      _applyOwnProfileUpdates({
        'companyPhotos': {...existing, ...urls}.toList(),
      });
    });
  }

  Future<void> _removeCompanyPhoto(String url) async {
    await _runMediaAction(() async {
      await editService.removeCompanyPhoto(uid: viewedUserId, url: url);
      final existing = WebProfileData(
        id: viewedUserId,
        data: latestProfileData,
      ).companyPhotos;
      _applyOwnProfileUpdates({
        'companyPhotos': existing.where((item) => item != url).toList(),
      });
    });
  }

  Future<void> _addPortfolio() async {
    await _runMediaAction(() async {
      final urls = await editService.pickAndAddWorkerPortfolio(viewedUserId);
      if (urls.isEmpty || !mounted) return;
      setState(() {
        portfolio = [
          ...portfolio,
          for (var index = 0; index < urls.length; index++)
            WebPortfolioItem(
              id: 'uploaded-${DateTime.now().microsecondsSinceEpoch}-$index',
              url: urls[index],
              data: {'imageUrl': urls[index], 'url': urls[index]},
            ),
        ];
      });
    });
  }

  Future<void> _removePortfolioPhoto(String url) async {
    await _runMediaAction(() async {
      await editService.removePortfolioPhoto(uid: viewedUserId, url: url);
      if (!mounted) return;
      setState(() {
        portfolio = portfolio.where((item) => item.url != url).toList();
      });
    });
  }

  Future<void> _runMediaAction(Future<void> Function() action) async {
    if (mediaBusy) return;
    setState(() => mediaBusy = true);
    try {
      await action();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update media: $error')),
      );
    } finally {
      if (mounted) setState(() => mediaBusy = false);
    }
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
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.profile,
    required this.role,
    required this.ownProfile,
    required this.mediaBusy,
    this.onBack,
    this.onEdit,
    this.onChangeAvatar,
    this.onChangeHeader,
    this.onSwitchAccount,
  });

  final WebProfileData profile;
  final String role;
  final bool ownProfile;
  final bool mediaBusy;
  final VoidCallback? onBack;
  final VoidCallback? onEdit;
  final VoidCallback? onChangeAvatar;
  final VoidCallback? onChangeHeader;
  final VoidCallback? onSwitchAccount;

  @override
  Widget build(BuildContext context) {
    final small = MediaQuery.sizeOf(context).width < WebBreakpoints.narrow;
    final avatarSize = small ? 112.0 : 150.0;
    return WebPanel(
      padding: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(WebRadii.panel),
        child: SizedBox(
          height: small ? 280 : 320,
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
                right: small ? 14 : 22,
                top: 22,
                child: Wrap(
                  spacing: 10,
                  children: [
                    if (onChangeHeader != null)
                      if (small)
                        IconButton.filledTonal(
                          tooltip: 'Change header',
                          onPressed: mediaBusy ? null : onChangeHeader,
                          icon: const Icon(
                            Icons.photo_size_select_actual_outlined,
                          ),
                        )
                      else
                        FilledButton.tonalIcon(
                          onPressed: mediaBusy ? null : onChangeHeader,
                          icon: const Icon(
                            Icons.photo_size_select_actual_outlined,
                          ),
                          label: const Text('Header'),
                        ),
                    if (onEdit != null)
                      if (small)
                        IconButton.filled(
                          tooltip: 'Edit profile',
                          onPressed: onEdit,
                          icon: const Icon(Icons.edit_outlined),
                        )
                      else
                        FilledButton.icon(
                          onPressed: onEdit,
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('Edit profile'),
                        ),
                    if (onSwitchAccount != null)
                      FilledButton.tonalIcon(
                        onPressed: onSwitchAccount,
                        icon: const Icon(Icons.swap_horiz),
                        label: const Text('Switch Account'),
                      ),
                  ],
                ),
              ),
              Positioned(
                left: small ? 16 : 30,
                right: small ? 16 : 30,
                bottom: small ? 20 : 28,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Stack(
                      children: [
                        WebCircleImage(
                          url: profile.avatarUrl,
                          size: avatarSize,
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
                              onPressed: mediaBusy ? null : onChangeAvatar,
                              icon: mediaBusy
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.photo_camera_outlined),
                            ),
                          ),
                      ],
                    ),
                    SizedBox(width: small ? 16 : 24),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            profile.displayName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: small ? 26 : 34,
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
    required this.mediaBusy,
    required this.ownProfile,
    this.onAddPortfolio,
    this.onRemovePortfolio,
    this.onCreateTeam,
    this.onOpenProfile,
  });

  final WebProfileData profile;
  final List<String> portfolio;
  final List<WebTeamData> teams;
  final bool loading;
  final bool mediaBusy;
  final bool ownProfile;
  final VoidCallback? onAddPortfolio;
  final ValueChanged<String>? onRemovePortfolio;
  final VoidCallback? onCreateTeam;
  final void Function(String, String)? onOpenProfile;

  @override
  Widget build(BuildContext context) {
    final cvItems = <MapEntry<String, String>>[
      MapEntry('Trade / position', profile.trade),
      MapEntry('Experience', profile.experience),
      for (final entry in const {
        'permits': 'Permits / licences',
        'education': 'Education',
        'previousWork': 'Previous work',
        'workHistory': 'Work history',
      }.entries)
        MapEntry(entry.value, profile.listField([entry.key]).join(', ')),
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
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
                _ResponsiveFieldGrid(items: cvItems),
              if (profile.references.isNotEmpty) ...[
                const SizedBox(height: 18),
                const Divider(),
                const SizedBox(height: 10),
                const Text(
                  'References',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 10),
                _ResponsiveFieldGrid(
                  items: profile.references.map((reference) {
                    final name = reference['name'] ?? '';
                    final details = [
                      reference['company'] ?? '',
                      reference['phone'] ?? '',
                      reference['email'] ?? '',
                    ].where((value) => value.isNotEmpty).join('\n');
                    return MapEntry(
                      name.isEmpty ? 'Reference' : name,
                      details,
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 18),
        _SectionPanel(
          title: 'Portfolio',
          action: onAddPortfolio == null
              ? null
              : FilledButton.icon(
                  onPressed: mediaBusy ? null : onAddPortfolio,
                  icon: mediaBusy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add_photo_alternate_outlined),
                  label: Text(mediaBusy ? 'Uploading...' : 'Add photos'),
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
                  onOpenProfile: onOpenProfile,
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
    required this.mediaBusy,
    required this.ownProfile,
    this.onAddCompanyPhotos,
    this.onRemoveCompanyPhoto,
    this.onOpenJob,
    this.contactAfterInformation,
  });

  final WebProfileData profile;
  final List<Job> jobs;
  final bool loading;
  final bool mediaBusy;
  final bool ownProfile;
  final VoidCallback? onAddCompanyPhotos;
  final ValueChanged<String>? onRemoveCompanyPhoto;
  final void Function(String jobId, bool ownerView)? onOpenJob;
  final Widget? contactAfterInformation;

  @override
  Widget build(BuildContext context) {
    final facts = <MapEntry<String, String>>[
      MapEntry('Website', profile.website),
      MapEntry('Speciality', profile.trade),
      MapEntry('Location', profile.location),
    ].where((entry) => entry.value.trim().isNotEmpty).toList();
    final sections = <MapEntry<String, String>>[
      for (final entry in const {
        'companyGoals': 'Our goals and objectives',
        'companyAdvantages': 'Our advantages',
        'companyClients': 'Our clients',
        'companyWhoWeAre': 'Who we are',
        'companyHistory': 'Our history',
      }.entries)
        MapEntry(entry.value, profile.data[entry.key]?.toString() ?? ''),
    ].where((entry) => entry.value.trim().isNotEmpty).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
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
              if (facts.isNotEmpty) ...[
                const SizedBox(height: 16),
                _ResponsiveFieldGrid(items: facts),
              ],
              for (final section in sections) ...[
                const SizedBox(height: 18),
                _FieldTile(
                  label: section.key,
                  value: section.value,
                  fullWidth: true,
                ),
              ],
            ],
          ),
        ),
        if (contactAfterInformation != null) ...[
          const SizedBox(height: 18),
          contactAfterInformation!,
        ],
        const SizedBox(height: 18),
        _SectionPanel(
          title: 'Company photos',
          action: onAddCompanyPhotos == null
              ? null
              : FilledButton.icon(
                  onPressed: mediaBusy ? null : onAddCompanyPhotos,
                  icon: mediaBusy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add_photo_alternate_outlined),
                  label: Text(mediaBusy ? 'Uploading...' : 'Add photos'),
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
              : _CompanyJobsList(
                  jobs: jobs,
                  ownProfile: ownProfile,
                  onOpenJob: onOpenJob,
                ),
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
      MapEntry(
          'Contact person', profile.data['contactPerson']?.toString() ?? ''),
      MapEntry(
          'Additional phones', profile.listField(const ['phones']).join(', ')),
      MapEntry('Website', profile.website),
    ].where((item) => item.value.trim().isNotEmpty).toList();
    final structuredContacts = (profile.data['contacts'] as List?)
            ?.whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList() ??
        const <Map<String, dynamic>>[];

    return WebPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Contacts', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 14),
          Wrap(spacing: 6, children: [
            if (profile.email.isNotEmpty)
              IconButton(
                  tooltip: 'Email',
                  icon: const Icon(Icons.email_outlined),
                  onPressed: () =>
                      launchUrl(Uri(scheme: 'mailto', path: profile.email))),
            if (profile.phone.isNotEmpty)
              IconButton(
                  tooltip: 'Call',
                  icon: const Icon(Icons.phone_outlined),
                  onPressed: () =>
                      launchUrl(Uri(scheme: 'tel', path: profile.phone))),
            if (profile.website.isNotEmpty)
              IconButton(
                  tooltip: 'Website',
                  icon: const Icon(Icons.language),
                  onPressed: () {
                    final uri = Uri.tryParse(profile.website.contains('://')
                        ? profile.website
                        : 'https://${profile.website}');
                    if (uri != null && ['https', 'http'].contains(uri.scheme)) {
                      launchUrl(uri, mode: LaunchMode.externalApplication);
                    }
                  }),
          ]),
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
          if (structuredContacts.isNotEmpty) ...[
            const Divider(height: 24),
            const Text('Team contacts',
                style: TextStyle(fontWeight: FontWeight.w800)),
            for (final contact in structuredContacts)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(contact['name']?.toString() ?? ''),
                subtitle: Text(contact['phone']?.toString() ?? ''),
              ),
          ],
        ],
      ),
    );
  }
}

class _TeamsList extends StatelessWidget {
  const _TeamsList({
    required this.teams,
    this.onOpenProfile,
  });

  final List<WebTeamData> teams;
  final void Function(String, String)? onOpenProfile;

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
            borderRadius: BorderRadius.circular(WebRadii.card),
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
                        const SizedBox(height: 4),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                team.description.isEmpty
                                    ? 'View team details'
                                    : team.description,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(height: 1.35),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              tooltip: 'Open Team',
                              visualDensity: VisualDensity.compact,
                              constraints: const BoxConstraints.tightFor(
                                width: 36,
                                height: 36,
                              ),
                              padding: EdgeInsets.zero,
                              onPressed: onOpenProfile == null
                                  ? null
                                  : () => onOpenProfile!(team.id, 'team'),
                              icon: const Icon(Icons.visibility_outlined),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          [
                            if (team.trade.isNotEmpty) team.trade,
                            '${team.memberCount} member${team.memberCount == 1 ? '' : 's'}',
                          ].join('  |  '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: WebTheme.muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (team.members.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: team.members
                      .map(
                        (member) => ActionChip(
                          onPressed: () =>
                              onOpenProfile?.call(member.id, 'worker'),
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
    this.onOpenJob,
  });

  final List<Job> jobs;
  final bool ownProfile;
  final void Function(String jobId, bool ownerView)? onOpenJob;

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
        return InkWell(
          onTap:
              onOpenJob == null ? null : () => onOpenJob!(job.id, ownProfile),
          borderRadius: BorderRadius.circular(WebRadii.card),
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: WebTheme.surfaceAlt,
              borderRadius: BorderRadius.circular(WebRadii.card),
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
  late final TextEditingController contactPerson;
  late final TextEditingController experience;
  late final TextEditingController qualifications;
  late final TextEditingController certifications;
  final references = <_ReferenceEditors>[];
  final extraPhones = <TextEditingController>[];
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
    contactPerson = TextEditingController(
      text: profile.data['contactPerson']?.toString() ?? '',
    );
    experience = TextEditingController(text: profile.experience);
    qualifications = TextEditingController(
      text: profile.listField(const ['qualifications']).join(', '),
    );
    certifications = TextEditingController(
      text: profile
          .listField(const ['certificationsText', 'certifications']).join(', '),
    );
    if (widget.role == 'worker') {
      final raw = profile.data['references'];
      if (raw is List) {
        for (final item in raw) {
          references.add(_ReferenceEditors.fromValue(item));
        }
      } else if (raw is String && raw.trim().isNotEmpty) {
        references.add(_ReferenceEditors.fromValue(raw));
      }
    } else {
      final raw = profile.data['phones'];
      if (raw is List) {
        for (final value in raw) {
          extraPhones.add(TextEditingController(text: value.toString()));
        }
      }
    }
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
      contactPerson,
      experience,
      qualifications,
      certifications,
    ]) {
      controller.dispose();
    }
    for (final reference in references) {
      reference.dispose();
    }
    for (final controller in extraPhones) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEmployer = widget.role == 'employer';
    return AlertDialog(
      title: Text(isEmployer ? 'Edit company profile' : 'Edit worker profile'),
      content: WebDialogScrollArea(
        preferredWidth: 720,
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
            if (isEmployer) ...[
              _input(website, 'Website'),
              _input(contactPerson, 'Contact person'),
              _additionalPhonesEditor(),
            ],
            if (!isEmployer) _referencesEditor(),
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
      {int lines = 1, TextInputType? keyboardType}) {
    return SizedBox(
      width: _dialogFieldWidth(lines > 1 ? 680 : 330),
      child: TextField(
        controller: controller,
        maxLines: lines,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  double _dialogFieldWidth(double preferred) =>
      (MediaQuery.sizeOf(context).width - 112)
          .clamp(240.0, preferred)
          .toDouble();

  Widget _referencesEditor() {
    return SizedBox(
      width: _dialogFieldWidth(680),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('References (optional)',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          for (var index = 0; index < references.length; index++)
            Container(
              key: ValueKey(references[index]),
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                border: Border.all(color: WebTheme.border),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    Expanded(child: Text('Reference ${index + 1}')),
                    IconButton(
                      tooltip: 'Remove reference',
                      onPressed: saving
                          ? null
                          : () => setState(() {
                                references.removeAt(index).dispose();
                              }),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ]),
                  Wrap(spacing: 12, runSpacing: 12, children: [
                    _input(references[index].name, 'Referee name'),
                    _input(references[index].company, 'Company / role'),
                    _input(references[index].phone, 'Phone',
                        keyboardType: TextInputType.phone),
                    _input(references[index].email, 'Email',
                        keyboardType: TextInputType.emailAddress),
                  ]),
                ],
              ),
            ),
          OutlinedButton.icon(
            onPressed: saving
                ? null
                : () => setState(() {
                      references.add(_ReferenceEditors.empty());
                    }),
            icon: const Icon(Icons.add),
            label: const Text('Add reference'),
          ),
        ],
      ),
    );
  }

  Widget _additionalPhonesEditor() {
    return SizedBox(
      width: _dialogFieldWidth(680),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Additional phones',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          for (var index = 0; index < extraPhones.length; index++)
            Padding(
              key: ValueKey(extraPhones[index]),
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(children: [
                Expanded(
                  child: _input(extraPhones[index], 'Phone',
                      keyboardType: TextInputType.phone),
                ),
                IconButton(
                  tooltip: 'Remove phone',
                  onPressed: saving
                      ? null
                      : () => setState(() {
                            extraPhones.removeAt(index).dispose();
                          }),
                  icon: const Icon(Icons.delete_outline),
                ),
              ]),
            ),
          TextButton.icon(
            onPressed: saving
                ? null
                : () => setState(() {
                      extraPhones.add(TextEditingController());
                    }),
            icon: const Icon(Icons.add),
            label: const Text('Add phone'),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    setState(() => saving = true);
    final isEmployer = widget.role == 'employer';
    final addressParts = [
      addressLine1.text.trim(),
      addressLine2.text.trim(),
      addressLine3.text.trim(),
      city.text.trim(),
      county.text.trim(),
      postcode.text.trim(),
      country.text.trim(),
    ].where((part) => part.isNotEmpty).toList();
    final singleLineAddress = addressParts.join(', ');
    final updates = <String, dynamic>{
      if (isEmployer) 'companyName': name.text.trim(),
      if (isEmployer) 'name': name.text.trim(),
      if (!isEmployer) 'name': name.text.trim(),
      'displayName': name.text.trim(),
      'email': email.text.trim(),
      'phone': phone.text.trim(),
      if (isEmployer) 'description': bio.text.trim(),
      if (isEmployer) 'bio': bio.text.trim(),
      if (!isEmployer) 'bio': bio.text.trim(),
      'trade': trade.text.trim(),
      'location': singleLineAddress,
      'address': singleLineAddress,
      'addressLine1': addressLine1.text.trim(),
      'addressLine2': addressLine2.text.trim(),
      'addressLine3': addressLine3.text.trim(),
      'city': city.text.trim(),
      'town': city.text.trim(),
      'townCity': city.text.trim(),
      'county': county.text.trim(),
      'postcode': postcode.text.trim(),
      'country': country.text.trim(),
      if (isEmployer) 'website': website.text.trim(),
      if (isEmployer) 'contactPerson': contactPerson.text.trim(),
      if (isEmployer) 'contactName': contactPerson.text.trim(),
      if (isEmployer)
        'phones': extraPhones
            .map((controller) => controller.text.trim())
            .where((value) => value.isNotEmpty)
            .toList(),
      if (!isEmployer) 'experience': experience.text.trim(),
      if (!isEmployer) 'qualifications': _splitList(qualifications.text),
      if (!isEmployer) 'certificationsText': certifications.text.trim(),
      if (!isEmployer)
        'references': references
            .map((reference) => reference.value())
            .where((reference) =>
                reference.values.any((value) => value.isNotEmpty))
            .toList(),
    };
    try {
      await widget.onSave(updates);
      if (mounted) Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }
}

class _ReferenceEditors {
  _ReferenceEditors({
    required this.name,
    required this.company,
    required this.phone,
    required this.email,
  });

  factory _ReferenceEditors.empty() => _ReferenceEditors.fromValue(null);

  factory _ReferenceEditors.fromValue(dynamic value) {
    final map = value is Map ? value : const <String, dynamic>{};
    return _ReferenceEditors(
      name: TextEditingController(
        text: value is String ? value.trim() : map['name']?.toString() ?? '',
      ),
      company: TextEditingController(text: map['company']?.toString() ?? ''),
      phone: TextEditingController(text: map['phone']?.toString() ?? ''),
      email: TextEditingController(text: map['email']?.toString() ?? ''),
    );
  }

  final TextEditingController name;
  final TextEditingController company;
  final TextEditingController phone;
  final TextEditingController email;

  Map<String, String> value() => {
        'name': name.text.trim(),
        'company': company.text.trim(),
        'phone': phone.text.trim(),
        'email': email.text.trim(),
      };

  void dispose() {
    name.dispose();
    company.dispose();
    phone.dispose();
    email.dispose();
  }
}

class _TeamDialog extends StatefulWidget {
  const _TeamDialog({
    required this.title,
    required this.onSave,
  });

  final String title;
  final Future<void> Function(Map<String, String> values) onSave;

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
    name = TextEditingController();
    description = TextEditingController();
    trade = TextEditingController();
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
      content: WebDialogScrollArea(
        preferredWidth: 560,
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
              color: WebTheme.ink,
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

class _ResponsiveFieldGrid extends StatelessWidget {
  const _ResponsiveFieldGrid({required this.items});

  final List<MapEntry<String, String>> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 18.0;
        final columns = constraints.maxWidth >= 620 ? 2 : 1;
        final itemWidth = columns == 1
            ? constraints.maxWidth
            : (constraints.maxWidth - gap) / 2;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: items
              .map(
                (item) => SizedBox(
                  width: itemWidth,
                  child: _FieldTile(
                    label: item.key,
                    value: item.value,
                    fullWidth: true,
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return WebStatusChip(label: label.replaceAll('_', ' '));
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
