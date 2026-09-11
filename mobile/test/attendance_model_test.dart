import 'package:cellen/core/models/attendance.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reads counters from the nested attendance summary returned by API', () {
    final summary = AttendanceSummary.fromJson({
      'records': [
        {
          'child_id': 'child-1',
          'first_name': 'Ana',
          'last_name': 'Silva',
          'status': 'unrecorded',
        }
      ],
      'summary': {
        'total_enrolled': 7,
        'checked_in': 3,
        'checked_out': 1,
        'absent': 1,
        'unrecorded': 2,
      },
    });

    expect(summary.totalEnrolled, 7);
    expect(summary.checkedIn, 3);
    expect(summary.checkedOut, 1);
    expect(summary.absent, 1);
    expect(summary.unrecorded, 2);
    expect(summary.records.single.childName, 'Ana Silva');
  });
}
