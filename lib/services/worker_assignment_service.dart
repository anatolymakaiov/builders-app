import 'package:cloud_firestore/cloud_firestore.dart';

class WorkerAssignment {
  const WorkerAssignment(this.id, this.data);
  final String id;
  final Map<String, dynamic> data;

  String get siteName => (data['siteName'] ?? 'Assigned work').toString();
  String get employerName => (data['employerName'] ?? '').toString();
  String get tradeId => (data['tradeId'] ?? '').toString();
  String get tradeName => (data['tradeName'] ?? tradeId).toString();
  String get status => (data['status'] ?? 'scheduled').toString();
  DateTime? get startDate => (data['startDate'] as Timestamp?)?.toDate();
  DateTime? get expectedEndDate =>
      (data['expectedEndDate'] as Timestamp?)?.toDate();
}

class WorkerAssignmentService {
  WorkerAssignmentService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  Stream<List<WorkerAssignment>> watchOwn(String workerId) => _db
      .collection('assignments')
      .where('workerId', isEqualTo: workerId)
      .snapshots()
      .map((snapshot) => snapshot.docs
          .map((doc) => WorkerAssignment(doc.id, doc.data()))
          .where((assignment) =>
              assignment.status == 'scheduled' || assignment.status == 'active')
          .toList());
}
