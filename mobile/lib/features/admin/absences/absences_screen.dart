import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_client.dart';

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------
class EmployeeAbsence {
  final String id;
  final String employeeId;
  final DateTime absenceDate;
  final bool isJustified;
  final String? reason;

  const EmployeeAbsence({
    required this.id,
    required this.employeeId,
    required this.absenceDate,
    required this.isJustified,
    this.reason,
  });

  factory EmployeeAbsence.fromJson(Map<String, dynamic> json) {
    return EmployeeAbsence(
      id: json['id']?.toString() ?? '',
      employeeId: json['employee_id']?.toString() ?? '',
      absenceDate: json['absence_date'] != null
          ? DateTime.tryParse(json['absence_date'] as String) ??
              DateTime.now()
          : DateTime.now(),
      isJustified: json['justified'] as bool? ?? false,
      reason: json['reason'] as String?,
    );
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------
final absencesProvider =
    FutureProvider.autoDispose<List<EmployeeAbsence>>((ref) async {
  final api = ref.read(apiClientProvider);
  final data = await api.get('/absences', queryParameters: {'ordering': '-absence_date'}) as List;
  return data
      .map((e) => EmployeeAbsence.fromJson(e as Map<String, dynamic>))
      .toList();
});

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------
class AbsencesScreen extends ConsumerWidget {
  const AbsencesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final absencesAsync = ref.watch(absencesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ausências'),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCreateAbsenceDialog(context, ref),
        tooltip: 'Registar Ausência',
        child: const Icon(Icons.add),
      ),
      body: absencesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 8),
              Text(e.toString()),
              TextButton(
                onPressed: () => ref.invalidate(absencesProvider),
                child: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
        data: (absences) {
          if (absences.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.event_available,
                      size: 64,
                      color:
                          Theme.of(context).colorScheme.outlineVariant),
                  const SizedBox(height: 16),
                  Text(
                    'Nenhuma ausência registada',
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
            onRefresh: () async => ref.invalidate(absencesProvider),
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 88),
              itemCount: absences.length,
              itemBuilder: (context, i) {
                final absence = absences[i];
                return Card(
                  margin: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 4),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: absence.isJustified
                          ? Colors.blue.withOpacity(0.15)
                          : Colors.red.withOpacity(0.15),
                      child: Icon(
                        absence.isJustified
                            ? Icons.check_circle
                            : Icons.cancel,
                        color: absence.isJustified
                            ? Colors.blue
                            : Colors.red,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      'Funcionário: ${absence.employeeId}',
                      style:
                          const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(DateFormat('dd/MM/yyyy')
                            .format(absence.absenceDate)),
                        if (absence.reason != null &&
                            absence.reason!.isNotEmpty)
                          Text(
                            absence.reason!,
                            style: const TextStyle(fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: absence.isJustified
                            ? Colors.blue.withOpacity(0.12)
                            : Colors.red.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        absence.isJustified ? 'Justificada' : 'Injustificada',
                        style: TextStyle(
                          color: absence.isJustified
                              ? Colors.blue
                              : Colors.red,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  void _showCreateAbsenceDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (_) => _CreateAbsenceDialog(
        onCreated: () {
          ref.invalidate(absencesProvider);
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Create Absence Dialog
// ---------------------------------------------------------------------------
class _CreateAbsenceDialog extends ConsumerStatefulWidget {
  final VoidCallback onCreated;
  const _CreateAbsenceDialog({required this.onCreated});

  @override
  ConsumerState<_CreateAbsenceDialog> createState() =>
      _CreateAbsenceDialogState();
}

class _CreateAbsenceDialogState extends ConsumerState<_CreateAbsenceDialog> {
  final _formKey = GlobalKey<FormState>();
  final _employeeIdCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();
  DateTime _date = DateTime.now();
  bool _isJustified = false;
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _employeeIdCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      await api.post('/absences', data: {
        'employee_id': _employeeIdCtrl.text.trim(),
        'absence_date':
            '${_date.year.toString().padLeft(4, '0')}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}',
        'justified': _isJustified,
        if (_reasonCtrl.text.trim().isNotEmpty)
          'reason': _reasonCtrl.text.trim(),
      });
      widget.onCreated();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Registar Ausência'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _employeeIdCtrl,
                decoration: const InputDecoration(
                  labelText: 'ID do Funcionário *',
                  prefixIcon: Icon(Icons.badge),
                ),
                validator: (v) => v == null || v.trim().isEmpty
                    ? 'Campo obrigatório'
                    : null,
              ),
              const SizedBox(height: 12),

              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _date,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) setState(() => _date = picked);
                },
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Data',
                    prefixIcon: Icon(Icons.calendar_today),
                  ),
                  child: Text(DateFormat('dd/MM/yyyy').format(_date)),
                ),
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _reasonCtrl,
                decoration: const InputDecoration(
                  labelText: 'Motivo (opcional)',
                ),
              ),
              const SizedBox(height: 8),

              SwitchListTile(
                title: const Text('Ausência Justificada'),
                value: _isJustified,
                onChanged: (v) => setState(() => _isJustified = v),
                contentPadding: EdgeInsets.zero,
              ),

              if (_error != null)
                Text(_error!,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.error)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _isLoading ? null : _submit,
          child: _isLoading
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Text('Registar'),
        ),
      ],
    );
  }
}
