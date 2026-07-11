class Incident {
  final String id;
  final String childId;
  final String childName;
  final String severity; // minor/moderate/serious
  final String description;
  final String? actionTaken;
  final bool parentNotified;
  final String incidentDate;
  final String? incidentTime;

  const Incident({
    required this.id,
    required this.childId,
    required this.childName,
    required this.severity,
    required this.description,
    this.actionTaken,
    required this.parentNotified,
    required this.incidentDate,
    this.incidentTime,
  });

  factory Incident.fromJson(Map<String, dynamic> json) {
    return Incident(
      id: json['id']?.toString() ?? '',
      childId: json['child_id']?.toString() ?? json['child']?.toString() ?? '',
      childName: json['child_name']?.toString() ?? json['child_full_name']?.toString() ?? '',
      severity: json['severity']?.toString() ?? 'minor',
      description: json['description']?.toString() ?? '',
      actionTaken: json['action_taken']?.toString(),
      parentNotified: json['parent_notified'] as bool? ?? false,
      incidentDate: json['incident_date']?.toString() ?? json['date']?.toString() ?? '',
      incidentTime: json['incident_time']?.toString() ?? json['time']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'child_id': childId,
        'child_name': childName,
        'severity': severity,
        'description': description,
        'action_taken': actionTaken,
        'parent_notified': parentNotified,
        'incident_date': incidentDate,
        'incident_time': incidentTime,
      };
}
