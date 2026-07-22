/// K-12 Timetable screen — school-year-centric design.
///
/// Tab 0 — Requisitos: All turmas for the selected year with their requirement
///   cards (subject × teacher × periods/week). Inline add/edit/delete.
///   "Gerar Horário" runs the constraint solver for ALL turmas at once,
///   preventing teacher double-booking across classes.
/// Tab 1 — Horário: turma selector → week grid (period rows × Mon–Fri cols).
///   Admin/Coordinator: tap any cell to assign subject, teacher, room.
///   Teacher: read-only view.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_client.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/auth/auth_state.dart';
import '../../../core/theme/app_theme.dart';

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

class _ScheduleItem {
  final String id;
  final String turmaId;
  final String turmaName;
  final String schoolYearId;
  const _ScheduleItem({
    required this.id,
    required this.turmaId,
    required this.turmaName,
    required this.schoolYearId,
  });
  factory _ScheduleItem.fromJson(Map<String, dynamic> j) {
    return _ScheduleItem(
      id: j['id'] as String,
      turmaId: j['turma_id'] as String? ?? '',
      turmaName: j['turma_name'] as String? ?? '',
      schoolYearId: j['school_year_id'] as String? ?? '',
    );
  }
}

class _Period {
  final String id;
  final int number;
  final String name;
  final String startTime;
  final String endTime;
  final bool isBreak;
  const _Period({
    required this.id,
    required this.number,
    required this.name,
    required this.startTime,
    required this.endTime,
    required this.isBreak,
  });
  factory _Period.fromJson(Map<String, dynamic> j) => _Period(
        id: j['id'] as String,
        number: (j['period_number'] as num).toInt(),
        name: j['name'] as String,
        startTime: j['start_time'] as String,
        endTime: j['end_time'] as String,
        isBreak: j['is_break'] as bool? ?? false,
      );
}

class _Cell {
  final int id;
  final int dayOfWeek;
  final String periodId;
  final String? subjectId;
  final String? subjectName;
  final String? subjectCode;
  final String? employeeId;
  final String? employeeName;
  final String? room;
  const _Cell({
    required this.id,
    required this.dayOfWeek,
    required this.periodId,
    this.subjectId,
    this.subjectName,
    this.subjectCode,
    this.employeeId,
    this.employeeName,
    this.room,
  });
  factory _Cell.fromJson(Map<String, dynamic> j) => _Cell(
        id: (j['id'] as num).toInt(),
        dayOfWeek: (j['day_of_week'] as num).toInt(),
        periodId: j['period_id'] as String,
        subjectId: j['subject_id'] as String?,
        subjectName: j['subject_name'] as String?,
        subjectCode: j['subject_code'] as String?,
        employeeId: j['employee_id'] as String?,
        employeeName: j['employee_name'] as String?,
        room: j['room'] as String?,
      );
}

class _GridData {
  final String scheduleId;
  final String turmaName;
  final String schoolYearLabel;
  final List<_Period> periods;
  final List<_Cell> cells;
  const _GridData({
    required this.scheduleId,
    required this.turmaName,
    required this.schoolYearLabel,
    required this.periods,
    required this.cells,
  });
}

class _SubjectItem {
  final String id;
  final String name;
  final String? code;
  const _SubjectItem({required this.id, required this.name, this.code});
  factory _SubjectItem.fromJson(Map<String, dynamic> j) => _SubjectItem(
        id: j['id'] as String,
        name: j['name'] as String,
        code: j['code'] as String?,
      );
}

class _Requirement {
  final String id;
  final String scheduleId;
  final String subjectId;
  final String? subjectName;
  final String? subjectCode;
  final String employeeId;
  final String? employeeName;
  final int periodsPerWeek;
  final bool allowDoublePeriod;
  final String? preferredTimeOfDay;
  const _Requirement({
    required this.id,
    required this.scheduleId,
    required this.subjectId,
    this.subjectName,
    this.subjectCode,
    required this.employeeId,
    this.employeeName,
    required this.periodsPerWeek,
    required this.allowDoublePeriod,
    this.preferredTimeOfDay,
  });
  factory _Requirement.fromJson(Map<String, dynamic> j) => _Requirement(
        id: j['id'] as String,
        scheduleId: j['schedule_id'] as String,
        subjectId: j['subject_id'] as String,
        subjectName: j['subject_name'] as String?,
        subjectCode: j['subject_code'] as String?,
        employeeId: j['employee_id'] as String,
        employeeName: j['employee_name'] as String?,
        periodsPerWeek: (j['periods_per_week'] as num).toInt(),
        allowDoublePeriod: j['allow_double_period'] as bool? ?? false,
        preferredTimeOfDay: j['preferred_time_of_day'] as String?,
      );
}

class _GenCell {
  final String scheduleId;
  final int dayOfWeek;
  final String periodId;
  final String subjectId;
  final String? subjectName;
  final String employeeId;
  final String? employeeName;
  const _GenCell({
    required this.scheduleId,
    required this.dayOfWeek,
    required this.periodId,
    required this.subjectId,
    this.subjectName,
    required this.employeeId,
    this.employeeName,
  });
  factory _GenCell.fromJson(Map<String, dynamic> j) => _GenCell(
        scheduleId: j['schedule_id'] as String,
        dayOfWeek: (j['day_of_week'] as num).toInt(),
        periodId: j['period_id'] as String,
        subjectId: j['subject_id'] as String,
        subjectName: j['subject_name'] as String?,
        employeeId: j['employee_id'] as String,
        employeeName: j['employee_name'] as String?,
      );
  Map<String, dynamic> toJson() => {
        'schedule_id': scheduleId,
        'day_of_week': dayOfWeek,
        'period_id': periodId,
        'subject_id': subjectId,
        'subject_name': subjectName,
        'employee_id': employeeId,
        'employee_name': employeeName,
      };
}

class _GenConflict {
  final String requirementId;
  final String subjectName;
  final String employeeName;
  final int periodsRequested;
  final int periodsAssigned;
  final String reason;
  const _GenConflict({
    required this.requirementId,
    required this.subjectName,
    required this.employeeName,
    required this.periodsRequested,
    required this.periodsAssigned,
    required this.reason,
  });
  factory _GenConflict.fromJson(Map<String, dynamic> j) => _GenConflict(
        requirementId: j['requirement_id'] as String,
        subjectName: j['subject_name'] as String,
        employeeName: j['employee_name'] as String,
        periodsRequested: (j['periods_requested'] as num).toInt(),
        periodsAssigned: (j['periods_assigned'] as num).toInt(),
        reason: j['reason'] as String,
      );
}

class _GenerateResult {
  final String status;
  final List<_GenCell> cells;
  final List<_GenConflict> conflicts;
  const _GenerateResult({
    required this.status,
    required this.cells,
    required this.conflicts,
  });
}

class _SchoolYear {
  final String id;
  final String label;
  final bool isActive;
  const _SchoolYear({required this.id, required this.label, required this.isActive});
  factory _SchoolYear.fromJson(Map<String, dynamic> j) => _SchoolYear(
        id: j['id'] as String,
        label: j['year_label'] as String,
        isActive: j['is_active'] as bool? ?? false,
      );
}

class _EmployeeItem {
  final String id;
  final String name;
  const _EmployeeItem({required this.id, required this.name});
  factory _EmployeeItem.fromJson(Map<String, dynamic> j) {
    final first = j['first_name'] as String? ?? '';
    final last = j['last_name'] as String? ?? '';
    return _EmployeeItem(id: j['id'] as String, name: '$first $last'.trim());
  }
}

class _TurmaItem {
  final String id;
  final String name;
  const _TurmaItem({required this.id, required this.name});
  factory _TurmaItem.fromJson(Map<String, dynamic> j) =>
      _TurmaItem(id: j['id'] as String, name: j['name'] as String);
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

final _turmasProvider = FutureProvider.autoDispose<List<_TurmaItem>>((ref) async {
  final data = await ref.read(apiClientProvider).get('/academic/turmas') as List;
  return data.map((e) => _TurmaItem.fromJson(e as Map<String, dynamic>)).toList();
});

/// All schedules for a given school year (with turma_name from server).
final _schedulesForYearProvider =
    FutureProvider.autoDispose.family<List<_ScheduleItem>, String>((ref, yearId) async {
  final data = await ref
      .read(apiClientProvider)
      .get('/academic/schedules?school_year_id=$yearId&limit=100') as List;
  return data.map((e) => _ScheduleItem.fromJson(e as Map<String, dynamic>)).toList();
});

final _gridProvider =
    FutureProvider.autoDispose.family<_GridData, String>((ref, scheduleId) async {
  final raw = await ref
      .read(apiClientProvider)
      .get('/timetable/grid?schedule_id=$scheduleId') as Map<String, dynamic>;
  return _GridData(
    scheduleId: raw['schedule_id'] as String,
    turmaName: raw['turma_name'] as String? ?? '',
    schoolYearLabel: raw['school_year_label'] as String? ?? '',
    periods: (raw['periods'] as List)
        .map((e) => _Period.fromJson(e as Map<String, dynamic>))
        .toList(),
    cells: (raw['cells'] as List)
        .map((e) => _Cell.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
});

final _subjectsProvider = FutureProvider.autoDispose<List<_SubjectItem>>((ref) async {
  final data = await ref.read(apiClientProvider).get('/grades/subjects') as List;
  return data.map((e) => _SubjectItem.fromJson(e as Map<String, dynamic>)).toList();
});

final _teachersProvider = FutureProvider.autoDispose<List<_EmployeeItem>>((ref) async {
  final data = await ref.read(apiClientProvider).get('/employees?limit=200') as List;
  return data.map((e) => _EmployeeItem.fromJson(e as Map<String, dynamic>)).toList();
});

final _periodsListProvider = FutureProvider.autoDispose<List<_Period>>((ref) async {
  final data = await ref.read(apiClientProvider).get('/timetable/periods') as List;
  return data.map((e) => _Period.fromJson(e as Map<String, dynamic>)).toList();
});

final _requirementsProvider =
    FutureProvider.autoDispose.family<List<_Requirement>, String>((ref, scheduleId) async {
  final data = await ref
      .read(apiClientProvider)
      .get('/timetable/requirements?schedule_id=$scheduleId') as List;
  return data.map((e) => _Requirement.fromJson(e as Map<String, dynamic>)).toList();
});

final _schoolYearsProvider = FutureProvider.autoDispose<List<_SchoolYear>>((ref) async {
  final data = await ref.read(apiClientProvider).get('/schools/school-years') as List;
  return data.map((e) => _SchoolYear.fromJson(e as Map<String, dynamic>)).toList();
});

// ---------------------------------------------------------------------------
// Deterministic subject color palette
// ---------------------------------------------------------------------------

const _subjectColors = [
  Color(0xFF1565C0),
  Color(0xFF2E7D32),
  Color(0xFF6A1B9A),
  Color(0xFFAD1457),
  Color(0xFFE65100),
  Color(0xFF00695C),
  Color(0xFF4527A0),
  Color(0xFF558B2F),
  Color(0xFF0277BD),
  Color(0xFF827717),
];

Color _colorForSubject(String? subjectId) {
  if (subjectId == null) return Colors.grey.shade400;
  final idx = subjectId.codeUnits.fold(0, (a, b) => a + b) % _subjectColors.length;
  return _subjectColors[idx];
}

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class TimetableScreen extends ConsumerStatefulWidget {
  const TimetableScreen({super.key});

  @override
  ConsumerState<TimetableScreen> createState() => _TimetableScreenState();
}

class _TimetableScreenState extends ConsumerState<TimetableScreen>
    with SingleTickerProviderStateMixin {
  _SchoolYear? _selectedYear;
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  bool get _canEdit {
    final auth = ref.read(authProvider);
    return auth.hasAnyRole([UserRole.schoolAdmin, UserRole.coordinator]);
  }

  @override
  Widget build(BuildContext context) {
    final yearsAsync = ref.watch(_schoolYearsProvider);

    // Auto-select active year on first load
    yearsAsync.whenData((years) {
      if (_selectedYear == null && years.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _selectedYear = years.firstWhere(
                (y) => y.isActive,
                orElse: () => years.first,
              );
            });
          }
        });
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Horário Lectivo'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.list_alt_outlined, size: 18), text: 'Requisitos'),
            Tab(icon: Icon(Icons.table_chart_outlined, size: 18), text: 'Horário'),
          ],
        ),
        actions: [
          if (_selectedYear != null && _canEdit)
            IconButton(
              icon: const Icon(Icons.auto_fix_high),
              tooltip: 'Gerar horário para todas as turmas do ano',
              onPressed: _generateForYear,
            ),
          IconButton(
            icon: const Icon(Icons.access_time_outlined),
            tooltip: 'Períodos lectivos',
            onPressed: _showPeriodsDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Year selector ───────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: yearsAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('Erro: $e',
                  style: const TextStyle(color: AppTheme.danger)),
              data: (years) => years.isEmpty
                  ? const Text(
                      'Nenhum ano lectivo encontrado.',
                      style: TextStyle(color: AppTheme.danger),
                    )
                  : DropdownButtonFormField<_SchoolYear>(
                      value: _selectedYear,
                      decoration: const InputDecoration(
                        labelText: 'Ano Lectivo',
                        border: OutlineInputBorder(),
                        isDense: true,
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      items: years
                          .map((y) => DropdownMenuItem(
                                value: y,
                                child: Row(
                                  children: [
                                    Text(y.label),
                                    if (y.isActive) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: Colors.green.withAlpha(30),
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        child: const Text('activo',
                                            style: TextStyle(
                                                fontSize: 10,
                                                color: Colors.green)),
                                      ),
                                    ],
                                  ],
                                ),
                              ))
                          .toList(),
                      onChanged: (y) => setState(() => _selectedYear = y),
                    ),
            ),
          ),
          // ── Tabs ────────────────────────────────────────────────────────
          Expanded(
            child: _selectedYear == null
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _RequirementsTab(
                        yearId: _selectedYear!.id,
                        canEdit: _canEdit,
                      ),
                      _GridTab(
                        yearId: _selectedYear!.id,
                        canEdit: _canEdit,
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  // ── Generate for whole year ─────────────────────────────────────────────

  Future<void> _generateForYear() async {
    final yearId = _selectedYear!.id;

    // ── Pre-check 1: periods must exist ────────────────────────────────
    List<_Period> periods = [];
    try {
      final raw =
          await ref.read(apiClientProvider).get('/timetable/periods') as List;
      periods = raw
          .map((e) => _Period.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {}

    final teachingPeriods = periods.where((p) => !p.isBreak).toList();
    if (teachingPeriods.isEmpty) {
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Períodos lectivos não configurados'),
          content: const Text(
            'Para gerar o horário o solver precisa de saber quais são os '
            'períodos de aula (ex: 1ª Aula 08:00–09:00, Intervalo 09:00–09:30, '
            '2ª Aula 09:30–10:30, …).\n\n'
            'Clique em "Configurar" para os definir agora.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(ctx).pop();
                _showPeriodsDialog();
              },
              icon: const Icon(Icons.access_time_outlined),
              label: const Text('Configurar Períodos'),
            ),
          ],
        ),
      );
      return;
    }

    // ── Pre-check 2: schedules must exist ──────────────────────────────
    final schedules = ref.read(_schedulesForYearProvider(yearId)).valueOrNull;

    if (schedules == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('A carregar turmas, aguarde e tente novamente.'),
      ));
      return;
    }
    if (schedules.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'Nenhuma turma tem horário lectivo criado para este ano.'),
      ));
      return;
    }

    await _generateAndPreview(schedules);
  }

  Future<void> _generateAndPreview(List<_ScheduleItem> schedules) async {
    final scheduleIds = schedules.map((s) => s.id).toList();

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: SizedBox(
          width: 220,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              const Text('A gerar horário…', textAlign: TextAlign.center),
              const SizedBox(height: 4),
              Text(
                'Solver verifica conflitos entre ${schedules.length} turma(s).',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      ),
    );

    _GenerateResult? result;
    String? error;
    try {
      final raw = await ref.read(apiClientProvider).post(
        '/timetable/generate',
        data: {'schedule_ids': scheduleIds},
      ) as Map<String, dynamic>;
      result = _GenerateResult(
        status: raw['status'] as String,
        cells: (raw['cells'] as List)
            .map((e) => _GenCell.fromJson(e as Map<String, dynamic>))
            .toList(),
        conflicts: (raw['conflicts'] as List)
            .map((e) => _GenConflict.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
    } catch (e) {
      error = e.toString();
    }

    if (!mounted) return;
    Navigator.of(context).pop(); // close loading dialog

    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Erro: $error')));
      return;
    }

    // Load periods for the preview grid
    List<_Period> periods = [];
    try {
      final raw = await ref
          .read(apiClientProvider)
          .get('/timetable/periods') as List;
      periods = raw
          .map((e) => _Period.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {}

    if (!mounted) return;
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _PreviewDialog(
        schedules: schedules,
        result: result!,
        periods: periods,
      ),
    );

    if (accepted == true) {
      try {
        await ref.read(apiClientProvider).post('/timetable/apply', data: {
          'schedule_ids': scheduleIds,
          'cells': result!.cells.map((c) => c.toJson()).toList(),
          'replace_existing': true,
        });
        for (final id in scheduleIds) {
          ref.invalidate(_gridProvider(id));
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
              'Horário aplicado: ${result!.cells.length} aulas em '
              '${schedules.length} turma(s)',
            ),
            backgroundColor: Colors.green,
          ));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('Erro ao aplicar: $e')));
        }
      }
    }
  }

  void _showPeriodsDialog() {
    showDialog(
      context: context,
      builder: (ctx) => _PeriodsDialog(
        canEdit: _canEdit,
        onChanged: () {},
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tab 0 — Requirements: all turmas for the year
// ---------------------------------------------------------------------------

class _RequirementsTab extends ConsumerWidget {
  final String yearId;
  final bool canEdit;
  const _RequirementsTab({required this.yearId, required this.canEdit});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schedulesAsync = ref.watch(_schedulesForYearProvider(yearId));

    return schedulesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: AppTheme.danger, size: 40),
            const SizedBox(height: 8),
            Text('Erro: $e'),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () => ref.invalidate(_schedulesForYearProvider(yearId)),
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
      data: (schedules) {
        if (schedules.isEmpty) {
          return _NoSchedulesSetup(yearId: yearId, canEdit: canEdit);
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
          itemCount: schedules.length,
          itemBuilder: (ctx, i) => _TurmaRequirementsCard(
            schedule: schedules[i],
            canEdit: canEdit,
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// No-schedules setup: list turmas + bulk-create schedules for the year
// ---------------------------------------------------------------------------

class _NoSchedulesSetup extends ConsumerStatefulWidget {
  final String yearId;
  final bool canEdit;
  const _NoSchedulesSetup({required this.yearId, required this.canEdit});

  @override
  ConsumerState<_NoSchedulesSetup> createState() => _NoSchedulesSetupState();
}

class _NoSchedulesSetupState extends ConsumerState<_NoSchedulesSetup> {
  bool _creating = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final turmasAsync = ref.watch(_turmasProvider);

    return Center(
      child: turmasAsync.when(
        loading: () => const CircularProgressIndicator(),
        error: (e, _) => Text('Erro ao carregar turmas: $e',
            style: const TextStyle(color: AppTheme.danger)),
        data: (turmas) {
          if (turmas.isEmpty) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.group_outlined,
                    size: 56, color: Colors.grey.shade300),
                const SizedBox(height: 12),
                const Text('Nenhuma turma criada.'),
                const SizedBox(height: 6),
                Text(
                  'Crie turmas primeiro em Académico → Turmas.',
                  style:
                      TextStyle(fontSize: 13, color: Colors.grey.shade500),
                ),
              ],
            );
          }
          return Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.table_chart_outlined,
                    size: 56, color: Colors.grey.shade300),
                const SizedBox(height: 16),
                Text(
                  'Nenhuma turma tem horário lectivo para este ano.',
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Crie os horários lectivos para as ${turmas.length} turma(s) de uma só vez:',
                  style:
                      TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                // Turma list preview
                Container(
                  constraints: const BoxConstraints(maxWidth: 320),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade200),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: turmas
                        .map((t) => ListTile(
                              dense: true,
                              leading: const Icon(Icons.class_outlined,
                                  size: 18),
                              title: Text(t.name),
                            ))
                        .toList(),
                  ),
                ),
                const SizedBox(height: 20),
                if (_error != null) ...[
                  Text(_error!,
                      style: const TextStyle(color: AppTheme.danger)),
                  const SizedBox(height: 12),
                ],
                if (widget.canEdit)
                  FilledButton.icon(
                    onPressed: _creating
                        ? null
                        : () => _createAll(turmas),
                    icon: _creating
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child:
                                CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.add_chart),
                    label: Text(
                        'Criar Horários para ${turmas.length} Turma(s)'),
                  )
                else
                  Text(
                    'Contacte um administrador para criar os horários.',
                    style: TextStyle(color: Colors.grey.shade500),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _createAll(List<_TurmaItem> turmas) async {
    setState(() {
      _creating = true;
      _error = null;
    });
    final api = ref.read(apiClientProvider);
    int created = 0;
    for (final turma in turmas) {
      try {
        await api.post('/academic/schedules', data: {
          'turma_id': turma.id,
          'school_year_id': widget.yearId,
        });
        created++;
      } catch (_) {
        // Ignore duplicates (409) — schedule may already exist
      }
    }
    if (mounted) {
      if (created == 0) {
        setState(() {
          _error = 'Não foi possível criar nenhum horário. Tente novamente.';
          _creating = false;
        });
      } else {
        ref.invalidate(_schedulesForYearProvider(widget.yearId));
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Per-turma expandable requirement card
// ---------------------------------------------------------------------------

class _TurmaRequirementsCard extends ConsumerStatefulWidget {
  final _ScheduleItem schedule;
  final bool canEdit;
  const _TurmaRequirementsCard(
      {required this.schedule, required this.canEdit});

  @override
  ConsumerState<_TurmaRequirementsCard> createState() =>
      _TurmaRequirementsCardState();
}

class _TurmaRequirementsCardState
    extends ConsumerState<_TurmaRequirementsCard> {
  @override
  Widget build(BuildContext context) {
    final reqsAsync = ref.watch(_requirementsProvider(widget.schedule.id));

    final totalPeriods = reqsAsync.valueOrNull
            ?.fold<int>(0, (s, r) => s + r.periodsPerWeek) ??
        0;
    final reqCount = reqsAsync.valueOrNull?.length ?? 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        initiallyExpanded: true,
        tilePadding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
        title: Text(
          widget.schedule.turmaName.isNotEmpty
              ? widget.schedule.turmaName
              : widget.schedule.id,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        subtitle: reqsAsync.when(
          data: (_) => Text(
            '$reqCount disciplina(s) · $totalPeriods aulas/semana',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          loading: () => const Text('A carregar…',
              style: TextStyle(fontSize: 12)),
          error: (_, __) => const Text('Erro ao carregar',
              style: TextStyle(fontSize: 12, color: AppTheme.danger)),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.canEdit)
              IconButton(
                icon: const Icon(Icons.add_circle_outline,
                    color: AppTheme.primary),
                tooltip: 'Adicionar requisito',
                onPressed: () => _addReq(context),
              ),
            const Icon(Icons.expand_more),
          ],
        ),
        children: [
          reqsAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: LinearProgressIndicator(),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Erro: $e',
                  style: const TextStyle(color: AppTheme.danger)),
            ),
            data: (reqs) => reqs.isEmpty
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    child: Row(
                      children: [
                        Text(
                          'Sem requisitos definidos.',
                          style: TextStyle(color: Colors.grey.shade500),
                        ),
                        if (widget.canEdit) ...[
                          const SizedBox(width: 12),
                          TextButton.icon(
                            onPressed: () => _addReq(context),
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('Adicionar'),
                          ),
                        ],
                      ],
                    ),
                  )
                : Column(
                    children: [
                      ...reqs.map(
                        (req) => _RequirementTile(
                          req: req,
                          onEdit: widget.canEdit
                              ? () => _editReq(context, req)
                              : () {},
                          onDelete: widget.canEdit
                              ? () => _deleteReq(context, req)
                              : () {},
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _addReq(BuildContext context) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => _AddRequirementDialog(
        scheduleId: widget.schedule.id,
        existing: null,
      ),
    );
    if (saved == true) {
      ref.invalidate(_requirementsProvider(widget.schedule.id));
    }
  }

  Future<void> _editReq(BuildContext context, _Requirement req) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => _AddRequirementDialog(
        scheduleId: widget.schedule.id,
        existing: req,
      ),
    );
    if (saved == true) {
      ref.invalidate(_requirementsProvider(widget.schedule.id));
    }
  }

  Future<void> _deleteReq(BuildContext context, _Requirement req) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover Requisito'),
        content: Text(
          'Remover "${req.subjectName ?? req.subjectId}" '
          '(${req.periodsPerWeek}×/semana)?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await ref
            .read(apiClientProvider)
            .delete('/timetable/requirements/${req.id}');
        ref.invalidate(_requirementsProvider(widget.schedule.id));
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('Erro: $e')));
        }
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Tab 1 — Grid: turma selector + week grid
// ---------------------------------------------------------------------------

class _GridTab extends ConsumerStatefulWidget {
  final String yearId;
  final bool canEdit;
  const _GridTab({required this.yearId, required this.canEdit});

  @override
  ConsumerState<_GridTab> createState() => _GridTabState();
}

class _GridTabState extends ConsumerState<_GridTab> {
  String? _selectedScheduleId;
  static const _days = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex'];

  @override
  Widget build(BuildContext context) {
    final schedulesAsync = ref.watch(_schedulesForYearProvider(widget.yearId));

    return Column(
      children: [
        // ── Turma selector ─────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: schedulesAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text('Erro: $e',
                style: const TextStyle(color: AppTheme.danger)),
            data: (schedules) {
              if (schedules.isEmpty) {
                return Text(
                  'Nenhuma turma com horário neste ano.',
                  style: TextStyle(color: Colors.grey.shade600),
                );
              }
              // Ensure selected id still valid in new list
              final valid = schedules
                  .where((s) => s.id == _selectedScheduleId)
                  .firstOrNull;
              return DropdownButtonFormField<String>(
                value: valid?.id,
                decoration: const InputDecoration(
                  labelText: 'Turma',
                  border: OutlineInputBorder(),
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                items: schedules
                    .map((s) => DropdownMenuItem(
                          value: s.id,
                          child: Text(
                            s.turmaName.isNotEmpty ? s.turmaName : s.id,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ))
                    .toList(),
                onChanged: (id) =>
                    setState(() => _selectedScheduleId = id),
              );
            },
          ),
        ),
        if (_selectedScheduleId != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () {
                  final schedules = ref
                      .read(_schedulesForYearProvider(widget.yearId))
                      .valueOrNull;
                  final s = schedules?.firstWhere(
                      (x) => x.id == _selectedScheduleId,
                      orElse: () => schedules!.first);
                  context.push(
                    '/lesson-attendance/summary/$_selectedScheduleId'
                    '?turmaName=${Uri.encodeComponent(s?.turmaName ?? '')}',
                  );
                },
                icon: const Icon(Icons.how_to_reg_outlined, size: 18),
                label: const Text('Ver Faltas'),
              ),
            ),
          ),
        const SizedBox(height: 12),
        // ── Grid ───────────────────────────────────────────────────────
        Expanded(
          child: _selectedScheduleId == null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.table_chart_outlined,
                          size: 64, color: Colors.grey.shade300),
                      const SizedBox(height: 12),
                      Text(
                        'Seleccione uma turma',
                        style: TextStyle(color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                )
              : ref
                  .watch(_gridProvider(_selectedScheduleId!))
                  .when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline,
                              size: 48, color: AppTheme.danger),
                          const SizedBox(height: 8),
                          Text(e.toString()),
                          const SizedBox(height: 12),
                          ElevatedButton.icon(
                            onPressed: () => ref
                                .invalidate(_gridProvider(_selectedScheduleId!)),
                            icon: const Icon(Icons.refresh),
                            label: const Text('Tentar novamente'),
                          ),
                        ],
                      ),
                    ),
                    data: _buildGrid,
                  ),
        ),
      ],
    );
  }

  Widget _buildGrid(_GridData grid) {
    final cellMap = <String, _Cell>{};
    for (final cell in grid.cells) {
      cellMap['${cell.periodId}_${cell.dayOfWeek}'] = cell;
    }

    const colWidth = 130.0;
    const rowHeaderWidth = 90.0;
    const cellHeight = 88.0;

    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Day header row
            Row(
              children: [
                const SizedBox(width: rowHeaderWidth),
                ..._days.asMap().entries.map((entry) => Container(
                      width: colWidth,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withAlpha(20),
                        border: Border(
                          bottom: BorderSide(color: Colors.grey.shade300),
                          right: BorderSide(color: Colors.grey.shade200),
                        ),
                      ),
                      child: Text(
                        _days[entry.key],
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primary,
                          fontSize: 13,
                        ),
                      ),
                    )),
              ],
            ),
            // Period rows
            ...grid.periods.map((period) => Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: rowHeaderWidth,
                      height: cellHeight,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        color: period.isBreak
                            ? Colors.grey.shade100
                            : Colors.white,
                        border: Border(
                          bottom: BorderSide(color: Colors.grey.shade200),
                          right: BorderSide(color: Colors.grey.shade300),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            period.name,
                            style: const TextStyle(
                                fontSize: 11, fontWeight: FontWeight.bold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            period.startTime.substring(0, 5),
                            style: TextStyle(
                                fontSize: 10, color: Colors.grey.shade600),
                          ),
                          Text(
                            period.endTime.substring(0, 5),
                            style: TextStyle(
                                fontSize: 10, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                    ...List.generate(5, (dayIdx) {
                      if (period.isBreak) {
                        return _BreakCell(
                            width: colWidth, height: cellHeight);
                      }
                      final cell = cellMap['${period.id}_$dayIdx'];
                      return _GridCell(
                        width: colWidth,
                        height: cellHeight,
                        cell: cell,
                        canEdit: widget.canEdit,
                        onTap: widget.canEdit
                            ? () => _showCellDialog(
                                  grid.scheduleId,
                                  period,
                                  dayIdx,
                                  cell,
                                )
                            : null,
                      );
                    }),
                  ],
                )),
          ],
        ),
      ),
    );
  }

  Future<void> _showCellDialog(
    String scheduleId,
    _Period period,
    int dayOfWeek,
    _Cell? existing,
  ) async {
    final roomCtrl = TextEditingController(text: existing?.room ?? '');

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => _CellEditDialog(
        period: period,
        dayLabel: _days[dayOfWeek],
        initialSubjectId: existing?.subjectId,
        initialEmployeeId: existing?.employeeId,
        roomController: roomCtrl,
        onSave: (sid, eid, room) async {
          await ref.read(apiClientProvider).post('/timetable/grid/cells', data: {
            'schedule_id': scheduleId,
            'day_of_week': dayOfWeek,
            'period_id': period.id,
            'subject_id': sid,
            'employee_id': eid,
            'room': room?.isEmpty == true ? null : room,
          });
        },
        onClear: existing != null
            ? () async {
                await ref
                    .read(apiClientProvider)
                    .delete('/timetable/grid/cells/${existing.id}');
              }
            : null,
      ),
    );

    if (result == true) {
      ref.invalidate(_gridProvider(scheduleId));
    }
  }
}

// ---------------------------------------------------------------------------
// Break cell widget
// ---------------------------------------------------------------------------

class _BreakCell extends StatelessWidget {
  final double width;
  final double height;
  const _BreakCell({required this.width, required this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade200),
          right: BorderSide(color: Colors.grey.shade200),
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        'Intervalo',
        style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Grid cell widget
// ---------------------------------------------------------------------------

class _GridCell extends StatelessWidget {
  final double width;
  final double height;
  final _Cell? cell;
  final bool canEdit;
  final VoidCallback? onTap;

  const _GridCell({
    required this.width,
    required this.height,
    required this.cell,
    required this.canEdit,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isEmpty = cell?.subjectId == null;
    final color = _colorForSubject(cell?.subjectId);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: isEmpty ? Colors.white : color.withAlpha(18),
          border: Border(
            bottom: BorderSide(color: Colors.grey.shade200),
            right: BorderSide(color: Colors.grey.shade200),
            left: isEmpty ? BorderSide.none : BorderSide(color: color, width: 3),
          ),
        ),
        child: isEmpty
            ? canEdit
                ? Center(
                    child: Icon(Icons.add,
                        size: 18, color: Colors.grey.shade300))
                : null
            : Padding(
                padding: const EdgeInsets.fromLTRB(6, 6, 6, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cell!.subjectCode ?? cell!.subjectName ?? '',
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (cell!.subjectCode != null && cell!.subjectName != null)
                      Text(
                        cell!.subjectName!,
                        style: TextStyle(
                            fontSize: 10, color: Colors.grey.shade700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    const SizedBox(height: 2),
                    if (cell!.employeeName != null)
                      Text(
                        cell!.employeeName!,
                        style: TextStyle(
                            fontSize: 10, color: Colors.grey.shade600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    if (cell!.room != null)
                      Text(
                        'Sala ${cell!.room}',
                        style: TextStyle(
                            fontSize: 10, color: Colors.grey.shade500),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Cell edit dialog
// ---------------------------------------------------------------------------

class _CellEditDialog extends ConsumerStatefulWidget {
  final _Period period;
  final String dayLabel;
  final String? initialSubjectId;
  final String? initialEmployeeId;
  final TextEditingController roomController;
  final Future<void> Function(String? subjectId, String? employeeId, String? room) onSave;
  final Future<void> Function()? onClear;

  const _CellEditDialog({
    required this.period,
    required this.dayLabel,
    required this.initialSubjectId,
    required this.initialEmployeeId,
    required this.roomController,
    required this.onSave,
    this.onClear,
  });

  @override
  ConsumerState<_CellEditDialog> createState() => _CellEditDialogState();
}

class _CellEditDialogState extends ConsumerState<_CellEditDialog> {
  late String? _subjectId;
  late String? _employeeId;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _subjectId = widget.initialSubjectId;
    _employeeId = widget.initialEmployeeId;
  }

  @override
  Widget build(BuildContext context) {
    final subjectsAsync = ref.watch(_subjectsProvider);
    final teachersAsync = ref.watch(_teachersProvider);

    return AlertDialog(
      title: Text('${widget.dayLabel} — ${widget.period.name}'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.danger.withAlpha(20),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_error!,
                    style: const TextStyle(color: AppTheme.danger)),
              ),
              const SizedBox(height: 12),
            ],
            subjectsAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('Erro ao carregar disciplinas: $e'),
              data: (subjects) => DropdownButtonFormField<String>(
                value: _subjectId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Disciplina',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  const DropdownMenuItem(
                      value: null, child: Text('— Nenhuma —')),
                  ...subjects.map((s) => DropdownMenuItem(
                        value: s.id,
                        child: Text(
                          s.code != null ? '${s.code} — ${s.name}' : s.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      )),
                ],
                onChanged: (v) => setState(() => _subjectId = v),
              ),
            ),
            const SizedBox(height: 12),
            teachersAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('Erro ao carregar professores: $e'),
              data: (teachers) => DropdownButtonFormField<String>(
                value: _employeeId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Professor',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  const DropdownMenuItem(
                      value: null, child: Text('— Nenhum —')),
                  ...teachers.map((t) => DropdownMenuItem(
                        value: t.id,
                        child: Text(t.name, overflow: TextOverflow.ellipsis),
                      )),
                ],
                onChanged: (v) => setState(() => _employeeId = v),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: widget.roomController,
              decoration: const InputDecoration(
                labelText: 'Sala (opcional)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
      ),
      actionsAlignment: widget.onClear != null
          ? MainAxisAlignment.spaceBetween
          : MainAxisAlignment.end,
      actions: [
        if (widget.onClear != null)
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppTheme.danger),
            onPressed: _saving ? null : _clear,
            child: const Text('Limpar'),
          ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              onPressed:
                  _saving ? null : () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Guardar'),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(_subjectId, _employeeId, widget.roomController.text);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _error = e.toString();
        _saving = false;
      });
    }
  }

  Future<void> _clear() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onClear!();
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _error = e.toString();
        _saving = false;
      });
    }
  }
}

// ---------------------------------------------------------------------------
// Periods management dialog
// ---------------------------------------------------------------------------

class _PeriodsDialog extends ConsumerStatefulWidget {
  final bool canEdit;
  final VoidCallback onChanged;
  const _PeriodsDialog({required this.canEdit, required this.onChanged});

  @override
  ConsumerState<_PeriodsDialog> createState() => _PeriodsDialogState();
}

class _PeriodsDialogState extends ConsumerState<_PeriodsDialog> {
  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_periodsListProvider);

    return AlertDialog(
      title: const Text('Períodos Lectivos'),
      content: SizedBox(
        width: 440,
        child: async.when(
          loading: () => const Center(
              child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator())),
          error: (e, _) => Text('Erro: $e'),
          data: (periods) => periods.isEmpty
              ? const Text('Nenhum período definido.')
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: periods.length,
                  itemBuilder: (ctx, i) {
                    final p = periods[i];
                    return ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        radius: 14,
                        backgroundColor: p.isBreak
                            ? Colors.grey.shade200
                            : AppTheme.primary.withAlpha(30),
                        child: Text(
                          p.number.toString(),
                          style: TextStyle(
                            fontSize: 11,
                            color: p.isBreak
                                ? Colors.grey.shade600
                                : AppTheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      title: Text(p.name),
                      subtitle: Text(
                          '${p.startTime.substring(0, 5)} – ${p.endTime.substring(0, 5)}'
                          '${p.isBreak ? '  (Intervalo)' : ''}'),
                      trailing: widget.canEdit
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit_outlined,
                                      size: 18),
                                  tooltip: 'Editar',
                                  onPressed: () =>
                                      _showPeriodForm(context, p),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outlined,
                                      size: 18, color: AppTheme.danger),
                                  tooltip: 'Eliminar',
                                  onPressed: () => _delete(p),
                                ),
                              ],
                            )
                          : null,
                    );
                  },
                ),
        ),
      ),
      actions: [
        if (widget.canEdit)
          TextButton.icon(
            onPressed: () => _showPeriodForm(context, null),
            icon: const Icon(Icons.add),
            label: const Text('Novo Período'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Fechar'),
        ),
      ],
    );
  }

  Future<void> _showPeriodForm(BuildContext ctx, _Period? existing) async {
    final numCtrl =
        TextEditingController(text: existing?.number.toString() ?? '');
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final startCtrl = TextEditingController(
        text: existing?.startTime.substring(0, 5) ?? '');
    final endCtrl =
        TextEditingController(text: existing?.endTime.substring(0, 5) ?? '');
    bool isBreak = existing?.isBreak ?? false;
    String? error;

    final saved = await showDialog<bool>(
      context: ctx,
      builder: (dctx) => StatefulBuilder(
        builder: (dctx, setS) => AlertDialog(
          title: Text(existing == null ? 'Novo Período' : 'Editar Período'),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (error != null) ...[
                  Text(error!,
                      style: const TextStyle(color: AppTheme.danger)),
                  const SizedBox(height: 8),
                ],
                if (existing == null)
                  TextFormField(
                    controller: numCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Nº do período',
                        border: OutlineInputBorder(),
                        isDense: true),
                    keyboardType: TextInputType.number,
                  ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Nome (ex: 1ª Aula)',
                      border: OutlineInputBorder(),
                      isDense: true),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: startCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Início (HH:MM)',
                      border: OutlineInputBorder(),
                      isDense: true),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: endCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Fim (HH:MM)',
                      border: OutlineInputBorder(),
                      isDense: true),
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Intervalo (sem disciplinas)'),
                  value: isBreak,
                  onChanged: (v) => setS(() => isBreak = v ?? false),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dctx).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () async {
                final api = ref.read(apiClientProvider);
                try {
                  final body = {
                    if (existing == null)
                      'period_number': int.parse(numCtrl.text),
                    'name': nameCtrl.text,
                    'start_time': '${startCtrl.text}:00',
                    'end_time': '${endCtrl.text}:00',
                    'is_break': isBreak,
                  };
                  if (existing == null) {
                    await api.post('/timetable/periods', data: body);
                  } else {
                    await api.patch(
                        '/timetable/periods/${existing.id}', data: body);
                  }
                  if (dctx.mounted) Navigator.of(dctx).pop(true);
                } catch (e) {
                  setS(() => error = e.toString());
                }
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );

    if (saved == true) {
      ref.invalidate(_periodsListProvider);
      widget.onChanged();
    }
  }

  Future<void> _delete(_Period p) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar Período'),
        content: Text('Eliminar "${p.name}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await ref.read(apiClientProvider).delete('/timetable/periods/${p.id}');
      ref.invalidate(_periodsListProvider);
      widget.onChanged();
    }
  }
}

// ---------------------------------------------------------------------------
// Requirement tile
// ---------------------------------------------------------------------------

class _RequirementTile extends StatelessWidget {
  final _Requirement req;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _RequirementTile({
    required this.req,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final color = _colorForSubject(req.subjectId);
    final timeLabel = switch (req.preferredTimeOfDay) {
      'morning' => '☀ Manhã',
      'afternoon' => '🌆 Tarde',
      _ => null,
    };
    return ListTile(
      dense: true,
      leading: CircleAvatar(
        backgroundColor: color.withAlpha(30),
        child: Text(
          req.periodsPerWeek.toString(),
          style: TextStyle(
              color: color, fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ),
      title: Text(
        req.subjectCode != null
            ? '${req.subjectCode} — ${req.subjectName ?? ''}'
            : (req.subjectName ?? req.subjectId),
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
      ),
      subtitle: Text(
        [
          req.employeeName ?? 'Professor não definido',
          '${req.periodsPerWeek}×/sem',
          if (req.allowDoublePeriod) 'Dupla',
          if (timeLabel != null) timeLabel,
        ].join(' · '),
        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 17),
            onPressed: onEdit,
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline,
                size: 17, color: AppTheme.danger),
            onPressed: onDelete,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Add / Edit requirement dialog
// ---------------------------------------------------------------------------

class _AddRequirementDialog extends ConsumerStatefulWidget {
  final String scheduleId;
  final _Requirement? existing;
  const _AddRequirementDialog(
      {required this.scheduleId, required this.existing});

  @override
  ConsumerState<_AddRequirementDialog> createState() =>
      _AddRequirementDialogState();
}

class _AddRequirementDialogState
    extends ConsumerState<_AddRequirementDialog> {
  String? _subjectId;
  String? _employeeId;
  int _periodsPerWeek = 2;
  bool _allowDouble = false;
  String? _preferredTime;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      final e = widget.existing!;
      _subjectId = e.subjectId;
      _employeeId = e.employeeId;
      _periodsPerWeek = e.periodsPerWeek;
      _allowDouble = e.allowDoublePeriod;
      _preferredTime = e.preferredTimeOfDay;
    }
  }

  @override
  Widget build(BuildContext context) {
    final subjectsAsync = ref.watch(_subjectsProvider);
    final teachersAsync = ref.watch(_teachersProvider);
    final isEdit = widget.existing != null;

    return AlertDialog(
      title: Text(isEdit ? 'Editar Requisito' : 'Novo Requisito'),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.danger.withAlpha(20),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(_error!,
                      style: const TextStyle(color: AppTheme.danger)),
                ),
                const SizedBox(height: 12),
              ],
              subjectsAsync.when(
                loading: () => const LinearProgressIndicator(),
                error: (e, _) =>
                    Text('Erro ao carregar disciplinas: $e'),
                data: (subjects) => DropdownButtonFormField<String>(
                  value: _subjectId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Disciplina *',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: subjects
                      .map((s) => DropdownMenuItem(
                            value: s.id,
                            child: Text(
                              s.code != null
                                  ? '${s.code} — ${s.name}'
                                  : s.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ))
                      .toList(),
                  onChanged: isEdit
                      ? null
                      : (v) => setState(() => _subjectId = v),
                ),
              ),
              const SizedBox(height: 12),
              teachersAsync.when(
                loading: () => const LinearProgressIndicator(),
                error: (e, _) =>
                    Text('Erro ao carregar professores: $e'),
                data: (teachers) => DropdownButtonFormField<String>(
                  value: _employeeId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Professor *',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: teachers
                      .map((t) => DropdownMenuItem(
                            value: t.id,
                            child: Text(t.name,
                                overflow: TextOverflow.ellipsis),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _employeeId = v),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Text('Aulas por semana:',
                      style: TextStyle(fontSize: 13)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: _periodsPerWeek > 1
                        ? () => setState(() => _periodsPerWeek--)
                        : null,
                  ),
                  Text(
                    '$_periodsPerWeek',
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: _periodsPerWeek < 10
                        ? () => setState(() => _periodsPerWeek++)
                        : null,
                  ),
                ],
              ),
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text(
                    'Permitir aula dupla (2 períodos seguidos)',
                    style: TextStyle(fontSize: 13)),
                value: _allowDouble,
                onChanged: (v) =>
                    setState(() => _allowDouble = v ?? false),
              ),
              const SizedBox(height: 4),
              const Text('Preferência de horário:',
                  style: TextStyle(fontSize: 13)),
              const SizedBox(height: 6),
              SegmentedButton<String?>(
                segments: const [
                  ButtonSegment(value: null, label: Text('Qualquer')),
                  ButtonSegment(value: 'morning', label: Text('Manhã')),
                  ButtonSegment(value: 'afternoon', label: Text('Tarde')),
                ],
                selected: {_preferredTime},
                onSelectionChanged: (s) =>
                    setState(() => _preferredTime = s.first),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed:
              _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Guardar'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (_subjectId == null) {
      setState(() => _error = 'Seleccione uma disciplina.');
      return;
    }
    if (_employeeId == null) {
      setState(() => _error = 'Seleccione um professor.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      if (widget.existing == null) {
        await api.post('/timetable/requirements', data: {
          'schedule_id': widget.scheduleId,
          'subject_id': _subjectId,
          'employee_id': _employeeId,
          'periods_per_week': _periodsPerWeek,
          'allow_double_period': _allowDouble,
          'preferred_time_of_day': _preferredTime,
        });
      } else {
        await api.patch(
          '/timetable/requirements/${widget.existing!.id}',
          data: {
            'employee_id': _employeeId,
            'periods_per_week': _periodsPerWeek,
            'allow_double_period': _allowDouble,
            'preferred_time_of_day': _preferredTime,
          },
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _error = e.toString();
        _saving = false;
      });
    }
  }
}

// ---------------------------------------------------------------------------
// Generate preview dialog — multi-schedule with turma selector
// ---------------------------------------------------------------------------

class _PreviewDialog extends StatefulWidget {
  final List<_ScheduleItem> schedules;
  final _GenerateResult result;
  final List<_Period> periods;
  const _PreviewDialog({
    required this.schedules,
    required this.result,
    required this.periods,
  });

  @override
  State<_PreviewDialog> createState() => _PreviewDialogState();
}

class _PreviewDialogState extends State<_PreviewDialog> {
  bool _showConflicts = true;
  String? _viewingScheduleId;
  static const _days = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex'];

  @override
  void initState() {
    super.initState();
    if (widget.schedules.isNotEmpty) {
      _viewingScheduleId = widget.schedules.first.id;
    }
  }

  @override
  Widget build(BuildContext context) {
    final allCells = widget.result.cells;
    final conflicts = widget.result.conflicts;
    final status = widget.result.status;

    // Filter cells for the currently-viewed schedule
    final viewCells = _viewingScheduleId == null
        ? allCells
        : allCells.where((c) => c.scheduleId == _viewingScheduleId).toList();

    final fakeCells = viewCells
        .map((c) => _Cell(
              id: -1,
              dayOfWeek: c.dayOfWeek,
              periodId: c.periodId,
              subjectId: c.subjectId,
              subjectName: c.subjectName,
              employeeId: c.employeeId,
              employeeName: c.employeeName,
            ))
        .toList();

    final cellMap = <String, _Cell>{};
    for (final cell in fakeCells) {
      cellMap['${cell.periodId}_${cell.dayOfWeek}'] = cell;
    }

    final (statusLabel, statusColor) = switch (status) {
      'optimal' => ('Óptimo — sem conflitos', Colors.green),
      'feasible' => ('Solução encontrada', Colors.green),
      'partial' => ('Parcial — ${conflicts.length} conflito(s)', Colors.orange),
      _ => ('Insolúvel', AppTheme.danger),
    };

    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          title: const Text('Proposta do Motor'),
          actions: [
            if (conflicts.isNotEmpty)
              IconButton(
                icon: Badge(
                  label: Text('${conflicts.length}'),
                  child: Icon(
                    Icons.warning_amber_outlined,
                    color: conflicts.isEmpty ? Colors.green : Colors.orange,
                  ),
                ),
                tooltip: 'Ver conflitos',
                onPressed: () =>
                    setState(() => _showConflicts = !_showConflicts),
              ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: allCells.isEmpty
                  ? null
                  : () => Navigator.of(context).pop(true),
              icon: const Icon(Icons.check),
              label: const Text('Aceitar e Aplicar'),
            ),
            const SizedBox(width: 12),
          ],
        ),
        body: Column(
          children: [
            // ── Status banner ────────────────────────────────────────────
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: statusColor.withAlpha(25),
              child: Row(
                children: [
                  Icon(
                    status == 'partial' || status == 'infeasible'
                        ? Icons.warning_amber_rounded
                        : Icons.check_circle_outline,
                    color: statusColor,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    statusLabel,
                    style: TextStyle(
                        color: statusColor, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  Text(
                    '${allCells.length} aulas · ${widget.schedules.length} turma(s)',
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),

            // ── Conflicts panel ──────────────────────────────────────────
            if (conflicts.isNotEmpty && _showConflicts)
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxHeight: 160),
                color: Colors.orange.withAlpha(15),
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  itemCount: conflicts.length,
                  itemBuilder: (ctx, i) {
                    final c = conflicts[i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.warning_amber_outlined,
                              size: 16, color: Colors.orange),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${c.subjectName} · ${c.employeeName} — '
                                  '${c.periodsAssigned}/${c.periodsRequested} aulas alocadas',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600),
                                ),
                                Text(
                                  c.reason,
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade700),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),

            // ── Turma selector (multi-schedule) ─────────────────────────
            if (widget.schedules.length > 1)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: DropdownButtonFormField<String>(
                  value: _viewingScheduleId,
                  decoration: const InputDecoration(
                    labelText: 'Ver turma',
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  items: widget.schedules
                      .map((s) => DropdownMenuItem(
                            value: s.id,
                            child: Text(
                              '${s.turmaName.isNotEmpty ? s.turmaName : s.id}'
                              ' (${allCells.where((c) => c.scheduleId == s.id).length} aulas)',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ))
                      .toList(),
                  onChanged: (id) =>
                      setState(() => _viewingScheduleId = id),
                ),
              ),

            // ── Grid preview ─────────────────────────────────────────────
            Expanded(
              child: allCells.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.block,
                              size: 56, color: Colors.grey.shade300),
                          const SizedBox(height: 12),
                          const Text(
                              'Não foi possível gerar nenhuma alocação.'),
                          const SizedBox(height: 8),
                          Text(
                            'Verifique os requisitos e a disponibilidade dos professores.',
                            style:
                                TextStyle(color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    )
                  : _buildPreviewGrid(cellMap),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewGrid(Map<String, _Cell> cellMap) {
    final periods = widget.periods;
    const colWidth = 130.0;
    const rowHeaderWidth = 90.0;
    const cellHeight = 88.0;

    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const SizedBox(width: rowHeaderWidth),
                ..._days.asMap().entries.map((e) => Container(
                      width: colWidth,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withAlpha(20),
                        border: Border(
                          bottom: BorderSide(color: Colors.grey.shade300),
                          right: BorderSide(color: Colors.grey.shade200),
                        ),
                      ),
                      child: Text(
                        _days[e.key],
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primary,
                          fontSize: 13,
                        ),
                      ),
                    )),
              ],
            ),
            ...periods.map((period) => Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: rowHeaderWidth,
                      height: cellHeight,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        color: period.isBreak
                            ? Colors.grey.shade100
                            : Colors.white,
                        border: Border(
                          bottom: BorderSide(color: Colors.grey.shade200),
                          right: BorderSide(color: Colors.grey.shade300),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(period.name,
                              style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          Text(period.startTime.substring(0, 5),
                              style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey.shade600)),
                        ],
                      ),
                    ),
                    ...List.generate(5, (dayIdx) {
                      if (period.isBreak) {
                        return _BreakCell(
                            width: colWidth, height: cellHeight);
                      }
                      final cell = cellMap['${period.id}_$dayIdx'];
                      return _GridCell(
                        width: colWidth,
                        height: cellHeight,
                        cell: cell,
                        canEdit: false,
                        onTap: null,
                      );
                    }),
                  ],
                )),
          ],
        ),
      ),
    );
  }
}
