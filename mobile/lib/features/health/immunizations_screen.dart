import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_client.dart';
import '../../core/models/child.dart';
import '../../core/theme/app_theme.dart';

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------
class Immunization {
  final String id;
  final String childId;
  final String? childName;
  final String vaccineName;
  final String? administeredAt;
  final String? dueDate;
  final String? administeredBy;
  final int? doseNumber;
  final String? notes;

  const Immunization({
    required this.id,
    required this.childId,
    this.childName,
    required this.vaccineName,
    this.administeredAt,
    this.dueDate,
    this.administeredBy,
    this.doseNumber,
    this.notes,
  });

  factory Immunization.fromJson(Map<String, dynamic> json) {
    return Immunization(
      id: json['id']?.toString() ?? '',
      childId: json['child_id']?.toString() ?? '',
      childName: json['child_name'] as String?,
      vaccineName: json['vaccine_name'] as String? ?? '',
      administeredAt: json['administered_at'] as String?,
      dueDate: json['due_date'] as String?,
      administeredBy: json['administered_by'] as String?,
      doseNumber: json['dose_number'] as int?,
      notes: json['notes'] as String?,
    );
  }

  /// Returns:
  ///   - green  if administered_at is set
  ///   - orange if due_date is in the future and not administered
  ///   - red    if due_date is past and not administered
  ///   - grey   if neither date is set
  Color get statusColor {
    if (administeredAt != null) return AppTheme.success;
    if (dueDate != null) {
      final due = DateTime.tryParse(dueDate!);
      if (due != null) {
        return due.isAfter(DateTime.now()) ? AppTheme.warning : AppTheme.danger;
      }
    }
    return AppTheme.textSecondary;
  }

  String get statusLabel {
    if (administeredAt != null) return 'Administrada';
    if (dueDate != null) {
      final due = DateTime.tryParse(dueDate!);
      if (due != null) {
        return due.isAfter(DateTime.now()) ? 'Prevista' : 'Em atraso';
      }
    }
    return 'Por agendar';
  }
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------
final immunizationsProvider =
    FutureProvider.autoDispose.family<List<Immunization>, String?>(
  (ref, childId) async {
    final api = ref.read(apiClientProvider);
    final path =
        childId != null ? '/immunizations?child_id=$childId' : '/immunizations';
    final res = await api.get(path) as List;
    return res
        .map((e) => Immunization.fromJson(e as Map<String, dynamic>))
        .toList();
  },
);

final childrenForImmunizationsProvider =
    FutureProvider.autoDispose((ref) async {
  final api = ref.read(apiClientProvider);
  final res = await api.get('/children?limit=200') as List;
  return res
      .map((e) => Child.fromJson(e as Map<String, dynamic>))
      .toList();
});

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------
class ImmunizationsScreen extends ConsumerStatefulWidget {
  const ImmunizationsScreen({super.key});

  @override
  ConsumerState<ImmunizationsScreen> createState() =>
      _ImmunizationsScreenState();
}

class _ImmunizationsScreenState extends ConsumerState<ImmunizationsScreen> {
  String? _selectedChildId;

  @override
  Widget build(BuildContext context) {
    final immunizationsAsync =
        ref.watch(immunizationsProvider(_selectedChildId));
    final childrenAsync = ref.watch(childrenForImmunizationsProvider);

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text('Vacinas'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                ref.invalidate(immunizationsProvider(_selectedChildId)),
          ),
        ],
      ),
      body: Column(
        children: [
          // Child filter
          childrenAsync.when(
            data: (children) => Padding(
              padding: const EdgeInsets.all(16),
              child: DropdownButtonFormField<String?>(
                value: _selectedChildId,
                decoration: const InputDecoration(
                  labelText: 'Filtrar por criança',
                  prefixIcon: Icon(Icons.child_care),
                  border: OutlineInputBorder(),
                  filled: true,
                  fillColor: Colors.white,
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Todas as crianças'),
                  ),
                  ...children.map((c) => DropdownMenuItem<String?>(
                        value: c.id,
                        child: Text('${c.firstName} ${c.lastName}'),
                      )),
                ],
                onChanged: (v) => setState(() => _selectedChildId = v),
              ),
            ),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
          // List
          Expanded(
            child: immunizationsAsync.when(
              data: (items) => items.isEmpty
                  ? const Center(
                      child: Text('Nenhum registo de vacinação encontrado'))
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) =>
                          _ImmunizationCard(immunization: items[i]),
                    ),
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Erro: $e')),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        onPressed: () async {
          if (!mounted) return;
          final created = await showDialog<bool>(useRootNavigator: false,
            context: context,
            builder: (ctx) => _CreateImmunizationDialog(
              preselectedChildId: _selectedChildId,
            ),
          );
          if (created == true) {
            ref.invalidate(immunizationsProvider(_selectedChildId));
          }
        },
        icon: const Icon(Icons.add),
        label: const Text('Registar'),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Immunization Card
// ---------------------------------------------------------------------------
class _ImmunizationCard extends StatelessWidget {
  final Immunization immunization;
  const _ImmunizationCard({required this.immunization});

  String _formatDate(String? raw) {
    if (raw == null) return '—';
    final d = DateTime.tryParse(raw);
    if (d == null) return raw;
    return DateFormat('dd/MM/yyyy').format(d);
  }

  @override
  Widget build(BuildContext context) {
    final color = immunization.statusColor;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppTheme.border),
      ),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row: status chip + child name
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    immunization.statusLabel,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
                const Spacer(),
                if (immunization.doseNumber != null)
                  Text(
                    'Dose ${immunization.doseNumber}',
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            // Vaccine name
            Text(
              immunization.vaccineName,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: AppTheme.textPrimary,
              ),
            ),
            // Child name
            if (immunization.childName != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.child_care,
                      size: 14, color: AppTheme.textSecondary),
                  const SizedBox(width: 4),
                  Text(
                    immunization.childName!,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            // Dates row
            Row(
              children: [
                if (immunization.administeredAt != null) ...[
                  const Icon(Icons.check_circle_outline,
                      size: 14, color: AppTheme.success),
                  const SizedBox(width: 4),
                  Text(
                    'Administrada em: ${_formatDate(immunization.administeredAt)}',
                    style: const TextStyle(
                        color: AppTheme.textSecondary, fontSize: 12),
                  ),
                  const SizedBox(width: 12),
                ],
                if (immunization.dueDate != null) ...[
                  const Icon(Icons.calendar_today,
                      size: 14, color: AppTheme.textSecondary),
                  const SizedBox(width: 4),
                  Text(
                    'Prevista para: ${_formatDate(immunization.dueDate)}',
                    style: const TextStyle(
                        color: AppTheme.textSecondary, fontSize: 12),
                  ),
                ],
              ],
            ),
            // Administered by
            if (immunization.administeredBy != null &&
                immunization.administeredBy!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.person_outline,
                      size: 14, color: AppTheme.textSecondary),
                  const SizedBox(width: 4),
                  Text(
                    'Por: ${immunization.administeredBy}',
                    style: const TextStyle(
                        color: AppTheme.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ],
            // Notes
            if (immunization.notes != null &&
                immunization.notes!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                immunization.notes!,
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Create Immunization Dialog
// ---------------------------------------------------------------------------
class _CreateImmunizationDialog extends ConsumerStatefulWidget {
  final String? preselectedChildId;

  const _CreateImmunizationDialog({
    this.preselectedChildId,
  });

  @override
  ConsumerState<_CreateImmunizationDialog> createState() =>
      _CreateImmunizationDialogState();
}

class _CreateImmunizationDialogState
    extends ConsumerState<_CreateImmunizationDialog> {
  final _formKey = GlobalKey<FormState>();
  String? _childId;
  final _vaccineCtrl = TextEditingController();
  final _administeredByCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  DateTime? _administeredAt;
  DateTime? _dueDate;
  int? _doseNumber;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _childId = widget.preselectedChildId;
  }

  @override
  void dispose() {
    _vaccineCtrl.dispose();
    _administeredByCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate({
    required String label,
    required DateTime? current,
    required ValueChanged<DateTime> onPicked,
  }) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: label,
    );
    if (picked != null) onPicked(picked);
  }

  String _formatDate(DateTime? d) {
    if (d == null) return 'Selecionar data';
    return DateFormat('dd/MM/yyyy').format(d);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_childId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Selecione uma criança')));
      return;
    }
    setState(() => _loading = true);
    try {
      final api = ref.read(apiClientProvider);
      final body = <String, dynamic>{
        'child_id': _childId,
        'vaccine_name': _vaccineCtrl.text.trim(),
      };
      if (_administeredAt != null) {
        body['administered_at'] =
            DateFormat('yyyy-MM-dd').format(_administeredAt!);
      }
      if (_dueDate != null) {
        body['due_date'] = DateFormat('yyyy-MM-dd').format(_dueDate!);
      }
      if (_administeredByCtrl.text.trim().isNotEmpty) {
        body['administered_by'] = _administeredByCtrl.text.trim();
      }
      if (_doseNumber != null) {
        body['dose_number'] = _doseNumber;
      }
      if (_notesCtrl.text.trim().isNotEmpty) {
        body['notes'] = _notesCtrl.text.trim();
      }
      await api.post('/immunizations', data: body);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final childrenAsync = ref.watch(childrenForImmunizationsProvider);
    return AlertDialog(
      title: const Text('Registar Vacina'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Child selector
                childrenAsync.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (_, __) => const Text('Erro ao carregar crianças'),
                  data: (children) => DropdownButtonFormField<String?>(
                    value: _childId,
                    decoration: const InputDecoration(
                      labelText: 'Criança *',
                      border: OutlineInputBorder(),
                    ),
                    items: children
                        .map((c) => DropdownMenuItem<String?>(
                              value: c.id,
                              child: Text('${c.firstName} ${c.lastName}'),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => _childId = v),
                    validator: (v) => v == null ? 'Obrigatório' : null,
                  ),
                ),
                const SizedBox(height: 12),
                // Vaccine name
                TextFormField(
                  controller: _vaccineCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Vacina *',
                    border: OutlineInputBorder(),
                    hintText: 'Ex: BCG, Hepatite B, DTPa...',
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Obrigatório' : null,
                ),
                const SizedBox(height: 12),
                // Dose number
                TextFormField(
                  decoration: const InputDecoration(
                    labelText: 'Dose',
                    border: OutlineInputBorder(),
                    hintText: 'Ex: 1',
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (v) =>
                      setState(() => _doseNumber = int.tryParse(v)),
                ),
                const SizedBox(height: 12),
                // Administered at picker
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    alignment: Alignment.centerLeft,
                    foregroundColor: _administeredAt != null
                        ? AppTheme.success
                        : AppTheme.textSecondary,
                    side: BorderSide(color: AppTheme.border),
                  ),
                  icon: const Icon(Icons.check_circle_outline, size: 18),
                  label: Text(
                    'Administrada em: ${_formatDate(_administeredAt)}',
                    style: const TextStyle(fontSize: 13),
                  ),
                  onPressed: () => _pickDate(
                    label: 'Administrada em',
                    current: _administeredAt,
                    onPicked: (d) => setState(() => _administeredAt = d),
                  ),
                ),
                const SizedBox(height: 8),
                // Due date picker
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    alignment: Alignment.centerLeft,
                    foregroundColor: _dueDate != null
                        ? AppTheme.primary
                        : AppTheme.textSecondary,
                    side: BorderSide(color: AppTheme.border),
                  ),
                  icon: const Icon(Icons.calendar_today, size: 18),
                  label: Text(
                    'Prevista para: ${_formatDate(_dueDate)}',
                    style: const TextStyle(fontSize: 13),
                  ),
                  onPressed: () => _pickDate(
                    label: 'Prevista para',
                    current: _dueDate,
                    onPicked: (d) => setState(() => _dueDate = d),
                  ),
                ),
                const SizedBox(height: 12),
                // Administered by
                TextFormField(
                  controller: _administeredByCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Por',
                    border: OutlineInputBorder(),
                    hintText: 'Nome do profissional de saúde',
                  ),
                ),
                const SizedBox(height: 12),
                // Notes
                TextFormField(
                  controller: _notesCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Notas',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _loading ? null : _submit,
          child: _loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Text('Registar'),
        ),
      ],
    );
  }
}
