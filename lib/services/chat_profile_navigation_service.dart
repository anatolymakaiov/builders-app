import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../screens/employer_profile_screen.dart';
import '../screens/team_details_screen.dart';
import '../screens/worker_profile_screen.dart';

class ChatProfileNavigationService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static Future<void> openFromChat(
    BuildContext context, {
    required Map<String, dynamic> chatData,
    required String currentUserId,
    bool preferTeamTarget = false,
  }) async {
    final target = _resolveTarget(
      chatData,
      currentUserId: currentUserId,
      preferTeamTarget: preferTeamTarget,
    );

    if (target == null) {
      _showUnavailable(context);
      return;
    }

    if (target.type == _ChatProfileTargetType.team) {
      await _openTeam(context, target.id);
      return;
    }

    await _openUser(context, target.id, roleHint: target.roleHint);
  }

  static _ChatProfileTarget? _resolveTarget(
    Map<String, dynamic> data, {
    required String currentUserId,
    required bool preferTeamTarget,
  }) {
    final type = _text(data["type"] ?? data["chatType"]).toLowerCase();
    final teamId = _text(data["teamId"]);
    final workerId = _text(data["workerId"]);
    final employerId = _text(data["employerId"] ?? data["companyId"]);
    final targetProfileId = _text(data["targetProfileId"]);
    final targetRole = _text(data["targetRole"]);

    if (type == "internal_team" && teamId.isNotEmpty) {
      return _ChatProfileTarget.team(teamId);
    }

    if (preferTeamTarget && teamId.isNotEmpty) {
      return _ChatProfileTarget.team(teamId);
    }

    if (workerId == currentUserId && employerId.isNotEmpty) {
      return _ChatProfileTarget.user(employerId, roleHint: "employer");
    }

    if (employerId == currentUserId) {
      if (teamId.isNotEmpty) return _ChatProfileTarget.team(teamId);
      if (workerId.isNotEmpty) {
        return _ChatProfileTarget.user(workerId, roleHint: "worker");
      }
    }

    if (targetProfileId.isNotEmpty && targetProfileId != currentUserId) {
      return _ChatProfileTarget.user(targetProfileId, roleHint: targetRole);
    }

    for (final key in const ["participantIds", "participants", "members"]) {
      final ids = _ids(data[key]);
      for (final id in ids) {
        if (id != currentUserId) return _ChatProfileTarget.user(id);
      }
    }

    return null;
  }

  static Future<void> _openUser(
    BuildContext context,
    String userId, {
    String roleHint = "",
  }) async {
    final snapshot = await _firestore.collection("users").doc(userId).get();
    if (!context.mounted) return;
    if (!snapshot.exists || _isInactive(snapshot.data())) {
      _showUnavailable(context);
      return;
    }

    final data = snapshot.data() ?? {};
    final role =
        _text(data["role"]).isNotEmpty ? _text(data["role"]) : roleHint;
    final isEmployer = role == "employer" || role == "company";

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => isEmployer
            ? EmployerProfileScreen(userId: userId, showBackButton: true)
            : WorkerProfileScreen(userId: userId),
      ),
    );
  }

  static Future<void> _openTeam(BuildContext context, String teamId) async {
    final snapshot = await _firestore.collection("teams").doc(teamId).get();
    if (!context.mounted) return;
    if (!snapshot.exists || _isInactive(snapshot.data())) {
      _showUnavailable(context);
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TeamDetailsScreen(
          teamId: teamId,
          teamData: snapshot.data() ?? {},
          showInternalChat: false,
        ),
      ),
    );
  }

  static bool _isInactive(Map<String, dynamic>? data) {
    if (data == null) return true;
    final status = _text(data["status"]).toLowerCase();
    final active = data["active"];
    return data["deleted"] == true ||
        data["accountDeleted"] == true ||
        data["anonymised"] == true ||
        data["companyDeleted"] == true ||
        status == "deleted" ||
        status == "inactive" ||
        active == false;
  }

  static List<String> _ids(dynamic value) {
    if (value is! List) return const [];
    return value
        .map((item) => item.toString())
        .where((id) => id.isNotEmpty)
        .toList();
  }

  static String _text(dynamic value) => value?.toString().trim() ?? "";

  static void _showUnavailable(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("This profile is no longer available.")),
    );
  }
}

enum _ChatProfileTargetType { user, team }

class _ChatProfileTarget {
  final _ChatProfileTargetType type;
  final String id;
  final String roleHint;

  const _ChatProfileTarget._(this.type, this.id, this.roleHint);

  factory _ChatProfileTarget.user(String id, {String roleHint = ""}) {
    return _ChatProfileTarget._(_ChatProfileTargetType.user, id, roleHint);
  }

  factory _ChatProfileTarget.team(String id) {
    return _ChatProfileTarget._(_ChatProfileTargetType.team, id, "");
  }
}
