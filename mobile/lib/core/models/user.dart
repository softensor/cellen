class User {
  final String id;
  final String username;
  final String? firstName;
  final String? lastName;
  final String? email;
  final String? role;
  final String? schoolId;
  final bool isActive;

  const User({
    required this.id,
    required this.username,
    this.firstName,
    this.lastName,
    this.email,
    this.role,
    this.schoolId,
    required this.isActive,
  });

  String get fullName {
    final parts = [firstName, lastName].whereType<String>().toList();
    return parts.isNotEmpty ? parts.join(' ') : username;
  }

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id']?.toString() ?? '',
      username: json['username'] as String? ?? '',
      firstName: json['first_name'] as String?,
      lastName: json['last_name'] as String?,
      email: json['email'] as String?,
      role: json['role'] as String?,
      schoolId: json['school_id']?.toString(),
      isActive: json['is_active'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        if (firstName != null) 'first_name': firstName,
        if (lastName != null) 'last_name': lastName,
        if (email != null) 'email': email,
        if (role != null) 'role': role,
        if (schoolId != null) 'school_id': schoolId,
        'is_active': isActive,
      };
}
