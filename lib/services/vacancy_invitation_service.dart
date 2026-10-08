import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

class VacancyInvitation {
  const VacancyInvitation({
    required this.id,
    required this.vacancyId,
    required this.workerId,
    required this.title,
    required this.company,
    required this.tradeId,
    required this.generalLocation,
    required this.status,
    this.createdAt,
  });

  final String id;
  final String vacancyId;
  final String workerId;
  final String title;
  final String company;
  final String tradeId;
  final String generalLocation;
  final String status;
  final DateTime? createdAt;

  bool get actionable => status == 'pending' || status == 'viewed';
  bool get closed => status == 'vacancy_closed' || status == 'vacancy_filled';

  String get statusLabel => switch (status) {
        'pending' => 'New',
        'viewed' => 'Viewed',
        'applied' => 'Applied',
        'not_interested' => 'Not interested',
        'vacancy_filled' => 'Vacancy filled',
        'vacancy_closed' => 'Vacancy closed',
        _ => 'Unavailable',
      };

  factory VacancyInvitation.fromDocument(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return VacancyInvitation(
      id: doc.id,
      vacancyId: (data['vacancyId'] as String?) ?? '',
      workerId: (data['workerId'] as String?) ?? '',
      title: (data['vacancyTitle'] as String?) ?? 'Construction vacancy',
      company: (data['companyName'] as String?) ?? 'Employer',
      tradeId: (data['tradeId'] as String?) ?? '',
      generalLocation: (data['generalLocation'] as String?) ?? '',
      status: (data['status'] as String?) ?? 'pending',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}

class VacancyInvitationService {
  VacancyInvitationService(
      {FirebaseFirestore? firestore, FirebaseFunctions? functions})
      : firestore = firestore ?? FirebaseFirestore.instance,
        functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFirestore firestore;
  final FirebaseFunctions functions;

  Stream<List<VacancyInvitation>> watchMine(String uid) => firestore
      .collection('vacancy_invitations')
      .where('workerId', isEqualTo: uid)
      .orderBy('createdAt', descending: true)
      .limit(50)
      .snapshots()
      .map((snapshot) => snapshot.docs
          .map(VacancyInvitation.fromDocument)
          .toList(growable: false));

  Future<Map<String, dynamic>> invite(String vacancyId, List<String> workerIds,
      {bool allowRelevanceMismatch = false}) async {
    final result =
        await functions.httpsCallable('inviteWorkersToVacancy').call({
      'vacancyId': vacancyId,
      'workerIds': workerIds,
      if (allowRelevanceMismatch) 'allowRelevanceMismatch': true,
    });
    return Map<String, dynamic>.from(result.data as Map);
  }

  Future<String> respond(String invitationId, String action) async {
    final result = await functions
        .httpsCallable('respondToVacancyInvitation')
        .call({'invitationId': invitationId, 'action': action});
    return (result.data as Map)['status'] as String;
  }
}
