import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/theme/app_theme.dart';

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

class _StudentSubjectRow {
  final String childId;
  final String childName;
  final String subjectId;
  final String subjectName;
  final int totalLessons;
  final int present;
  final int absent;
  final int late;
  final int justified;
  final double absencePct;
  final bool atRisk;

  const _StudentSubjectRow({
    required this.childId,
    required this.childName,
    required this.subjectId,
    required this.subjectName,
    required this.totalLessons,
    required this.present,
    required this.absent,
    required this.late,
    required this.justified,
    required this.absencePct,
    required this.atRisk,
  });

  factory _StudentSubjectRow.fromJson(Map<String, dynamic> j) =>
      _StudentSubjectRow(
        childId: j['child_id'] as String,
        childName: j['child_name'] as String? ?? '',
        subjectId: j['subject_id'] as String,
        subjectName: j['subject_name'] as String? ?? '',
        totalLessons: j['total_lessons'] as int? ?? 0,
        present: j['present'] as int? ?? 0,
        absent: j['absent'] as int? ?? 0,
        late: j['late'] as int? ?? 0,
        justified: j['justified'] as int? ?? 0,
        absencePct: (j['absence_pct'] as num?)?.toDouble() ?? 0.0,
        atRisk: j['at_risk'] as bool? ?? false,
      );
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final _summaryProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>(
  (ref, scheduleId) async {
    final data = await ref.read(apiClientProvider)
        .get('/lesson-attendance/turma/$scheduleId/summary');
    return data as Map<String, dynamic>;
  },
);

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class LessonAttendanceSummaryScreen extends ConsumerStatefulWidget {
  final String scheduleId;
  final String turmaName;

  const LessonAttendanceSummaryScreen({
    super.key,
    required this.scheduleId,
    required this.turmaName,
  });

  @override
  ConsumerState<LessonAttendanceSummaryScreen> createState() =>
      _LessonAttendanceSummaryScreenState();
}

class _LessonAttendanceSummaryScreenState
    extends ConsumerState<LessonAttendanceSummaryScreen> {
  bool _atRiskOnly = false;
  String? _filterSubject;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_summaryProvider(widget.scheduleId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Faltas por Disciplina'),
        subtitle: Text(widget.turmaName,
            style: const TextStyle(fontSize: 13)),
        actions: [
          IconButton(
            tooltip: _atRiskOnly ? 'Mostrar todos' : 'Só em risco',
            icon: Icon(
              Icons.warning_amber_outlined,
              color: _atRiskOnly ? Colors.orange : null,
            ),
            onPressed: () => setState(() => _atRiskOnly = !_atRiskOnly),
          ),
        ],
      ),
      body: async.when(
        loading: () =>
            const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erro: $e')),
        data: (raw) {
          final rows = (raw['rows'] as List? ?? [])
              .map((e) =>
                  _StudentSubjectRow.fromJson(e as Map<String, dynamic>))
              .toList();

          // Build subject list for filter
          final subjects = rows
              .map((r) => r.subjectName)
              .toSet()
              .toList()
            ..sort();

          var filtered = rows;
          if (_atRiskOnly) {
            filtered = filtered.where((r) => r.atRisk).toList();
          }
          if (_filterSubject != null) {
            filtered = filtered
                .where((r) => r.subjectName == _filterSubject)
                .toList();
          }

          // Group by student
          final byStudent = <String, List<_StudentSubjectRow>>{};
          for (final r in filtered) {
            byStudent.putIfAbsent(r.childName, () => []).add(r);
          }
          final studentNames = byStudent.keys.toList()..sort();

          return Column(
            children: [
              // Subject filter chips
              if (subjects.isNotEmpty)
                SizedBox(
                  height: 44,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 6),
                    children: [
                      FilterChip(
                        label: const Text('Todas'),
                        selected: _filterSubject == null,
                        onSelected: (_) =>
                            setState(() => _filterSubject = null),
                      ),
                      const SizedBox(width: 8),
                      ...subjects.map((s) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: FilterChip(
                              label: Text(s),
                              selected: _filterSubject == s,
                              onSelected: (_) => setState(
                                  () => _filterSubject =
                                      _filterSubject == s ? null : s),
                            ),
                          )),
                    ],
                  ),
                ),

              if (filtered.isEmpty)
                const Expanded(
                  child: Center(
                      child: Text('Sem registos de faltas')),
                )
              else
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: studentNames.length,
                    itemBuilder: (_, i) {
                      final name = studentNames[i];
                      final studentRows = byStudent[name]!;
                      return _StudentCard(
                          studentName: name, rows: studentRows);
                    },
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _StudentCard extends StatelessWidget {
  final String studentName;
  final List<_StudentSubjectRow> rows;
  const _StudentCard(
      {required this.studentName, required this.rows});

  @override
  Widget build(BuildContext context) {
    final hasRisk = rows.any((r) => r.atRisk);
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
            color: hasRisk
                ? Colors.orange.withOpacity(0.5)
                : Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: AppTheme.primary.withOpacity(0.12),
                  child: Text(
                    studentName.isNotEmpty
                        ? studentName[0].toUpperCase()
                        : '?',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: AppTheme.primary),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    studentName,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ),
                if (hasRisk)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Em risco',
                      style: TextStyle(
                          color: Colors.orange,
                          fontSize: 11,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            ...rows.map((r) => _SubjectRow(row: r)),
          ],
        ),
      ),
    );
  }
}

class _SubjectRow extends StatelessWidget {
  final _StudentSubjectRow row;
  const _SubjectRow({required this.row});

  @override
  Widget build(BuildContext context) {
    final pct = row.absencePct;
    final color = row.atRisk
        ? Colors.orange
        : pct > 0
            ? AppTheme.danger
            : AppTheme.success;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(row.subjectName,
                style: const TextStyle(fontSize: 13)),
          ),
          Text(
            '${row.absent + row.late}/${row.totalLessons} faltas',
            style: TextStyle(
                color: AppTheme.textSecondary, fontSize: 12),
          ),
          const SizedBox(width: 8),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${pct.toStringAsFixed(0)}%',
              style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w700,
                  fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
