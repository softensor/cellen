import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_client.dart';
import '../../../core/providers/currency_provider.dart';
import '../../../core/widgets/app_error_widget.dart';
import 'fee_automation_common.dart';

final _modalitiesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final data =
      await ref.read(apiClientProvider).get('/billing/modalities') as List;
  return data.map((row) => Map<String, dynamic>.from(row as Map)).toList();
});

class ModalitiesScreen extends ConsumerWidget {
  const ModalitiesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final modalities = ref.watch(_modalitiesProvider);
    final currency = ref.watch(currencyFormatProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Modalidades'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(_modalitiesProvider),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Nova modalidade'),
      ),
      body: modalities.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => AppErrorWidget(
          error: error,
          onRetry: () => ref.invalidate(_modalitiesProvider),
        ),
        data: (rows) {
          if (rows.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(28),
                child: Text(
                  'Nenhuma modalidade. Crie balé, capoeira, natação e as '
                  'restantes actividades extracurriculares para as cobrar '
                  'automaticamente.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(_modalitiesProvider),
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
              itemCount: rows.length,
              itemBuilder: (_, index) => _ModalityCard(
                modality: rows[index],
                currency: currency,
                onChanged: () => ref.invalidate(_modalitiesProvider),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _openEditor(BuildContext context, WidgetRef ref) async {
    final changed = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (_) => const _ModalityDialog(),
    );
    if (changed == true) ref.invalidate(_modalitiesProvider);
  }
}

class _ModalityCard extends ConsumerWidget {
  const _ModalityCard({
    required this.modality,
    required this.currency,
    required this.onChanged,
  });

  final Map<String, dynamic> modality;
  final NumberFormat currency;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = modality['is_active'] != false;
    final item = Map<String, dynamic>.from(
      modality['billing_item'] as Map? ?? const {},
    );
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text(
                  modality['name']?.toString() ?? 'Modalidade',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Chip(label: Text(active ? 'Activa' : 'Inactiva')),
            ]),
            if ((modality['description']?.toString() ?? '').isNotEmpty)
              Text(modality['description'].toString()),
            const SizedBox(height: 8),
            Wrap(spacing: 16, runSpacing: 6, children: [
              Text('Mensal: ${currency.format(
                (modality['monthly_fee'] as num?)?.toDouble() ?? 0,
              )}'),
              Text('Inscrição: ${currency.format(
                (modality['inscription_fee'] as num?)?.toDouble() ?? 0,
              )}'),
              Text('Inscritos: ${modality['enrolled_count'] ?? 0}'),
            ]),
            if ((item['name']?.toString() ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Serviço fiscal: ${item['name']}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 4),
            Row(children: [
              TextButton.icon(
                onPressed: () => _enroll(context, ref),
                icon: const Icon(Icons.person_add_alt_outlined, size: 18),
                label: const Text('Inscrever aluno'),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Editar',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => _edit(context, ref),
              ),
              IconButton(
                tooltip: active ? 'Desactivar' : 'Reactivar',
                icon: Icon(
                  active
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
                onPressed: () => _toggle(context, ref, active),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final changed = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (_) => _ModalityDialog(modality: modality),
    );
    if (changed == true) onChanged();
  }

  Future<void> _toggle(
    BuildContext context,
    WidgetRef ref,
    bool active,
  ) async {
    try {
      await ref.read(apiClientProvider).patch(
        '/billing/modalities/${modality['id']}',
        data: {'is_active': !active},
      );
      onChanged();
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro: $error')));
      }
    }
  }

  Future<void> _enroll(BuildContext context, WidgetRef ref) async {
    final message = await showDialog<String>(
      context: context,
      useRootNavigator: false,
      builder: (_) => _EnrollDialog(
        modalityId: modality['id'].toString(),
        modalityName: modality['name']?.toString() ?? 'Modalidade',
      ),
    );
    if (message != null) {
      onChanged();
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    }
  }
}

class _ModalityDialog extends ConsumerStatefulWidget {
  const _ModalityDialog({this.modality});

  final Map<String, dynamic>? modality;

  @override
  ConsumerState<_ModalityDialog> createState() => _ModalityDialogState();
}

class _ModalityDialogState extends ConsumerState<_ModalityDialog> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _inscriptionFee;
  late final TextEditingController _monthlyFee;
  String? _billingItemId;
  bool _active = true;
  bool _saving = false;
  String? _error;

  bool get _editing => widget.modality != null;

  @override
  void initState() {
    super.initState();
    final modality = widget.modality ?? const <String, dynamic>{};
    _name = TextEditingController(text: modality['name']?.toString() ?? '');
    _description =
        TextEditingController(text: modality['description']?.toString() ?? '');
    _inscriptionFee = TextEditingController(
      text: moneyText(modality['inscription_fee'] ?? 0),
    );
    _monthlyFee = TextEditingController(
      text: moneyText(modality['monthly_fee'] ?? 0),
    );
    _billingItemId = modality['billing_item_id']?.toString();
    _active = modality['is_active'] != false;
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _inscriptionFee.dispose();
    _monthlyFee.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(feeBillingItemsProvider);
    return AlertDialog(
      title: Text(_editing ? 'Editar modalidade' : 'Nova modalidade'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Nome *'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _description,
              decoration: const InputDecoration(labelText: 'Descrição'),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _monthlyFee,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration:
                      const InputDecoration(labelText: 'Mensalidade (Kz)'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _inscriptionFee,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration:
                      const InputDecoration(labelText: 'Inscrição (Kz)'),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            items.when(
              loading: () => const LinearProgressIndicator(),
              error: (_, __) =>
                  const Text('Não foi possível carregar os serviços.'),
              data: (rows) => DropdownButtonFormField<String?>(
                value: _billingItemId,
                decoration: const InputDecoration(
                  labelText: 'Serviço fiscal',
                  helperText:
                      'Necessário para cobrar a inscrição e a mensalidade.',
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Sem serviço fiscal'),
                  ),
                  for (final item in rows)
                    DropdownMenuItem<String?>(
                      value: item['id'].toString(),
                      child: Text(item['name'].toString()),
                    ),
                ],
                onChanged: (value) => setState(() => _billingItemId = value),
              ),
            ),
            const SizedBox(height: 4),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Activa'),
              value: _active,
              onChanged: (value) => setState(() => _active = value),
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ]),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_editing ? 'Guardar' : 'Criar'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Indique o nome da modalidade.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final body = {
      'name': _name.text.trim(),
      'description':
          _description.text.trim().isEmpty ? null : _description.text.trim(),
      'inscription_fee': parseMoney(_inscriptionFee.text),
      'monthly_fee': parseMoney(_monthlyFee.text),
      'billing_item_id': _billingItemId,
      'is_active': _active,
    };
    try {
      final api = ref.read(apiClientProvider);
      if (_editing) {
        await api.patch(
          '/billing/modalities/${widget.modality!['id']}',
          data: body,
        );
      } else {
        await api.post('/billing/modalities', data: body);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      setState(() {
        _saving = false;
        _error = error.toString();
      });
    }
  }
}

class _EnrollDialog extends ConsumerStatefulWidget {
  const _EnrollDialog({required this.modalityId, required this.modalityName});

  final String modalityId;
  final String modalityName;

  @override
  ConsumerState<_EnrollDialog> createState() => _EnrollDialogState();
}

class _EnrollDialogState extends ConsumerState<_EnrollDialog> {
  String? _childId;
  DateTime _startDate = DateTime.now();
  bool _saving = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final students = ref.watch(feeStudentsProvider);
    return AlertDialog(
      title: Text('Inscrever em ${widget.modalityName}'),
      content: SizedBox(
        width: 460,
        child: students.when(
          loading: () => const SizedBox(
            height: 120,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => Text('Erro ao carregar alunos: $error'),
          data: (rows) => SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String>(
                value: _childId,
                decoration: const InputDecoration(labelText: 'Aluno *'),
                items: [
                  for (final row in rows)
                    DropdownMenuItem(
                      value: row['id'].toString(),
                      child: Text(
                        '${row['first_name'] ?? ''} ${row['last_name'] ?? ''}'
                            .trim(),
                      ),
                    ),
                ],
                onChanged: (value) => setState(() => _childId = value),
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Início'),
                subtitle: Text(
                  '${_startDate.day.toString().padLeft(2, '0')}/'
                  '${_startDate.month.toString().padLeft(2, '0')}/'
                  '${_startDate.year}',
                ),
                trailing: const Icon(Icons.calendar_today_outlined),
                onTap: () async {
                  final value = await showDatePicker(
                    context: context,
                    initialDate: _startDate,
                    firstDate: DateTime(2000),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (value != null) setState(() => _startDate = value);
                },
              ),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ]),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'A inscrever…' : 'Inscrever'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (_childId == null) {
      setState(() => _error = 'Seleccione o aluno.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final response = await ref.read(apiClientProvider).post(
        '/billing/modalities/${widget.modalityId}/enroll',
        data: {
          'child_id': _childId,
          'start_date':
              '${_startDate.year}-${_startDate.month.toString().padLeft(2, '0')}'
                  '-${_startDate.day.toString().padLeft(2, '0')}',
        },
      ) as Map;
      final inscription = Map<String, dynamic>.from(
        response['inscription'] as Map? ?? const {},
      );
      final message = switch (inscription['mode']) {
        'finreg' => inscription['status'] == 'confirmed'
            ? 'Inscrição registada e cobrança confirmada no Finreg.'
            : 'Inscrição registada. A cobrança segue para o Finreg pela fila.',
        'internal' => 'Inscrição registada e factura emitida: '
            '${inscription['invoice_number'] ?? ''}.',
        _ => 'Inscrição registada (sem taxa de inscrição).',
      };
      if (mounted) Navigator.pop(context, message);
    } catch (error) {
      setState(() {
        _saving = false;
        _error = error.toString();
      });
    }
  }
}
