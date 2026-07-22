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

class _Subject {
  final String id;
  final String name;
  final String? code;
  const _Subject({required this.id, required this.name, this.code});
  factory _Subject.fromJson(Map<String, dynamic> j) => _Subject(
        id: j['id'] as String,
        name: j['name'] as String,
        code: j['code'] as String?,
      );
}

class _Teacher {
  final String id;
  final String name;
  const _Teacher({required this.id, required this.name});
  factory _Teacher.fromJson(Map<String, dynamic> j) => _Teacher(
        id: j['id'] as String,
        name: '${j['first_name']} ${j['last_name']}',
      );
}

class _TurmaSubject {
  final String id;
  final String subjectId;
  final String subjectName;
  final String? subjectCode;
  final String? teacherId;
  final String? teacherName;
  final bool isLocked;
  const _TurmaSubject({
    required this.id,
    required this.subjectId,
    required this.subjectName,
    this.subjectCode,
    this.teacherId,
    this.teacherName,
    required this.isLocked,
  });
  factory _TurmaSubject.fromJson(Map<String, dynamic> j) => _TurmaSubject(
        id: j['id'] as String,
        subjectId: j['subject_id'] as String,
        subjectName: j['subject_name'] as String? ?? '',
        subjectCode: j['subject_code'] as String?,
        teacherId: j['teacher_id'] as String?,
        teacherName: j['teacher_name'] as String?,
        isLocked: j['is_locked'] as bool? ?? false,
      );
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

final _tsTurmasProvider = FutureProvider.autoDispose<List<_Turma>>((ref) async {
  final data = await ref.read(apiClientProvider).get('/academic/turmas') as List;
  return data.map((e) => _Turma.fromJson(e as Map<String, dynamic>)).toList();
});

final _tsYearsProvider = FutureProvider.autoDispose<List<_SchoolYear>>((ref) async {
  final data = await ref.read(apiClientProvider).get('/schools/school-years') as List;
  return data.map((e) => _SchoolYear.fromJson(e as Map<String, dynamic>)).toList();
});

final _tsSubjectsProvider = FutureProvider.autoDispose<List<_Subject>>((ref) async {
  final data = await ref.read(apiClientProvider).get('/grades/subjects') as List;
  return data.map((e) => _Subject.fromJson(e as Map<String, dynamic>)).toList();
});

final _tsTeachersProvider = FutureProvider.autoDispose<List<_Teacher>>((ref) async {
  final data = await ref.read(apiClientProvider).get('/employees?employee_type=teacher&limit=200') as List;
  return data.map((e) => _Teacher.fromJson(e as Map<String, dynamic>)).toList();
});

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class TurmaSubjectsScreen extends ConsumerStatefulWidget {
  const TurmaSubjectsScreen({super.key});

  @override
  ConsumerState<TurmaSubjectsScreen> createState() => _TurmaSubjectsScreenState();
}

class _TurmaSubjectsScreenState extends ConsumerState<TurmaSubjectsScreen> {
  _Turma? _selectedTurma;
  _SchoolYear? _selectedYear;
  List<_TurmaSubject>? _assignments;
  bool _loading = false;
  String? _error;
  bool _yearsLoaded = false;

  Future<void> _load() async {
    if (_selectedTurma == null || _selectedYear == null) return;
    setState(() { _loading = true; _error = null; });
    try {
      final api = ref.read(apiClientProvider);
      final data = await api.get(
        '/grades/turma-subjects?turma_id=${_selectedTurma!.id}&school_year_id=${_selectedYear!.id}',
      ) as List;
      setState(() {
        _assignments = data.map((e) => _TurmaSubject.fromJson(e as Map<String, dynamic>)).toList();
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _delete(String id) async {
    try {
      await ref.read(apiClientProvider).delete('/grades/turma-subjects/$id');
      setState(() => _assignments?.removeWhere((a) => a.id == id));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro: $e'), backgroundColor: AppTheme.danger),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final turmasAsync = ref.watch(_tsTurmasProvider);
    final yearsAsync = ref.watch(_tsYearsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Disciplinas por Turma')),
      floatingActionButton: (_selectedTurma != null && _selectedYear != null)
          ? FloatingActionButton(
              onPressed: () => _showAssignDialog(context),
              tooltip: 'Atribuir Disciplina',
              child: const Icon(Icons.add),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              children: [
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
                          _assignments = null;
                        });
                      },
                    );
                  },
                ),
                const SizedBox(height: 10),
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
                              _assignments = null;
                            });
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.tonal(
                      onPressed: (_loading || _selectedTurma == null || _selectedYear == null) ? null : _load,
                      child: _loading
                          ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Carregar'),
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
            child: _assignments == null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.book_outlined, size: 64, color: Colors.grey.shade300),
                        const SizedBox(height: 16),
                        const Text(
                          'Seleccione turma e ano lectivo e toque em "Carregar"',
                          style: TextStyle(color: AppTheme.textSecondary),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  )
                : _assignments!.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.table_chart_outlined, size: 64, color: Colors.grey.shade300),
                              const SizedBox(height: 16),
                              const Text(
                                'Sem disciplinas atribuídas',
                                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'As disciplinas e professores são preenchidos automaticamente '
                                'ao gerar e aplicar o Horário Lectivo.\n\n'
                                'Vá a Horário Lectivo → Gerar Horário → Aceitar e Aplicar.',
                                style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      )
                    : Column(
                        children: [
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.06),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.blue.withOpacity(0.2)),
                            ),
                            child: const Row(children: [
                              Icon(Icons.info_outline, size: 15, color: Colors.blue),
                              SizedBox(width: 8),
                              Expanded(child: Text(
                                'Preenchido automaticamente pelo Horário Lectivo. '
                                'Pode editar o professor atribuído se necessário.',
                                style: TextStyle(fontSize: 12, color: Colors.blue),
                              )),
                            ]),
                          ),
                          Expanded(
                            child: ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
                              itemCount: _assignments!.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          final a = _assignments![i];
                          return Card(
                            margin: EdgeInsets.zero,
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: AppTheme.primary.withOpacity(0.1),
                                child: Text(
                                  a.subjectCode ?? a.subjectName[0].toUpperCase(),
                                  style: const TextStyle(
                                    color: AppTheme.primary,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                              title: Text(a.subjectName, style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: Text(
                                a.teacherName != null ? 'Professor: ${a.teacherName}' : 'Sem professor atribuído',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: a.teacherName != null ? null : Colors.orange,
                                ),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (a.isLocked)
                                    const Icon(Icons.lock_outlined, size: 18, color: AppTheme.textSecondary),
                                  IconButton(
                                    icon: const Icon(Icons.edit_outlined, size: 20),
                                    onPressed: () => _showEditDialog(context, a),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, size: 20, color: AppTheme.danger),
                                    onPressed: () => _confirmDelete(context, a),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, _TurmaSubject a) {
    showDialog(
      useRootNavigator: false,
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remover disciplina?'),
        content: Text('Remover "${a.subjectName}" desta turma? As notas já lançadas serão mantidas.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () { Navigator.pop(context); _delete(a.id); },
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
  }

  void _showAssignDialog(BuildContext context) {
    showDialog(
      useRootNavigator: false,
      context: context,
      builder: (_) => _AssignDialog(
        turmaId: _selectedTurma!.id,
        schoolYearId: _selectedYear!.id,
        onSaved: _load,
      ),
    );
  }

  void _showEditDialog(BuildContext context, _TurmaSubject a) {
    showDialog(
      useRootNavigator: false,
      context: context,
      builder: (_) => _EditAssignDialog(assignment: a, onSaved: _load),
    );
  }
}

// ---------------------------------------------------------------------------
// Assign discipline dialog
// ---------------------------------------------------------------------------

class _AssignDialog extends ConsumerStatefulWidget {
  final String turmaId;
  final String schoolYearId;
  final VoidCallback onSaved;
  const _AssignDialog({required this.turmaId, required this.schoolYearId, required this.onSaved});

  @override
  ConsumerState<_AssignDialog> createState() => _AssignDialogState();
}

class _AssignDialogState extends ConsumerState<_AssignDialog> {
  String? _subjectId;
  String? _teacherId;
  bool _saving = false;
  String? _error;

  Future<void> _submit() async {
    if (_subjectId == null) {
      setState(() => _error = 'Seleccione uma disciplina');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      await ref.read(apiClientProvider).post('/grades/turma-subjects', data: {
        'turma_id': widget.turmaId,
        'subject_id': _subjectId,
        'school_year_id': widget.schoolYearId,
        if (_teacherId != null) 'teacher_id': _teacherId,
      });
      widget.onSaved();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() { _error = e.toString(); _saving = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final subjectsAsync = ref.watch(_tsSubjectsProvider);
    final teachersAsync = ref.watch(_tsTeachersProvider);

    return AlertDialog(
      title: const Text('Atribuir Disciplina'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            subjectsAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('$e', style: const TextStyle(color: AppTheme.danger)),
              data: (subjects) => DropdownButtonFormField<String>(
                value: _subjectId,
                decoration: const InputDecoration(labelText: 'Disciplina *', isDense: true),
                items: subjects
                    .map((s) => DropdownMenuItem(value: s.id, child: Text(s.name)))
                    .toList(),
                onChanged: (v) => setState(() => _subjectId = v),
              ),
            ),
            const SizedBox(height: 12),
            teachersAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => const SizedBox.shrink(),
              data: (teachers) => DropdownButtonFormField<String>(
                value: _teacherId,
                decoration: const InputDecoration(
                  labelText: 'Professor (opcional)',
                  isDense: true,
                ),
                items: [
                  const DropdownMenuItem<String>(value: null, child: Text('— Sem professor —')),
                  ...teachers.map((t) => DropdownMenuItem(value: t.id, child: Text(t.name))),
                ],
                onChanged: (v) => setState(() => _teacherId = v),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: const TextStyle(color: AppTheme.danger, fontSize: 13)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Atribuir'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Edit assignment dialog (change teacher / lock)
// ---------------------------------------------------------------------------

class _EditAssignDialog extends ConsumerStatefulWidget {
  final _TurmaSubject assignment;
  final VoidCallback onSaved;
  const _EditAssignDialog({required this.assignment, required this.onSaved});

  @override
  ConsumerState<_EditAssignDialog> createState() => _EditAssignDialogState();
}

class _EditAssignDialogState extends ConsumerState<_EditAssignDialog> {
  late String? _teacherId;
  late bool _isLocked;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _teacherId = widget.assignment.teacherId;
    _isLocked = widget.assignment.isLocked;
  }

  Future<void> _submit() async {
    setState(() { _saving = true; _error = null; });
    try {
      await ref.read(apiClientProvider).patch(
        '/grades/turma-subjects/${widget.assignment.id}',
        data: {'teacher_id': _teacherId, 'is_locked': _isLocked},
      );
      widget.onSaved();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() { _error = e.toString(); _saving = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final teachersAsync = ref.watch(_tsTeachersProvider);

    return AlertDialog(
      title: Text('Editar: ${widget.assignment.subjectName}'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            teachersAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => const SizedBox.shrink(),
              data: (teachers) => DropdownButtonFormField<String>(
                value: _teacherId,
                decoration: const InputDecoration(labelText: 'Professor', isDense: true),
                items: [
                  const DropdownMenuItem<String>(value: null, child: Text('— Sem professor —')),
                  ...teachers.map((t) => DropdownMenuItem(value: t.id, child: Text(t.name))),
                ],
                onChanged: (v) => setState(() => _teacherId = v),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Bloquear lançamento de notas'),
              subtitle: const Text('Impede alterações às notas desta disciplina', style: TextStyle(fontSize: 12)),
              value: _isLocked,
              onChanged: (v) => setState(() => _isLocked = v),
            ),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: AppTheme.danger, fontSize: 13)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Guardar'),
        ),
      ],
    );
  }
}
