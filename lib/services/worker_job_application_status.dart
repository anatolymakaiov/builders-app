import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class WorkerJobApplicationStatus {
  static bool isActive(Map<String, dynamic> data) {
    final status = data['status']?.toString().trim().toLowerCase();
    return status != 'withdrawn' &&
        status != 'cancelled' &&
        status != 'deleted';
  }

  static Set<String> teamIdsForWorker(
    String uid,
    Map<String, Map<String, dynamic>> teams,
  ) {
    return teams.entries
        .where((entry) {
          final data = entry.value;
          final status = data['status']?.toString().trim().toLowerCase();
          if (data['deleted'] == true ||
              data['accountDeleted'] == true ||
              data['active'] == false ||
              {'deleted', 'suspended', 'on_hold'}.contains(status)) {
            return false;
          }
          if (['ownerId', 'createdBy', 'leaderId']
              .any((key) => data[key]?.toString() == uid)) {
            return true;
          }
          for (final key in ['members', 'memberIds']) {
            final members = data[key];
            if (members is List &&
                members.any((member) => _memberId(member) == uid)) {
              return true;
            }
          }
          for (final key in ['memberStatuses', 'membersStatus']) {
            final statuses = data[key];
            if (statuses is Map && statuses.containsKey(uid)) {
              final memberStatus =
                  statuses[uid]?.toString().trim().toLowerCase();
              if (!{'removed', 'deleted', 'inactive', 'left', 'rejected'}
                  .contains(memberStatus)) {
                return true;
              }
            }
          }
          return false;
        })
        .map((entry) => entry.key)
        .toSet();
  }

  static String? _memberId(dynamic member) {
    if (member is String) return member;
    if (member is Map) {
      return (member['userId'] ??
              member['uid'] ??
              member['workerId'] ??
              member['id'])
          ?.toString();
    }
    return null;
  }

  static Set<String> appliedJobIds({
    required String uid,
    required Iterable<Map<String, dynamic>> workerApplications,
    required Map<String, List<Map<String, dynamic>>> teamApplications,
    required Set<String> teamIds,
  }) {
    final result = <String>{};
    void add(Map<String, dynamic> data, {String? teamId}) {
      if (!isActive(data)) return;
      final jobId = data['jobId']?.toString().trim() ?? '';
      if (jobId.isEmpty) return;
      final applicationTeamId = data['teamId']?.toString().trim() ?? '';
      final type = (data['applicationType'] ?? data['type'])
          ?.toString()
          .trim()
          .toLowerCase();
      final isTeam = type == 'team' || applicationTeamId.isNotEmpty;
      final workerMatch = data['workerId']?.toString() == uid;
      final teamMatch = isTeam &&
          teamId != null &&
          applicationTeamId == teamId &&
          teamIds.contains(teamId);
      if (workerMatch || teamMatch) result.add(jobId);
    }

    for (final data in workerApplications) {
      add(data);
    }
    for (final entry in teamApplications.entries) {
      for (final data in entry.value) {
        add(data, teamId: entry.key);
      }
    }
    return result;
  }

  static Stream<Set<String>> watch(String uid, {FirebaseFirestore? firestore}) {
    final db = firestore ?? FirebaseFirestore.instance;
    late StreamController<Set<String>> controller;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? workerSub;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? teamsSub;
    final teamSubs =
        <String, StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>{};
    List<Map<String, dynamic>> workerApps = [];
    final teamApps = <String, List<Map<String, dynamic>>>{};
    var activeTeamIds = <String>{};
    var workerReady = false;
    var teamsReady = false;
    var cancelled = false;
    var generation = 0;

    void emit() {
      if (cancelled || controller.isClosed || !workerReady || !teamsReady) {
        return;
      }
      controller.add(appliedJobIds(
        uid: uid,
        workerApplications: workerApps,
        teamApplications: teamApps,
        teamIds: activeTeamIds,
      ));
    }

    void reportError(Object error, StackTrace stack) {
      if (!cancelled && !controller.isClosed) controller.addError(error, stack);
    }

    controller = StreamController<Set<String>>(
      onListen: () {
        workerSub = db
            .collection('applications')
            .where('workerId', isEqualTo: uid)
            .snapshots()
            .listen((snapshot) {
          workerApps = snapshot.docs.map((doc) => doc.data()).toList();
          workerReady = true;
          emit();
        }, onError: reportError);

        teamsSub = db.collection('teams').snapshots().listen((snapshot) async {
          final teams = {for (final doc in snapshot.docs) doc.id: doc.data()};
          final ids = teamIdsForWorker(uid, teams);
          if (setEquals(ids, activeTeamIds) && teamsReady) return;

          final currentGeneration = ++generation;
          teamsReady = false;
          activeTeamIds = ids;
          final oldSubs = teamSubs.values.toList();
          teamSubs.clear();
          teamApps.clear();
          await Future.wait(oldSubs.map((sub) => sub.cancel()));
          if (cancelled || currentGeneration != generation) return;
          if (ids.isEmpty) {
            teamsReady = true;
            emit();
            return;
          }

          final received = <String>{};
          for (final teamId in ids) {
            teamSubs[teamId] = db
                .collection('applications')
                .where('teamId', isEqualTo: teamId)
                .snapshots()
                .listen((applicationSnapshot) {
              if (cancelled || currentGeneration != generation) return;
              teamApps[teamId] =
                  applicationSnapshot.docs.map((doc) => doc.data()).toList();
              received.add(teamId);
              teamsReady = received.length == ids.length;
              emit();
            }, onError: reportError);
          }
        }, onError: reportError);
      },
      onCancel: () async {
        cancelled = true;
        generation++;
        await workerSub?.cancel();
        await teamsSub?.cancel();
        await Future.wait(teamSubs.values.map((sub) => sub.cancel()));
      },
    );
    return controller.stream;
  }
}
