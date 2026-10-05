import 'package:cloud_firestore/cloud_firestore.dart';

/// Employer-safe worker projection. Contact and residential fields do not
/// exist on this model. Employer-wide reads stay disabled until trusted role
/// authorization is available in a later security phase.
class WorkerDiscoveryProfile {
  const WorkerDiscoveryProfile({
    required this.workerId,
    required this.displayNameShort,
    required this.avatarUrl,
    required this.tradeIds,
    required this.primaryTradeId,
    required this.experienceYears,
    required this.rating,
    required this.ratingCount,
    required this.availabilityStatus,
    required this.availableFrom,
    required this.allowVacancyInvites,
    required this.generalArea,
    required this.region,
    required this.discoveryVisible,
  });

  final String workerId;
  final String displayNameShort;
  final String avatarUrl;
  final List<String> tradeIds;
  final String primaryTradeId;
  final int experienceYears;
  final double rating;
  final int ratingCount;
  final String availabilityStatus;
  final DateTime? availableFrom;
  final bool allowVacancyInvites;
  final String generalArea;
  final String region;
  final bool discoveryVisible;

  factory WorkerDiscoveryProfile.fromFirestore(
          DocumentSnapshot<Map<String, dynamic>> snapshot) =>
      WorkerDiscoveryProfile.fromMap(
          snapshot.id, snapshot.data() ?? const <String, dynamic>{});

  factory WorkerDiscoveryProfile.fromMap(String id, Map<String, dynamic> data) {
    final rawAvailableFrom = data['availableFrom'];
    return WorkerDiscoveryProfile(
      workerId: id,
      displayNameShort: data['displayNameShort']?.toString() ?? 'Worker',
      avatarUrl: data['avatarUrl']?.toString() ?? '',
      tradeIds: (data['tradeIds'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(growable: false),
      primaryTradeId: data['primaryTradeId']?.toString() ?? '',
      experienceYears: (data['experienceYears'] as num?)?.toInt() ?? 0,
      rating: (data['rating'] as num?)?.toDouble() ?? 0,
      ratingCount: (data['ratingCount'] as num?)?.toInt() ?? 0,
      availabilityStatus: data['availabilityStatus']?.toString() ?? 'unknown',
      availableFrom: rawAvailableFrom is Timestamp
          ? rawAvailableFrom.toDate()
          : rawAvailableFrom is DateTime
              ? rawAvailableFrom
              : rawAvailableFrom is String
                  ? DateTime.tryParse(rawAvailableFrom)
                  : null,
      allowVacancyInvites: data['allowVacancyInvites'] == true,
      generalArea: data['generalArea']?.toString() ?? '',
      region: data['region']?.toString() ?? '',
      discoveryVisible: data['discoveryVisible'] == true,
    );
  }
}

class WorkerDiscoveryService {
  WorkerDiscoveryService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Future<WorkerDiscoveryProfile?> loadOwn(String uid) async {
    final snapshot =
        await _firestore.collection('worker_discovery').doc(uid).get();
    return snapshot.exists
        ? WorkerDiscoveryProfile.fromFirestore(snapshot)
        : null;
  }
}
