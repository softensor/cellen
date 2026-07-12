enum UserRole { platformAdmin, schoolAdmin, teacher, staff, parent }

UserRole? _roleFromString(String? s) {
  switch (s) {
    case 'platform_admin':
      return UserRole.platformAdmin;
    case 'school_admin':
      return UserRole.schoolAdmin;
    case 'teacher':
      return UserRole.teacher;
    case 'staff':
      return UserRole.staff;
    case 'parent':
      return UserRole.parent;
    default:
      return null;
  }
}

String? _roleToString(UserRole? role) {
  switch (role) {
    case UserRole.platformAdmin:
      return 'platform_admin';
    case UserRole.schoolAdmin:
      return 'school_admin';
    case UserRole.teacher:
      return 'teacher';
    case UserRole.staff:
      return 'staff';
    case UserRole.parent:
      return 'parent';
    case null:
      return null;
  }
}

class AuthState {
  final bool isAuthenticated;
  final bool isLoading;
  final String? accessToken;
  final String? refreshToken;
  final UserRole? role;
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
    this.role,
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
        role = null,
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
        role = null,
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
        role = null,
        userId = null,
        schoolId = null,
        username = null,
        employeeId = null,
        guardianId = null,
        error = message;

  AuthState copyWith({
    bool? isAuthenticated,
    bool? isLoading,
    String? accessToken,
    String? refreshToken,
    UserRole? role,
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
      role: role ?? this.role,
      userId: userId ?? this.userId,
      schoolId: schoolId ?? this.schoolId,
      username: username ?? this.username,
      employeeId: employeeId ?? this.employeeId,
      guardianId: guardianId ?? this.guardianId,
      error: error,
    );
  }

  bool get isAdmin =>
      role == UserRole.schoolAdmin || role == UserRole.platformAdmin;
  bool get isTeacher => role == UserRole.teacher;
  bool get isParent => role == UserRole.parent;
  bool get isStaff => role == UserRole.staff;

  String get roleStorageString => _roleToString(role) ?? '';
  static UserRole? roleFromString(String? s) => _roleFromString(s);
  static String roleToStorageString(UserRole? role) =>
      _roleToString(role) ?? '';
}
