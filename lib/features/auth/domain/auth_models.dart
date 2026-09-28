/// Domain models for the `/api/v1/me` response. Field shapes are the exact
/// contract documented in `docs/desktop-api.md` — REAL, wired to the network,
/// not mock data.
class AuthUser {
  const AuthUser({
    required this.id,
    required this.name,
    required this.email,
    this.phone,
    this.emailVerified = true,
  });

  final String id;
  final String name;
  final String email;
  final String? phone;

  /// `false` until the person confirms the link emailed to them at sign-up.
  /// Accounts that existed before email confirmation was introduced are
  /// treated as confirmed by the server, so this defaults to `true` for any
  /// payload that omits it.
  final bool emailVerified;

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
        id: json['id'] as String,
        name: json['name'] as String,
        email: json['email'] as String,
        phone: json['phone'] as String?,
        emailVerified: json['emailVerified'] as bool? ?? true,
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
    this.logoUrl,
    this.registrationNumber,
    this.address,
    this.phone,
    this.email,
    this.taxName,
    this.taxRate = 0,
    this.timezone,
    this.dateFormat,
    this.currentPeriodEnd,
    this.cancelAtPeriodEnd = false,
  });

  final String id;
  final String name;
  final String industry;
  final String currency;

  /// `null` until the organization has at least one warehouse — a brand-new
  /// trial org has none yet, so this is a normal, common state to see on
  /// `/me`, not a data error.
  final String? warehouseName;
  final String subscriptionStatus;
  final DateTime? trialEndsAt;

  /// Public image URL, or `null` if the owner hasn't uploaded a logo on the
  /// website. Can be shown directly (app header, printed receipts).
  final String? logoUrl;

  /// `null` until the owner fills these in on the website.
  final String? registrationNumber;
  final String? address;
  final String? phone;
  final String? email;
  final String? taxName;

  /// Defaults to `0` until the owner sets a rate on the website.
  final double taxRate;

  /// e.g. `"Africa/Lagos"`. The organization's preference for displaying
  /// dates/times in the desktop app.
  final String? timezone;

  /// e.g. `"DD/MM/YYYY"`. See `shared/utils/formatters.dart` for how this is
  /// turned into an `intl` pattern.
  final String? dateFormat;

  /// Set once the organization has paid at least once (via Paystack on the
  /// website) — the date the current paid period ends. `null` for an org
  /// that has never paid (still on trial, or `pending`).
  final DateTime? currentPeriodEnd;

  /// True when the owner has cancelled but the paid period hasn't ended yet.
  /// Access and [subscriptionStatus] stay completely normal until
  /// [currentPeriodEnd] passes — this is purely informational until then.
  final bool cancelAtPeriodEnd;

  factory Organization.fromJson(Map<String, dynamic> json) => Organization(
        id: json['id'] as String,
        name: json['name'] as String,
        industry: json['industry'] as String,
        currency: json['currency'] as String,
        warehouseName: json['warehouseName'] as String?,
        subscriptionStatus: json['subscriptionStatus'] as String,
        trialEndsAt: json['trialEndsAt'] == null
            ? null
            : DateTime.tryParse(json['trialEndsAt'] as String),
        logoUrl: json['logoUrl'] as String?,
        registrationNumber: json['registrationNumber'] as String?,
        address: json['address'] as String?,
        phone: json['phone'] as String?,
        email: json['email'] as String?,
        taxName: json['taxName'] as String?,
        taxRate: (json['taxRate'] as num?)?.toDouble() ?? 0,
        timezone: json['timezone'] as String?,
        dateFormat: json['dateFormat'] as String?,
        currentPeriodEnd: json['currentPeriodEnd'] == null
            ? null
            : DateTime.tryParse(json['currentPeriodEnd'] as String),
        cancelAtPeriodEnd: json['cancelAtPeriodEnd'] as bool? ?? false,
      );

  /// One of `pending`, `trial`, `active`, `past_due`, `expired`, `cancelled`,
  /// `suspended`. Only `trial`/`active`/`past_due` unlock the API — see
  /// `SubscriptionStatusX.isLocked` below.
  bool get isTrial => subscriptionStatus == 'trial';
  bool get isPastDue => subscriptionStatus == 'past_due';

  /// True for `pending`, `expired`, `cancelled`, `suspended` — the desktop
  /// app should show the locked screen instead of the normal app shell.
  bool get isLocked => !const {'trial', 'active', 'past_due'}.contains(subscriptionStatus);
}

/// A plan's caps on team members, active warehouses and active products,
/// plus the organization's current usage against them. A `null` limit means
/// unlimited.
class PlanLimits {
  const PlanLimits({this.users, this.warehouses, this.products});

  final int? users;
  final int? warehouses;
  final int? products;

  factory PlanLimits.fromJson(Map<String, dynamic> json) => PlanLimits(
        users: json['users'] as int?,
        warehouses: json['warehouses'] as int?,
        products: json['products'] as int?,
      );
}

class PlanUsage {
  const PlanUsage({required this.users, required this.warehouses, required this.products});

  final int users;
  final int warehouses;
  final int products;

  factory PlanUsage.fromJson(Map<String, dynamic> json) => PlanUsage(
        users: json['users'] as int? ?? 0,
        warehouses: json['warehouses'] as int? ?? 0,
        products: json['products'] as int? ?? 0,
      );
}

class Plan {
  const Plan({required this.name, required this.limits, required this.usage});

  final String name;
  final PlanLimits limits;
  final PlanUsage usage;

  factory Plan.fromJson(Map<String, dynamic> json) => Plan(
        name: json['name'] as String,
        limits: PlanLimits.fromJson(json['limits'] as Map<String, dynamic>),
        usage: PlanUsage.fromJson(json['usage'] as Map<String, dynamic>),
      );

  /// True once usage has reached (or somehow exceeded) the cap for [key] —
  /// `null` limit means unlimited, so never at cap.
  bool isAtCap({required int? limit, required int used}) => limit != null && used >= limit;

  bool get warehousesAtCap => isAtCap(limit: limits.warehouses, used: usage.warehouses);
  bool get productsAtCap => isAtCap(limit: limits.products, used: usage.products);
  bool get usersAtCap => isAtCap(limit: limits.users, used: usage.users);
}

/// The full `/api/v1/me` payload. [organization] and [role] are null when
/// the signed-in user hasn't created an organization yet, OR when their
/// email isn't confirmed yet (check [AuthUser.emailVerified] first — it's
/// the more specific reason to show).
class MeResponse {
  const MeResponse({
    required this.user,
    required this.organization,
    required this.role,
    this.permissions = const [],
    this.plan,
  });

  final AuthUser user;
  final Organization? organization;
  final String? role;

  /// The signed-in role's permission keys (e.g. `products.write`) — see
  /// `auth/domain/permissions.dart` for the keys this app checks against.
  /// Reading is open to every role and isn't gated by a permission key.
  final List<String> permissions;

  final Plan? plan;

  bool get hasCompletedOnboarding => organization != null && role != null;

  bool hasPermission(String key) => permissions.contains(key);

  factory MeResponse.fromJson(Map<String, dynamic> json) => MeResponse(
        user: AuthUser.fromJson(json['user'] as Map<String, dynamic>),
        organization: json['organization'] == null
            ? null
            : Organization.fromJson(
                json['organization'] as Map<String, dynamic>,
              ),
        role: json['role'] as String?,
        permissions: (json['permissions'] as List<dynamic>?)?.cast<String>() ?? const [],
        plan: json['plan'] == null ? null : Plan.fromJson(json['plan'] as Map<String, dynamic>),
      );
}
