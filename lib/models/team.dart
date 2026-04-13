class Team {
  final String id;
  final String name;
  final String leaderId;
  final List<String> memberIds;

  Team({
    required this.id,
    required this.name,
    required this.leaderId,
    required this.memberIds,
  });

  factory Team.fromMap(Map<String, dynamic> map, String id) {
    return Team(
      id: id,
      name: map['name'] ?? '',
      leaderId: map['leaderId'] ?? '',
      memberIds: List<String>.from(map['memberIds'] ?? []),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'leaderId': leaderId,
      'memberIds': memberIds,
    };
  }
}