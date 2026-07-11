class Child {
  final String id;
  final String schoolId;
  final String cedula;
  final String firstName;
  final String? middleName;
  final String lastName;
  final DateTime? birthDate;
  final String? sex;
  final String? specialNeeds;
  final String? medicalPrescription;
  final String? photoUrl;
  final bool isActive;
  final String? turmaId;
  final String? turmaName;
  final String? address;
  final String? addressCity;
  final String? addressPostalCode;

  const Child({
    required this.id,
    required this.schoolId,
    required this.cedula,
    required this.firstName,
    this.middleName,
    required this.lastName,
    this.birthDate,
    this.sex,
    this.specialNeeds,
    this.medicalPrescription,
    this.photoUrl,
    required this.isActive,
    this.turmaId,
    this.turmaName,
    this.address,
    this.addressCity,
    this.addressPostalCode,
  });

  String get fullName =>
      [firstName, middleName, lastName].whereType<String>().join(' ');

  String get sexLabel => sex == 'M' ? 'Masculino' : sex == 'F' ? 'Feminino' : '';

  factory Child.fromJson(Map<String, dynamic> json) {
    return Child(
      id: json['id']?.toString() ?? '',
      schoolId: json['school_id']?.toString() ?? '',
      cedula: json['cedula'] as String? ?? '',
      firstName: json['first_name'] as String? ?? '',
      middleName: json['middle_name'] as String?,
      lastName: json['last_name'] as String? ?? '',
      birthDate: json['birth_date'] != null
          ? DateTime.tryParse(json['birth_date'] as String)
          : null,
      sex: json['sex'] as String?,
      specialNeeds: json['special_needs'] as String?,
      medicalPrescription: json['medical_prescription'] as String?,
      photoUrl: json['photo_url'] as String?,
      isActive: json['is_active'] as bool? ?? true,
      turmaId: json['turma_id']?.toString(),
      turmaName: json['turma_name'] as String?,
      address: json['address'] as String?,
      addressCity: json['address_city'] as String?,
      addressPostalCode: json['address_postal_code'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'school_id': schoolId,
        'cedula': cedula,
        'first_name': firstName,
        if (middleName != null) 'middle_name': middleName,
        'last_name': lastName,
        if (birthDate != null)
          'birth_date':
              '${birthDate!.year.toString().padLeft(4, '0')}-${birthDate!.month.toString().padLeft(2, '0')}-${birthDate!.day.toString().padLeft(2, '0')}',
        if (sex != null) 'sex': sex,
        if (specialNeeds != null) 'special_needs': specialNeeds,
        if (medicalPrescription != null)
          'medical_prescription': medicalPrescription,
        if (photoUrl != null) 'photo_url': photoUrl,
        'is_active': isActive,
        if (turmaId != null) 'turma_id': turmaId,
        if (address != null) 'address': address,
        if (addressCity != null) 'address_city': addressCity,
        if (addressPostalCode != null) 'address_postal_code': addressPostalCode,
      };
}
