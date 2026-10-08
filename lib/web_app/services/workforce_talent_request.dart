import 'workforce_planning_service.dart';

class WorkforceTalentRequest {
  const WorkforceTalentRequest(
      {required this.tradeId,
      required this.location,
      required this.availableBy,
      required this.siteId,
      required this.vacancyId});

  final String tradeId;
  final String location;
  final DateTime availableBy;
  final String siteId;
  final String vacancyId;

  factory WorkforceTalentRequest.fromGap(WorkforcePlan plan, StaffingGap gap) {
    final site = plan.sites.where((item) => item.id == gap.siteId).firstOrNull;
    return WorkforceTalentRequest(
      tradeId: gap.tradeId,
      location: site?.city.isNotEmpty == true
          ? site!.city
          : (site?.data['region'] ?? '').toString(),
      availableBy: gap.needDate,
      siteId: gap.siteId,
      vacancyId: gap.vacancies.first.id,
    );
  }
}
