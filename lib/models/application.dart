class Application {
  final String id;
  final String jobId;
  final String applicantId; // worker или team leader
  final String? teamId; // null если одиночная заявка
  final String status; 
  // applied, negotiation, offer, hired, rejected

  final DateTime createdAt;

  Application({
    required this.id,
    required this.jobId,
    required this.applicantId,
    this.teamId,
    required this.status,
    required this.createdAt,
  });

  factory Application.fromMap(Map<String, dynamic> map, String id) {
    return Application(
      id: id,
      jobId: map['jobId'] ?? '',
      applicantId: map['applicantId'] ?? '',
      teamId: map['teamId'],
      status: map['status'] ?? 'applied',
      createdAt: DateTime.parse(map['createdAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'jobId': jobId,
      'applicantId': applicantId,
      'teamId': teamId,
      'status': status,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}