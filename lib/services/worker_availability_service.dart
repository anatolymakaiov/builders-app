import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

enum WorkerAvailability { openToWork, busy }

class WorkerAvailabilityService {
  static const field = 'availabilityStatus';

  static WorkerAvailability fromProfile(Map<String, dynamic> profile) =>
      profile[field] == 'busy'
          ? WorkerAvailability.busy
          : WorkerAvailability.openToWork;

  static String value(WorkerAvailability availability) =>
      availability == WorkerAvailability.busy ? 'busy' : 'open_to_work';

  static String label(WorkerAvailability availability) =>
      availability == WorkerAvailability.busy ? 'Busy' : 'Open to Work';

  Future<void> updateOwnStatus(
    String workerId,
    WorkerAvailability availability,
  ) async {
    if (FirebaseAuth.instance.currentUser?.uid != workerId) {
      throw StateError('Only the profile owner can change availability.');
    }
    await FirebaseFirestore.instance.collection('users').doc(workerId).update({
      field: value(availability),
    });
  }
}
