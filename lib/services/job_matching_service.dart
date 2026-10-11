import 'dart:math' as math;

import '../models/job.dart';
import 'job_taxonomy_service.dart';

enum JobMatchCategory {
  bestMatch,
  startsLater,
  alreadyStartedStillHiring,
  dateUnknown,
  alternativeLocation,
}

class JobMatchCriteria {
  const JobMatchCriteria({
    this.roles = const [],
    this.query = '',
    this.locations = '',
    this.radiusMiles = 50,
    this.minPay = 0,
    this.maxPay = 50,
    this.employmentTypes = const {},
    this.availableFrom,
  });

  final List<ConstructionRole> roles;
  final String query;

  /// Comma/semicolon/newline-separated places; any one may match.
  final String locations;
  final double radiusMiles;
  final double minPay;
  final double maxPay;
  final Set<String> employmentTypes;
  final DateTime? availableFrom;

  List<String> get selectedLocations => locations
      .split(RegExp(r'[,;\n]+'))
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toSet()
      .toList();
}

class RankedJob {
  const RankedJob(this.job, this.category);
  final Job job;
  final JobMatchCategory category;
}

class JobMatchResults {
  const JobMatchResults(this.entries, {required this.bestMatchCount});
  final List<RankedJob> entries;
  final int bestMatchCount;
  bool get hasSimilarButNoBest => bestMatchCount == 0 && entries.isNotEmpty;
  bool get isEmpty => entries.isEmpty;
}

/// Ranks only the caller's already-authorized candidate window. No reads or
/// account-specific cache live here; Web, Mobile and AI handoff use the same rules.
class JobMatchingService {
  static const int bestMatchWindowDays = 3;
  static const int maxAlternativeLocations = 30;

  static JobMatchResults rank(
    List<Job> candidates,
    JobMatchCriteria criteria, {
    Comparator<Job>? withinCategory,
    bool includeAlternatives = true,
    bool requirePublic = true,
  }) {
    final locations = criteria.selectedLocations;
    final origins = <String, ({double lat, double lng})>{};
    for (final location in locations) {
      final positioned = candidates
          .where((job) =>
              (!requirePublic ||
                  (job.isPubliclyVisible && job.remainingPositions > 0)) &&
              _cityMatches(job, location) &&
              _hasCoordinates(job))
          .toList();
      if (positioned.isNotEmpty) {
        origins[location] = (
          lat: positioned.map((job) => job.lat).reduce((a, b) => a + b) /
              positioned.length,
          lng: positioned.map((job) => job.lng).reduce((a, b) => a + b) /
              positioned.length,
        );
      }
    }

    final primary = <RankedJob>[];
    final alternative = <RankedJob>[];
    for (final job in candidates) {
      if (requirePublic &&
          (!job.isPubliclyVisible || job.remainingPositions <= 0)) {
        continue;
      }
      if (!JobTaxonomyService.matchesAnyRole(job, criteria.roles)) {
        continue;
      }
      if (!_queryMatches(job, criteria.query)) {
        continue;
      }
      if (criteria.employmentTypes.isNotEmpty &&
          !criteria.employmentTypes.contains(job.jobType)) {
        continue;
      }
      if (job.jobType == 'hourly' &&
          job.rate > 0 &&
          (job.rate < criteria.minPay || job.rate > criteria.maxPay)) {
        continue;
      }

      final locationMatches = locations.isEmpty ||
          locations.any((location) {
            if (_cityMatches(job, location)) return true;
            final origin = origins[location];
            return origin != null &&
                _hasCoordinates(job) &&
                _distanceMiles(origin.lat, origin.lng, job.lat, job.lng) <=
                    criteria.radiusMiles;
          });
      if (locationMatches) {
        primary.add(RankedJob(job, dateCategory(job, criteria.availableFrom)));
      } else if (includeAlternatives) {
        alternative.add(RankedJob(job, JobMatchCategory.alternativeLocation));
      }
    }

    int compare(RankedJob a, RankedJob b) {
      final tier = a.category.index.compareTo(b.category.index);
      if (tier != 0) return tier;
      final userSort = withinCategory?.call(a.job, b.job) ?? 0;
      if (userSort != 0) return userSort;
      if (withinCategory == null &&
          a.category == JobMatchCategory.startsLater &&
          a.job.startDate != null &&
          b.job.startDate != null) {
        final soonest = a.job.startDate!.compareTo(b.job.startDate!);
        if (soonest != 0) return soonest;
      }
      final newest = (b.job.createdAt ?? DateTime(1970))
          .compareTo(a.job.createdAt ?? DateTime(1970));
      return newest != 0 ? newest : a.job.id.compareTo(b.job.id);
    }

    primary.sort(compare);
    alternative.sort(compare);
    final entries = primary.isNotEmpty
        ? primary
        : [...primary, ...alternative.take(maxAlternativeLocations)];
    return JobMatchResults(entries,
        bestMatchCount: primary
            .where((entry) => entry.category == JobMatchCategory.bestMatch)
            .length);
  }

  static JobMatchCategory dateCategory(Job job, DateTime? availableFrom) {
    if (availableFrom == null) return JobMatchCategory.bestMatch;
    final start = job.startDate;
    if (start == null) return JobMatchCategory.dateUnknown;
    final available = DateTime.utc(
        availableFrom.year, availableFrom.month, availableFrom.day);
    final date = DateTime.utc(start.year, start.month, start.day);
    final days = date.difference(available).inDays;
    if (days < 0) return JobMatchCategory.alreadyStartedStillHiring;
    return days <= bestMatchWindowDays
        ? JobMatchCategory.bestMatch
        : JobMatchCategory.startsLater;
  }

  static String labelFor(RankedJob entry) => switch (entry.category) {
        JobMatchCategory.bestMatch => 'Best match',
        JobMatchCategory.startsLater =>
          'Starts ${entry.job.startDate!.day}/${entry.job.startDate!.month}',
        JobMatchCategory.alreadyStartedStillHiring =>
          'Already started · Still hiring',
        JobMatchCategory.dateUnknown => 'Start date not set',
        JobMatchCategory.alternativeLocation => 'Other location',
      };

  static bool _queryMatches(Job job, String query) {
    if (query.trim().isEmpty || JobTaxonomyService.matchesJob(job, query)) {
      return true;
    }
    final normal = JobTaxonomyService.normalise(query);
    final compact = JobTaxonomyService.compactNormalise(query);
    return [
      job.canonicalRoleName,
      job.originalEmployerInput,
      job.title,
      job.trade
    ]
        .where((value) => value.trim().isNotEmpty)
        .expand(JobTaxonomyService.searchTermsFor)
        .any((term) =>
            JobTaxonomyService.normalise(term).contains(normal) ||
            JobTaxonomyService.compactNormalise(term).contains(compact));
  }

  static bool _cityMatches(Job job, String city) => [
        job.city,
        job.location,
        job.fullAddress,
        job.postcode
      ].any((value) => value.toLowerCase().contains(city.toLowerCase()));

  static bool _hasCoordinates(Job job) => job.lat != 0 && job.lng != 0;

  static double _distanceMiles(
      double aLat, double aLng, double bLat, double bLng) {
    const radius = 3958.8;
    double rad(double degrees) => degrees * math.pi / 180;
    final dLat = rad(bLat - aLat);
    final dLng = rad(bLng - aLng);
    final haversine = math.pow(math.sin(dLat / 2), 2) +
        math.cos(rad(aLat)) *
            math.cos(rad(bLat)) *
            math.pow(math.sin(dLng / 2), 2);
    return 2 * radius * math.asin(math.sqrt(haversine.clamp(0, 1)));
  }
}
