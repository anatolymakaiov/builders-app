import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'application_activity_service.dart';

class WebHomeBadgeService {
  WebHomeBadgeService({
    FirebaseFirestore? firestore,
    this.refreshInterval = const Duration(seconds: 20),
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;
  final Duration refreshInterval;

  Stream<int> unreadWorkerApplications(String workerId) {
    return _pollCount(() => _loadUnreadWorkerApplications(workerId));
  }

  Stream<int> unreadProfileNotices({
    required String userId,
    required String role,
  }) {
    if (role == "admin") return const Stream.empty();
    return _pollCount(() => _loadUnreadProfileNotices(userId));
  }

  Stream<int> _pollCount(Future<int> Function() load) {
    late final Timer timer;
    var lastValue = 0;
    var loading = false;
    final controller = StreamController<int>();

    Future<void> refresh() async {
      if (loading || controller.isClosed) return;
      loading = true;
      try {
        lastValue = await load();
        if (!controller.isClosed) controller.add(lastValue);
      } catch (_) {
        if (!controller.isClosed) controller.add(lastValue);
      } finally {
        loading = false;
      }
    }

    controller.onListen = () {
      unawaited(refresh());
      timer = Timer.periodic(refreshInterval, (_) {
        unawaited(refresh());
      });
    };
    controller.onCancel = () async {
      timer.cancel();
    };

    return controller.stream;
  }

  Future<int> _loadUnreadWorkerApplications(String workerId) async {
    final applicationsRef = _firestore.collection("applications");
    final workerDocs =
        await applicationsRef.where("workerId", isEqualTo: workerId).get();
    final teamIds = await _loadWorkerTeamIds(workerId);

    final seen = <String>{};
    var count = 0;

    void countUnread(
        Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
      for (final doc in docs) {
        if (!seen.add(doc.id)) continue;
        if (ApplicationActivityService.isUnreadFor(doc.data(), workerId)) {
          count++;
        }
      }
    }

    countUnread(workerDocs.docs);

    for (final teamId in teamIds) {
      final teamDocs =
          await applicationsRef.where("teamId", isEqualTo: teamId).get();
      countUnread(teamDocs.docs.where((doc) {
        return _isRelevantTeamApplication(doc.data(), teamId);
      }));
    }

    return count;
  }

  Future<List<String>> _loadWorkerTeamIds(String workerId) async {
    final snapshot = await _firestore.collection("teams").get();
    return snapshot.docs
        .where((doc) => _isWorkerTeam(doc.data(), workerId))
        .map((doc) => doc.id)
        .toSet()
        .toList();
  }

  Future<int> _loadUnreadProfileNotices(String userId) async {
    final adminMessages = await _firestore
        .collection("admin_messages")
        .where("receiverId", isEqualTo: userId)
        .where("readByReceiver", isEqualTo: false)
        .get();
    final policyNotices = await _firestore
        .collection("users")
        .doc(userId)
        .collection("notifications")
        .where("read", isEqualTo: false)
        .where("category", isEqualTo: "policy")
        .get();

    final adminCount = adminMessages.docs
        .where((doc) => doc.data()["deletedByReceiver"] != true)
        .length;
    return adminCount + policyNotices.docs.length;
  }

  bool _isWorkerTeam(Map<String, dynamic> data, String workerId) {
    return data["ownerId"] == workerId ||
        data["createdBy"] == workerId ||
        data["leaderId"] == workerId ||
        _idsFromList(data["memberIds"]).contains(workerId) ||
        _idsFromList(data["members"]).contains(workerId) ||
        _mapHasActiveMember(data["memberStatuses"], workerId) ||
        _mapHasActiveMember(data["membersStatus"], workerId);
  }

  List<String> _idsFromList(dynamic value) {
    if (value is! List) return [];
    return value
        .map((item) {
          if (item is String) return item;
          if (item is Map) {
            return (item["userId"] ?? item["uid"] ?? item["id"])?.toString();
          }
          return null;
        })
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
  }

  bool _mapHasActiveMember(dynamic value, String workerId) {
    if (value is! Map || !value.containsKey(workerId)) return false;
    return _activeStatus(value[workerId]);
  }

  bool _activeStatus(dynamic value) {
    final status = value?.toString().trim().toLowerCase() ?? "";
    return ![
      "removed",
      "deleted",
      "inactive",
      "left",
      "rejected",
    ].contains(status);
  }

  bool _isRelevantTeamApplication(
    Map<String, dynamic> data,
    String teamId,
  ) {
    final type = data["type"]?.toString().trim().toLowerCase();
    final applicationType =
        data["applicationType"]?.toString().trim().toLowerCase();
    final status = data["status"]?.toString().toLowerCase().trim();
    return data["teamId"]?.toString() == teamId &&
        (type == "team" || applicationType == "team") &&
        status != "withdrawn" &&
        status != "cancelled" &&
        status != "deleted";
  }
}
