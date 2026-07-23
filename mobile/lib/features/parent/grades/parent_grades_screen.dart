import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/theme/app_theme.dart';

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

class _SubjectRow {
  final String subjectName;
  final String? subjectCode;
  final double? t1Final;
  final double? t2Final;
  final double? t3Final;
  final double? annualAverage;
  final bool? passed;

  const _SubjectRow({
    required this.subjectName,
    this.subjectCode,
    this.t1Final,
    this.t2Final,
    this.t3Final,
    this.annualAverage,
    this.passed,
  });

  factory _SubjectRow.fromJson(Map<String, dynamic> j) => _SubjectRow(
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
  final String childName;
  final String turmaName;
  final String schoolYear;
  final List<_SubjectRow> subjects;
  final double? overallAverage;
  final bool? promoted;

  const _ReportCard({
    required this.childName,
    required this.turmaName,
    required this.schoolYear,
    required this.subjects,
    this.overallAverage,
    this.promoted,
  });

  factory _ReportCard.fromJson(Map<String, dynamic> j) => _ReportCard(
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

// Handles Decimal-as-string from backend (e.g. "14.0" or 14.0)
double? _n(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final _parentReportCardProvider = FutureProvider.autoDispose<_ReportCard>((ref) async {
  final api = ref.read(apiClientProvider);
  final data = await api.get('/grades/my-report-card');
  return _ReportCard.fromJson(data as Map<String, dynamic>);
});

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class ParentGradesScreen extends ConsumerWidget {
  const ParentGradesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_parentReportCardProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Boletim Escolar'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(_parentReportCardProvider),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.assignment_late_outlined, size: 64, color: AppTheme.textSecondary),
              const SizedBox(height: 16),
              Text(
                e.toString().contains('No active enrollment')
                    ? 'Sem matrícula activa encontrada'
                    : 'Não foi possível carregar as notas',
                style: const TextStyle(color: AppTheme.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => ref.invalidate(_parentReportCardProvider),
                icon: const Icon(Icons.refresh),
                label: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
        data: (card) => _ReportCardView(card: card),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Report card view
// ---------------------------------------------------------------------------

class _ReportCardView extends StatelessWidget {
  final _ReportCard card;
  const _ReportCardView({required this.card});

  @override
  Widget build(BuildContext context) {
    final promoted = card.promoted;
    final avg = card.overallAverage;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppTheme.primary, AppTheme.primary.withOpacity(0.75)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  card.childName,
                  style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  '${card.turmaName}  •  ${card.schoolYear}',
                  style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 14),
                ),
                if (avg != null) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            avg.toStringAsFixed(1),
                            style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            'Média Geral',
                            style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12),
                          ),
                        ],
                      ),
                      const SizedBox(width: 24),
                      if (promoted != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white.withOpacity(0.4)),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                promoted ? Icons.check_circle_outline : Icons.cancel_outlined,
                                color: Colors.white,
                                size: 18,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                promoted ? 'Aprovado' : 'Reprovado',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Trimester tabs
          DefaultTabController(
            length: 4,
            child: Column(
              children: [
                TabBar(
                  tabs: const [
                    Tab(text: '1º Trim.'),
                    Tab(text: '2º Trim.'),
                    Tab(text: '3º Trim.'),
                    Tab(text: 'Anual'),
                  ],
                  labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  indicatorColor: AppTheme.primary,
                  labelColor: AppTheme.primary,
                  unselectedLabelColor: AppTheme.textSecondary,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: card.subjects.length * 52.0 + 60,
                  child: TabBarView(
                    children: [
                      _TrimesterTable(subjects: card.subjects, trimester: 1),
                      _TrimesterTable(subjects: card.subjects, trimester: 2),
                      _TrimesterTable(subjects: card.subjects, trimester: 3),
                      _AnnualTable(subjects: card.subjects),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),
          const Text(
            'Escala: 0–20  •  Aprovado: ≥ 10  •  MAC: Avaliação Contínua (60%)  •  PE: Prova Escrita (40%)',
            style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Per-trimester table
// ---------------------------------------------------------------------------

class _TrimesterTable extends StatelessWidget {
  final List<_SubjectRow> subjects;
  final int trimester;
  const _TrimesterTable({required this.subjects, required this.trimester});

  @override
  Widget build(BuildContext context) {
    if (subjects.isEmpty) {
      return const Center(child: Text('Sem notas lançadas', style: TextStyle(color: AppTheme.textSecondary)));
    }

    double? Function(_SubjectRow) getFinal = switch (trimester) {
      1 => (s) => s.t1Final,
      2 => (s) => s.t2Final,
      3 => (s) => s.t3Final,
      _ => (s) => null,
    };

    return SingleChildScrollView(
      child: DataTable(
        columnSpacing: 20,
        headingRowHeight: 36,
        dataRowMinHeight: 48,
        dataRowMaxHeight: 48,
        columns: const [
          DataColumn(label: Text('Disciplina', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Final', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
          DataColumn(label: Text('', style: TextStyle(fontWeight: FontWeight.bold))),
        ],
        rows: subjects.map((s) {
          final final_ = getFinal(s);
          return DataRow(cells: [
            DataCell(Text(
              s.subjectCode != null ? '${s.subjectName} (${s.subjectCode})' : s.subjectName,
              style: const TextStyle(fontSize: 13),
            )),
            DataCell(Text(
              final_?.toStringAsFixed(1) ?? '—',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: final_ == null
                    ? AppTheme.textSecondary
                    : final_ >= 10
                        ? Colors.green.shade700
                        : AppTheme.danger,
              ),
            )),
            DataCell(
              final_ == null
                  ? const SizedBox.shrink()
                  : Icon(
                      final_ >= 10 ? Icons.check_circle_outline : Icons.cancel_outlined,
                      color: final_ >= 10 ? Colors.green : AppTheme.danger,
                      size: 18,
                    ),
            ),
          ]);
        }).toList(),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Annual summary table
// ---------------------------------------------------------------------------

class _AnnualTable extends StatelessWidget {
  final List<_SubjectRow> subjects;
  const _AnnualTable({required this.subjects});

  @override
  Widget build(BuildContext context) {
    if (subjects.isEmpty) {
      return const Center(child: Text('Sem notas lançadas', style: TextStyle(color: AppTheme.textSecondary)));
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: 16,
        headingRowHeight: 36,
        dataRowMinHeight: 48,
        dataRowMaxHeight: 48,
        columns: const [
          DataColumn(label: Text('Disciplina', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('1º T', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
          DataColumn(label: Text('2º T', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
          DataColumn(label: Text('3º T', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
          DataColumn(label: Text('Média', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
        ],
        rows: subjects.map((s) {
          return DataRow(cells: [
            DataCell(Text(
              s.subjectCode != null ? '${s.subjectName} (${s.subjectCode})' : s.subjectName,
              style: const TextStyle(fontSize: 13),
            )),
            DataCell(Text(_fmt(s.t1Final), style: _style(s.t1Final))),
            DataCell(Text(_fmt(s.t2Final), style: _style(s.t2Final))),
            DataCell(Text(_fmt(s.t3Final), style: _style(s.t3Final))),
            DataCell(Text(
              s.annualAverage?.toStringAsFixed(1) ?? '—',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: s.annualAverage == null
                    ? AppTheme.textSecondary
                    : s.annualAverage! >= 10
                        ? Colors.green.shade700
                        : AppTheme.danger,
              ),
            )),
          ]);
        }).toList(),
      ),
    );
  }

  String _fmt(double? v) => v?.toStringAsFixed(1) ?? '—';
  TextStyle _style(double? v) => TextStyle(
        color: v == null
            ? AppTheme.textSecondary
            : v >= 10
                ? Colors.green.shade700
                : AppTheme.danger,
      );
}
