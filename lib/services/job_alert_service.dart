import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';

class JobAlertService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<void> saveWorkerAlert({
    required String userId,
    required String trade,
    required String jobType,
    required double distance,
    required double lat,
    required double lng,
  }) async {
    await _db
        .collection("users")
        .doc(userId)
        .collection("job_alerts")
        .doc("default")
        .set({
      "trade": trade,
      "jobType": jobType,
      "distance": distance,
      "lat": lat,
      "lng": lng,
      "active": true,
      "updatedAt": FieldValue.serverTimestamp(),
      "createdAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> notifyMatchingWorkers({
    required String jobId,
    required Map<String, dynamic> jobData,
  }) async {
    final jobLat = _safeDouble(jobData["lat"]);
    final jobLng = _safeDouble(jobData["lng"]);

    if (jobLat == null || jobLng == null) return;

    final alerts = await _db
        .collectionGroup("job_alerts")
        .where("active", isEqualTo: true)
        .get();

    final batch = _db.batch();
    var writes = 0;

    for (final alertDoc in alerts.docs) {
      final alert = alertDoc.data();
      final userRef = alertDoc.reference.parent.parent;

      if (userRef == null) continue;

      final trade = (alert["trade"] ?? "All").toString();
      final jobType = (alert["jobType"] ?? "All").toString();
      final distance = _safeDouble(alert["distance"]) ?? 50;
      final alertLat = _safeDouble(alert["lat"]);
      final alertLng = _safeDouble(alert["lng"]);

      if (alertLat == null || alertLng == null) continue;

      if (trade != "All" &&
          trade.toLowerCase() !=
              (jobData["trade"] ?? "").toString().toLowerCase()) {
        continue;
      }

      if (jobType != "All" &&
          jobType.toLowerCase() !=
              (jobData["jobType"] ?? "").toString().toLowerCase()) {
        continue;
      }

      final miles = Geolocator.distanceBetween(
            alertLat,
            alertLng,
            jobLat,
            jobLng,
          ) /
          1609.34;

      if (miles > distance) continue;

      final notificationRef = userRef.collection("notifications").doc();
      batch.set(notificationRef, {
        "type": "job_alert",
        "title": "New matching job",
        "body": jobData["title"] ?? "A new job matches your alert",
        "jobId": jobId,
        "trade": jobData["trade"] ?? "",
        "jobType": jobData["jobType"] ?? "",
        "distanceMiles": miles,
        "createdAt": FieldValue.serverTimestamp(),
        "read": false,
      });

      writes++;
    }

    if (writes > 0) {
      await batch.commit();
    }
  }

  double? _safeDouble(dynamic value) {
    if (value is int) return value.toDouble();
    if (value is double) return value;
    if (value is String) return double.tryParse(value);
    return null;
  }
}
