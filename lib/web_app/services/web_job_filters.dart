import 'package:geolocator/geolocator.dart';

import '../../models/job.dart';
import '../../services/job_taxonomy_service.dart';

enum WebJobSort { nearest, highestPay, newest }

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
  });

  final List<ConstructionRole> roles;
  final String city;
  final double distance;
  final double minPay;
  final double maxPay;
  final Set<String> employmentTypes;

  List<Job> apply(List<Job> jobs, String query) {
    final cityJobs =
        jobs.where((job) => _matchesCity(job) && _hasCoordinates(job)).toList();
    final origin = cityJobs.isEmpty
        ? null
        : (
            lat: cityJobs.fold<double>(0, (sum, job) => sum + job.lat) /
                cityJobs.length,
            lng: cityJobs.fold<double>(0, (sum, job) => sum + job.lng) /
                cityJobs.length,
          );
    return jobs.where((job) {
      if (!JobTaxonomyService.matchesAnyRole(job, roles)) return false;
      if (query.trim().isNotEmpty && !_matchesSmartQuery(job, query)) {
        return false;
      }
      if (employmentTypes.isNotEmpty &&
          !employmentTypes.contains(job.jobType)) {
        return false;
      }
      if (city.trim().isNotEmpty) {
        if (origin != null && _hasCoordinates(job)) {
          if (Geolocator.distanceBetween(
                      origin.lat, origin.lng, job.lat, job.lng) /
                  1609.34 >
              distance) {
            return false;
          }
        } else if (!_matchesCity(job)) {
          return false;
        }
      }
      if (job.jobType == 'hourly' &&
          job.rate > 0 &&
          (job.rate < minPay || job.rate > maxPay)) {
        return false;
      }
      return true;
    }).toList();
  }

  bool _matchesCity(Job job) => [
        job.city,
        job.location,
        job.fullAddress,
        job.postcode
      ].any((value) => value.toLowerCase().contains(city.trim().toLowerCase()));
  bool _hasCoordinates(Job job) => job.lat != 0 && job.lng != 0;

  bool _matchesSmartQuery(Job job, String query) {
    if (JobTaxonomyService.matchesJob(job, query)) return true;

    final normalizedQuery = JobTaxonomyService.normalise(query);
    if (normalizedQuery.isEmpty) return true;
    final compactQuery = JobTaxonomyService.compactNormalise(query);
    final roleValues = <String>{
      job.canonicalRoleName,
      job.originalEmployerInput,
      job.title,
      job.trade,
    }.where((value) => value.trim().isNotEmpty);

    for (final value in roleValues) {
      for (final term in JobTaxonomyService.searchTermsFor(value)) {
        final normalizedTerm = JobTaxonomyService.normalise(term);
        final compactTerm = JobTaxonomyService.compactNormalise(term);
        if (normalizedTerm.contains(normalizedQuery) ||
            compactTerm.contains(compactQuery)) {
          return true;
        }
      }
    }
    return false;
  }
}
