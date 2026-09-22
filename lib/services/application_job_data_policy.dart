import '../models/job.dart';
import 'application_status_utils.dart';

class ApplicationJobDataPolicy {
  const ApplicationJobDataPolicy._();

  static const _historicalStatuses = <String>{
    'rejected',
    'withdrawn',
    'offer_rejected',
    'offer_withdrawn',
    'expired',
    'offer_expired',
    'closed',
    'archived',
    'removed',
  };

  static bool shouldListenToLiveJob(Map<String, dynamic> application) {
    final status = ApplicationStatusUtils.normalizeStatus(
      application['status'],
    );
    return !_historicalStatuses.contains(status);
  }

  static Job fallbackJob(String id, Map<String, dynamic> data) {
    return Job.fromFirestore(id, {
      'title': data['jobTitle'] ?? data['title'] ?? data['trade'] ?? 'Job',
      'trade': data['jobTrade'] ?? data['trade'] ?? data['jobTitle'] ?? 'Job',
      'site': data['jobSite'] ?? data['site'] ?? '',
      'location': data['jobLocation'] ??
          data['siteAddress'] ??
          data['jobAddress'] ??
          data['location'] ??
          '',
      'street': data['siteStreet'] ?? data['street'] ?? '',
      'city': data['siteCity'] ?? data['city'] ?? '',
      'postcode': data['sitePostcode'] ?? data['postcode'] ?? '',
      'county': data['siteCounty'] ?? data['county'] ?? '',
      'rate': _snapshotRate(data),
      'companyName': data['companyName'] ??
          data['employerName'] ??
          data['ownerName'] ??
          '',
      'companyLogo': _firstNonEmpty([
        data['companyLogoUrl'],
        data['companyLogo'],
        data['companyAvatarUrl'],
        data['employerAvatarUrl'],
        data['employerLogo'],
        data['ownerAvatarUrl'],
        data['ownerLogo'],
        data['logo'],
        data['photo'],
        data['avatarUrl'],
      ]),
      'photos': data['jobPhotos'] ?? data['photos'] ?? const [],
      'jobType': _snapshotJobType(data),
      'duration': _firstNonEmpty([
        data['duration'],
        data['jobDuration'],
        data['workPeriod'],
      ]),
      'weeklyHours': data['weeklyHours'] ?? '',
      'employmentType': data['employmentType'] ?? '',
      'ownerId': data['ownerId'] ?? data['employerId'] ?? '',
      'createdAt': data['createdAt'],
      'status': 'active',
      'moderationStatus': 'approved',
    });
  }

  static String _firstNonEmpty(List<dynamic> values) {
    for (final value in values) {
      final text = value?.toString().trim() ?? '';
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  static String _snapshotJobType(Map<String, dynamic> data) {
    final raw = _firstNonEmpty([
      data['jobType'],
      data['payType'],
      data['workFormat'],
      data['paymentType'],
    ]).toLowerCase();
    if (raw.isEmpty) return '';
    if (raw.contains('negoti')) return 'negotiable';
    if (raw.contains('price') || raw.contains('fixed')) return 'price';
    if (raw.contains('day') || raw.contains('hour')) return 'hourly';
    return raw;
  }

  static double _snapshotRate(Map<String, dynamic> data) {
    for (final value in [
      data['rate'],
      data['jobRate'],
      data['payAmount'],
      data['salary'],
      data['amount'],
    ]) {
      if (value is num) return value.toDouble();
      if (value is String) {
        final parsed =
            double.tryParse(value.replaceAll(RegExp(r'[^0-9.]'), ''));
        if (parsed != null) return parsed;
      }
    }
    return 0;
  }
}
