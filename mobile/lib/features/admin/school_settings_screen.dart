import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_client.dart';

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------
class SchoolYear {
  final String id;
  final String yearLabel;
  final DateTime startDate;
  final DateTime endDate;
  final bool isActive;

  const SchoolYear({
    required this.id,
    required this.yearLabel,
    required this.startDate,
    required this.endDate,
    required this.isActive,
  });

  factory SchoolYear.fromJson(Map<String, dynamic> json) => SchoolYear(
        id: json['id']?.toString() ?? '',
        yearLabel: json['year_label'] as String? ?? '',
        startDate:
            DateTime.tryParse(json['start_date'] as String? ?? '') ??
                DateTime.now(),
        endDate:
            DateTime.tryParse(json['end_date'] as String? ?? '') ??
                DateTime.now(),
        isActive: json['is_active'] as bool? ?? false,
      );
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------
final schoolYearsProvider =
    FutureProvider.autoDispose<List<SchoolYear>>((ref) async {
  final api = ref.read(apiClientProvider);
  final data = await api.get('/schools/school-years') as List;
  return data
      .map((e) => SchoolYear.fromJson(e as Map<String, dynamic>))
      .toList();
});

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------
class SchoolSettingsScreen extends ConsumerWidget {
  const SchoolSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schoolYearsAsync = ref.watch(schoolYearsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Anos Lectivos'),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCreateYearDialog(context, ref),
        tooltip: 'Novo Ano Lectivo',
        child: const Icon(Icons.add),
      ),
      body: schoolYearsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline,
                  size: 48, color: Colors.red),
              const SizedBox(height: 8),
              Text(e.toString(), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => ref.invalidate(schoolYearsProvider),
                icon: const Icon(Icons.refresh),
                label: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
        data: (years) {
          if (years.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.calendar_today,
                      size: 64,
                      color: Theme.of(context)
                          .colorScheme
                          .outlineVariant),
                  const SizedBox(height: 16),
                  Text(
                    'Nenhum ano lectivo encontrado',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Toque em + para criar o primeiro ano lectivo',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async =>
                ref.invalidate(schoolYearsProvider),
            child: ListView.builder(
              padding: const EdgeInsets.only(
                  left: 12, right: 12, top: 12, bottom: 88),
              itemCount: years.length,
              itemBuilder: (context, i) {
                final year = years[i];
                return _SchoolYearCard(
                  year: year,
                  onActivated: () =>
                      ref.invalidate(schoolYearsProvider),
                );
              },
            ),
          );
        },
      ),
    );
  }

  void _showCreateYearDialog(BuildContext context, WidgetRef ref) {
    showDialog(useRootNavigator: false, 
      context: context,
      builder: (_) => _CreateSchoolYearDialog(
        onCreated: () => ref.invalidate(schoolYearsProvider),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// School year card
// ---------------------------------------------------------------------------
class _SchoolYearCard extends ConsumerStatefulWidget {
  final SchoolYear year;
  final VoidCallback onActivated;

  const _SchoolYearCard(
      {required this.year, required this.onActivated});

  @override
  ConsumerState<_SchoolYearCard> createState() =>
      _SchoolYearCardState();
}

class _SchoolYearCardState
    extends ConsumerState<_SchoolYearCard> {
  bool _activating = false;

  Future<void> _activate() async {
    setState(() => _activating = true);
    try {
      final api = ref.read(apiClientProvider);
      await api.post(
          '/schools/school-years/${widget.year.id}/activate');
      widget.onActivated();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('Erro ao activar ano lectivo: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _activating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final year = widget.year;
    final dateFmt = DateFormat('dd/MM/yyyy');

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        year.yearLabel,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(
                                fontWeight: FontWeight.bold),
                      ),
                      if (year.isActive) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.15),
                            borderRadius:
                                BorderRadius.circular(10),
                            border: Border.all(
                                color:
                                    Colors.green.withOpacity(0.5)),
                          ),
                          child: const Text(
                            'Activo',
                            style: TextStyle(
                              color: Colors.green,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${dateFmt.format(year.startDate)} – ${dateFmt.format(year.endDate)}',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant),
                  ),
                ],
              ),
            ),
            if (!year.isActive)
              _activating
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2))
                  : OutlinedButton(
                      onPressed: _activate,
                      child: const Text('Activar'),
                    ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Create school year dialog
// ---------------------------------------------------------------------------
class _CreateSchoolYearDialog extends ConsumerStatefulWidget {
  final VoidCallback onCreated;

  const _CreateSchoolYearDialog({required this.onCreated});

  @override
  ConsumerState<_CreateSchoolYearDialog> createState() =>
      _CreateSchoolYearDialogState();
}

class _CreateSchoolYearDialogState
    extends ConsumerState<_CreateSchoolYearDialog> {
  final _formKey = GlobalKey<FormState>();
  final _labelCtrl = TextEditingController();
  DateTime _startDate = DateTime.now();
  DateTime _endDate =
      DateTime.now().add(const Duration(days: 365));
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _labelCtrl.dispose();
    super.dispose();
  }

  String _fmtDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _pickStart() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2050),
    );
    if (picked != null) setState(() => _startDate = picked);
  }

  Future<void> _pickEnd() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2050),
    );
    if (picked != null) setState(() => _endDate = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_endDate.isBefore(_startDate)) {
      setState(() =>
          _error = 'A data de fim deve ser após a data de início');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final api = ref.read(apiClientProvider);
      await api.post('/schools/school-years', data: {
        'year_label': _labelCtrl.text.trim(),
        'start_date': _fmtDate(_startDate),
        'end_date': _fmtDate(_endDate),
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
    final displayFmt = DateFormat('dd/MM/yyyy');

    return AlertDialog(
      title: const Text('Novo Ano Lectivo'),
      content: SizedBox(
        width: double.maxFinite,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _labelCtrl,
                decoration: const InputDecoration(
                  labelText: 'Designação (ex: 2024/2025) *',
                  prefixIcon: Icon(Icons.label_outline),
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty
                        ? 'Campo obrigatório'
                        : null,
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: _pickStart,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Data de Início *',
                    prefixIcon: Icon(Icons.calendar_today),
                  ),
                  child:
                      Text(displayFmt.format(_startDate)),
                ),
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: _pickEnd,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Data de Fim *',
                    prefixIcon: Icon(Icons.calendar_month),
                  ),
                  child: Text(displayFmt.format(_endDate)),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!,
                    style: TextStyle(
                        color: Theme.of(context)
                            .colorScheme
                            .error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed:
              _isLoading ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _isLoading ? null : _submit,
          child: _isLoading
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white))
              : const Text('Criar'),
        ),
      ],
    );
  }
}
