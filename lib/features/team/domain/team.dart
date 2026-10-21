/// A member of the organization, from `GET /api/v1/team`.
class TeamMember {
  const TeamMember({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.joinedAt,
  });

  final String id;
  final String name;
  final String email;
  final String role;
  final DateTime? joinedAt;

  factory TeamMember.fromJson(Map<String, dynamic> json) => TeamMember(
        id: json['id'] as String,
        name: json['name'] as String,
        email: json['email'] as String,
        role: json['role'] as String,
        joinedAt: DateTime.tryParse(json['joinedAt'] as String? ?? ''),
      );
}

/// An invitation that hasn't been accepted, revoked or expired yet.
class PendingInvitation {
  const PendingInvitation({
    required this.id,
    required this.email,
    required this.role,
    this.expiresAt,
  });

  final String id;
  final String email;
  final String role;
  final DateTime? expiresAt;

  factory PendingInvitation.fromJson(Map<String, dynamic> json) => PendingInvitation(
        id: json['id'] as String,
        email: json['email'] as String,
        role: json['role'] as String,
        expiresAt: DateTime.tryParse(json['expiresAt'] as String? ?? ''),
      );
}

/// Everything the Team step needs in one read: who is in, who is invited,
/// which roles this person may hand out, and seat use against the plan.
class TeamOverview {
  const TeamOverview({
    required this.members,
    required this.invitations,
    required this.assignableRoles,
    required this.seatsUsed,
    this.seatLimit,
  });

  final List<TeamMember> members;
  final List<PendingInvitation> invitations;
  final List<String> assignableRoles;

  /// Members plus pending invitations — what the plan's team limit counts.
  final int seatsUsed;

  /// `null` when the plan doesn't cap team size.
  final int? seatLimit;

  bool get isFull => seatLimit != null && seatsUsed >= seatLimit!;

  factory TeamOverview.fromJson(Map<String, dynamic> json) {
    final seats = json['seats'] as Map<String, dynamic>? ?? const {};
    return TeamOverview(
      members: [
        for (final row in (json['members'] as List<dynamic>? ?? const []))
          TeamMember.fromJson(row as Map<String, dynamic>),
      ],
      invitations: [
        for (final row in (json['invitations'] as List<dynamic>? ?? const []))
          PendingInvitation.fromJson(row as Map<String, dynamic>),
      ],
      assignableRoles: [
        for (final role in (json['assignableRoles'] as List<dynamic>? ?? const [])) role as String,
      ],
      seatsUsed: seats['used'] as int? ?? 0,
      seatLimit: seats['limit'] as int?,
    );
  }
}
