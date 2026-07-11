class Guardian {
  final String id;
  final String childId;
  final String firstName;
  final String? middleName;
  final String lastName;
  final String relationship;
  final String? phone;
  final String? email;
  final String? cedula;
  final String? address;
  final bool isPrimary;
  final bool authorizedPickup;

  const Guardian({
    required this.id,
    required this.childId,
    required this.firstName,
    this.middleName,
    required this.lastName,
    required this.relationship,
    this.phone,
    this.email,
    this.cedula,
    this.address,
    required this.isPrimary,
    required this.authorizedPickup,
  });

  String get fullName =>
      [firstName, middleName, lastName].whereType<String>().join(' ');

  String get relationshipLabel {
    switch (relationship) {
      case 'mother':
        return 'Mãe';
      case 'father':
        return 'Pai';
      case 'grandparent':
        return 'Avó/Avô';
      case 'sibling':
        return 'Irmão/Irmã';
      case 'guardian':
        return 'Tutor(a)';
      default:
        return relationship;
    }
  }

  factory Guardian.fromJson(Map<String, dynamic> json) {
    return Guardian(
      id: json['id']?.toString() ?? '',
      childId: json['child_id']?.toString() ?? '',
      firstName: json['first_name'] as String? ?? '',
      middleName: json['middle_name'] as String?,
      lastName: json['last_name'] as String? ?? '',
      relationship: json['relationship'] as String? ?? '',
      phone: json['phone'] as String?,
      email: json['email'] as String?,
      cedula: json['cedula'] as String?,
      address: json['address'] as String?,
      isPrimary: json['is_primary'] as bool? ?? false,
      authorizedPickup: json['authorized_pickup'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'child_id': childId,
        'first_name': firstName,
        if (middleName != null) 'middle_name': middleName,
        'last_name': lastName,
        'relationship': relationship,
        if (phone != null) 'phone': phone,
        if (email != null) 'email': email,
        if (cedula != null) 'cedula': cedula,
        if (address != null) 'address': address,
        'is_primary': isPrimary,
        'authorized_pickup': authorizedPickup,
      };
}
