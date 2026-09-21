import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/worker_review_service.dart';
import 'app_cached_image.dart';

String _reviewError(Object error) {
  if (error is FirebaseFunctionsException) {
    return error.message ?? 'Could not update the review request.';
  }
  return 'Could not update the review request. Please try again.';
}

Future<bool> showRequestEmployerReviewDialog(BuildContext context) async {
  return await showDialog<bool>(
        context: context,
        builder: (_) => const _RequestEmployerReviewDialog(),
      ) ??
      false;
}

Future<bool> showEmployerReviewRequestDialog(
  BuildContext context, {
  required String requestId,
}) async {
  return await showDialog<bool>(
        context: context,
        builder: (_) => _EmployerReviewRequestDialog(requestId: requestId),
      ) ??
      false;
}

class WorkerReviewRequestsPanel extends StatefulWidget {
  const WorkerReviewRequestsPanel({super.key, this.onChanged});

  final VoidCallback? onChanged;

  @override
  State<WorkerReviewRequestsPanel> createState() =>
      _WorkerReviewRequestsPanelState();
}

class _WorkerReviewRequestsPanelState extends State<WorkerReviewRequestsPanel> {
  final service = WorkerReviewService();
  late Future<List<EmployerReviewRequest>> requests = service.myRequests();

  void reload() => setState(() => requests = service.myRequests());

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: () async {
              if (await showRequestEmployerReviewDialog(context) && mounted) {
                reload();
                widget.onChanged?.call();
              }
            },
            icon: const Icon(Icons.add_comment_outlined),
            label: const Text('Request a review'),
          ),
        ),
        FutureBuilder<List<EmployerReviewRequest>>(
          future: requests,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.only(top: 10),
                child: LinearProgressIndicator(),
              );
            }
            if (snapshot.hasError) {
              return TextButton(
                onPressed: reload,
                child: const Text('Could not load review requests. Retry'),
              );
            }
            final items = snapshot.data ?? const <EmployerReviewRequest>[];
            if (items.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Column(
                children: [
                  for (final item in items.take(5))
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.rate_review_outlined),
                      title: Text(item.employerName),
                      subtitle:
                          Text('${item.jobTitle} • ${_status(item.status)}'),
                      trailing: item.awaitingWorker
                          ? const Icon(Icons.chevron_right)
                          : null,
                      onTap: item.awaitingWorker
                          ? () async {
                              if (await showEmployerReviewRequestDialog(
                                    context,
                                    requestId: item.id,
                                  ) &&
                                  mounted) {
                                reload();
                                widget.onChanged?.call();
                              }
                            }
                          : null,
                    ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _RequestEmployerReviewDialog extends StatefulWidget {
  const _RequestEmployerReviewDialog();

  @override
  State<_RequestEmployerReviewDialog> createState() =>
      _RequestEmployerReviewDialogState();
}

class _RequestEmployerReviewDialogState
    extends State<_RequestEmployerReviewDialog> {
  final service = WorkerReviewService();
  late final Future<List<ReviewEngagement>> engagements =
      service.eligibleEngagements();
  String? selectedApplicationId;
  bool busy = false;
  String? error;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Request a review'),
      content: SizedBox(
        width: 520,
        child: FutureBuilder<List<ReviewEngagement>>(
          future: engagements,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.hasError) {
              return Text(_reviewError(snapshot.error!));
            }
            final items = snapshot.data ?? const <ReviewEngagement>[];
            if (items.isEmpty) {
              return const Text(
                'No eligible completed or accepted work relationships were found.',
              );
            }
            return ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 420),
              child: ListView(
                shrinkWrap: true,
                children: [
                  const Text(
                    'Choose a company from confirmed work engagements.',
                  ),
                  const SizedBox(height: 8),
                  for (final item in items)
                    ListTile(
                      selected: selectedApplicationId == item.applicationId,
                      onTap: !item.canRequest || busy
                          ? null
                          : () => setState(
                                () =>
                                    selectedApplicationId = item.applicationId,
                              ),
                      leading: _CompanyLogo(url: item.employerLogoUrl),
                      title: Text(item.employerName),
                      subtitle: Text(item.canRequest
                          ? item.jobTitle
                          : '${item.jobTitle} • ${_status(item.requestStatus)}'),
                      trailing: Icon(
                        selectedApplicationId == item.applicationId
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                      ),
                    ),
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Text(error!, style: const TextStyle(color: Colors.red)),
                  ],
                ],
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed:
              busy || selectedApplicationId == null ? null : _submitRequest,
          child: busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Send request'),
        ),
      ],
    );
  }

  Future<void> _submitRequest() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await service.requestReview(selectedApplicationId!);
      if (mounted) Navigator.pop(context, true);
    } catch (exception) {
      if (mounted) setState(() => error = _reviewError(exception));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}

class _EmployerReviewRequestDialog extends StatefulWidget {
  const _EmployerReviewRequestDialog({required this.requestId});

  final String requestId;

  @override
  State<_EmployerReviewRequestDialog> createState() =>
      _EmployerReviewRequestDialogState();
}

class _EmployerReviewRequestDialogState
    extends State<_EmployerReviewRequestDialog> {
  final service = WorkerReviewService();
  final reviewController = TextEditingController();
  late Future<EmployerReviewRequest> request =
      service.getRequest(widget.requestId);
  int rating = 5;
  bool busy = false;
  String? error;

  @override
  void dispose() {
    reviewController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<EmployerReviewRequest>(
      future: request,
      builder: (context, snapshot) {
        final item = snapshot.data;
        return AlertDialog(
          title: const Text('Employer review'),
          content: SizedBox(
            width: 520,
            child: snapshot.connectionState == ConnectionState.waiting
                ? const SizedBox(
                    height: 120,
                    child: Center(child: CircularProgressIndicator()),
                  )
                : snapshot.hasError
                    ? Text(_reviewError(snapshot.error!))
                    : _content(item!),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(context, false),
              child: const Text('Close'),
            ),
            if (item != null) ..._actions(item),
          ],
        );
      },
    );
  }

  Widget _content(EmployerReviewRequest item) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final employerResponding = uid == item.employerId && item.awaitingEmployer;
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            employerResponding ? item.workerName : item.employerName,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(item.jobTitle),
          const SizedBox(height: 16),
          if (employerResponding) ...[
            Row(
              children: List.generate(
                5,
                (index) => IconButton(
                  tooltip: '${index + 1} stars',
                  onPressed:
                      busy ? null : () => setState(() => rating = index + 1),
                  icon: Icon(
                    index < rating ? Icons.star : Icons.star_border,
                    color: Colors.orange,
                  ),
                ),
              ),
            ),
            TextField(
              controller: reviewController,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: 'Written review',
                hintText: 'Quality of work, reliability and communication',
              ),
            ),
          ] else if (item.rating > 0) ...[
            Row(
              children: [
                for (var index = 0; index < 5; index++)
                  Icon(
                    index < item.rating ? Icons.star : Icons.star_border,
                    color: Colors.orange,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(item.review),
            if (item.awaitingWorker) ...[
              const SizedBox(height: 16),
              const Text(
                'This review is private until you choose Publish on my profile.',
              ),
            ],
          ] else
            Text('Status: ${_status(item.status)}'),
          if (error != null) ...[
            const SizedBox(height: 12),
            Text(error!, style: const TextStyle(color: Colors.red)),
          ],
        ],
      ),
    );
  }

  List<Widget> _actions(EmployerReviewRequest item) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == item.employerId && item.awaitingEmployer) {
      return [
        FilledButton(
          onPressed: busy ? null : () => _respond(item),
          child: const Text('Submit review'),
        ),
      ];
    }
    if (uid == item.workerId && item.awaitingWorker) {
      return [
        OutlinedButton(
          onPressed: busy ? null : () => _decide(item, false),
          child: const Text('Decline'),
        ),
        FilledButton(
          onPressed: busy ? null : () => _decide(item, true),
          child: const Text('Publish on my profile'),
        ),
      ];
    }
    return const [];
  }

  Future<void> _respond(EmployerReviewRequest item) async {
    if (reviewController.text.trim().isEmpty) {
      setState(() => error = 'Enter a written review.');
      return;
    }
    await _run(() => service.respond(
          requestId: item.id,
          rating: rating,
          review: reviewController.text,
        ));
  }

  Future<void> _decide(EmployerReviewRequest item, bool publish) async {
    await _run(() => service.decide(requestId: item.id, publish: publish));
  }

  Future<void> _run(Future<void> Function() operation) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await operation();
      if (mounted) Navigator.pop(context, true);
    } catch (exception) {
      if (mounted) setState(() => error = _reviewError(exception));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}

class _CompanyLogo extends StatelessWidget {
  const _CompanyLogo({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: SizedBox(
        width: 42,
        height: 42,
        child: url.trim().isEmpty
            ? const ColoredBox(
                color: Color(0xFFE8EEF2),
                child: Icon(Icons.business_outlined),
              )
            : AppCachedImage(
                imageUrl: url,
                fit: BoxFit.cover,
                errorWidget: const ColoredBox(
                  color: Color(0xFFE8EEF2),
                  child: Icon(Icons.business_outlined),
                ),
              ),
      ),
    );
  }
}

String _status(String value) {
  return switch (value) {
    'requested' => 'Waiting for company',
    'responded' => 'Ready for your decision',
    'published' => 'Published',
    'declined' => 'Declined',
    'cancelled' => 'Cancelled',
    _ => value,
  };
}
