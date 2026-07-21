import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/theme/app_theme.dart';

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------
class Schedule {
  final String id;
  final String turmaId;
  final String schoolYearId;
  final String? turmaName;
  final String? schoolYearLabel;
  final List<ScheduleSlot> slots;

  const Schedule({
    required this.id,
    required this.turmaId,
    required this.schoolYearId,
    this.turmaName,
    this.schoolYearLabel,
    this.slots = const [],
  });

  factory Schedule.fromJson(Map<String, dynamic> json) {
    final rawSlots = json['slots'] as List<dynamic>? ?? [];
    return Schedule(
      id: json['id']?.toString() ?? '',
      turmaId: json['turma_id']?.toString() ?? '',
      schoolYearId: json['school_year_id']?.toString() ?? '',
      turmaName: json['turma_name'] as String?,
      schoolYearLabel: json['school_year_label'] as String?,
      slots: rawSlots
          .map((e) => ScheduleSlot.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class ScheduleSlot {
  final int id;
  final String scheduleId;
  final int dayOfWeek;
  final String slotTime;
  final String? activityId;
  final String? activityName;

  const ScheduleSlot({
    required this.id,
    required this.scheduleId,
    required this.dayOfWeek,
    required this.slotTime,
    this.activityId,
    this.activityName,
  });

  factory ScheduleSlot.fromJson(Map<String, dynamic> json) {
    return ScheduleSlot(
      id: (json['id'] as num?)?.toInt() ?? 0,
      scheduleId: json['schedule_id']?.toString() ?? '',
      dayOfWeek: (json['day_of_week'] as num?)?.toInt() ?? 1,
      slotTime: json['slot_time']?.toString() ?? '',
      activityId: json['activity_id']?.toString(),
      activityName: json['activity_name'] as String?,
    );
  }
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------
final schedulesProvider =
    FutureProvider.autoDispose<List<Schedule>>((ref) async {
  final api = ref.read(apiClientProvider);
  final data = await api.get('/academic/schedules') as List;
  return data
      .map((e) => Schedule.fromJson(e as Map<String, dynamic>))
      .toList();
});

final _activitiesForScheduleProvider =
    FutureProvider.autoDispose<List<Map<String, String>>>((ref) async {
  final api = ref.read(apiClientProvider);
  final data = await api.get('/academic/activities') as List;
  return data.map((e) {
    final m = e as Map<String, dynamic>;
    return {
      'id': m['id']?.toString() ?? '',
      'name': m['name']?.toString() ?? ''
    };
  }).toList();
});

// ---------------------------------------------------------------------------
// Main list screen
// ---------------------------------------------------------------------------
class SchedulesScreen extends ConsumerWidget {
  const SchedulesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schedulesAsync = ref.watch(schedulesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Horários')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCreateSheet(context, ref),
        tooltip: 'Novo Horário',
        child: const Icon(Icons.add),
      ),
      body: schedulesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 8),
              Text(e.toString()),
              TextButton(
                onPressed: () => ref.invalidate(schedulesProvider),
                child: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
        data: (schedules) {
          if (schedules.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.table_chart_outlined,
                      size: 64,
                      color: Theme.of(context).colorScheme.outlineVariant),
                  const SizedBox(height: 16),
                  Text('Nenhum horário criado',
                      style: Theme.of(context).textTheme.bodyLarge),
                  const SizedBox(height: 8),
                  const Text(
                    'Crie primeiro uma Turma e um Ano Lectivo\nem Configurações, depois adicione um Horário.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: schedules.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final s = schedules[i];
              return Card(
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppTheme.primaryLight,
                    child: const Icon(Icons.table_chart,
                        color: AppTheme.primary, size: 20),
                  ),
                  title: Text(
                    s.turmaName ?? 'Turma',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(s.schoolYearLabel ?? ''),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Chip(
                        label: Text('${s.slots.length} blocos',
                            style: const TextStyle(fontSize: 11)),
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 20),
                        onPressed: () => _confirmDelete(context, ref, s),
                      ),
                    ],
                  ),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => _TimetableDetailScreen(schedule: s),
                    ),
                  ).then((_) => ref.invalidate(schedulesProvider)),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _showCreateSheet(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _CreateScheduleSheet(),
    );
    ref.invalidate(schedulesProvider);
  }

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, Schedule s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Apagar horário?'),
        content:
            Text('Apagar horário da turma "${s.turmaName ?? s.turmaId}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Apagar')),
        ],
      ),
    );
    if (ok == true) {
      try {
        final api = ref.read(apiClientProvider);
        await api.delete('/academic/schedules/${s.id}');
        ref.invalidate(schedulesProvider);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(e.toString())));
        }
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Timetable detail screen
// ---------------------------------------------------------------------------
class _TimetableDetailScreen extends ConsumerStatefulWidget {
  final Schedule schedule;
  const _TimetableDetailScreen({required this.schedule});

  @override
  ConsumerState<_TimetableDetailScreen> createState() =>
      _TimetableDetailScreenState();
}

class _TimetableDetailScreenState
    extends ConsumerState<_TimetableDetailScreen> {
  late Schedule _schedule;

  static const _dayLabels = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex'];
  static const _dayNumbers = [1, 2, 3, 4, 5];

  @override
  void initState() {
    super.initState();
    _schedule = widget.schedule;
  }

  Future<void> _refresh() async {
    final api = ref.read(apiClientProvider);
    try {
      final data =
          await api.get('/academic/schedules/${_schedule.id}');
      if (mounted) {
        setState(() =>
            _schedule = Schedule.fromJson(data as Map<String, dynamic>));
      }
    } catch (_) {}
  }

  Future<void> _autoGenerate() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Gerar Horário Automático'),
        content: const Text(
          'Isto irá criar blocos das 08:00 às 17:00 (de hora em hora) '
          'de Segunda a Sexta. Blocos já existentes são mantidos.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Gerar')),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    final api = ref.read(apiClientProvider);
    final times = [
      '08:00:00', '09:00:00', '10:00:00', '11:00:00', '12:00:00',
      '13:00:00', '14:00:00', '15:00:00', '16:00:00', '17:00:00',
    ];
    int created = 0;
    for (final day in _dayNumbers) {
      for (final t in times) {
        try {
          await api.post('/academic/schedules/${_schedule.id}/slots',
              data: {'day_of_week': day, 'slot_time': t});
          created++;
        } catch (_) {}
      }
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$created blocos criados')));
      await _refresh();
    }
  }

  Future<void> _addSlot() async {
    await showDialog(
      context: context,
      builder: (_) => _AddSlotDialog(scheduleId: _schedule.id),
    );
    await _refresh();
  }

  Future<void> _deleteSlot(ScheduleSlot slot) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Apagar bloco?'),
        content: Text(
            '${_dayLabels[slot.dayOfWeek - 1]} ${slot.slotTime.substring(0, 5)}'
            '${slot.activityName != null ? ' — ${slot.activityName}' : ''}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Apagar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final api = ref.read(apiClientProvider);
      await api
          .delete('/academic/schedules/${_schedule.id}/slots/${slot.id}');
      await _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final allTimes = _schedule.slots
        .map((s) => s.slotTime)
        .toSet()
        .toList()
      ..sort();

    final Map<String, Map<int, ScheduleSlot>> grid = {
      for (final t in allTimes) t: {}
    };
    for (final slot in _schedule.slots) {
      grid[slot.slotTime]?[slot.dayOfWeek] = slot;
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_schedule.turmaName ?? 'Horário',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700)),
            if (_schedule.schoolYearLabel != null)
              Text(_schedule.schoolYearLabel!,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.normal)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_awesome),
            tooltip: 'Gerar automaticamente',
            onPressed: _autoGenerate,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addSlot,
        icon: const Icon(Icons.add),
        label: const Text('Adicionar Bloco'),
      ),
      body: _schedule.slots.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.table_chart_outlined,
                      size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text('Horário vazio',
                      style: TextStyle(fontSize: 16)),
                  const SizedBox(height: 8),
                  const Text(
                    'Adicione blocos lectivos manualmente\nou gere automaticamente.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _autoGenerate,
                    icon: const Icon(Icons.auto_awesome),
                    label: const Text('Gerar Automaticamente'),
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              scrollDirection: Axis.vertical,
              padding: const EdgeInsets.all(12),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: _buildGrid(grid, allTimes),
              ),
            ),
    );
  }

  Widget _buildGrid(
      Map<String, Map<int, ScheduleSlot>> grid, List<String> times) {
    const timeColWidth = 72.0;
    const cellWidth = 110.0;
    const headerHeight = 40.0;
    const cellHeight = 52.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header row
        Row(
          children: [
            Container(
              width: timeColWidth,
              height: headerHeight,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: AppTheme.primary,
                borderRadius:
                    BorderRadius.only(topLeft: Radius.circular(8)),
              ),
              child: const Text('Hora',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12)),
            ),
            ..._dayNumbers.asMap().entries.map((e) => Container(
                  width: cellWidth,
                  height: headerHeight,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppTheme.primary,
                    border: Border(
                        left: BorderSide(
                            color: Colors.white.withOpacity(0.3))),
                    borderRadius: e.key == _dayNumbers.length - 1
                        ? const BorderRadius.only(
                            topRight: Radius.circular(8))
                        : null,
                  ),
                  child: Text(_dayLabels[e.key],
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13)),
                )),
          ],
        ),
        // Time rows
        ...times.map((t) {
          final displayTime =
              t.length >= 5 ? t.substring(0, 5) : t;
          return Row(
            children: [
              Container(
                width: timeColWidth,
                height: cellHeight,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppTheme.primaryLight,
                  border: Border(
                      top: BorderSide(color: AppTheme.border)),
                ),
                child: Text(displayTime,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                        color: AppTheme.primary)),
              ),
              ..._dayNumbers.map((day) {
                final slot = grid[t]?[day];
                return GestureDetector(
                  onLongPress:
                      slot != null ? () => _deleteSlot(slot) : null,
                  child: Container(
                    width: cellWidth,
                    height: cellHeight,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 4),
                    decoration: BoxDecoration(
                      color: slot != null
                          ? (slot.activityName != null
                              ? const Color(0xFFDEF7EC)
                              : const Color(0xFFF0F9FF))
                          : Colors.white,
                      border: const Border(
                        top: BorderSide(color: AppTheme.border),
                        left: BorderSide(color: AppTheme.border),
                      ),
                    ),
                    child: slot != null
                        ? Text(
                            slot.activityName ?? '•',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: slot.activityName != null
                                  ? AppTheme.success
                                  : AppTheme.primary,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          )
                        : const SizedBox.shrink(),
                  ),
                );
              }),
            ],
          );
        }),
        // Bottom + right border
        Container(
            height: 1,
            width: timeColWidth + cellWidth * _dayNumbers.length,
            color: AppTheme.border),
        const SizedBox(height: 8),
        const Text('Pressão longa num bloco para o apagar',
            style: TextStyle(
                fontSize: 11, color: AppTheme.textSecondary)),
        const SizedBox(height: 88),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Add slot dialog
// ---------------------------------------------------------------------------
class _AddSlotDialog extends ConsumerStatefulWidget {
  final String scheduleId;
  const _AddSlotDialog({required this.scheduleId});

  @override
  ConsumerState<_AddSlotDialog> createState() => _AddSlotDialogState();
}

class _AddSlotDialogState extends ConsumerState<_AddSlotDialog> {
  int _dayOfWeek = 1;
  TimeOfDay _time = const TimeOfDay(hour: 8, minute: 0);
  String? _activityId;
  bool _loading = false;

  static const _days = [
    (1, 'Segunda-feira'),
    (2, 'Terça-feira'),
    (3, 'Quarta-feira'),
    (4, 'Quinta-feira'),
    (5, 'Sexta-feira'),
  ];

  Future<void> _submit() async {
    setState(() => _loading = true);
    try {
      final api = ref.read(apiClientProvider);
      await api.post('/academic/schedules/${widget.scheduleId}/slots',
          data: {
            'day_of_week': _dayOfWeek,
            'slot_time':
                '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}:00',
            if (_activityId != null) 'activity_id': _activityId,
          });
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final activitiesAsync = ref.watch(_activitiesForScheduleProvider);
    return AlertDialog(
      title: const Text('Adicionar Bloco'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<int>(
              value: _dayOfWeek,
              decoration:
                  const InputDecoration(labelText: 'Dia da Semana'),
              items: _days
                  .map((d) => DropdownMenuItem(
                      value: d.$1, child: Text(d.$2)))
                  .toList(),
              onChanged: (v) => setState(() => _dayOfWeek = v!),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: () async {
                final t = await showTimePicker(
                    context: context, initialTime: _time);
                if (t != null) setState(() => _time = t);
              },
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Hora',
                  prefixIcon: Icon(Icons.access_time),
                ),
                child: Text(_time.format(context)),
              ),
            ),
            const SizedBox(height: 12),
            activitiesAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (_, __) => const SizedBox.shrink(),
              data: (activities) => DropdownButtonFormField<String>(
                value: _activityId,
                decoration: const InputDecoration(
                    labelText: 'Actividade (opcional)'),
                items: [
                  const DropdownMenuItem(
                      value: null, child: Text('Nenhuma')),
                  ...activities.map((a) => DropdownMenuItem(
                      value: a['id'], child: Text(a['name']!))),
                ],
                onChanged: (v) => setState(() => _activityId = v),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
        FilledButton(
          onPressed: _loading ? null : _submit,
          child: _loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Text('Adicionar'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Create schedule bottom sheet
// ---------------------------------------------------------------------------
class _CreateScheduleSheet extends ConsumerStatefulWidget {
  const _CreateScheduleSheet();

  @override
  ConsumerState<_CreateScheduleSheet> createState() =>
      _CreateScheduleSheetState();
}

class _CreateScheduleSheetState
    extends ConsumerState<_CreateScheduleSheet> {
  String? _selectedTurmaId;
  String? _selectedSchoolYearId;

  List<Map<String, dynamic>> _turmas = [];
  List<Map<String, dynamic>> _schoolYears = [];
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = ref.read(apiClientProvider);
    try {
      final results = await Future.wait([
        api.get('/academic/turmas') as Future,
        api.get('/schools/school-years') as Future,
      ]);
      if (mounted) {
        setState(() {
          _turmas = (results[0] as List)
              .map((e) => e as Map<String, dynamic>)
              .toList();
          _schoolYears = (results[1] as List)
              .map((e) => e as Map<String, dynamic>)
              .toList();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    if (_selectedTurmaId == null) {
      setState(() => _error = 'Seleccione uma turma');
      return;
    }
    if (_selectedSchoolYearId == null) {
      setState(() => _error = 'Seleccione um ano lectivo');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      await api.post('/academic/schedules', data: {
        'turma_id': _selectedTurmaId,
        'school_year_id': _selectedSchoolYearId,
      });
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Novo Horário',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 24),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else ...[
            DropdownButtonFormField<String>(
              value: _selectedTurmaId,
              decoration: const InputDecoration(
                  labelText: 'Turma *',
                  border: OutlineInputBorder()),
              items: _turmas.map((t) {
                final name = t['name'] as String? ?? '';
                final level = t['level'] as String? ?? '';
                return DropdownMenuItem(
                  value: t['id']?.toString(),
                  child:
                      Text(level.isNotEmpty ? '$name ($level)' : name),
                );
              }).toList(),
              onChanged: (v) => setState(() => _selectedTurmaId = v),
              hint: _turmas.isEmpty
                  ? const Text('Nenhuma turma criada')
                  : const Text('Seleccione a turma'),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _selectedSchoolYearId,
              decoration: const InputDecoration(
                  labelText: 'Ano Lectivo *',
                  border: OutlineInputBorder()),
              items: _schoolYears.map((sy) {
                final label = sy['year_label'] as String? ?? '';
                return DropdownMenuItem(
                    value: sy['id']?.toString(), child: Text(label));
              }).toList(),
              onChanged: (v) =>
                  setState(() => _selectedSchoolYearId = v),
              hint: _schoolYears.isEmpty
                  ? const Text('Nenhum ano lectivo criado')
                  : const Text('Seleccione o ano lectivo'),
            ),
            if (_turmas.isEmpty || _schoolYears.isEmpty) ...[
              const SizedBox(height: 12),
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    _turmas.isEmpty && _schoolYears.isEmpty
                        ? 'Crie primeiro uma Turma em "Turmas" e um Ano Lectivo em "Configurações".'
                        : _turmas.isEmpty
                            ? 'Crie primeiro uma Turma em "Turmas".'
                            : 'Crie primeiro um Ano Lectivo em "Configurações".',
                    style: TextStyle(
                        color: Theme.of(context)
                            .colorScheme
                            .onErrorContainer),
                  ),
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancelar')),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _saving ? null : _submit,
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2))
                      : const Text('Criar'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
