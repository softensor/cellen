class Employee {
  final String id;
  final String schoolId;
  final String firstName;
  final String? middleName;
  final String lastName;
  final String employeeType; // teacher, staff, admin
  final String? position;
  final String? cedula;
  final String? phone;
  final String? email;
  final String? photoUrl;
  final DateTime? hireDate;
  final bool isActive;
  final String? userId;

  const Employee({
    required this.id,
    required this.schoolId,
    required this.firstName,
    this.middleName,
    required this.lastName,
    required this.employeeType,
    this.position,
    this.cedula,
    this.phone,
    this.email,
    this.photoUrl,
    this.hireDate,
    required this.isActive,
    this.userId,
  });

  String get fullName =>
      [firstName, middleName, lastName].whereType<String>().join(' ');

  String get employeeTypeLabel {
    switch (employeeType) {
      case 'teacher':
        return 'Educador(a)';
      case 'staff':
        return 'Auxiliar';
      case 'admin':
        return 'Administração';
      default:
        return employeeType;
    }
  }

  factory Employee.fromJson(Map<String, dynamic> json) {
    return Employee(
      id: json['id']?.toString() ?? '',
      schoolId: json['school_id']?.toString() ?? '',
      firstName: json['first_name'] as String? ?? '',
      middleName: json['middle_name'] as String?,
      lastName: json['last_name'] as String? ?? '',
      employeeType: json['employee_type'] as String? ?? 'staff',
      position: json['position'] as String?,
      cedula: json['cedula'] as String?,
      phone: json['phone'] as String?,
      email: json['email'] as String?,
      photoUrl: json['photo_url'] as String?,
      hireDate: json['hire_date'] != null
          ? DateTime.tryParse(json['hire_date'] as String)
          : null,
      isActive: json['is_active'] as bool? ?? true,
      userId: json['user_id']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'school_id': schoolId,
        'first_name': firstName,
        if (middleName != null) 'middle_name': middleName,
        'last_name': lastName,
        'employee_type': employeeType,
        if (position != null) 'position': position,
        if (cedula != null) 'cedula': cedula,
        if (phone != null) 'phone': phone,
        if (email != null) 'email': email,
        if (photoUrl != null) 'photo_url': photoUrl,
        if (hireDate != null)
          'hire_date':
              '${hireDate!.year.toString().padLeft(4, '0')}-${hireDate!.month.toString().padLeft(2, '0')}-${hireDate!.day.toString().padLeft(2, '0')}',
        'is_active': isActive,
        if (userId != null) 'user_id': userId,
      };
}
