import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_error_widget.dart';

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
// Activity color palette (cycling, deterministic by name hash)
// ---------------------------------------------------------------------------
const _activityColors = [
  Color(0xFF4CAF50), // green
  Color(0xFF2196F3), // blue
  Color(0xFFFF9800), // orange
  Color(0xFF9C27B0), // purple
  Color(0xFFE91E63), // pink
  Color(0xFF00BCD4), // cyan
  Color(0xFF8BC34A), // light green
  Color(0xFFF44336), // red
  Color(0xFF607D8B), // blue-grey
  Color(0xFFFF5722), // deep orange
];

Color _colorForActivity(String? name) {
  if (name == null) return AppTheme.textSecondary;
  final idx = name.codeUnits.fold(0, (a, b) => a + b) % _activityColors.length;
  return _activityColors[idx];
}

// ---------------------------------------------------------------------------
// Standard childcare day template
// ---------------------------------------------------------------------------
class _TemplateEntry {
  String time; // HH:MM
  String activityName;
  bool selected;

  _TemplateEntry({
    required this.time,
    required this.activityName,
    this.selected = true,
  });

  _TemplateEntry copy() =>
      _TemplateEntry(time: time, activityName: activityName, selected: selected);
}

final _defaultDayTemplate = [
  _TemplateEntry(time: '08:00', activityName: 'Acolhimento'),
  _TemplateEntry(time: '09:00', activityName: 'Pequeno-Almoço'),
  _TemplateEntry(time: '09:30', activityName: 'Actividades'),
  _TemplateEntry(time: '10:30', activityName: 'Recreio'),
  _TemplateEntry(time: '11:00', activityName: 'Actividades Dirigidas'),
  _TemplateEntry(time: '12:00', activityName: 'Almoço'),
  _TemplateEntry(time: '13:00', activityName: 'Sesta'),
  _TemplateEntry(time: '14:30', activityName: 'Actividades Livres'),
  _TemplateEntry(time: '15:00', activityName: 'Lanche'),
  _TemplateEntry(time: '15:30', activityName: 'Tempo Livre'),
  _TemplateEntry(time: '16:00', activityName: 'Saída'),
  _TemplateEntry(time: '17:00', activityName: 'Prolongamento'),
];

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
      'name': m['name']?.toString() ?? '',
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
        error: (e, _) => AppErrorWidget(
            error: e, onRetry: () => ref.invalidate(schedulesProvider)),
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
                    'Crie primeiro uma Turma e um Ano Lectivo,\ndepois adicione um Horário.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: () => _showCreateSheet(context, ref),
                    icon: const Icon(Icons.add),
                    label: const Text('Novo Horário'),
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
                  title: Text(s.turmaName ?? 'Turma',
                      style:
                          const TextStyle(fontWeight: FontWeight.w600)),
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
    final ok = await showDialog<bool>(useRootNavigator: false, 
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
        await ref.read(apiClientProvider).delete('/academic/schedules/${s.id}');
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
    try {
      final data = await ref
          .read(apiClientProvider)
          .get('/academic/schedules/${_schedule.id}');
      if (mounted) {
        setState(
            () => _schedule = Schedule.fromJson(data as Map<String, dynamic>));
      }
    } catch (_) {}
  }

  Future<void> _autoGenerate() async {
    final result = await showDialog<List<({String time, String activityName, List<int> days})>>(
      useRootNavigator: false,
      context: context,
      builder: (_) => _AutoGenerateDialog(),
    );
    if (result == null || result.isEmpty || !mounted) return;

    final api = ref.read(apiClientProvider);

    // Step 1: fetch existing activities
    List<Map<String, String>> existing = [];
    try {
      final data = await api.get('/academic/activities') as List;
      existing = data.map((e) {
        final m = e as Map<String, dynamic>;
        return {'id': m['id']?.toString() ?? '', 'name': m['name']?.toString() ?? ''};
      }).toList();
    } catch (_) {}

    // Step 2: ensure each activity exists, create if not
    final activityMap = <String, String>{}; // name → id
    for (final e in existing) {
      activityMap[e['name']!.toLowerCase()] = e['id']!;
    }

    for (final entry in result) {
      final key = entry.activityName.toLowerCase();
      if (!activityMap.containsKey(key)) {
        try {
          final created = await api.post('/academic/activities',
              data: {'name': entry.activityName, 'description': ''});
          final id = (created as Map<String, dynamic>)['id']?.toString() ?? '';
          if (id.isNotEmpty) activityMap[key] = id;
        } catch (_) {}
      }
    }

    // Step 3: create slots
    int created = 0;
    for (final entry in result) {
      final activityId = activityMap[entry.activityName.toLowerCase()];
      for (final day in entry.days) {
        try {
          await api.post('/academic/schedules/${_schedule.id}/slots', data: {
            'day_of_week': day,
            'slot_time': '${entry.time}:00',
            if (activityId != null) 'activity_id': activityId,
          });
          created++;
        } catch (_) {} // skip duplicates
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$created blocos criados')));
      await _refresh();
    }
  }

  Future<void> _addSlotAt(int day, String time) async {
    await showDialog(useRootNavigator: false, 
      context: context,
      builder: (_) => _AddSlotDialog(
          scheduleId: _schedule.id, prefilledDay: day, prefilledTime: time),
    );
    await _refresh();
  }

  Future<void> _addSlot() async {
    await showDialog(useRootNavigator: false, 
      context: context,
      builder: (_) => _AddSlotDialog(scheduleId: _schedule.id),
    );
    await _refresh();
  }

  Future<void> _editSlot(ScheduleSlot slot) async {
    await showDialog(useRootNavigator: false, 
      context: context,
      builder: (_) => _EditSlotDialog(
        scheduleId: _schedule.id,
        slot: slot,
      ),
    );
    await _refresh();
  }

  Future<void> _deleteSlot(ScheduleSlot slot) async {
    final ok = await showDialog<bool>(useRootNavigator: false, 
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
      await ref.read(apiClientProvider)
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

    // Collect unique activities for legend
    final uniqueActivities = _schedule.slots
        .where((s) => s.activityName != null)
        .map((s) => s.activityName!)
        .toSet()
        .toList()
      ..sort();

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
            icon: const Icon(Icons.add),
            tooltip: 'Adicionar bloco',
            onPressed: _addSlot,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          ),
        ],
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
                    'Use "Gerar automaticamente" para criar um horário\ncom as actividades típicas de uma creche.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _autoGenerate,
                    icon: const Icon(Icons.auto_awesome),
                    label: const Text('Gerar Automaticamente'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _addSlot,
                    icon: const Icon(Icons.add),
                    label: const Text('Adicionar Bloco Manual'),
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: _buildGrid(grid, allTimes),
                  ),
                  if (uniqueActivities.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _buildLegend(uniqueActivities),
                  ],
                  const SizedBox(height: 8),
                  const Text(
                    'Toque numa célula preenchida para editar · Célula vazia para adicionar · Pressão longa para apagar',
                    style: TextStyle(
                        fontSize: 11, color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 88),
                ],
              ),
            ),
    );
  }

  Widget _buildLegend(List<String> activities) {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: activities.map((name) {
        final color = _colorForActivity(name);
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 4),
            Text(name,
                style: const TextStyle(
                    fontSize: 11, color: AppTheme.textSecondary)),
          ],
        );
      }).toList(),
    );
  }

  Widget _buildGrid(
      Map<String, Map<int, ScheduleSlot>> grid, List<String> times) {
    const timeColWidth = 68.0;
    const cellWidth = 108.0;
    const headerHeight = 38.0;
    const cellHeight = 50.0;

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
                  border: Border(top: BorderSide(color: AppTheme.border)),
                ),
                child: Text(displayTime,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                        color: AppTheme.primary)),
              ),
              ..._dayNumbers.map((day) {
                final slot = grid[t]?[day];
                final actColor = _colorForActivity(slot?.activityName);

                return GestureDetector(
                  onTap: slot == null
                      ? () => _addSlotAt(day, displayTime)
                      : () => _editSlot(slot),
                  onLongPress:
                      slot != null ? () => _deleteSlot(slot) : null,
                  child: Container(
                    width: cellWidth,
                    height: cellHeight,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 4),
                    decoration: BoxDecoration(
                      color: slot != null
                          ? actColor.withOpacity(0.12)
                          : Colors.white,
                      border: const Border(
                        top: BorderSide(color: AppTheme.border),
                        left: BorderSide(color: AppTheme.border),
                      ),
                    ),
                    child: slot != null
                        ? Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 4,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: actColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                slot.activityName ?? '•',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: actColor,
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          )
                        : Icon(Icons.add,
                            size: 14,
                            color: Colors.grey.shade300),
                  ),
                );
              }),
            ],
          );
        }),
        // Bottom border
        Container(
            height: 1,
            width: timeColWidth + cellWidth * _dayNumbers.length,
            color: AppTheme.border),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Auto-generate dialog
// ---------------------------------------------------------------------------
class _AutoGenerateDialog extends StatefulWidget {
  @override
  State<_AutoGenerateDialog> createState() => _AutoGenerateDialogState();
}

class _AutoGenerateDialogState extends State<_AutoGenerateDialog> {
  late List<_TemplateEntry> _entries;
  final Set<int> _selectedDays = {1, 2, 3, 4, 5};

  static const _dayNames = [
    (1, 'Seg'),
    (2, 'Ter'),
    (3, 'Qua'),
    (4, 'Qui'),
    (5, 'Sex'),
  ];

  @override
  void initState() {
    super.initState();
    _entries = _defaultDayTemplate.map((e) => e.copy()).toList();
  }

  void _addEntry() {
    setState(() {
      _entries.add(_TemplateEntry(time: '08:00', activityName: ''));
    });
  }

  void _removeEntry(int i) {
    setState(() => _entries.removeAt(i));
  }

  Future<void> _pickTime(int i) async {
    final parts = _entries[i].time.split(':');
    final initial = TimeOfDay(
      hour: int.tryParse(parts[0]) ?? 8,
      minute: int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0,
    );
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked != null) {
      setState(() {
        _entries[i].time =
            '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      });
    }
  }

  void _submit() {
    final valid = _entries.where((e) => e.selected && e.activityName.trim().isNotEmpty).toList();
    if (valid.isEmpty || _selectedDays.isEmpty) {
      Navigator.pop(context, null);
      return;
    }
    final result = valid.map((e) => (
          time: e.time,
          activityName: e.activityName.trim(),
          days: _selectedDays.toList(),
        )).toList();
    Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 640),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: AppTheme.primary,
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Gerar Horário Automático',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w700)),
                  SizedBox(height: 4),
                  Text(
                    'Configure as actividades do dia-tipo e seleccione os dias.',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),

            // Days selector
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Aplicar a:',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textSecondary)),
                  const SizedBox(height: 6),
                  Row(
                    children: _dayNames.map((d) {
                      final selected = _selectedDays.contains(d.$1);
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: FilterChip(
                          label: Text(d.$2),
                          selected: selected,
                          onSelected: (v) => setState(() {
                            if (v) {
                              _selectedDays.add(d.$1);
                            } else {
                              _selectedDays.remove(d.$1);
                            }
                          }),
                          selectedColor:
                              AppTheme.primary.withOpacity(0.15),
                          checkmarkColor: AppTheme.primary,
                          labelStyle: TextStyle(
                            fontSize: 12,
                            color: selected
                                ? AppTheme.primary
                                : AppTheme.textSecondary,
                            fontWeight: selected
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 0),
                          visualDensity: VisualDensity.compact,
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            // Template entries
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: _entries.length,
                itemBuilder: (context, i) {
                  final e = _entries[i];
                  final color = _colorForActivity(
                      e.activityName.isNotEmpty ? e.activityName : null);
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 3),
                    child: Row(
                      children: [
                        // Checkbox
                        Checkbox(
                          value: e.selected,
                          onChanged: (v) =>
                              setState(() => e.selected = v ?? false),
                          visualDensity: VisualDensity.compact,
                        ),
                        // Color dot
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: e.activityName.isNotEmpty
                                ? color
                                : Colors.grey.shade300,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Time button
                        InkWell(
                          onTap: () => _pickTime(i),
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryLight,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(e.time,
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.primary)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Activity name
                        Expanded(
                          child: TextFormField(
                            initialValue: e.activityName,
                            decoration: const InputDecoration(
                              hintText: 'Nome da actividade',
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 8),
                              border: OutlineInputBorder(),
                            ),
                            style: const TextStyle(fontSize: 13),
                            onChanged: (v) =>
                                setState(() => e.activityName = v),
                          ),
                        ),
                        // Remove
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline,
                              size: 18, color: Colors.red),
                          onPressed: () => _removeEntry(i),
                          padding: const EdgeInsets.all(4),
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

            const Divider(height: 1),

            // Actions
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: _addEntry,
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Adicionar'),
                    style: TextButton.styleFrom(
                        foregroundColor: AppTheme.primary),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context, null),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _submit,
                    icon: const Icon(Icons.auto_awesome, size: 16),
                    label: const Text('Gerar Horário'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Add slot dialog
// ---------------------------------------------------------------------------
class _AddSlotDialog extends ConsumerStatefulWidget {
  final String scheduleId;
  final int? prefilledDay;
  final String? prefilledTime;

  const _AddSlotDialog({
    required this.scheduleId,
    this.prefilledDay,
    this.prefilledTime,
  });

  @override
  ConsumerState<_AddSlotDialog> createState() => _AddSlotDialogState();
}

class _AddSlotDialogState extends ConsumerState<_AddSlotDialog> {
  late int _dayOfWeek;
  late TimeOfDay _time;
  String? _activityId;
  bool _loading = false;

  static const _days = [
    (1, 'Segunda-feira'),
    (2, 'Terça-feira'),
    (3, 'Quarta-feira'),
    (4, 'Quinta-feira'),
    (5, 'Sexta-feira'),
  ];

  @override
  void initState() {
    super.initState();
    _dayOfWeek = widget.prefilledDay ?? 1;
    if (widget.prefilledTime != null) {
      final parts = widget.prefilledTime!.split(':');
      _time = TimeOfDay(
        hour: int.tryParse(parts[0]) ?? 8,
        minute: int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0,
      );
    } else {
      _time = const TimeOfDay(hour: 8, minute: 0);
    }
  }

  Future<void> _submit() async {
    setState(() => _loading = true);
    try {
      await ref.read(apiClientProvider).post(
          '/academic/schedules/${widget.scheduleId}/slots',
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
                final t =
                    await showTimePicker(context: context, initialTime: _time);
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
                  ...activities.map((a) {
                    final color = _colorForActivity(a['name']);
                    return DropdownMenuItem(
                      value: a['id'],
                      child: Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                                color: color, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 8),
                          Text(a['name']!),
                        ],
                      ),
                    );
                  }),
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
// Edit slot dialog
// ---------------------------------------------------------------------------
class _EditSlotDialog extends ConsumerStatefulWidget {
  final String scheduleId;
  final ScheduleSlot slot;

  const _EditSlotDialog({required this.scheduleId, required this.slot});

  @override
  ConsumerState<_EditSlotDialog> createState() => _EditSlotDialogState();
}

class _EditSlotDialogState extends ConsumerState<_EditSlotDialog> {
  late int _dayOfWeek;
  late TimeOfDay _time;
  String? _activityId;
  bool _loading = false;

  static const _days = [
    (1, 'Segunda-feira'),
    (2, 'Terça-feira'),
    (3, 'Quarta-feira'),
    (4, 'Quinta-feira'),
    (5, 'Sexta-feira'),
  ];

  @override
  void initState() {
    super.initState();
    _dayOfWeek = widget.slot.dayOfWeek;
    final parts = widget.slot.slotTime.split(':');
    _time = TimeOfDay(
      hour: int.tryParse(parts[0]) ?? 8,
      minute: int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0,
    );
    _activityId = widget.slot.activityId;
  }

  Future<void> _submit() async {
    setState(() => _loading = true);
    try {
      await ref.read(apiClientProvider).patch(
          '/academic/schedules/${widget.scheduleId}/slots/${widget.slot.id}',
          data: {
            'day_of_week': _dayOfWeek,
            'slot_time':
                '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}:00',
            'activity_id': _activityId,
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

  Future<void> _delete() async {
    final ok = await showDialog<bool>(useRootNavigator: false, 
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Apagar bloco?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Apagar')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _loading = true);
    try {
      await ref.read(apiClientProvider).delete(
          '/academic/schedules/${widget.scheduleId}/slots/${widget.slot.id}');
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final activitiesAsync = ref.watch(_activitiesForScheduleProvider);
    return AlertDialog(
      title: const Text('Editar Bloco'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<int>(
              value: _dayOfWeek,
              decoration: const InputDecoration(labelText: 'Dia da Semana'),
              items: _days
                  .map((d) =>
                      DropdownMenuItem(value: d.$1, child: Text(d.$2)))
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
                decoration:
                    const InputDecoration(labelText: 'Actividade (opcional)'),
                items: [
                  const DropdownMenuItem(
                      value: null, child: Text('Nenhuma')),
                  ...activities.map((a) {
                    final color = _colorForActivity(a['name']);
                    return DropdownMenuItem(
                      value: a['id'],
                      child: Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                                color: color, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 8),
                          Text(a['name']!),
                        ],
                      ),
                    );
                  }),
                ],
                onChanged: (v) => setState(() => _activityId = v),
              ),
            ),
          ],
        ),
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        TextButton(
          onPressed: _loading ? null : _delete,
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          child: const Text('Apagar'),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar')),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _loading ? null : _submit,
              child: _loading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Guardar'),
            ),
          ],
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
      await ref.read(apiClientProvider).post('/academic/schedules', data: {
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
                  labelText: 'Turma *', border: OutlineInputBorder()),
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
