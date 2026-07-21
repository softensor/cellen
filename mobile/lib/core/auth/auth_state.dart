// ---------------------------------------------------------------------------
// UserRole enum — all roles the system supports
// ---------------------------------------------------------------------------

enum UserRole {
  platformAdmin,   // platform owner — cross-school
  schoolAdmin,     // full school management
  coordinator,     // academic coordination — no finance, no user mgmt
  financeOfficer,  // finance module only
  secretary,       // read + comms — enrollment lookup, no create/delete
  teacher,         // classroom: attendance, grades, caderneta
  nurse,           // health events + immunizations only
  parent,          // their children only
  student,         // own boletim/timetable (secondary only)
}

// ---------------------------------------------------------------------------
// Role ↔ String conversion
// ---------------------------------------------------------------------------

UserRole? _roleFromString(String? s) {
  switch (s) {
    case 'platform_admin':  return UserRole.platformAdmin;
    case 'school_admin':    return UserRole.schoolAdmin;
    case 'coordinator':     return UserRole.coordinator;
    case 'finance_officer': return UserRole.financeOfficer;
    case 'secretary':       return UserRole.secretary;
    case 'teacher':         return UserRole.teacher;
    case 'nurse':           return UserRole.nurse;
    case 'parent':          return UserRole.parent;
    case 'student':         return UserRole.student;
    default:                return null;
  }
}

String? _roleToString(UserRole? role) {
  switch (role) {
    case UserRole.platformAdmin:  return 'platform_admin';
    case UserRole.schoolAdmin:    return 'school_admin';
    case UserRole.coordinator:    return 'coordinator';
    case UserRole.financeOfficer: return 'finance_officer';
    case UserRole.secretary:      return 'secretary';
    case UserRole.teacher:        return 'teacher';
    case UserRole.nurse:          return 'nurse';
    case UserRole.parent:         return 'parent';
    case UserRole.student:        return 'student';
    case null:                    return null;
  }
}

// ---------------------------------------------------------------------------
// Primary role priority (highest privilege wins for navigation)
// ---------------------------------------------------------------------------

const _rolePriority = [
  UserRole.platformAdmin,
  UserRole.schoolAdmin,
  UserRole.coordinator,
  UserRole.financeOfficer,
  UserRole.secretary,
  UserRole.teacher,
  UserRole.nurse,
  UserRole.parent,
  UserRole.student,
];

UserRole? _primaryRole(Set<UserRole> roles) {
  for (final r in _rolePriority) {
    if (roles.contains(r)) return r;
  }
  return null;
}

String _rolesHomeRoute(Set<UserRole> roles) {
  return switch (_primaryRole(roles)) {
    UserRole.platformAdmin  => '/platform',
    UserRole.schoolAdmin    => '/admin',
    UserRole.coordinator    => '/admin',
    UserRole.financeOfficer => '/admin/finance',
    UserRole.secretary      => '/admin/people',
    UserRole.teacher        => '/teacher',
    UserRole.nurse          => '/health',
    UserRole.parent         => '/parent',
    UserRole.student        => '/parent/grades',
    null                    => '/login',
  };
}

// ---------------------------------------------------------------------------
// AuthState
// ---------------------------------------------------------------------------

class AuthState {
  final bool isAuthenticated;
  final bool isLoading;
  final String? accessToken;
  final String? refreshToken;
  final Set<UserRole> roles;
  final String? userId;
  final String? schoolId;
  final String? username;
  final String? employeeId;
  final String? guardianId;
  final String? error;

  const AuthState({
    required this.isAuthenticated,
    required this.isLoading,
    this.accessToken,
    this.refreshToken,
    this.roles = const {},
    this.userId,
    this.schoolId,
    this.username,
    this.employeeId,
    this.guardianId,
    this.error,
  });

  const AuthState.initial()
      : isAuthenticated = false,
        isLoading = false,
        accessToken = null,
        refreshToken = null,
        roles = const {},
        userId = null,
        schoolId = null,
        username = null,
        employeeId = null,
        guardianId = null,
        error = null;

  const AuthState.loading()
      : isAuthenticated = false,
        isLoading = true,
        accessToken = null,
        refreshToken = null,
        roles = const {},
        userId = null,
        schoolId = null,
        username = null,
        employeeId = null,
        guardianId = null,
        error = null;

  AuthState.error(String message)
      : isAuthenticated = false,
        isLoading = false,
        accessToken = null,
        refreshToken = null,
        roles = const {},
        userId = null,
        schoolId = null,
        username = null,
        employeeId = null,
        guardianId = null,
        error = message;

  // ── Role checks ──────────────────────────────────────────────────────────

  bool hasRole(UserRole r) => roles.contains(r);

  bool hasAnyRole(Iterable<UserRole> check) => check.any(roles.contains);

  /// Primary role (highest privilege) — used for navigation and display.
  UserRole? get primaryRole => _primaryRole(roles);

  /// Compat getter — equivalent to primaryRole.
  UserRole? get role => primaryRole;

  /// Home route based on primary role.
  String get homeRoute => _rolesHomeRoute(roles);

  // ── Convenience booleans ─────────────────────────────────────────────────

  bool get isAdmin => hasAnyRole([UserRole.schoolAdmin, UserRole.platformAdmin]);
  bool get canManageFinance =>
      hasAnyRole([UserRole.schoolAdmin, UserRole.financeOfficer]);
  bool get canManageAcademic =>
      hasAnyRole([UserRole.schoolAdmin, UserRole.coordinator]);
  bool get isTeacherRole =>
      hasAnyRole([UserRole.teacher, UserRole.coordinator, UserRole.schoolAdmin]);
  bool get isParent => hasRole(UserRole.parent);
  bool get isSchoolStaff => hasAnyRole([
        UserRole.schoolAdmin,
        UserRole.coordinator,
        UserRole.financeOfficer,
        UserRole.secretary,
        UserRole.teacher,
        UserRole.nurse,
      ]);

  /// Compat: true if user has the teacher role specifically.
  bool get isTeacher => hasRole(UserRole.teacher);

  /// Compat: true for any school staff (replaces old staff-role check).
  bool get isStaff => isSchoolStaff;

  // ── copyWith ─────────────────────────────────────────────────────────────

  AuthState copyWith({
    bool? isAuthenticated,
    bool? isLoading,
    String? accessToken,
    String? refreshToken,
    Set<UserRole>? roles,
    String? userId,
    String? schoolId,
    String? username,
    String? employeeId,
    String? guardianId,
    String? error,
  }) {
    return AuthState(
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      isLoading: isLoading ?? this.isLoading,
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
      roles: roles ?? this.roles,
      userId: userId ?? this.userId,
      schoolId: schoolId ?? this.schoolId,
      username: username ?? this.username,
      employeeId: employeeId ?? this.employeeId,
      guardianId: guardianId ?? this.guardianId,
      error: error,
    );
  }

  // ── Static helpers (used externally) ─────────────────────────────────────

  static UserRole? roleFromString(String? s) => _roleFromString(s);

  static String? roleToString(UserRole? role) => _roleToString(role);

  // Kept for backward compat with auth_service storage key migration
  static String roleStorageKey(UserRole? role) => _roleToString(role) ?? '';
}
