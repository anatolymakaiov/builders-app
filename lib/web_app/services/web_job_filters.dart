import '../../models/job.dart';
import '../../services/job_matching_service.dart';
import '../../services/job_taxonomy_service.dart';

enum WebJobSort { nearest, highestPay, newest }

bool matchesSiteFilter(Job job, String? siteFilterId) =>
    siteFilterId == null || job.siteId == siteFilterId;

/// Web adapter for the matching rules embedded in mobile SmartJobSearchField.
/// The mobile presentation file cannot be imported into the separate Web app.
class WebJobFilters {
  const WebJobFilters({
    this.roles = const [],
    this.city = '',
    this.distance = 50,
    this.minPay = 0,
    this.maxPay = 50,
    this.employmentTypes = const {},
    this.availableFrom,
  });

  final List<ConstructionRole> roles;
  final String city;
  final double distance;
  final double minPay;
  final double maxPay;
  final Set<String> employmentTypes;
  final DateTime? availableFrom;

  JobMatchCriteria criteria(String query) => JobMatchCriteria(
        roles: roles,
        query: query,
        locations: city,
        radiusMiles: distance,
        minPay: minPay,
        maxPay: maxPay,
        employmentTypes: employmentTypes,
        availableFrom: availableFrom,
      );

  List<Job> apply(List<Job> jobs, String query, {bool requirePublic = true}) =>
      JobMatchingService.rank(jobs, criteria(query),
              includeAlternatives: false, requirePublic: requirePublic)
          .entries
          .map((entry) => entry.job)
          .toList();
}
