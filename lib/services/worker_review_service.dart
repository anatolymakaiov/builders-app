import 'package:cloud_functions/cloud_functions.dart';

class ReviewEngagement {
  const ReviewEngagement({
    required this.applicationId,
    required this.employerId,
    required this.employerName,
    required this.employerLogoUrl,
    required this.jobId,
    required this.jobTitle,
    required this.requestStatus,
  });

  final String applicationId;
  final String employerId;
  final String employerName;
  final String employerLogoUrl;
  final String jobId;
  final String jobTitle;
  final String requestStatus;

  bool get canRequest => requestStatus.isEmpty;

  factory ReviewEngagement.fromMap(Map<String, dynamic> data) {
    return ReviewEngagement(
      applicationId: (data['applicationId'] ?? '').toString(),
      employerId: (data['employerId'] ?? '').toString(),
      employerName: (data['employerName'] ?? 'Company').toString(),
      employerLogoUrl: (data['employerLogoUrl'] ?? '').toString(),
      jobId: (data['jobId'] ?? '').toString(),
      jobTitle: (data['jobTitle'] ?? 'Work engagement').toString(),
      requestStatus: (data['requestStatus'] ?? '').toString(),
    );
  }
}

class EmployerReviewRequest {
  const EmployerReviewRequest({
    required this.id,
    required this.workerId,
    required this.employerId,
    required this.applicationId,
    required this.jobId,
    required this.jobTitle,
    required this.workerName,
    required this.employerName,
    required this.employerLogoUrl,
    required this.status,
    required this.rating,
    required this.review,
    required this.createdAt,
  });

  final String id;
  final String workerId;
  final String employerId;
  final String applicationId;
  final String jobId;
  final String jobTitle;
  final String workerName;
  final String employerName;
  final String employerLogoUrl;
  final String status;
  final int rating;
  final String review;
  final DateTime? createdAt;

  bool get awaitingEmployer => status == 'requested';
  bool get awaitingWorker => status == 'responded';

  factory EmployerReviewRequest.fromMap(Map<String, dynamic> data) {
    final millis = (data['createdAtMillis'] as num?)?.toInt() ?? 0;
    return EmployerReviewRequest(
      id: (data['id'] ?? '').toString(),
      workerId: (data['workerId'] ?? '').toString(),
      employerId: (data['employerId'] ?? '').toString(),
      applicationId: (data['applicationId'] ?? '').toString(),
      jobId: (data['jobId'] ?? '').toString(),
      jobTitle: (data['jobTitle'] ?? 'Work engagement').toString(),
      workerName: (data['workerName'] ?? 'Worker').toString(),
      employerName: (data['employerName'] ?? 'Company').toString(),
      employerLogoUrl: (data['employerLogoUrl'] ?? '').toString(),
      status: (data['status'] ?? '').toString(),
      rating: (data['rating'] as num?)?.toInt() ?? 0,
      review: (data['review'] ?? '').toString(),
      createdAt:
          millis > 0 ? DateTime.fromMillisecondsSinceEpoch(millis) : null,
    );
  }
}

class WorkerReviewService {
  WorkerReviewService({FirebaseFunctions? functions})
      : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  Future<List<ReviewEngagement>> eligibleEngagements() async {
    final result =
        await _functions.httpsCallable('listEligibleEmployerReviews').call();
    final data = Map<String, dynamic>.from(result.data as Map);
    final items = data['engagements'];
    if (items is! Iterable) return const [];
    return items
        .whereType<Map>()
        .map((item) => ReviewEngagement.fromMap(
              Map<String, dynamic>.from(item),
            ))
        .toList(growable: false);
  }

  Future<List<EmployerReviewRequest>> myRequests() async {
    final result =
        await _functions.httpsCallable('listMyEmployerReviewRequests').call();
    final data = Map<String, dynamic>.from(result.data as Map);
    final items = data['reviews'];
    if (items is! Iterable) return const [];
    return items
        .whereType<Map>()
        .map((item) => EmployerReviewRequest.fromMap(
              Map<String, dynamic>.from(item),
            ))
        .toList(growable: false);
  }

  Future<EmployerReviewRequest> getRequest(String requestId) async {
    final result = await _functions
        .httpsCallable('getEmployerReviewRequest')
        .call({'requestId': requestId});
    final data = Map<String, dynamic>.from(result.data as Map);
    return EmployerReviewRequest.fromMap(
      Map<String, dynamic>.from(data['review'] as Map),
    );
  }

  Future<String> requestReview(String applicationId) async {
    final result = await _functions
        .httpsCallable('requestEmployerReview')
        .call({'applicationId': applicationId});
    final data = Map<String, dynamic>.from(result.data as Map);
    return (data['requestId'] ?? '').toString();
  }

  Future<void> respond({
    required String requestId,
    required int rating,
    required String review,
  }) async {
    await _functions.httpsCallable('respondEmployerReview').call({
      'requestId': requestId,
      'rating': rating,
      'review': review.trim(),
    });
  }

  Future<void> decide({
    required String requestId,
    required bool publish,
  }) async {
    await _functions.httpsCallable('decideEmployerReview').call({
      'requestId': requestId,
      'decision': publish ? 'publish' : 'decline',
    });
  }
}
