class Employee {
  final String id;
  final String schoolId;
  final String firstName;
  final String? middleName;
  final String lastName;
  final String employeeType; // teacher, staff, admin (HR category)
  final List<String> roles; // actual system roles from User.roles
  final String? position;
  final String? cedula;
  final String? taxId;
  final String? socialSecurity;
  final String? contractType;
  final double? salary;
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
    this.roles = const [],
    this.position,
    this.cedula,
    this.taxId,
    this.socialSecurity,
    this.contractType,
    this.salary,
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
        return 'Professor / Educador';
      case 'staff':
        return 'Funcionário';
      case 'admin':
        return 'Administrador';
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
      roles: (json['roles'] as List?)?.map((e) => e.toString()).toList() ?? [],
      position: json['position'] as String?,
      cedula: json['id_card_number'] as String?,
      taxId: json['tax_id'] as String?,
      socialSecurity: json['social_security'] as String?,
      contractType: json['contract_type'] as String?,
      salary: (json['salary'] as num?)?.toDouble(),
      phone: json['mobile_first'] as String?,
      email: json['email'] as String?,
      photoUrl: json['photo_url'] as String?,
      hireDate: json['hire_date'] != null
          ? DateTime.tryParse(json['hire_date'] as String)
          : null,
      isActive: (json['status'] as String? ?? 'active') == 'active',
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
        if (cedula != null) 'id_card_number': cedula,
        if (taxId != null) 'tax_id': taxId,
        if (socialSecurity != null) 'social_security': socialSecurity,
        if (contractType != null) 'contract_type': contractType,
        if (salary != null) 'salary': salary,
        if (phone != null) 'mobile_first': phone,
        if (email != null) 'email': email,
        if (photoUrl != null) 'photo_url': photoUrl,
        if (hireDate != null)
          'hire_date':
              '${hireDate!.year.toString().padLeft(4, '0')}-${hireDate!.month.toString().padLeft(2, '0')}-${hireDate!.day.toString().padLeft(2, '0')}',
        'status': isActive ? 'active' : 'inactive',
        if (userId != null) 'user_id': userId,
      };
}
