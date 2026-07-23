import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/theme/app_theme.dart';

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

class _Turma {
  final String id;
  final String name;
  final String level;
  const _Turma({required this.id, required this.name, required this.level});
  factory _Turma.fromJson(Map<String, dynamic> j) => _Turma(
        id: j['id'] as String,
        name: j['name'] as String,
        level: j['level'] as String? ?? '',
      );
}

class _SchoolYear {
  final String id;
  final String yearLabel;
  final bool isActive;
  const _SchoolYear({required this.id, required this.yearLabel, required this.isActive});
  factory _SchoolYear.fromJson(Map<String, dynamic> j) => _SchoolYear(
        id: j['id'] as String,
        yearLabel: j['year_label'] as String,
        isActive: j['is_active'] as bool? ?? false,
      );
}

class _SubjectRow {
  final String subjectId;
  final String subjectName;
  final String? subjectCode;
  final double? t1Final;
  final double? t2Final;
  final double? t3Final;
  final double? annualAverage;
  final bool? passed;

  const _SubjectRow({
    required this.subjectId,
    required this.subjectName,
    this.subjectCode,
    this.t1Final,
    this.t2Final,
    this.t3Final,
    this.annualAverage,
    this.passed,
  });

  factory _SubjectRow.fromJson(Map<String, dynamic> j) => _SubjectRow(
        subjectId: j['subject_id'] as String,
        subjectName: j['subject_name'] as String,
        subjectCode: j['subject_code'] as String?,
        t1Final: _n(j['t1_final']),
        t2Final: _n(j['t2_final']),
        t3Final: _n(j['t3_final']),
        annualAverage: _n(j['annual_average']),
        passed: j['passed'] as bool?,
      );
}

class _ReportCard {
  final String enrollmentId;
  final String childName;
  final String turmaName;
  final String schoolYear;
  final List<_SubjectRow> subjects;
  final double? overallAverage;
  final bool? promoted;

  const _ReportCard({
    required this.enrollmentId,
    required this.childName,
    required this.turmaName,
    required this.schoolYear,
    required this.subjects,
    this.overallAverage,
    this.promoted,
  });

  factory _ReportCard.fromJson(Map<String, dynamic> j) => _ReportCard(
        enrollmentId: j['enrollment_id'] as String,
        childName: j['child_name'] as String,
        turmaName: j['turma_name'] as String,
        schoolYear: j['school_year'] as String,
        subjects: (j['subjects'] as List? ?? [])
            .map((e) => _SubjectRow.fromJson(e as Map<String, dynamic>))
            .toList(),
        overallAverage: _n(j['overall_average']),
        promoted: j['promoted'] as bool?,
      );
}

double? _n(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

final _turmasRcProvider = FutureProvider.autoDispose<List<_Turma>>((ref) async {
  final data = await ref.read(apiClientProvider).get('/academic/turmas') as List;
  return data.map((e) => _Turma.fromJson(e as Map<String, dynamic>)).toList();
});

final _schoolYearsRcProvider = FutureProvider.autoDispose<List<_SchoolYear>>((ref) async {
  final data = await ref.read(apiClientProvider).get('/schools/school-years') as List;
  return data.map((e) => _SchoolYear.fromJson(e as Map<String, dynamic>)).toList();
});

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class ReportCardsScreen extends ConsumerStatefulWidget {
  const ReportCardsScreen({super.key});

  @override
  ConsumerState<ReportCardsScreen> createState() => _ReportCardsScreenState();
}

class _ReportCardsScreenState extends ConsumerState<ReportCardsScreen> {
  _Turma? _selectedTurma;
  _SchoolYear? _selectedYear;
  List<_ReportCard>? _cards;
  bool _loading = false;
  String? _error;
  bool _yearsLoaded = false;

  Future<void> _load() async {
    if (_selectedTurma == null) return;
    setState(() { _loading = true; _error = null; });
    try {
      final api = ref.read(apiClientProvider);
      var path = '/grades/class-report?turma_id=${_selectedTurma!.id}';
      if (_selectedYear != null) path += '&school_year_id=${_selectedYear!.id}';
      final data = await api.get(path) as List;
      setState(() {
        _cards = data.map((e) => _ReportCard.fromJson(e as Map<String, dynamic>)).toList();
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final turmasAsync = ref.watch(_turmasRcProvider);
    final yearsAsync = ref.watch(_schoolYearsRcProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Pautas & Boletins')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              children: [
                // Year selector
                yearsAsync.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (e, _) => const SizedBox.shrink(),
                  data: (years) {
                    if (!_yearsLoaded && years.isNotEmpty) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) {
                          setState(() {
                            _selectedYear = years.firstWhere(
                              (y) => y.isActive,
                              orElse: () => years.first,
                            );
                            _yearsLoaded = true;
                          });
                        }
                      });
                    }
                    return DropdownButtonFormField<String>(
                      value: _selectedYear?.id,
                      decoration: const InputDecoration(
                        labelText: 'Ano Lectivo',
                        prefixIcon: Icon(Icons.calendar_today_outlined),
                        isDense: true,
                      ),
                      items: years
                          .map((y) => DropdownMenuItem(
                                value: y.id,
                                child: Text(y.yearLabel + (y.isActive ? ' (activo)' : '')),
                              ))
                          .toList(),
                      onChanged: (id) {
                        setState(() {
                          _selectedYear = years.firstWhere((y) => y.id == id);
                          _cards = null;
                        });
                      },
                    );
                  },
                ),
                const SizedBox(height: 10),
                // Turma + load
                Row(
                  children: [
                    Expanded(
                      child: turmasAsync.when(
                        loading: () => const LinearProgressIndicator(),
                        error: (e, _) => Text('Erro: $e', style: const TextStyle(color: AppTheme.danger)),
                        data: (turmas) => DropdownButtonFormField<String>(
                          value: _selectedTurma?.id,
                          decoration: const InputDecoration(
                            labelText: 'Turma',
                            prefixIcon: Icon(Icons.class_outlined),
                            isDense: true,
                          ),
                          items: turmas
                              .map((t) => DropdownMenuItem(
                                    value: t.id,
                                    child: Text('${t.name} — ${t.level}'),
                                  ))
                              .toList(),
                          onChanged: (id) {
                            setState(() {
                              _selectedTurma = turmasAsync.value?.firstWhere((t) => t.id == id);
                              _cards = null;
                            });
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.tonal(
                      onPressed: (_loading || _selectedTurma == null) ? null : _load,
                      child: _loading
                          ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Ver Pautas'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_error!, style: const TextStyle(color: AppTheme.danger)),
            ),
          Expanded(
            child: _cards == null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.assignment_outlined, size: 64, color: Colors.grey.shade300),
                        const SizedBox(height: 16),
                        const Text(
                          'Seleccione uma turma e toque em "Ver Pautas"',
                          style: TextStyle(color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  )
                : _cards!.isEmpty
                    ? const Center(child: Text('Nenhum aluno matriculado nesta turma'))
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _cards!.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, i) => _ReportCardTile(card: _cards![i]),
                      ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Report card tile (expandable)
// ---------------------------------------------------------------------------

class _ReportCardTile extends StatelessWidget {
  final _ReportCard card;
  const _ReportCardTile({required this.card});

  @override
  Widget build(BuildContext context) {
    final promoted = card.promoted;
    final avg = card.overallAverage;

    return Card(
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: promoted == true
              ? Colors.green.shade100
              : promoted == false
                  ? Colors.red.shade100
                  : Colors.grey.shade100,
          child: Icon(
            promoted == true
                ? Icons.check_circle_outline
                : promoted == false
                    ? Icons.cancel_outlined
                    : Icons.pending_outlined,
            color: promoted == true
                ? Colors.green
                : promoted == false
                    ? AppTheme.danger
                    : Colors.grey,
          ),
        ),
        title: Text(card.childName, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          avg != null
              ? 'Média geral: ${avg.toStringAsFixed(1)} — ${promoted == true ? "Aprovado" : promoted == false ? "Reprovado" : "Em curso"}'
              : 'Sem notas lançadas',
          style: TextStyle(
            fontSize: 12,
            color: promoted == true ? Colors.green : promoted == false ? AppTheme.danger : AppTheme.textSecondary,
          ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 16,
                headingRowHeight: 36,
                dataRowMinHeight: 36,
                dataRowMaxHeight: 36,
                columns: const [
                  DataColumn(label: Text('Disciplina', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('1º T', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
                  DataColumn(label: Text('2º T', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
                  DataColumn(label: Text('3º T', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
                  DataColumn(label: Text('Média', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
                ],
                rows: card.subjects.map((s) {
                  final Color avgColor = s.annualAverage == null
                      ? AppTheme.textSecondary
                      : s.annualAverage! >= 10
                          ? Colors.green.shade700
                          : AppTheme.danger;
                  return DataRow(cells: [
                    DataCell(Text(
                      s.subjectCode != null ? '${s.subjectName} (${s.subjectCode})' : s.subjectName,
                      style: const TextStyle(fontSize: 13),
                    )),
                    DataCell(Text(_fmt(s.t1Final), style: _gradeStyle(s.t1Final))),
                    DataCell(Text(_fmt(s.t2Final), style: _gradeStyle(s.t2Final))),
                    DataCell(Text(_fmt(s.t3Final), style: _gradeStyle(s.t3Final))),
                    DataCell(Text(
                      s.annualAverage?.toStringAsFixed(1) ?? '—',
                      style: TextStyle(fontWeight: FontWeight.bold, color: avgColor),
                    )),
                  ]);
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _fmt(double? v) => v?.toStringAsFixed(1) ?? '—';

  TextStyle _gradeStyle(double? v) => TextStyle(
        color: v == null
            ? AppTheme.textSecondary
            : v >= 10
                ? Colors.green.shade700
                : AppTheme.danger,
      );
}
