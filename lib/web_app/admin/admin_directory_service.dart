import 'package:cloud_functions/cloud_functions.dart';

import '../../services/job_taxonomy_service.dart';
import '../services/web_admin_profile_service.dart';

class AdminDirectoryEntry {
  const AdminDirectoryEntry(this.record, this.distanceKm);

  final WebAdminRecord record;
  final double? distanceKm;
}

class AdminDirectoryPageResult {
  const AdminDirectoryPageResult(this.entries, this.nextCursor);

  final List<AdminDirectoryEntry> entries;
  final String? nextCursor;
}

class AdminDirectoryService {
  AdminDirectoryService({FirebaseFunctions? functions})
      : _functions = functions;

  final FirebaseFunctions? _functions;

  Future<AdminDirectoryPageResult> load({
    required String role,
    required String search,
    required String location,
    required String status,
    required List<ConstructionRole> professions,
    int? radiusKm,
    String? cursor,
  }) async {
    final terms = professions
        .expand((role) => role.searchableTerms)
        .map(JobTaxonomyService.normalise)
        .toSet()
        .toList();
    final result = await (_functions ?? FirebaseFunctions.instance)
        .httpsCallable('listAdminDirectory').call({
      'role': role,
      'search': search.trim(),
      'location': location.trim(),
      'status': status,
      'professionTerms': terms,
      if (radiusKm != null && location.trim().isNotEmpty) 'radiusKm': radiusKm,
      if (cursor != null) 'cursor': cursor,
    });
    final data = Map<String, dynamic>.from(result.data as Map);
    final entries = (data['records'] as List? ?? const []).map((raw) {
      final row = Map<String, dynamic>.from(raw as Map);
      return AdminDirectoryEntry(
        WebAdminRecord('users', row['id'].toString(),
            Map<String, dynamic>.from(row['data'] as Map)),
        (row['distanceKm'] as num?)?.toDouble(),
      );
    }).toList(growable: false);
    return AdminDirectoryPageResult(entries, data['nextCursor'] as String?);
  }
}
