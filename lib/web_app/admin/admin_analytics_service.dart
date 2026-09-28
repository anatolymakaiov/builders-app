import 'package:cloud_functions/cloud_functions.dart';

class AdminAnalyticsReport {
  const AdminAnalyticsReport({
    required this.keys,
    required this.series,
    required this.kpis,
    required this.notes,
  });

  final List<String> keys;
  final Map<String, List<num>> series;
  final Map<String, num?> kpis;
  final List<String> notes;

  factory AdminAnalyticsReport.fromMap(Map<String, dynamic> data) {
    final rawSeries = Map<String, dynamic>.from(data['series'] as Map? ?? {});
    final rawKpis = Map<String, dynamic>.from(data['kpis'] as Map? ?? {});
    return AdminAnalyticsReport(
      keys: (data['keys'] as List? ?? [])
          .map((value) => value.toString())
          .toList(),
      series: rawSeries.map((key, value) =>
          MapEntry(key, (value as List).map((item) => item as num).toList())),
      kpis: rawKpis
          .map((key, value) => MapEntry(key, value is num ? value : null)),
      notes: (data['notes'] as List? ?? [])
          .map((value) => value.toString())
          .toList(),
    );
  }
}

class AdminAnalyticsService {
  AdminAnalyticsService({FirebaseFunctions? functions})
      : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  Future<AdminAnalyticsReport> load(String tab, String period) async {
    final result = await _functions.httpsCallable('getAdminAnalytics').call({
      'tab': tab,
      'period': period,
    });
    return AdminAnalyticsReport.fromMap(
        Map<String, dynamic>.from(result.data as Map));
  }
}
