import 'package:cloud_functions/cloud_functions.dart';

class WebEmployerEntitlements {
  const WebEmployerEntitlements(this.data);

  final Map<String, dynamic> data;

  bool get candidateSearch => data['canUseCandidateSearch'] == true;
  bool get talentPool => data['canUseTalentPool'] == true;
  bool get vacancyInvites => data['canInviteToVacancy'] == true;
  bool get talentOutreach => data['canUseTalentOutreach'] == true;
  String get planId => data['planId']?.toString() ?? '';
  String get planName => data['planName']?.toString() ?? 'No plan';
  String get status => data['subscriptionStatus']?.toString() ?? 'inactive';
  int get invitationLimit =>
      (data['vacancyInviteMonthlyLimit'] as num?)?.toInt() ?? 0;
  int get invitationUsed =>
      ((data['usage'] as Map?)?['vacancyInvitations'] as num?)?.toInt() ?? 0;
  int get outreachLimit =>
      (data['talentOutreachMonthlyLimit'] as num?)?.toInt() ?? 0;
  int get outreachUsed =>
      ((data['usage'] as Map?)?['talentOutreach'] as num?)?.toInt() ?? 0;
  List<Map<String, dynamic>> get plans => (data['plans'] as List? ?? const [])
      .whereType<Map>()
      .map((plan) => Map<String, dynamic>.from(plan))
      .toList(growable: false);
}

class WebEmployerEntitlementsService {
  Future<WebEmployerEntitlements> load() async {
    final result = await FirebaseFunctions.instance
        .httpsCallable('getEmployerEntitlements')
        .call();
    return WebEmployerEntitlements(
        Map<String, dynamic>.from(result.data as Map));
  }
}
