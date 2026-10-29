import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/providers/currency_provider.dart';
import '../../../core/widgets/app_error_widget.dart';
import 'fee_automation_common.dart';

const _bucketLabels = <String, String>{
  'current': 'Em dia',
  'bucket_0_30': '0–30 dias',
  'bucket_31_60': '31–60 dias',
  'bucket_61_90': '61–90 dias',
  'bucket_90_plus': '+90 dias',
};

final _debtsProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, key) async {
  final parts = key.split('|');
  final overdue = parts.first == 'overdue';
  final service = parts.length > 1 && parts[1].isNotEmpty ? parts[1] : null;
  final bucket = parts.length > 2 && parts[2].isNotEmpty ? parts[2] : null;
  final data = await ref.read(apiClientProvider).get(
    '/billing/debts',
    queryParameters: {
      'overdue_only': overdue,
      if (service != null) 'service': service,
      if (bucket != null) 'bucket': bucket,
    },
  ) as Map;
  return Map<String, dynamic>.from(data);
});

/// Every open debt, whichever engine owns the school, grouped by student.
/// The director sees one number per pupil and one per service, and can open
/// a principia-pay reference straight from the row.
///
/// It accepts the dashboard's filters ([initialOverdue], [initialService],
/// [initialBucket]) so clicking a KPI, an aging chip or a service row lands
/// on exactly the documents behind that number.
class DebtControlScreen extends ConsumerStatefulWidget {
  const DebtControlScreen({
    super.key,
    this.initialOverdue = false,
    this.initialService,
    this.initialBucket,
  });

  final bool initialOverdue;
  final String? initialService;
  final String? initialBucket;

  @override
  ConsumerState<DebtControlScreen> createState() => _DebtControlScreenState();
}

class _DebtControlScreenState extends ConsumerState<DebtControlScreen> {
  late bool _overdueOnly;
  late String? _service;
  late String? _bucket;
  String? _generatingDocumentId;

  @override
  void initState() {
    super.initState();
    _overdueOnly = widget.initialOverdue;
    _service = widget.initialService;
    _bucket = widget.initialBucket;
  }

  String get _key =>
      '${_overdueOnly ? 'overdue' : 'all'}|${_service ?? ''}|${_bucket ?? ''}';

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

    final documentId = row['document_id']?.toString();
    setState(() => _generatingDocumentId = documentId);
    try {
      final reference = await ref.read(apiClientProvider).post(
            '/billing/principia-pay/references',
            data: {
              'document_id': documentId,
              'amount': amount,
            },
            // The rail is an external provider; give it more room than the
            // default list call so a slow provider does not look like a dead
            // network to the person waiting.
            receiveTimeout: const Duration(seconds: 45),
          ) as Map;
      // Stop the row spinner before the dialog opens; a spinner running
      // under a modal keeps the whole route animating.
      if (mounted) setState(() => _generatingDocumentId = null);
      if (!context.mounted) return;
      await _showReference(context, Map<String, dynamic>.from(reference));
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(apiErrorMessage(error))),
      );
    } finally {
      if (mounted) setState(() => _generatingDocumentId = null);
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

  Future<void> _showDetails(
    BuildContext context,
    Map<String, dynamic> row,
    NumberFormat currency,
  ) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _DebtDetailSheet(row: row, currency: currency),
    );
    if (!context.mounted) return;
    if (action == 'student') {
      final studentId = row['student_id']?.toString();
      if (studentId != null && studentId.isNotEmpty) {
        context.push('/admin/children/$studentId');
      }
    } else if (action == 'reference') {
      await _openReference(context, row, currency);
    } else if (action == 'payment') {
      final documentId = row['document_id']?.toString();
      if (documentId != null && documentId.isNotEmpty) {
        await context.push(
          '/admin/finance/record-payment'
          '?document_id=${Uri.encodeQueryComponent(documentId)}',
        );
        ref.invalidate(_debtsProvider(_key));
      }
    }
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
            bucket: _bucket,
            generatingDocumentId: _generatingDocumentId,
            onOverdueChanged: (value) => setState(() => _overdueOnly = value),
            onServiceChanged: (value) => setState(() => _service = value),
            onClearBucket: () => setState(() => _bucket = null),
            onClearFilters: () => setState(() {
              _overdueOnly = false;
              _service = null;
              _bucket = null;
            }),
            onOpenReference: (row) => _openReference(context, row, currency),
            onOpenDetails: (row) => _showDetails(context, row, currency),
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
    required this.bucket,
    required this.generatingDocumentId,
    required this.onOverdueChanged,
    required this.onServiceChanged,
    required this.onClearBucket,
    required this.onClearFilters,
    required this.onOpenReference,
    required this.onOpenDetails,
  });

  final Map<String, dynamic> data;
  final NumberFormat currency;
  final bool overdueOnly;
  final String? service;
  final String? bucket;
  final String? generatingDocumentId;
  final ValueChanged<bool> onOverdueChanged;
  final ValueChanged<String?> onServiceChanged;
  final VoidCallback onClearBucket;
  final VoidCallback onClearFilters;
  final ValueChanged<Map<String, dynamic>> onOpenReference;
  final ValueChanged<Map<String, dynamic>> onOpenDetails;

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
    // A filter arriving from the dashboard may not be present in the
    // filtered response (for example, no rows match it). The dropdown
    // still needs an item carrying the selected value.
    final serviceKeys = {
      for (final entry in services)
        entry['service']?.toString() ?? entry['service_label']?.toString(),
    };
    final syntheticService = service != null && !serviceKeys.contains(service)
        ? [
            <String, dynamic>{
              'service': service,
              'service_label': service,
            }
          ]
        : const <Map<String, dynamic>>[];
    final serviceOptions = [...syntheticService, ...services];
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
            if (serviceOptions.isNotEmpty)
              DropdownButton<String?>(
                value: service,
                hint: const Text('Serviço'),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Todos'),
                  ),
                  for (final entry in serviceOptions)
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
        if (overdueOnly || service != null || bucket != null) ...[
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (overdueOnly)
                InputChip(
                  label: const Text('Em atraso'),
                  avatar: const Icon(Icons.warning_amber, size: 16),
                  onDeleted: () => onOverdueChanged(false),
                ),
              if (service != null)
                InputChip(
                  label: Text('Serviço: $service'),
                  avatar: const Icon(Icons.sell_outlined, size: 16),
                  onDeleted: () => onServiceChanged(null),
                ),
              if (bucket != null)
                InputChip(
                  label:
                      Text('Antiguidade: ${_bucketLabels[bucket] ?? bucket}'),
                  avatar: const Icon(Icons.schedule, size: 16),
                  onDeleted: onClearBucket,
                ),
              TextButton(
                onPressed: onClearFilters,
                child: const Text('Limpar filtros'),
              ),
            ],
          ),
        ],
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
            studentId: entry.key == 'sem-aluno' ? null : entry.key,
            generatingDocumentId: generatingDocumentId,
            onOpenReference: onOpenReference,
            onOpenDetails: onOpenDetails,
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
    required this.studentId,
    required this.generatingDocumentId,
    required this.onOpenReference,
    required this.onOpenDetails,
  });

  final List<Map<String, dynamic>> rows;
  final NumberFormat currency;
  final String? studentId;
  final String? generatingDocumentId;
  final ValueChanged<Map<String, dynamic>> onOpenReference;
  final ValueChanged<Map<String, dynamic>> onOpenDetails;

  @override
  Widget build(BuildContext context) {
    final total = rows.fold<double>(
        0, (sum, row) => sum + ((row['outstanding'] as num?)?.toDouble() ?? 0));
    final name =
        rows.first['student_name']?.toString() ?? 'Sem aluno associado';
    final guardian = rows.first['guardian_name']?.toString();
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(
          [
            '${rows.length} documento(s)',
            if (guardian != null && guardian.isNotEmpty) guardian,
          ].join(' · '),
        ),
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
          if (studentId != null)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 16),
                child: TextButton.icon(
                  onPressed: () => context.push('/admin/children/$studentId'),
                  icon: const Icon(Icons.person_outline, size: 18),
                  label: const Text('Abrir ficha do aluno'),
                ),
              ),
            ),
          for (final row in rows)
            _DebtRowTile(
              row: row,
              currency: currency,
              generating: generatingDocumentId != null &&
                  generatingDocumentId == row['document_id']?.toString(),
              onOpenReference: () => onOpenReference(row),
              onOpenDetails: () => onOpenDetails(row),
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
    required this.generating,
    required this.onOpenReference,
    required this.onOpenDetails,
  });

  final Map<String, dynamic> row;
  final NumberFormat currency;
  final bool generating;
  final VoidCallback onOpenReference;
  final VoidCallback onOpenDetails;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final days = (row['days_overdue'] as num?)?.toInt() ?? 0;
    final services = ((row['services'] as List?) ?? const [])
        .whereType<Map>()
        .map((service) => Map<String, dynamic>.from(service))
        .toList();
    final documentType = row['document_type']?.toString();
    return InkWell(
      onTap: onOpenDetails,
      child: Padding(
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
                        '${documentType == null ? '' : '$documentType · '}'
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
                  currency
                      .format((row['outstanding'] as num?)?.toDouble() ?? 0),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 2),
                Icon(Icons.chevron_right,
                    size: 18, color: theme.colorScheme.onSurfaceVariant),
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
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: onOpenDetails,
                  icon: const Icon(Icons.receipt_long_outlined, size: 18),
                  label: const Text('Detalhe'),
                ),
                const SizedBox(width: 4),
                TextButton.icon(
                  onPressed: generating ? null : onOpenReference,
                  icon: generating
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.qr_code_2, size: 18),
                  label: Text(
                    generating ? 'A criar…' : 'Gerar referência',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DebtDetailSheet extends StatelessWidget {
  const _DebtDetailSheet({required this.row, required this.currency});

  final Map<String, dynamic> row;
  final NumberFormat currency;

  double _money(String key) => (row[key] as num?)?.toDouble() ?? 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final services = ((row['services'] as List?) ?? const [])
        .whereType<Map>()
        .map((service) => Map<String, dynamic>.from(service))
        .toList();
    final studentId = row['student_id']?.toString();
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              row['document_number']?.toString() ?? 'Documento',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              [
                row['document_type']?.toString(),
                if (row['source'] != null)
                  row['source'] == 'internal' ? 'Motor interno' : 'FinReg',
                'Vence ${formatIsoDate(row['due_date']?.toString())}',
              ].whereType<String>().where((v) => v.isNotEmpty).join(' · '),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            _DetailRow(
              label: 'Em dívida',
              value: currency.format(_money('outstanding')),
              bold: true,
            ),
            _DetailRow(
              label: 'Total do documento',
              value: currency.format(_money('gross_total')),
            ),
            _DetailRow(
              label: 'Pago',
              value: currency.format(_money('paid_total')),
            ),
            if (_money('credited_total') > 0)
              _DetailRow(
                label: 'Creditado',
                value: currency.format(_money('credited_total')),
              ),
            _DetailRow(
              label: 'Dias em atraso',
              value: '${(row['days_overdue'] as num?)?.toInt() ?? 0}',
            ),
            const Divider(height: 24),
            _DetailRow(
              label: 'Aluno',
              value: row['student_name']?.toString() ?? '—',
            ),
            _DetailRow(
              label: 'Encarregado',
              value: row['guardian_name']?.toString() ?? '—',
            ),
            if (services.isNotEmpty) ...[
              const Divider(height: 24),
              Text('Por serviço',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              for (final service in services)
                _DetailRow(
                  label: service['service_label']?.toString() ??
                      service['service']?.toString() ??
                      'Serviço',
                  value: currency.format(
                      (service['outstanding_amount'] as num?)?.toDouble() ?? 0),
                ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => Navigator.of(context).pop('payment'),
                icon: const Icon(Icons.payments_outlined),
                label: const Text('Registar pagamento'),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (studentId != null && studentId.isNotEmpty)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).pop('student'),
                      icon: const Icon(Icons.person_outline),
                      label: const Text('Ficha do aluno'),
                    ),
                  ),
                if (studentId != null && studentId.isNotEmpty)
                  const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => Navigator.of(context).pop('reference'),
                    icon: const Icon(Icons.qr_code_2),
                    label: const Text('Gerar referência'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.bold = false,
  });

  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            textAlign: TextAlign.end,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
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
  String? _error;

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

  void _submit() {
    final value = parseMoney(_amount.text);
    if (value <= 0) {
      setState(() => _error = 'Indique um valor positivo.');
      return;
    }
    if (value > widget.outstanding + 0.01) {
      setState(() => _error = 'O valor excede o saldo em dívida.');
      return;
    }
    Navigator.pop(context, value);
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
            decoration: InputDecoration(
              labelText: 'Valor (Kz)',
              errorText: _error,
            ),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Gerar'),
        ),
      ],
    );
  }
}

class _ReferenceDialog extends ConsumerStatefulWidget {
  const _ReferenceDialog({required this.reference});

  final Map<String, dynamic> reference;

  @override
  ConsumerState<_ReferenceDialog> createState() => _ReferenceDialogState();
}

class _ReferenceDialogState extends ConsumerState<_ReferenceDialog> {
  late Map<String, dynamic> _reference;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _reference = Map<String, dynamic>.from(widget.reference);
  }

  Future<void> _copy(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copiado.')),
    );
  }

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    try {
      final data = await ref.read(apiClientProvider).post(
            '/billing/principia-pay/references/${_reference['id']}/refresh',
          ) as Map;
      if (!mounted) return;
      setState(() {
        _reference = Map<String, dynamic>.from(data);
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(apiErrorMessage(error))),
      );
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entity = _reference['entity']?.toString() ?? '';
    final number = _reference['reference']?.toString() ?? '';
    final checkout = _reference['checkout_url']?.toString();
    final status = _reference['status']?.toString() ?? 'creating';
    final pending = entity.isEmpty || number.isEmpty;
    return AlertDialog(
      title: Text(pending ? 'Referência em confirmação' : 'Referência criada'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (pending) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 10),
            Text(
              'O serviço de pagamentos ainda não devolveu a entidade e a '
              'referência. Consulte o estado antes de partilhar com o '
              'encarregado.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
          ],
          if (!pending) ...[
            _CopyRow(
              label: 'Entidade',
              value: entity,
              onCopy: () => _copy(entity),
            ),
            const SizedBox(height: 8),
            _CopyRow(
              label: 'Referência',
              value: number,
              onCopy: () => _copy(number),
            ),
          ],
          if (checkout != null && checkout.isNotEmpty) ...[
            const SizedBox(height: 8),
            SelectableText(
              checkout,
              style: theme.textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 8),
          Text(
            'O pagamento é conciliado automaticamente e fica registado no motor fiscal.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        if (status != 'paid' && status != 'cancelled')
          TextButton.icon(
            onPressed: _refreshing ? null : _refresh,
            icon: _refreshing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync, size: 18),
            label: const Text('Consultar estado'),
          ),
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
