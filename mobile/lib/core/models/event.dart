class SchoolEvent {
  final String id;
  final String title;
  final String? description;
  final String eventType;
  final DateTime startDate;
  final DateTime? endDate;
  final bool allDay;
  final String? location;

  const SchoolEvent({
    required this.id,
    required this.title,
    this.description,
    required this.eventType,
    required this.startDate,
    this.endDate,
    required this.allDay,
    this.location,
  });

  factory SchoolEvent.fromJson(Map<String, dynamic> json) {
    return SchoolEvent(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString(),
      eventType: json['event_type']?.toString() ?? json['type']?.toString() ?? 'general',
      startDate: json['start_date'] != null
          ? DateTime.tryParse(json['start_date'].toString()) ?? DateTime.now()
          : DateTime.now(),
      endDate: json['end_date'] != null
          ? DateTime.tryParse(json['end_date'].toString())
          : null,
      allDay: json['all_day'] as bool? ?? json['is_all_day'] as bool? ?? false,
      location: json['location']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'event_type': eventType,
        'start_date': startDate.toIso8601String(),
        'end_date': endDate?.toIso8601String(),
        'all_day': allDay,
        'location': location,
      };
}
