class Caderneta {
  final String id;
  final String childId;
  final String? childName;
  final String teacherId;
  final String? teacherName;
  final DateTime reportDate;
  final String? breakfastRating; // Bem, Muito Bem, Mal, Não Comeu
  final String? lunchRating;
  final String? snackRating;
  final String? physiologicalNeeds; // Normal, Mole, Duro
  final bool? hadNap;
  final String? sensorialMotorDevelopment;
  final String? intellectualDevelopment;
  final String? socialDevelopment;
  final String? affectiveDevelopment;
  final String? generalObservations;

  const Caderneta({
    required this.id,
    required this.childId,
    this.childName,
    required this.teacherId,
    this.teacherName,
    required this.reportDate,
    this.breakfastRating,
    this.lunchRating,
    this.snackRating,
    this.physiologicalNeeds,
    this.hadNap,
    this.sensorialMotorDevelopment,
    this.intellectualDevelopment,
    this.socialDevelopment,
    this.affectiveDevelopment,
    this.generalObservations,
  });

  factory Caderneta.fromJson(Map<String, dynamic> json) {
    return Caderneta(
      id: json['id']?.toString() ?? '',
      childId: json['child_id']?.toString() ?? '',
      childName: json['child_name'] as String?,
      teacherId: json['teacher_id']?.toString() ?? '',
      teacherName: json['teacher_name'] as String?,
      reportDate: json['report_date'] != null
          ? DateTime.tryParse(json['report_date'] as String) ?? DateTime.now()
          : DateTime.now(),
      breakfastRating: json['breakfast_rating'] as String?,
      lunchRating: json['lunch_rating'] as String?,
      snackRating: json['snack_rating'] as String?,
      physiologicalNeeds: json['physiological_needs'] as String?,
      hadNap: json['had_nap'] as bool?,
      sensorialMotorDevelopment:
          json['sensorial_motor_development'] as String?,
      intellectualDevelopment: json['intellectual_development'] as String?,
      socialDevelopment: json['social_development'] as String?,
      affectiveDevelopment: json['affective_development'] as String?,
      generalObservations: json['general_observations'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'child_id': childId,
        'teacher_id': teacherId,
        'report_date':
            '${reportDate.year.toString().padLeft(4, '0')}-${reportDate.month.toString().padLeft(2, '0')}-${reportDate.day.toString().padLeft(2, '0')}',
        if (breakfastRating != null) 'breakfast_rating': breakfastRating,
        if (lunchRating != null) 'lunch_rating': lunchRating,
        if (snackRating != null) 'snack_rating': snackRating,
        if (physiologicalNeeds != null)
          'physiological_needs': physiologicalNeeds,
        if (hadNap != null) 'had_nap': hadNap,
        if (sensorialMotorDevelopment != null)
          'sensorial_motor_development': sensorialMotorDevelopment,
        if (intellectualDevelopment != null)
          'intellectual_development': intellectualDevelopment,
        if (socialDevelopment != null) 'social_development': socialDevelopment,
        if (affectiveDevelopment != null)
          'affective_development': affectiveDevelopment,
        if (generalObservations != null)
          'general_observations': generalObservations,
      };
}
