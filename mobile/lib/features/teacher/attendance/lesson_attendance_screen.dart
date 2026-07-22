import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_client.dart';
import '../../../core/theme/app_theme.dart';

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

class TodaySession {
  final String scheduleId;
  final String turmaName;
  final String subjectId;
  final String subjectName;
  final String periodId;
  final String? periodName;
  final int? periodNumber;
  final String? slotTime;
  final bool attendanceTaken;
  final int studentCount;

  const TodaySession({
    required this.scheduleId,
    required this.turmaName,
    required this.subjectId,
    required this.subjectName,
    required this.periodId,
    this.periodName,
    this.periodNumber,
    this.slotTime,
    required this.attendanceTaken,
    required this.studentCount,
  });

  factory TodaySession.fromJson(Map<String, dynamic> j) => TodaySession(
        scheduleId: j['schedule_id'] as String,
        turmaName: j['turma_name'] as String? ?? '',
        subjectId: j['subject_id'] as String,
        subjectName: j['subject_name'] as String? ?? '',
        periodId: j['period_id'] as String,
        periodName: j['period_name'] as String?,
        periodNumber: j['period_number'] as int?,
        slotTime: j['slot_time'] as String?,
        attendanceTaken: j['attendance_taken'] as bool? ?? false,
        studentCount: j['student_count'] as int? ?? 0,
      );
}

class _Student {
  final String childId;
  final String childName;
  String status; // present | absent | late | justified
  String? notes;

  _Student({
    required this.childId,
    required this.childName,
    required this.status,
    this.notes,
  });

  factory _Student.fromJson(Map<String, dynamic> j) => _Student(
        childId: j['child_id'] as String,
        childName: j['child_name'] as String? ?? '',
        status: j['status'] as String? ?? 'present',
        notes: j['notes'] as String?,
      );
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

final sessionsForDateProvider =
    FutureProvider.autoDispose.family<List<TodaySession>, String>((ref, dateStr) async {
  final data = await ref.read(apiClientProvider).get('/lesson-attendance/today?date=$dateStr') as List;
  return data
      .map((e) => TodaySession.fromJson(e as Map<String, dynamic>))
      .toList();
});

final _sessionStudentsProvider = FutureProvider.autoDispose
    .family<List<_Student>, Map<String, String>>((ref, params) async {
  final q = [
    'schedule_id=${params['schedule_id']}',
    'subject_id=${params['subject_id']}',
    'date=${params['date']}',
    'period_id=${params['period_id']}',
  ].join('&');
  final data =
      await ref.read(apiClientProvider).get('/lesson-attendance/session?$q')
          as Map<String, dynamic>;
  final records = data['records'] as List? ?? [];
  return records
      .map((e) => _Student.fromJson(e as Map<String, dynamic>))
      .toList();
});

// ---------------------------------------------------------------------------
// Today Sessions Screen (entry point for teacher) — with week navigation
// ---------------------------------------------------------------------------

class LessonAttendanceTodayScreen extends ConsumerStatefulWidget {
  const LessonAttendanceTodayScreen({super.key});

  @override
  ConsumerState<LessonAttendanceTodayScreen> createState() =>
      _LessonAttendanceTodayScreenState();
}

class _LessonAttendanceTodayScreenState
    extends ConsumerState<LessonAttendanceTodayScreen> {
  late DateTime _selectedDate;

  @override
  void initState() {
    super.initState();
    _selectedDate = _nearestWeekday(DateTime.now());
  }

  /// Snap to nearest weekday (if today is weekend, go to last Friday)
  static DateTime _nearestWeekday(DateTime d) {
    if (d.weekday == DateTime.saturday) return d.subtract(const Duration(days: 1));
    if (d.weekday == DateTime.sunday) return d.subtract(const Duration(days: 2));
    return d;
  }

  String get _dateStr =>
      DateFormat('yyyy-MM-dd').format(_selectedDate);

  bool get _isToday {
    final now = DateTime.now();
    return _selectedDate.year == now.year &&
        _selectedDate.month == now.month &&
        _selectedDate.day == now.day;
  }

  bool get _isPast => _selectedDate.isBefore(
        DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day),
      );

  void _prevDay() {
    setState(() {
      var d = _selectedDate.subtract(const Duration(days: 1));
      while (d.weekday > 5) d = d.subtract(const Duration(days: 1));
      _selectedDate = d;
    });
  }

  void _nextDay() {
    setState(() {
      var d = _selectedDate.add(const Duration(days: 1));
      while (d.weekday > 5) d = d.add(const Duration(days: 1));
      _selectedDate = d;
    });
  }

  @override
  Widget build(BuildContext context) {
    final sessionsAsync = ref.watch(sessionsForDateProvider(_dateStr));
    final dayLabel = DateFormat('EEEE, d MMM', 'pt').format(_selectedDate);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Livro de Ponto'),
            Text(dayLabel,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w400)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            tooltip: 'Dia anterior',
            onPressed: _prevDay,
          ),
          IconButton(
            icon: Icon(
              Icons.today_outlined,
              color: _isToday ? AppTheme.primary : null,
            ),
            tooltip: 'Hoje',
            onPressed: _isToday
                ? null
                : () => setState(
                    () => _selectedDate = _nearestWeekday(DateTime.now())),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Dia seguinte',
            onPressed: _nextDay,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
            onPressed: () => ref.invalidate(sessionsForDateProvider(_dateStr)),
          ),
        ],
      ),
      body: Column(
        children: [
          // Past-day banner
          if (_isPast)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              color: Colors.orange.shade50,
              child: Row(
                children: [
                  Icon(Icons.edit_calendar_outlined,
                      size: 18, color: Colors.orange.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Dia anterior — modificações ficam registadas com a data original.',
                      style: TextStyle(
                          fontSize: 12, color: Colors.orange.shade800),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: sessionsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Erro: $e')),
              data: (sessions) {
                if (sessions.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.event_busy_outlined,
                            size: 64, color: Colors.grey.shade400),
                        const SizedBox(height: 16),
                        Text(
                          _isToday
                              ? 'Sem aulas hoje'
                              : 'Sem aulas neste dia',
                          style: TextStyle(
                              fontSize: 18, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: sessions.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (_, i) => _SessionCard(
                    session: sessions[i],
                    date: _dateStr,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  final TodaySession session;
  final String date;
  const _SessionCard({required this.session, required this.date});

  @override
  Widget build(BuildContext context) {
    final taken = session.attendanceTaken;
    final timeLabel = session.slotTime != null
        ? session.slotTime!.substring(0, 5)
        : (session.periodName ?? 'Período ${session.periodNumber ?? ''}');

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
            color: taken
                ? AppTheme.success.withOpacity(0.4)
                : Colors.orange.withOpacity(0.4)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => context.push(
          '/lesson-attendance/session',
          extra: {
            'scheduleId': session.scheduleId,
            'subjectId': session.subjectId,
            'periodId': session.periodId,
            'turmaName': session.turmaName,
            'subjectName': session.subjectName,
            'date': date,
          },
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: (taken ? AppTheme.success : Colors.orange)
                      .withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  taken
                      ? Icons.check_circle_outline
                      : Icons.pending_outlined,
                  color: taken ? AppTheme.success : Colors.orange,
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.subjectName,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${session.turmaName} · $timeLabel',
                      style: TextStyle(
                          color: AppTheme.textSecondary, fontSize: 13),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      taken
                          ? 'Presença registada'
                          : '${session.studentCount} alunos · Por registar',
                      style: TextStyle(
                        color: taken ? AppTheme.success : Colors.orange,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Session Attendance Screen — mark each student present/absent/late/justified
// ---------------------------------------------------------------------------

class LessonAttendanceSessionScreen extends ConsumerStatefulWidget {
  final String scheduleId;
  final String subjectId;
  final String periodId;
  final String turmaName;
  final String subjectName;
  final String? date; // null = today

  const LessonAttendanceSessionScreen({
    super.key,
    required this.scheduleId,
    required this.subjectId,
    required this.periodId,
    required this.turmaName,
    required this.subjectName,
    this.date,
  });

  @override
  ConsumerState<LessonAttendanceSessionScreen> createState() =>
      _LessonAttendanceSessionScreenState();
}

class _LessonAttendanceSessionScreenState
    extends ConsumerState<LessonAttendanceSessionScreen> {
  late final String _dateStr =
      widget.date ?? DateFormat('yyyy-MM-dd').format(DateTime.now());
  List<_Student>? _students;
  bool _saving = false;

  bool get _isPast {
    final d = DateTime.tryParse(_dateStr);
    if (d == null) return false;
    final today = DateTime.now();
    return d.isBefore(DateTime(today.year, today.month, today.day));
  }

  Map<String, String> get _params => {
        'schedule_id': widget.scheduleId,
        'subject_id': widget.subjectId,
        'date': _dateStr,
        'period_id': widget.periodId,
      };

  void _markAll(String status) {
    if (_students == null) return;
    setState(() {
      for (final s in _students!) {
        s.status = status;
      }
    });
  }

  Future<void> _save() async {
    if (_students == null) return;
    setState(() => _saving = true);
    try {
      final records = _students!
          .map((s) => {
                'child_id': s.childId,
                'status': s.status,
                if (s.notes != null && s.notes!.isNotEmpty) 'notes': s.notes,
              })
          .toList();

      await ref.read(apiClientProvider).post('/lesson-attendance/session/bulk', data: {
        'schedule_id': widget.scheduleId,
        'subject_id': widget.subjectId,
        'date': _dateStr,
        'period_id': widget.periodId,
        'records': records,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Presenças guardadas'),
              backgroundColor: Colors.green),
        );
        // Invalidate sessions list so the card updates
        ref.invalidate(sessionsForDateProvider(_dateStr));
        if (context.canPop()) context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final studentsAsync =
        ref.watch(_sessionStudentsProvider(_params));

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.subjectName),
            Text(
              '${widget.turmaName} · ${DateFormat('d MMM', 'pt').format(DateTime.tryParse(_dateStr) ?? DateTime.now())}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w400),
            ),
          ],
        ),
        actions: [
          if (_students != null)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: _markAll,
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'present', child: Text('Marcar todos — Presente')),
                PopupMenuItem(value: 'absent', child: Text('Marcar todos — Falta')),
              ],
            ),
        ],
      ),
      body: Column(
        children: [
          if (_isPast)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              color: Colors.orange.shade50,
              child: Row(
                children: [
                  Icon(Icons.edit_calendar_outlined,
                      size: 18, color: Colors.orange.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'A modificar presença de dia anterior (${_dateStr}). O registo original ficará substituído.',
                      style: TextStyle(
                          fontSize: 12, color: Colors.orange.shade800),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: studentsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erro: $e')),
        data: (students) {
          if (_students == null) {
            // Initialise mutable state from async data (once)
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _students = List.from(students));
            });
            _students = List.from(students);
          }
          if (_students!.isEmpty) {
            return const Center(child: Text('Sem alunos matriculados'));
          }
          return Column(
            children: [
              _AttendanceSummaryBar(students: _students!),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  itemCount: _students!.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) => _StudentRow(
                    student: _students![i],
                    onStatusChanged: (s) =>
                        setState(() => _students![i].status = s),
                  ),
                ),
              ),
            ],
          );
        },
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: SizedBox(
            height: 52,
            child: ElevatedButton.icon(
              onPressed: (_saving || _students == null) ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save_outlined),
              label: const Text('Guardar Presenças',
                  style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          ),
        ),
      ),
    );
  }
}

class _AttendanceSummaryBar extends StatelessWidget {
  final List<_Student> students;
  const _AttendanceSummaryBar({required this.students});

  @override
  Widget build(BuildContext context) {
    final present =
        students.where((s) => s.status == 'present').length;
    final absent =
        students.where((s) => s.status == 'absent').length;
    final late = students.where((s) => s.status == 'late').length;
    final justified =
        students.where((s) => s.status == 'justified').length;

    return Container(
      color: Colors.grey.shade50,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _SummaryChip(
              label: 'Presente', count: present, color: AppTheme.success),
          _SummaryChip(
              label: 'Falta', count: absent, color: AppTheme.danger),
          _SummaryChip(
              label: 'Atraso', count: late, color: Colors.orange),
          _SummaryChip(
              label: 'Justif.', count: justified, color: Colors.blue),
        ],
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  const _SummaryChip(
      {required this.label, required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$count',
            style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 18,
                color: color)),
        Text(label,
            style:
                TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
      ],
    );
  }
}

class _StudentRow extends StatelessWidget {
  final _Student student;
  final ValueChanged<String> onStatusChanged;
  const _StudentRow(
      {required this.student, required this.onStatusChanged});

  static const _statuses = [
    ('present', 'Presente', Colors.green, Icons.check_circle_outline),
    ('absent', 'Falta', Colors.red, Icons.cancel_outlined),
    ('late', 'Atraso', Colors.orange, Icons.watch_later_outlined),
    ('justified', 'Justificada', Colors.blue, Icons.assignment_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: AppTheme.primary.withOpacity(0.12),
            child: Text(
              student.childName.isNotEmpty
                  ? student.childName[0].toUpperCase()
                  : '?',
              style: TextStyle(
                  fontWeight: FontWeight.w700, color: AppTheme.primary),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              student.childName,
              style: const TextStyle(
                  fontWeight: FontWeight.w500, fontSize: 15),
            ),
          ),
          // Status selector
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: student.status,
              isDense: true,
              borderRadius: BorderRadius.circular(10),
              items: _statuses
                  .map((t) => DropdownMenuItem(
                        value: t.$1,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(t.$4, color: t.$3, size: 18),
                            const SizedBox(width: 6),
                            Text(t.$2,
                                style: TextStyle(
                                    color: t.$3,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ))
                  .toList(),
              onChanged: (v) {
                if (v != null) onStatusChanged(v);
              },
            ),
          ),
        ],
      ),
    );
  }
}
