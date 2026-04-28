import 'package:cloud_firestore/cloud_firestore.dart';

class ApplicationActivityService {
  static Map<String, dynamic> createdForEmployer(String? employerId) {
    final unreadFor = <String>[
      if (employerId != null && employerId.isNotEmpty) employerId,
    ];

    return {
      "applicationActivityAt": FieldValue.serverTimestamp(),
      "unreadFor": unreadFor,
    };
  }

  static List<String> workerRecipients(Map<String, dynamic> data) {
    final recipients = <String>{};

    final workerId = data["workerId"]?.toString();
    if (workerId != null && workerId.isNotEmpty) recipients.add(workerId);

    final members = data["members"];
    if (members is List) {
      for (final member in members) {
        final id = member?.toString() ?? "";
        if (id.isNotEmpty) recipients.add(id);
      }
    }

    return recipients.toList();
  }

  static List<String> employerRecipients(Map<String, dynamic> data) {
    final employerId = data["employerId"]?.toString();
    if (employerId == null || employerId.isEmpty) return [];
    return [employerId];
  }

  static bool isUnreadFor(Map<String, dynamic> data, String userId) {
    final unreadFor = data["unreadFor"];
    return unreadFor is List &&
        unreadFor.map((e) => e.toString()).contains(userId);
  }

  static DateTime activityDate(Map<String, dynamic> data) {
    final value =
        data["applicationActivityAt"] ?? data["updatedAt"] ?? data["createdAt"];
    if (value is Timestamp) return value.toDate();
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  static int compareForUser(
    QueryDocumentSnapshot a,
    QueryDocumentSnapshot b,
    String userId,
  ) {
    final aData = a.data() as Map<String, dynamic>;
    final bData = b.data() as Map<String, dynamic>;
    final aUnread = isUnreadFor(aData, userId);
    final bUnread = isUnreadFor(bData, userId);

    if (aUnread != bUnread) return aUnread ? -1 : 1;

    return activityDate(bData).compareTo(activityDate(aData));
  }

  static Future<void> markRead(String applicationId, String userId) async {
    await FirebaseFirestore.instance
        .collection("applications")
        .doc(applicationId)
        .set({
      "unreadFor": FieldValue.arrayRemove([userId]),
    }, SetOptions(merge: true));
  }

  static Future<void> updateStatus({
    required String applicationId,
    required String status,
    required List<String> unreadFor,
    Map<String, dynamic> extra = const {},
  }) async {
    await FirebaseFirestore.instance
        .collection("applications")
        .doc(applicationId)
        .set({
      "status": status,
      "applicationActivityAt": FieldValue.serverTimestamp(),
      "updatedAt": FieldValue.serverTimestamp(),
      if (unreadFor.isNotEmpty) "unreadFor": FieldValue.arrayUnion(unreadFor),
      ...extra,
    }, SetOptions(merge: true));
  }
}
