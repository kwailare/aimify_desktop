/// Domain models for the `/api/v1/me` response. Field shapes are the exact
/// contract documented in `docs/desktop-api.md` — REAL, wired to the network,
/// not mock data.
class AuthUser {
  const AuthUser({
    required this.id,
    required this.name,
    required this.email,
    this.phone,
  });

  final String id;
  final String name;
  final String email;
  final String? phone;

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
        id: json['id'] as String,
        name: json['name'] as String,
        email: json['email'] as String,
        phone: json['phone'] as String?,
      );
}

class Organization {
  const Organization({
    required this.id,
    required this.name,
    required this.industry,
    required this.currency,
    required this.warehouseName,
    required this.subscriptionStatus,
    this.trialEndsAt,
  });

  final String id;
  final String name;
  final String industry;
  final String currency;
  final String warehouseName;
  final String subscriptionStatus;
  final DateTime? trialEndsAt;

  factory Organization.fromJson(Map<String, dynamic> json) => Organization(
        id: json['id'] as String,
        name: json['name'] as String,
        industry: json['industry'] as String,
        currency: json['currency'] as String,
        warehouseName: json['warehouseName'] as String,
        subscriptionStatus: json['subscriptionStatus'] as String,
        trialEndsAt: json['trialEndsAt'] == null
            ? null
            : DateTime.tryParse(json['trialEndsAt'] as String),
      );
}

/// The full `/api/v1/me` payload. [organization] and [role] are null when
/// the signed-in user hasn't finished onboarding on aimify-web yet — that is
/// a normal, expected state, not an error.
class MeResponse {
  const MeResponse({
    required this.user,
    required this.organization,
    required this.role,
  });

  final AuthUser user;
  final Organization? organization;
  final String? role;

  bool get hasCompletedOnboarding => organization != null && role != null;

  factory MeResponse.fromJson(Map<String, dynamic> json) => MeResponse(
        user: AuthUser.fromJson(json['user'] as Map<String, dynamic>),
        organization: json['organization'] == null
            ? null
            : Organization.fromJson(
                json['organization'] as Map<String, dynamic>,
              ),
        role: json['role'] as String?,
      );
}
