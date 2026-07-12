import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------
class Schedule {
  final String id;
  final String turmaId;
  final String schoolYearId;
  final String? turmaName;
  final String? schoolYearLabel;

  const Schedule({
    required this.id,
    required this.turmaId,
    required this.schoolYearId,
    this.turmaName,
    this.schoolYearLabel,
  });

  String get displayLabel {
    final t = turmaName ?? turmaId.substring(0, 8);
    final y = schoolYearLabel ?? schoolYearId.substring(0, 8);
    return '$t – $y';
  }

  factory Schedule.fromJson(Map<String, dynamic> json) {
    return Schedule(
      id: json['id']?.toString() ?? '',
      turmaId: json['turma_id']?.toString() ?? '',
      schoolYearId: json['school_year_id']?.toString() ?? '',
      turmaName: json['turma_name'] as String?,
      schoolYearLabel: json['school_year_label'] as String?,
    );
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------
final schedulesProvider = FutureProvider.autoDispose<List<Schedule>>((ref) async {
  final api = ref.read(apiClientProvider);
  final data = await api.get('/academic/schedules') as List;
  return data.map((e) => Schedule.fromJson(e as Map<String, dynamic>)).toList();
});

// ---------------------------------------------------------------------------
// Screen
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
                  Icon(Icons.schedule, size: 64,
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
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor:
                        Theme.of(context).colorScheme.primaryContainer,
                    child: Icon(Icons.schedule,
                        color: Theme.of(context).colorScheme.onPrimaryContainer),
                  ),
                  title: Text(s.turmaName ?? 'Turma'),
                  subtitle: Text(s.schoolYearLabel ?? 'Ano lectivo'),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Apagar horário',
                    onPressed: () => _confirmDelete(context, ref, s),
                  ),
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
        content: Text('Apagar "${s.displayLabel}"?'),
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
// Create sheet
// ---------------------------------------------------------------------------
class _CreateScheduleSheet extends ConsumerStatefulWidget {
  const _CreateScheduleSheet();

  @override
  ConsumerState<_CreateScheduleSheet> createState() =>
      _CreateScheduleSheetState();
}

class _CreateScheduleSheetState extends ConsumerState<_CreateScheduleSheet> {
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
            // Turma dropdown
            DropdownButtonFormField<String>(
              value: _selectedTurmaId,
              decoration: const InputDecoration(
                labelText: 'Turma *',
                border: OutlineInputBorder(),
              ),
              items: _turmas.map((t) {
                final name = t['name'] as String? ?? '';
                final level = t['level'] as String? ?? '';
                return DropdownMenuItem(
                  value: t['id']?.toString(),
                  child: Text(level.isNotEmpty ? '$name ($level)' : name),
                );
              }).toList(),
              onChanged: (v) => setState(() => _selectedTurmaId = v),
              hint: _turmas.isEmpty
                  ? const Text('Nenhuma turma criada')
                  : const Text('Seleccione a turma'),
            ),
            const SizedBox(height: 16),
            // School year dropdown
            DropdownButtonFormField<String>(
              value: _selectedSchoolYearId,
              decoration: const InputDecoration(
                labelText: 'Ano Lectivo *',
                border: OutlineInputBorder(),
              ),
              items: _schoolYears.map((sy) {
                final label = sy['year_label'] as String? ?? '';
                return DropdownMenuItem(
                  value: sy['id']?.toString(),
                  child: Text(label),
                );
              }).toList(),
              onChanged: (v) => setState(() => _selectedSchoolYearId = v),
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
                        color: Theme.of(context).colorScheme.onErrorContainer),
                  ),
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.error)),
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
                          child: CircularProgressIndicator(strokeWidth: 2))
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
