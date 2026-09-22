import 'package:cloud_firestore/cloud_firestore.dart';

enum WorkerReviewSort { newest, highest, lowest, oldest }

enum RatingStarFill { empty, half, full }

class WorkerReview {
  const WorkerReview({
    required this.id,
    required this.reviewerName,
    required this.reviewerLogoUrl,
    required this.rating,
    required this.text,
    required this.createdAt,
    required this.jobTitle,
    required this.jobId,
    required this.applicationId,
  });

  final String id;
  final String reviewerName;
  final String reviewerLogoUrl;
  final double rating;
  final String text;
  final DateTime? createdAt;
  final String jobTitle;
  final String jobId;
  final String applicationId;

  factory WorkerReview.fromMap(String id, Map<String, dynamic> data) {
    return WorkerReview(
      id: id,
      reviewerName: (data['employerName'] ?? 'Employer').toString().trim(),
      reviewerLogoUrl: (data['employerLogoUrl'] ?? '').toString().trim(),
      rating: ((data['rating'] as num?)?.toDouble() ?? 0).clamp(0, 5),
      text: (data['review'] ?? '').toString().trim(),
      createdAt: workerReviewDate(data['createdAt']),
      jobTitle: (data['jobTitle'] ?? '').toString().trim(),
      jobId: (data['jobId'] ?? '').toString().trim(),
      applicationId: (data['applicationId'] ?? '').toString().trim(),
    );
  }
}

DateTime? workerReviewDate(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is num && value > 0) {
    return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  }
  return null;
}

double workerAverageRating(Iterable<WorkerReview> reviews) {
  final rated = reviews.where((review) => review.rating > 0).toList();
  if (rated.isEmpty) return 0;
  return rated.fold<double>(0, (total, review) => total + review.rating) /
      rated.length;
}

List<RatingStarFill> workerRatingStars(double rating) {
  final rounded = (rating.clamp(0, 5) * 2).round() / 2;
  return List<RatingStarFill>.generate(5, (index) {
    final remaining = rounded - index;
    if (remaining >= 1) return RatingStarFill.full;
    if (remaining >= .5) return RatingStarFill.half;
    return RatingStarFill.empty;
  }, growable: false);
}

List<WorkerReview> sortWorkerReviews(
  Iterable<WorkerReview> reviews,
  WorkerReviewSort sort,
) {
  final result = reviews.toList();
  int compareDate(WorkerReview a, WorkerReview b) {
    final aDate = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final bDate = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    return aDate.compareTo(bDate);
  }

  result.sort((a, b) => switch (sort) {
        WorkerReviewSort.highest => b.rating.compareTo(a.rating),
        WorkerReviewSort.lowest => a.rating.compareTo(b.rating),
        WorkerReviewSort.newest => compareDate(b, a),
        WorkerReviewSort.oldest => compareDate(a, b),
      });
  return result;
}
