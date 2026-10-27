import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_client.dart';
import '../../../core/providers/currency_provider.dart';
import '../../../core/widgets/app_error_widget.dart';
import 'fee_automation_common.dart';

final _debtsProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, key) async {
  final parts = key.split('|');
  final overdue = parts.first == 'overdue';
  final service = parts.length > 1 && parts[1].isNotEmpty ? parts[1] : null;
  final data = await ref.read(apiClientProvider).get(
    '/billing/debts',
    queryParameters: {
      'overdue_only': overdue,
      if (service != null) 'service': service,
    },
  ) as Map;
  return Map<String, dynamic>.from(data);
});

/// Every open debt, whichever engine owns the school, grouped by student.
/// The director sees one number per pupil and one per service, and can open
/// a principia-pay reference straight from the row.
class DebtControlScreen extends ConsumerStatefulWidget {
  const DebtControlScreen({super.key});

  @override
  ConsumerState<DebtControlScreen> createState() => _DebtControlScreenState();
}

class _DebtControlScreenState extends ConsumerState<DebtControlScreen> {
  bool _overdueOnly = false;
  String? _service;

  String get _key => '${_overdueOnly ? 'overdue' : 'all'}|${_service ?? ''}';

  Future<void> _openReference(
    BuildContext context,
    Map<String, dynamic> row,
    NumberFormat currency,
  ) async {
    final outstanding = (row['outstanding'] as num?)?.toDouble() ?? 0;
    final amount = await showDialog<double>(
      context: context,
      builder: (context) => _ReferenceAmountDialog(
        title: row['document_number']?.toString() ?? 'Dívida',
        student: row['student_name']?.toString() ?? '',
        outstanding: outstanding,
        currency: currency,
      ),
    );
    if (amount == null || !context.mounted) return;
    try {
      final reference = await ref.read(apiClientProvider).post(
        '/billing/principia-pay/references',
        data: {
          'document_id': row['document_id'].toString(),
          'amount': amount,
        },
      ) as Map;
      if (!context.mounted) return;
      await _showReference(context, Map<String, dynamic>.from(reference));
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível gerar a referência: $error')),
      );
    }
  }

  Future<void> _showReference(
    BuildContext context,
    Map<String, dynamic> reference,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (context) => _ReferenceDialog(reference: reference),
    );
  }

  @override
  Widget build(BuildContext context) {
    final debts = ref.watch(_debtsProvider(_key));
    final currency = ref.watch(currencyFormatProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Controlo de Dívidas'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(_debtsProvider(_key)),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(_debtsProvider(_key)),
        child: debts.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => ListView(
            children: [
              const SizedBox(height: 80),
              AppErrorWidget(
                error: error,
                onRetry: () => ref.invalidate(_debtsProvider(_key)),
              ),
            ],
          ),
          data: (data) => _DebtsBody(
            data: data,
            currency: currency,
            overdueOnly: _overdueOnly,
            service: _service,
            onOverdueChanged: (value) => setState(() => _overdueOnly = value),
            onServiceChanged: (value) => setState(() => _service = value),
            onOpenReference: (row) => _openReference(context, row, currency),
          ),
        ),
      ),
    );
  }
}

class _DebtsBody extends StatelessWidget {
  const _DebtsBody({
    required this.data,
    required this.currency,
    required this.overdueOnly,
    required this.service,
    required this.onOverdueChanged,
    required this.onServiceChanged,
    required this.onOpenReference,
  });

  final Map<String, dynamic> data;
  final NumberFormat currency;
  final bool overdueOnly;
  final String? service;
  final ValueChanged<bool> onOverdueChanged;
  final ValueChanged<String?> onServiceChanged;
  final ValueChanged<Map<String, dynamic>> onOpenReference;

  double _money(dynamic value) => (value as num?)?.toDouble() ?? 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = ((data['rows'] as List?) ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
    final services = ((data['by_service'] as List?) ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
    final byStudent = <String, List<Map<String, dynamic>>>{};
    for (final row in rows) {
      final key = row['student_id']?.toString() ?? 'sem-aluno';
      byStudent.putIfAbsent(key, () => []).add(row);
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: theme.colorScheme.surfaceContainerHighest,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Total em dívida',
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant)),
                      Text(
                        currency.format(_money(data['total_outstanding'])),
                        style: theme.textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        '${data['count'] ?? 0} documento(s) · '
                        '${currency.format(_money(data['total_overdue']))} em atraso',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Chip(
                  label:
                      Text(data['mode'] == 'internal' ? 'Interno' : 'FinReg'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Só em atraso'),
                value: overdueOnly,
                onChanged: onOverdueChanged,
              ),
            ),
            if (services.isNotEmpty)
              DropdownButton<String?>(
                value: service,
                hint: const Text('Serviço'),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Todos'),
                  ),
                  for (final entry in services)
                    DropdownMenuItem<String?>(
                      value: entry['service']?.toString() ??
                          entry['service_label']?.toString(),
                      child: Text(
                        entry['service_label']?.toString() ??
                            entry['service']?.toString() ??
                            'Outros',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: onServiceChanged,
              ),
          ],
        ),
        const Divider(),
        if (rows.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: Text('Sem dívidas com estes filtros.')),
          ),
        for (final entry in byStudent.entries) ...[
          _StudentDebtGroup(
            rows: entry.value,
            currency: currency,
            onOpenReference: onOpenReference,
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _StudentDebtGroup extends StatelessWidget {
  const _StudentDebtGroup({
    required this.rows,
    required this.currency,
    required this.onOpenReference,
  });

  final List<Map<String, dynamic>> rows;
  final NumberFormat currency;
  final ValueChanged<Map<String, dynamic>> onOpenReference;

  @override
  Widget build(BuildContext context) {
    final total = rows.fold<double>(
        0, (sum, row) => sum + ((row['outstanding'] as num?)?.toDouble() ?? 0));
    final name =
        rows.first['student_name']?.toString() ?? 'Sem aluno associado';
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text('${rows.length} documento(s)'),
        trailing: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              currency.format(total),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const Icon(Icons.expand_more, size: 18),
          ],
        ),
        children: [
          for (final row in rows)
            _DebtRowTile(
              row: row,
              currency: currency,
              onOpenReference: () => onOpenReference(row),
            ),
        ],
      ),
    );
  }
}

class _DebtRowTile extends StatelessWidget {
  const _DebtRowTile({
    required this.row,
    required this.currency,
    required this.onOpenReference,
  });

  final Map<String, dynamic> row;
  final NumberFormat currency;
  final VoidCallback onOpenReference;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final days = (row['days_overdue'] as num?)?.toInt() ?? 0;
    final services = ((row['services'] as List?) ?? const [])
        .whereType<Map>()
        .map((service) => Map<String, dynamic>.from(service))
        .toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row['document_number']?.toString() ?? 'Documento',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      'Vence ${formatIsoDate(row['due_date']?.toString())}'
                      '${days > 0 ? ' · $days dia(s) em atraso' : ''}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: days > 0
                            ? theme.colorScheme.error
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                currency.format((row['outstanding'] as num?)?.toDouble() ?? 0),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          if (services.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final service in services)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text(
                      '${service['service_label'] ?? service['service'] ?? 'Serviço'}'
                      ' · ${currency.format((service['outstanding_amount'] as num?)?.toDouble() ?? 0)}',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onOpenReference,
              icon: const Icon(Icons.qr_code_2, size: 18),
              label: const Text('Gerar referência'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReferenceAmountDialog extends StatefulWidget {
  const _ReferenceAmountDialog({
    required this.title,
    required this.student,
    required this.outstanding,
    required this.currency,
  });

  final String title;
  final String student;
  final double outstanding;
  final NumberFormat currency;

  @override
  State<_ReferenceAmountDialog> createState() => _ReferenceAmountDialogState();
}

class _ReferenceAmountDialogState extends State<_ReferenceAmountDialog> {
  late final TextEditingController _amount;

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController(text: moneyText(widget.outstanding));
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Gerar referência de pagamento'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${widget.title} · ${widget.student}'),
          Text(
            'Saldo: ${widget.currency.format(widget.outstanding)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Valor (Kz)'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            final value = parseMoney(_amount.text);
            if (value <= 0) return;
            Navigator.pop(context, value);
          },
          child: const Text('Gerar'),
        ),
      ],
    );
  }
}

class _ReferenceDialog extends StatelessWidget {
  const _ReferenceDialog({required this.reference});

  final Map<String, dynamic> reference;

  Future<void> _copy(BuildContext context, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copiado.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final entity = reference['entity']?.toString() ?? '—';
    final number = reference['reference']?.toString() ?? '—';
    final checkout = reference['checkout_url']?.toString();
    return AlertDialog(
      title: const Text('Referência criada'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CopyRow(
            label: 'Entidade',
            value: entity,
            onCopy: () => _copy(context, entity),
          ),
          const SizedBox(height: 8),
          _CopyRow(
            label: 'Referência',
            value: number,
            onCopy: () => _copy(context, number),
          ),
          if (checkout != null && checkout.isNotEmpty) ...[
            const SizedBox(height: 8),
            SelectableText(
              checkout,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 8),
          Text(
            'O pagamento é conciliado automaticamente e fica registado no motor fiscal.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Fechar'),
        ),
      ],
    );
  }
}

class _CopyRow extends StatelessWidget {
  const _CopyRow({
    required this.label,
    required this.value,
    required this.onCopy,
  });

  final String label;
  final String value;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 92, child: Text(label)),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 15),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.copy, size: 18),
          onPressed: onCopy,
        ),
      ],
    );
  }
}
