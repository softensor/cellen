import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------
class Turma {
  final String id;
  final String name;
  final String? level;
  final String? room;
  final int maxCapacity;
  final int currentPupils;
  final String? teacherId;
  final String? teacherName;

  const Turma({
    required this.id,
    required this.name,
    this.level,
    this.room,
    required this.maxCapacity,
    required this.currentPupils,
    this.teacherId,
    this.teacherName,
  });

  double get occupancyRate =>
      maxCapacity > 0 ? currentPupils / maxCapacity : 0;

  factory Turma.fromJson(Map<String, dynamic> json) {
    return Turma(
      id: json['id']?.toString() ?? '',
      name: json['name'] as String? ?? '',
      level: json['level'] as String?,
      room: json['room'] as String?,
      maxCapacity: json['max_capacity'] as int? ?? 0,
      currentPupils: json['current_pupils'] as int? ?? 0,
      teacherId: json['teacher_id']?.toString(),
      teacherName: json['teacher_name'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (level != null) 'level': level,
        if (room != null) 'room': room,
        'max_capacity': maxCapacity,
        if (teacherId != null) 'teacher_id': teacherId,
      };
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------
final turmasProvider = FutureProvider.autoDispose<List<Turma>>((ref) async {
  final api = ref.read(apiClientProvider);
  final data = await api.get('/academic/turmas') as List;
  return data
      .map((e) => Turma.fromJson(e as Map<String, dynamic>))
      .toList();
});

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------
class TurmasScreen extends ConsumerWidget {
  const TurmasScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final turmasAsync = ref.watch(turmasProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Turmas'),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showTurmaSheet(context, ref, null),
        tooltip: 'Nova Turma',
        child: const Icon(Icons.add),
      ),
      body: turmasAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 8),
              Text(e.toString()),
              TextButton(
                onPressed: () => ref.invalidate(turmasProvider),
                child: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
        data: (turmas) {
          if (turmas.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.school,
                      size: 64,
                      color:
                          Theme.of(context).colorScheme.outlineVariant),
                  const SizedBox(height: 16),
                  Text(
                    'Nenhuma turma criada',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(turmasProvider),
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 88),
              itemCount: turmas.length,
              itemBuilder: (context, i) {
                final turma = turmas[i];
                return _TurmaCard(
                  turma: turma,
                  onEdit: () => _showTurmaSheet(context, ref, turma),
                );
              },
            ),
          );
        },
      ),
    );
  }

  void _showTurmaSheet(
      BuildContext context, WidgetRef ref, Turma? turma) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _TurmaFormSheet(
        turma: turma,
        onSaved: () {
          ref.invalidate(turmasProvider);
          Navigator.pop(context);
        },
      ),
    );
  }
}

class _TurmaCard extends StatelessWidget {
  final Turma turma;
  final VoidCallback onEdit;

  const _TurmaCard({required this.turma, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final occupancy = turma.occupancyRate;
    Color occupancyColor;
    if (occupancy >= 0.9) {
      occupancyColor = Colors.red;
    } else if (occupancy >= 0.7) {
      occupancyColor = Colors.orange;
    } else {
      occupancyColor = Colors.green;
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    turma.name,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                if (turma.level != null)
                  Chip(
                    label: Text(turma.level!),
                    visualDensity: VisualDensity.compact,
                  ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.edit, size: 18),
                  onPressed: onEdit,
                  tooltip: 'Editar',
                ),
              ],
            ),
            if (turma.room != null)
              Text(
                'Sala: ${turma.room}',
                style: TextStyle(
                    color:
                        Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            if (turma.teacherName != null)
              Text(
                'Educador(a): ${turma.teacherName}',
                style:
                    const TextStyle(fontSize: 13),
              ),
            const SizedBox(height: 12),

            // Capacity bar
            Row(
              children: [
                Text(
                  '${turma.currentPupils} / ${turma.maxCapacity} crianças',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const Spacer(),
                Text(
                  '${(occupancy * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                    color: occupancyColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: occupancy.clamp(0.0, 1.0),
                color: occupancyColor,
                backgroundColor: occupancyColor.withOpacity(0.15),
                minHeight: 8,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Turma Form Bottom Sheet
// ---------------------------------------------------------------------------
class _TurmaFormSheet extends ConsumerStatefulWidget {
  final Turma? turma;
  final VoidCallback onSaved;

  const _TurmaFormSheet({this.turma, required this.onSaved});

  @override
  ConsumerState<_TurmaFormSheet> createState() =>
      _TurmaFormSheetState();
}

class _TurmaFormSheetState extends ConsumerState<_TurmaFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _roomCtrl;
  late final TextEditingController _capacityCtrl;
  late final TextEditingController _levelCtrl;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.turma?.name ?? '');
    _roomCtrl = TextEditingController(text: widget.turma?.room ?? '');
    _capacityCtrl = TextEditingController(
        text: widget.turma?.maxCapacity.toString() ?? '');
    _levelCtrl = TextEditingController(text: widget.turma?.level ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _roomCtrl.dispose();
    _capacityCtrl.dispose();
    _levelCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    final body = <String, dynamic>{
      'name': _nameCtrl.text.trim(),
      if (_roomCtrl.text.trim().isNotEmpty) 'room': _roomCtrl.text.trim(),
      if (_levelCtrl.text.trim().isNotEmpty) 'level': _levelCtrl.text.trim(),
      'max_capacity': int.tryParse(_capacityCtrl.text) ?? 0,
    };
    try {
      final api = ref.read(apiClientProvider);
      if (widget.turma != null) {
        await api.patch('/academic/turmas/${widget.turma!.id}', data: body);
      } else {
        await api.post('/academic/turmas', data: body);
      }
      widget.onSaved();
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.turma != null ? 'Editar Turma' : 'Nova Turma',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                  labelText: 'Nome da Turma *',
                  prefixIcon: Icon(Icons.school)),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Campo obrigatório' : null,
            ),
            const SizedBox(height: 12),

            TextFormField(
              controller: _levelCtrl,
              decoration: const InputDecoration(
                  labelText: 'Nível (ex: Berçário, Creche)',
                  prefixIcon: Icon(Icons.grade)),
            ),
            const SizedBox(height: 12),

            TextFormField(
              controller: _roomCtrl,
              decoration: const InputDecoration(
                  labelText: 'Sala',
                  prefixIcon: Icon(Icons.meeting_room)),
            ),
            const SizedBox(height: 12),

            TextFormField(
              controller: _capacityCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'Capacidade Máxima *',
                  prefixIcon: Icon(Icons.group)),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Campo obrigatório' : null,
            ),

            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error)),
            ],

            const SizedBox(height: 16),
            FilledButton(
              onPressed: _isLoading ? null : _submit,
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Text(widget.turma != null
                      ? 'Guardar Alterações'
                      : 'Criar Turma'),
            ),
          ],
        ),
      ),
    );
  }
}
