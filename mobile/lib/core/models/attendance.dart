class AttendanceRecord {
  final String id;
  final String childId;
  final String childName;
  final String? childPhotoUrl;
  final String status; // present/absent/late/excused
  final String? checkInTime;
  final String? checkOutTime;
  final String? notes;

  const AttendanceRecord({
    required this.id,
    required this.childId,
    required this.childName,
    this.childPhotoUrl,
    required this.status,
    this.checkInTime,
    this.checkOutTime,
    this.notes,
  });

  factory AttendanceRecord.fromJson(Map<String, dynamic> json) {
    return AttendanceRecord(
      id: json['id']?.toString() ?? '',
      childId: json['child_id']?.toString() ?? json['child']?.toString() ?? '',
      childName: json['child_name']?.toString() ?? json['child_full_name']?.toString() ?? '',
      childPhotoUrl: json['child_photo_url']?.toString() ?? json['child_photo']?.toString(),
      status: json['status']?.toString() ?? 'absent',
      checkInTime: json['check_in_time']?.toString() ?? json['checkin_time']?.toString(),
      checkOutTime: json['check_out_time']?.toString() ?? json['checkout_time']?.toString(),
      notes: json['notes']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'child_id': childId,
        'child_name': childName,
        'child_photo_url': childPhotoUrl,
        'status': status,
        'check_in_time': checkInTime,
        'check_out_time': checkOutTime,
        'notes': notes,
      };
}

class AttendanceSummary {
  final int totalEnrolled;
  final int checkedIn;
  final int checkedOut;
  final int absent;
  final List<AttendanceRecord> records;

  const AttendanceSummary({
    required this.totalEnrolled,
    required this.checkedIn,
    required this.checkedOut,
    required this.absent,
    required this.records,
  });

  factory AttendanceSummary.fromJson(Map<String, dynamic> json) {
    final rawRecords = json['records'] as List<dynamic>? ?? [];
    return AttendanceSummary(
      totalEnrolled: json['total_enrolled'] as int? ?? rawRecords.length,
      checkedIn: json['checked_in'] as int? ?? 0,
      checkedOut: json['checked_out'] as int? ?? 0,
      absent: json['absent'] as int? ?? 0,
      records: rawRecords
          .map((e) => AttendanceRecord.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
