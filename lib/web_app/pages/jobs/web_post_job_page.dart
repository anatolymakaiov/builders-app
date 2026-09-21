import 'package:flutter/material.dart';

import '../../../models/job.dart';
import '../../../services/address_lookup_service.dart';
import '../../../services/billing_service.dart';
import '../../../services/job_taxonomy_service.dart';
import '../../../services/job_start_date.dart';
import '../../../services/vacancy_import_service.dart';
import '../../services/web_job_management_service.dart';
import '../../services/web_vacancy_import_metadata.dart';
import '../../theme/web_breakpoints.dart';
import '../../theme/web_theme.dart';
import '../../widgets/web_page_container.dart';
import '../../widgets/web_panel.dart';
import '../../widgets/web_remote_image.dart';
import '../../widgets/web_design_components.dart';
import '../../widgets/web_vacancy_import_dialog.dart';

class WebPostJobPage extends StatefulWidget {
  const WebPostJobPage({
    super.key,
    required this.userId,
    this.existingJob,
    this.onDone,
    this.onCancel,
    this.onOpenBilling,
  });

  final String userId;
  final Job? existingJob;
  final ValueChanged<String?>? onDone;
  final VoidCallback? onCancel;
  final VoidCallback? onOpenBilling;

  @override
  State<WebPostJobPage> createState() => _WebPostJobPageState();
}

class _WebPostJobPageState extends State<WebPostJobPage> {
  final service = WebJobManagementService();
  final addressLookup = IdealPostcodesAddressLookupService();
  late final TextEditingController role;
  late final TextEditingController site;
  late final TextEditingController duration;
  late final TextEditingController weeklyHours;
  late final TextEditingController positions;
  late final TextEditingController rate;
  late final TextEditingController postcode;
  late final TextEditingController addressLine1;
  late final TextEditingController addressLine2;
  late final TextEditingController addressLine3;
  late final TextEditingController city;
  late final TextEditingController county;
  late final TextEditingController country;
  late final TextEditingController description;
  late final TextEditingController responsibilities;
  late final TextEditingController candidateRequirements;
  late final TextEditingController requiredDocuments;
  late final TextEditingController additionalInformation;
  String jobType = 'hourly';
  List<String> photos = const <String>[];
  double lat = 0;
  double lng = 0;
  bool saving = false;
  bool uploading = false;
  int uploadCompleted = 0;
  int uploadTotal = 0;
  bool importingVacancy = false;
  bool lookingUp = false;
  String? error;
  DateTime? selectedStartDate;
  late final String mediaScope;

  bool get editing => widget.existingJob != null;

  @override
  void initState() {
    super.initState();
    final job = widget.existingJob;
    mediaScope = job?.id.trim().isNotEmpty == true
        ? job!.id.trim()
        : 'draft-${DateTime.now().microsecondsSinceEpoch}';
    role = TextEditingController(
      text: job?.canonicalRoleName.isNotEmpty == true
          ? job!.canonicalRoleName
          : job?.displayTitle ?? '',
    );
    site = TextEditingController(text: job?.site ?? '');
    duration = TextEditingController(text: job?.duration ?? '');
    weeklyHours = TextEditingController(text: job?.weeklyHours ?? '');
    selectedStartDate =
        job?.startDate == null ? null : jobDateOnly(job!.startDate!);
    positions = TextEditingController(text: (job?.positions ?? 1).toString());
    rate = TextEditingController(
        text: job == null || job.rate <= 0 ? '' : job.rate.toString());
    postcode = TextEditingController(text: job?.postcode ?? '');
    addressLine1 = TextEditingController(text: job?.street ?? '');
    addressLine2 = TextEditingController(text: '');
    addressLine3 = TextEditingController(text: '');
    city = TextEditingController(text: job?.city ?? '');
    county = TextEditingController(text: job?.county ?? '');
    country = TextEditingController(text: 'United Kingdom');
    description = TextEditingController(text: job?.description ?? '');
    responsibilities = TextEditingController(text: job?.responsibilities ?? '');
    candidateRequirements =
        TextEditingController(text: job?.candidateRequirements ?? '');
    requiredDocuments =
        TextEditingController(text: job?.requiredDocuments ?? '');
    additionalInformation =
        TextEditingController(text: job?.additionalInformation ?? '');
    jobType = job?.jobType ?? 'hourly';
    photos = List<String>.from(job?.photos ?? const <String>[]);
    lat = job?.lat ?? 0;
    lng = job?.lng ?? 0;
  }

  @override
  void dispose() {
    for (final controller in [
      role,
      site,
      duration,
      weeklyHours,
      positions,
      rate,
      postcode,
      addressLine1,
      addressLine2,
      addressLine3,
      city,
      county,
      country,
      description,
      responsibilities,
      candidateRequirements,
      requiredDocuments,
      additionalInformation,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WebPageContainer(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            WebPageHeader(
              title: editing ? 'Edit vacancy' : 'Post a job',
              subtitle: editing
                  ? 'Update vacancy details and submit changes for review.'
                  : 'Create a clear vacancy for qualified construction workers.',
              leading: IconButton(
                tooltip: 'Back',
                onPressed: saving ? null : widget.onCancel,
                icon: const Icon(Icons.arrow_back),
              ),
              actions: [
                if (!editing)
                  OutlinedButton.icon(
                    onPressed:
                        saving || importingVacancy ? null : _importVacancy,
                    icon: importingVacancy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.upload_file_outlined),
                    label: Text(
                      importingVacancy
                          ? 'Parsing vacancy file...'
                          : 'Import PDF / Word',
                    ),
                  ),
              ],
            ),
            if (error != null) _ErrorBanner(message: error!),
            LayoutBuilder(
              builder: (context, constraints) {
                final compact =
                    constraints.maxWidth < WebBreakpoints.compactWidth;
                final main = _mainForm();
                final side = _sideForm();
                if (compact) {
                  return Column(
                    children: [
                      main,
                      const SizedBox(height: 18),
                      side,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 7, child: main),
                    const SizedBox(width: 22),
                    Expanded(flex: 4, child: side),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _mainForm() {
    return Column(
      children: [
        WebPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Vacancy role',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 14),
              Autocomplete<String>(
                initialValue: TextEditingValue(text: role.text),
                optionsBuilder: (value) {
                  final query = value.text.trim();
                  if (query.isEmpty) {
                    return JobTaxonomyService.canonicalRoles.take(12);
                  }
                  return JobTaxonomyService.suggestions(query, limit: 12)
                      .map((item) => item.canonical);
                },
                onSelected: (value) => role.text = value,
                fieldViewBuilder: (
                  context,
                  controller,
                  focusNode,
                  onFieldSubmitted,
                ) {
                  if (controller.text != role.text) controller.text = role.text;
                  controller.addListener(() => role.text = controller.text);
                  return TextField(
                    controller: controller,
                    focusNode: focusNode,
                    decoration: const InputDecoration(
                      labelText: 'Job role / trade',
                      border: OutlineInputBorder(),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        WebPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Description',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 14),
              _input(description, 'Description', lines: 5),
              _gap(),
              _input(responsibilities, 'Responsibilities', lines: 4),
              _gap(),
              _input(candidateRequirements, 'Candidate requirements', lines: 4),
              _gap(),
              _input(requiredDocuments, 'Required documents / certifications',
                  lines: 3),
              _gap(),
              _input(additionalInformation, 'Additional information', lines: 3),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sideForm() {
    return Column(
      children: [
        WebPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Work details',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 14),
              _input(site, 'Site / project name'),
              _gap(),
              _input(positions, 'Workers needed',
                  keyboardType: TextInputType.number),
              _gap(),
              DropdownButtonFormField<String>(
                initialValue: jobType,
                decoration: const InputDecoration(
                  labelText: 'Work format',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'hourly', child: Text('Daywork')),
                  DropdownMenuItem(value: 'price', child: Text('Price')),
                  DropdownMenuItem(
                      value: 'negotiable', child: Text('Negotiable')),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => jobType = value);
                },
              ),
              if (jobType != 'negotiable') ...[
                _gap(),
                _input(rate, jobType == 'price' ? 'Price (£)' : 'Rate (£)',
                    keyboardType: TextInputType.number),
              ],
              _gap(),
              _input(duration, 'Duration'),
              _gap(),
              _input(weeklyHours, 'Hours per week'),
              _gap(),
              InkWell(
                onTap: saving ? null : _pickStartDate,
                borderRadius: BorderRadius.circular(WebRadii.input),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Expected start date',
                    helperText:
                        'Choose the expected or approximate date the work will begin.',
                    suffixIcon: Icon(Icons.calendar_month_outlined),
                    border: OutlineInputBorder(),
                  ),
                  child: Text(formatJobStartDate(selectedStartDate)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        WebPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Address', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(child: _input(postcode, 'UK postcode')),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: 'Find address',
                    onPressed: lookingUp ? null : _lookupAddress,
                    icon: lookingUp
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.search),
                  ),
                ],
              ),
              _gap(),
              _input(addressLine1, 'Address Line 1'),
              _gap(),
              _input(addressLine2, 'Address Line 2'),
              _gap(),
              _input(addressLine3, 'Address Line 3'),
              _gap(),
              _input(city, 'Town / City'),
              _gap(),
              _input(county, 'County'),
              _gap(),
              _input(country, 'Country'),
            ],
          ),
        ),
        const SizedBox(height: 18),
        WebPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('Photos',
                        style: Theme.of(context).textTheme.titleLarge),
                  ),
                  OutlinedButton.icon(
                    onPressed: uploading ? null : _addPhotos,
                    icon: uploading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add_photo_alternate_outlined),
                    label: const Text('Add'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _PhotoPreview(
                photos: photos,
                onRemove: (url) => setState(
                  () => photos = photos.where((item) => item != url).toList(),
                ),
              ),
              if (uploading) ...[
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: uploadTotal > 0 ? uploadCompleted / uploadTotal : null,
                ),
                const SizedBox(height: 6),
                Text(
                  uploadTotal > 0
                      ? 'Uploading photos: $uploadCompleted of $uploadTotal'
                      : 'Preparing selected photos...',
                  style: const TextStyle(color: WebTheme.muted),
                ),
              ] else if (photos.isNotEmpty) ...[
                const SizedBox(height: 10),
                const Text(
                  'Photos are uploaded and ready. Sending for approval will only submit the vacancy details and photo links.',
                  style: TextStyle(color: WebTheme.muted),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: saving || uploading || importingVacancy ? null : _submit,
            icon: saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send_outlined),
            label: Text(
              saving
                  ? (editing
                      ? 'Sending edit for review...'
                      : 'Sending for approval...')
                  : (editing ? 'Send edit for review' : 'Send for approval'),
            ),
          ),
        ),
        if (editing && widget.existingJob?.moderationStatus == 'approved')
          const Padding(
            padding: EdgeInsets.only(top: 10),
            child: Text(
              'Approved vacancy edits are sent for administrator review before going live.',
              style: TextStyle(color: WebTheme.muted),
            ),
          ),
      ],
    );
  }

  Widget _input(
    TextEditingController controller,
    String label, {
    int lines = 1,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      minLines: lines,
      maxLines: lines,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    );
  }

  Widget _gap() => const SizedBox(height: 12);

  Future<void> _lookupAddress() async {
    setState(() {
      lookingUp = true;
      error = null;
    });
    try {
      final normalized = addressLookup.normalizePostcode(postcode.text);
      postcode.text = normalized;
      if (!addressLookup.isValidPostcode(normalized)) {
        throw StateError(
            'Enter a valid UK postcode or enter address manually.');
      }
      final found = await addressLookup.lookupPostcode(normalized);
      if (found == null) {
        throw StateError('Postcode not found. Enter address manually.');
      }
      setState(() {
        if (found.addressLine1.isNotEmpty) {
          addressLine1.text = found.addressLine1;
        }
        if (found.addressLine2.isNotEmpty) {
          addressLine2.text = found.addressLine2;
        }
        if (found.addressLine3.isNotEmpty) {
          addressLine3.text = found.addressLine3;
        }
        if (found.townCity.isNotEmpty) city.text = found.townCity;
        if (found.county.isNotEmpty) county.text = found.county;
        if (found.country.isNotEmpty) country.text = found.country;
        lat = found.latitude ?? lat;
        lng = found.longitude ?? lng;
      });
    } catch (err) {
      setState(() => error = err.toString().replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) setState(() => lookingUp = false);
    }
  }

  Future<void> _addPhotos() async {
    setState(() {
      uploading = true;
      uploadCompleted = 0;
      uploadTotal = 0;
      error = null;
    });
    try {
      final uploaded = await service.pickAndUploadPhotos(
        ownerId: widget.userId,
        mediaScope: mediaScope,
        onProgress: (completed, total) {
          if (!mounted) return;
          setState(() {
            uploadCompleted = completed;
            uploadTotal = total;
          });
        },
      );
      if (uploaded.isNotEmpty) {
        setState(() => photos = [...photos, ...uploaded]);
      }
    } catch (err) {
      setState(() => error = 'Could not upload photos: $err');
    } finally {
      if (mounted) {
        setState(() {
          uploading = false;
          uploadCompleted = 0;
          uploadTotal = 0;
        });
      }
    }
  }

  Future<void> _importVacancy() async {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      importingVacancy = true;
      error = null;
    });
    try {
      final parsed = await VacancyImportService.pickAndParseVacancyFile();
      if (parsed == null || !mounted) return;
      final reviewed = await showDialog<ParsedVacancy>(
        context: context,
        builder: (_) => WebVacancyImportDialog(parsedVacancy: parsed),
      );
      if (reviewed == null || !mounted) return;

      final metadata = WebVacancyImportMetadata.fromParsed(reviewed);
      setState(() {
        if (reviewed.jobDescription.isNotEmpty) {
          description.text = reviewed.jobDescription;
        }
        if (reviewed.responsibilities.isNotEmpty) {
          responsibilities.text = reviewed.responsibilities;
        }
        if (reviewed.requirements.isNotEmpty) {
          candidateRequirements.text = reviewed.requirements;
        }
        if (reviewed.requiredDocumentsAndCertifications.isNotEmpty) {
          requiredDocuments.text = reviewed.requiredDocumentsAndCertifications;
        }
        if (reviewed.additionalInformation.isNotEmpty) {
          additionalInformation.text = reviewed.additionalInformation;
        }
        if (role.text.trim().isEmpty &&
            reviewed.suggestedRole?.trim().isNotEmpty == true) {
          role.text = reviewed.suggestedRole!.trim();
        }
        if (site.text.trim().isEmpty && metadata.site.isNotEmpty) {
          site.text = metadata.site;
        }
        if (metadata.positions != null && metadata.positions! > 0) {
          positions.text = metadata.positions.toString();
        }
        if (metadata.rate != null && metadata.rate! > 0) {
          rate.text = metadata.rate!.toStringAsFixed(
            metadata.rate! % 1 == 0 ? 0 : 2,
          );
          jobType = 'hourly';
        }
        if (metadata.duration.isNotEmpty) {
          duration.text = metadata.duration;
        }
        if (metadata.weeklyHours.isNotEmpty) {
          weeklyHours.text = metadata.weeklyHours;
        }
        if (reviewed.expectedStartDate != null) {
          selectedStartDate = jobDateOnly(reviewed.expectedStartDate!);
        }
        if (postcode.text.trim().isEmpty && metadata.postcode.isNotEmpty) {
          postcode.text = metadata.postcode;
        }
        if (addressLine1.text.trim().isEmpty &&
            metadata.addressLine1.isNotEmpty) {
          addressLine1.text = metadata.addressLine1;
        }
        if (city.text.trim().isEmpty && metadata.city.isNotEmpty) {
          city.text = metadata.city;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vacancy imported. Review all fields before sending.'),
        ),
      );
    } on VacancyImportException catch (err) {
      if (mounted) setState(() => error = err.message);
    } catch (err) {
      debugPrint('WEB VACANCY IMPORT ERROR $err');
      if (mounted) {
        setState(() {
          error = 'Could not import this vacancy file. '
              'You can continue entering the vacancy manually.';
        });
      }
    } finally {
      if (mounted) setState(() => importingVacancy = false);
    }
  }

  Future<void> _submit() async {
    final validation = _validate();
    if (validation != null) {
      setState(() => error = validation);
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final companyName = await service.companyName(widget.userId);
      final data = service.buildJobData(
        ownerId: widget.userId,
        title: role.text.trim(),
        site: site.text.trim(),
        duration: duration.text.trim(),
        weeklyHours: weeklyHours.text.trim(),
        startDate: selectedStartDate,
        positions: int.tryParse(positions.text) ?? 1,
        filledPositions: widget.existingJob?.filledPositions ?? 0,
        jobType: jobType,
        rate: double.tryParse(rate.text) ?? 0,
        addressLine1: addressLine1.text.trim(),
        addressLine2: addressLine2.text.trim(),
        addressLine3: addressLine3.text.trim(),
        city: city.text.trim(),
        county: county.text.trim(),
        postcode: addressLookup.normalizePostcode(postcode.text),
        country: country.text.trim(),
        description: description.text.trim(),
        responsibilities: responsibilities.text.trim(),
        candidateRequirements: candidateRequirements.text.trim(),
        requiredDocuments: requiredDocuments.text.trim(),
        additionalInformation: additionalInformation.text.trim(),
        photos: photos,
        lat: lat,
        lng: lng,
        companyName: companyName,
        create: !editing,
      );
      if (editing) {
        await service.submitVacancyEditReview(
          jobId: widget.existingJob!.id,
          proposedChanges: data,
        );
        widget.onDone?.call(widget.existingJob!.id);
      } else {
        final id = await service.createVacancy(data);
        widget.onDone?.call(id.isEmpty ? null : id);
      }
    } on BillingLimitException catch (err) {
      setState(() => error = err.message);
      widget.onOpenBilling?.call();
    } catch (err) {
      setState(() => error = err.toString());
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  String? _validate() {
    if (role.text.trim().isEmpty) return 'Enter job role / trade.';
    if (site.text.trim().isEmpty) return 'Enter site / project name.';
    if (!addressLookup.isValidPostcode(postcode.text)) {
      return 'Enter a valid UK postcode.';
    }
    if (addressLine1.text.trim().isEmpty) return 'Enter Address Line 1.';
    if (city.text.trim().isEmpty) return 'Enter Town / City.';
    if (country.text.trim().isEmpty) return 'Enter Country.';
    if (!editing && selectedStartDate == null) {
      return 'Choose the expected start date.';
    }
    if (!editing &&
        selectedStartDate != null &&
        isHistoricalJobStartDate(selectedStartDate!)) {
      return 'Expected start date cannot be in the past.';
    }
    if ((int.tryParse(positions.text) ?? 0) <= 0) {
      return 'Workers needed must be at least 1.';
    }
    return null;
  }

  Future<void> _pickStartDate() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final today = jobDateOnly(DateTime.now());
    final existing = selectedStartDate;
    final firstDate =
        existing != null && existing.isBefore(today) ? existing : today;
    final picked = await showDatePicker(
      context: context,
      initialDate: existing ?? today,
      firstDate: firstDate,
      lastDate: DateTime(today.year + 10, 12, 31),
      helpText: 'Expected start date',
    );
    if (picked == null || !mounted) return;
    setState(() => selectedStartDate = jobDateOnly(picked));
  }
}

class _PhotoPreview extends StatelessWidget {
  const _PhotoPreview({required this.photos, required this.onRemove});

  final List<String> photos;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    if (photos.isEmpty) {
      return const Text('No vacancy photos yet.',
          style: TextStyle(color: WebTheme.muted));
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: photos.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemBuilder: (context, index) {
        final url = photos[index];
        return Stack(
          fit: StackFit.expand,
          children: [
            WebRemoteImage(url: url, borderRadius: 10),
            Positioned(
              right: 4,
              top: 4,
              child: IconButton.filledTonal(
                onPressed: () => onRemove(url),
                icon: const Icon(Icons.close, size: 16),
                style: IconButton.styleFrom(
                  fixedSize: const Size(30, 30),
                  minimumSize: const Size(30, 30),
                ),
              ),
            ),
          ],
        );
      },
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
