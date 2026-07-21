/// K-12 Timetable screen — week grid: period rows × Mon–Fri columns.
///
/// Admin / Coordinator: tap any cell to assign subject, teacher, room.
/// Teacher: read-only view of the grid.
///
/// Data flow:
///   1. Load turmas list
///   2. User selects a turma → load schedules for that turma
///   3. User selects a schedule → load timetable grid
///   4. Grid shows periods (rows) × days (columns) × cells (subject/teacher/room)
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/auth/auth_state.dart';
import '../../../core/theme/app_theme.dart';

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

class _TurmaItem {
  final String id;
  final String name;
  const _TurmaItem({required this.id, required this.name});
  factory _TurmaItem.fromJson(Map<String, dynamic> j) =>
      _TurmaItem(id: j['id'] as String, name: j['name'] as String);
}

class _ScheduleItem {
  final String id;
  final String? label;
  const _ScheduleItem({required this.id, this.label});
  factory _ScheduleItem.fromJson(Map<String, dynamic> j) => _ScheduleItem(
        id: j['id'] as String,
        label: [j['school_year_label'], j['turma_name']]
            .where((v) => v != null && (v as String).isNotEmpty)
            .cast<String>()
            .join(' — '),
      );
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

class _EmployeeItem {
  final String id;
  final String name;
  const _EmployeeItem({required this.id, required this.name});
  factory _EmployeeItem.fromJson(Map<String, dynamic> j) {
    final first = j['first_name'] as String? ?? '';
    final last = j['last_name'] as String? ?? '';
    return _EmployeeItem(
      id: j['id'] as String,
      name: '$first $last'.trim(),
    );
  }
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

final _turmasProvider = FutureProvider.autoDispose<List<_TurmaItem>>((ref) async {
  final data = await ref.read(apiClientProvider).get('/academic/turmas') as List;
  return data.map((e) => _TurmaItem.fromJson(e as Map<String, dynamic>)).toList();
});

final _schedulesForTurmaProvider =
    FutureProvider.autoDispose.family<List<_ScheduleItem>, String>((ref, turmaId) async {
  final data = await ref
      .read(apiClientProvider)
      .get('/academic/schedules?turma_id=$turmaId') as List;
  return data.map((e) => _ScheduleItem.fromJson(e as Map<String, dynamic>)).toList();
});

final _gridProvider =
    FutureProvider.autoDispose.family<_GridData, String>((ref, scheduleId) async {
  final api = ref.read(apiClientProvider);
  final raw = await api.get('/timetable/grid?schedule_id=$scheduleId') as Map<String, dynamic>;
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

// ---------------------------------------------------------------------------
// Deterministic subject color palette
// ---------------------------------------------------------------------------

const _subjectColors = [
  Color(0xFF1565C0), // blue-800
  Color(0xFF2E7D32), // green-800
  Color(0xFF6A1B9A), // purple-800
  Color(0xFFAD1457), // pink-800
  Color(0xFFE65100), // orange-800
  Color(0xFF00695C), // teal-800
  Color(0xFF4527A0), // deep-purple-800
  Color(0xFF558B2F), // light-green-800
  Color(0xFF0277BD), // light-blue-800
  Color(0xFF827717), // lime-900
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

class _TimetableScreenState extends ConsumerState<TimetableScreen> {
  _TurmaItem? _selectedTurma;
  _ScheduleItem? _selectedSchedule;

  static const _days = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex'];

  bool get _canEdit {
    final auth = ref.read(authProvider);
    return auth.hasAnyRole([UserRole.schoolAdmin, UserRole.coordinator]);
  }

  @override
  Widget build(BuildContext context) {
    final turmasAsync = ref.watch(_turmasProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Horário Lectivo'),
        actions: [
          if (_selectedSchedule != null)
            IconButton(
              icon: const Icon(Icons.access_time_outlined),
              tooltip: 'Períodos',
              onPressed: () => _showPeriodsDialog(),
            ),
        ],
      ),
      body: Column(
        children: [
          // ── Selectors ──────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: turmasAsync.when(
                    loading: () => const LinearProgressIndicator(),
                    error: (e, _) => Text('Erro: $e',
                        style: const TextStyle(color: AppTheme.danger)),
                    data: (turmas) => DropdownButtonFormField<_TurmaItem>(
                      value: _selectedTurma,
                      decoration: const InputDecoration(
                        labelText: 'Turma',
                        border: OutlineInputBorder(),
                        isDense: true,
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      items: turmas
                          .map((t) => DropdownMenuItem(
                              value: t, child: Text(t.name)))
                          .toList(),
                      onChanged: (t) => setState(() {
                        _selectedTurma = t;
                        _selectedSchedule = null;
                      }),
                    ),
                  ),
                ),
                if (_selectedTurma != null) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: ref
                        .watch(_schedulesForTurmaProvider(_selectedTurma!.id))
                        .when(
                          loading: () => const LinearProgressIndicator(),
                          error: (e, _) => Text('Erro: $e'),
                          data: (schedules) =>
                              DropdownButtonFormField<_ScheduleItem>(
                            value: _selectedSchedule,
                            decoration: const InputDecoration(
                              labelText: 'Horário',
                              border: OutlineInputBorder(),
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                            ),
                            items: schedules
                                .map((s) => DropdownMenuItem(
                                    value: s,
                                    child: Text(s.label ?? s.id,
                                        overflow: TextOverflow.ellipsis)))
                                .toList(),
                            onChanged: (s) =>
                                setState(() => _selectedSchedule = s),
                          ),
                        ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          // ── Grid ──────────────────────────────────────────────────────────
          Expanded(
            child: _selectedSchedule == null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.table_chart_outlined,
                            size: 64, color: Colors.grey.shade300),
                        const SizedBox(height: 12),
                        Text(
                          _selectedTurma == null
                              ? 'Seleccione uma turma'
                              : 'Seleccione um horário',
                          style: TextStyle(color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                  )
                : ref.watch(_gridProvider(_selectedSchedule!.id)).when(
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
                              onPressed: () => ref.invalidate(
                                  _gridProvider(_selectedSchedule!.id)),
                              icon: const Icon(Icons.refresh),
                              label: const Text('Tentar novamente'),
                            ),
                          ],
                        ),
                      ),
                      data: (grid) => _buildGrid(grid),
                    ),
          ),
        ],
      ),
    );
  }

  Widget _buildGrid(_GridData grid) {
    // Build lookup: periodId × dayOfWeek → _Cell
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
            // ── Day header row ────────────────────────────────────────────
            Row(
              children: [
                SizedBox(width: rowHeaderWidth), // period label space
                ..._days.asMap().entries.map((entry) {
                  return Container(
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
                  );
                }),
              ],
            ),
            // ── Period rows ───────────────────────────────────────────────
            ...grid.periods.map((period) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Period label
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
                  // Day cells
                  ...List.generate(5, (dayIdx) {
                    final cell = cellMap['${period.id}_$dayIdx'];
                    if (period.isBreak) {
                      return _BreakCell(
                          width: colWidth, height: cellHeight);
                    }
                    return _GridCell(
                      width: colWidth,
                      height: cellHeight,
                      cell: cell,
                      canEdit: _canEdit,
                      onTap: _canEdit
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
              );
            }),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Cell edit dialog
  // ---------------------------------------------------------------------------

  Future<void> _showCellDialog(
    String scheduleId,
    _Period period,
    int dayOfWeek,
    _Cell? existing,
  ) async {
    String? subjectId = existing?.subjectId;
    String? employeeId = existing?.employeeId;
    final roomCtrl = TextEditingController(text: existing?.room ?? '');

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => _CellEditDialog(
        period: period,
        dayLabel: _days[dayOfWeek],
        initialSubjectId: subjectId,
        initialEmployeeId: employeeId,
        roomController: roomCtrl,
        onSave: (sid, eid, room) async {
          final api = ref.read(apiClientProvider);
          await api.post('/timetable/grid/cells', data: {
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
                final api = ref.read(apiClientProvider);
                await api.delete('/timetable/grid/cells/${existing.id}');
              }
            : null,
      ),
    );

    if (result == true) {
      ref.invalidate(_gridProvider(scheduleId));
    }
  }

  // ---------------------------------------------------------------------------
  // Periods management dialog
  // ---------------------------------------------------------------------------

  void _showPeriodsDialog() {
    showDialog(
      context: context,
      builder: (ctx) => _PeriodsDialog(
        canEdit: _canEdit,
        onChanged: () {
          if (_selectedSchedule != null) {
            ref.invalidate(_gridProvider(_selectedSchedule!.id));
          }
        },
      ),
    );
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
            left: isEmpty
                ? BorderSide.none
                : BorderSide(color: color, width: 3),
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
                    if (cell!.subjectCode != null &&
                        cell!.subjectName != null)
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
              error: (e, _) =>
                  Text('Erro ao carregar disciplinas: $e'),
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
              error: (e, _) =>
                  Text('Erro ao carregar professores: $e'),
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
                        child: Text(t.name,
                            overflow: TextOverflow.ellipsis),
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
              onPressed: _saving
                  ? null
                  : () => Navigator.of(context).pop(false),
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
      await widget.onSave(
          _subjectId, _employeeId, widget.roomController.text);
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
// Periods management dialog (admin: create/edit periods)
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
