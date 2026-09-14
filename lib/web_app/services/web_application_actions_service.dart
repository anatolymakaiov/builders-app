import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../services/application_activity_service.dart';
import '../../services/chat_service.dart';
import '../../services/offer_acceptance_service.dart';
import 'web_applications_data_service.dart';

class WebApplicationActionsService {
  WebApplicationActionsService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  Future<void> markReadOnce(WebApplicationSummary application) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null || !application.unreadFor(uid)) return;
    await ApplicationActivityService.markRead(application.id, uid);
  }

  Future<void> markViewedByEmployerOnce(
      WebApplicationSummary application) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null || application.employerId != uid) return;
    if (application.data['viewedByEmployer'] == true) return;
    await ApplicationActivityService.markViewedByEmployer(application.id);
  }

  Future<void> setStatus({
    required WebApplicationSummary application,
    required String status,
    required List<String> unreadFor,
    Map<String, dynamic> extra = const {},
  }) {
    return ApplicationActivityService.updateStatus(
      applicationId: application.id,
      status: status,
      unreadFor: unreadFor,
      extra: extra,
    );
  }

  Future<void> withdrawApplication(WebApplicationSummary application) {
    return _firestore.collection('applications').doc(application.id).delete();
  }

  Future<void> rejectOffer(WebApplicationSummary application) {
    return setStatus(
      application: application,
      status: 'offer_rejected',
      unreadFor:
          ApplicationActivityService.employerRecipients(application.data),
    );
  }

  Future<bool> acceptOffer(WebApplicationSummary application) async {
    final uid = _auth.currentUser?.uid;
    final accepted = await OfferAcceptanceService.acceptOffer(
      applicationId: application.id,
      currentUserId: uid,
    );
    if (accepted && uid != null) {
      await ApplicationActivityService.markRead(application.id, uid);
    }
    return accepted;
  }

  Future<void> sendOffer({
    required WebApplicationSummary application,
    required Map<String, dynamic> result,
    List<String> selectedWorkerIds = const <String>[],
    List<String> selectedWorkerNames = const <String>[],
  }) {
    final offer = {
      'jobType': result['jobType'],
      'workFormat': _jobTypeLabel(result['jobType']?.toString() ?? 'hourly'),
      'rate': result['rate'],
      'workPeriod': result['workPeriod'],
      'weeklyHours': result['weeklyHours'],
      'schedule': result['schedule'],
      'startDateTime': result['startDateTime'],
      if (result['startDateTimestamp'] is DateTime)
        'startDateTimestamp':
            Timestamp.fromDate(result['startDateTimestamp'] as DateTime),
      'siteStreet': result['siteStreet'],
      'siteAddressLine1': result['siteAddressLine1'],
      'siteAddressLine2': result['siteAddressLine2'],
      'siteAddressLine3': result['siteAddressLine3'],
      'siteCity': result['siteCity'],
      'sitePostcode': result['sitePostcode'],
      'siteCounty': result['siteCounty'],
      'siteCountry': result['siteCountry'],
      'siteAddress': result['siteAddress'],
      'fullAddress': result['siteAddress'],
      'firstDayRequirements': result['firstDayRequirements'],
      'description': result['description'],
      'validUntil': result['validUntil'],
      if (result['validUntilTimestamp'] is DateTime)
        'validUntilTimestamp':
            Timestamp.fromDate(result['validUntilTimestamp'] as DateTime),
      'startDate': result['startDateTime'],
      'message': result['description'],
      if (selectedWorkerIds.isNotEmpty) ...{
        'applicationId': application.id,
        'jobId': application.data['jobId'],
        'employerId': application.employerId,
        'teamId': application.teamId,
        'selectedWorkerIds': selectedWorkerIds,
        'selectedWorkerNames': selectedWorkerNames,
        'selectedWorkersCount': selectedWorkerIds.length,
      },
      'createdAt': FieldValue.serverTimestamp(),
    };

    return setStatus(
      application: application,
      status: 'offer_sent',
      unreadFor: selectedWorkerIds.isNotEmpty
          ? selectedWorkerIds
          : ApplicationActivityService.workerRecipients(application.data),
      extra: {
        'offer': offer,
        if (selectedWorkerIds.isNotEmpty) ...{
          'selectedWorkerIds': selectedWorkerIds,
          'selectedWorkerNames': selectedWorkerNames,
        },
      },
    );
  }

  Future<String?> chatIdForApplication(
      WebApplicationSummary application) async {
    final data = application.data;
    final isTeam = application.isTeam;
    final employerId = application.employerId;
    final jobId = data['jobId']?.toString() ?? '';
    if (employerId.isEmpty || jobId.isEmpty) return null;
    if (isTeam) {
      final teamId = application.teamId;
      final members = application.memberIds;
      if (teamId.isEmpty || members.isEmpty) return null;
      return ChatService.getOrCreateTeamChat(
        teamId: teamId,
        employerId: employerId,
        jobId: jobId,
        members: members,
        applicationId: application.id,
      );
    }
    final workerId = application.workerId;
    if (workerId.isEmpty) return null;
    return ChatService.getOrCreateChat(
      workerId: workerId,
      employerId: employerId,
      jobId: jobId,
      applicationId: application.id,
      jobTitle: application.jobTitle,
    );
  }

  String _jobTypeLabel(String value) {
    switch (value) {
      case 'price':
        return 'Price';
      case 'negotiable':
        return 'Negotiable';
      default:
        return 'Daywork';
    }
  }
}
