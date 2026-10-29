import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/providers/currency_provider.dart';
import '../../../core/widgets/app_error_widget.dart';
import 'fee_automation_common.dart';

/// Records a payment the family made at the school — cash at the counter, a
/// transfer receipt, a card terminal — against the document the debt ledger
/// shows. The backend settles it in whichever engine owns the school, so the
/// parent portal and the legal receipt reflect it immediately.
class RecordPaymentScreen extends ConsumerStatefulWidget {
  const RecordPaymentScreen({super.key, this.documentId});

  /// When opened from a debt row, the document to pay without searching.
  final String? documentId;

  @override
  ConsumerState<RecordPaymentScreen> createState() =>
      _RecordPaymentScreenState();
}

final _recordableDebtsProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final data = await ref.read(apiClientProvider).get('/billing/debts') as Map;
  return Map<String, dynamic>.from(data);
});

class _RecordPaymentScreenState extends ConsumerState<RecordPaymentScreen> {
  final _search = TextEditingController();
  String _query = '';
  bool _autoOpened = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _rows(Map<String, dynamic> data) {
    final rows = ((data['rows'] as List?) ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return rows;
    return rows.where((row) {
      final haystack = [
        row['student_name'],
        row['guardian_name'],
        row['document_number'],
        row['document_type'],
      ].whereType<Object>().join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList();
  }

  Future<void> _openPayment(
    Map<String, dynamic> row,
    NumberFormat currency,
  ) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _RecordPaymentDialog(row: row, currency: currency),
    );
    if (!mounted || saved != true) return;
    ref.invalidate(_recordableDebtsProvider);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Pagamento registado com sucesso.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final debts = ref.watch(_recordableDebtsProvider);
    final currency = ref.watch(currencyFormatProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Registar pagamento')),
      body: debts.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => ListView(
          children: [
            const SizedBox(height: 80),
            AppErrorWidget(
              error: error,
              onRetry: () => ref.invalidate(_recordableDebtsProvider),
            ),
          ],
        ),
        data: (data) {
          final rows = _rows(data);
          final requested = widget.documentId;
          if (!_autoOpened && requested != null && requested.isNotEmpty) {
            final match = rows
                .where((row) => row['document_id']?.toString() == requested);
            if (match.isNotEmpty) {
              _autoOpened = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                _openPayment(match.first, currency);
              });
            }
          }
          return Column(
            children: [
              Container(
                width: double.infinity,
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withOpacity(0.5),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: const Text(
                  'Registe aqui os pagamentos feitos na escola. O valor é '
                  'abatido à dívida e o pagamento fica visível para o '
                  'encarregado.',
                  style: TextStyle(fontSize: 12.5),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                child: TextField(
                  controller: _search,
                  onChanged: (value) => setState(() => _query = value),
                  decoration: InputDecoration(
                    hintText: 'Procurar aluno, encarregado ou documento',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _search.clear();
                              setState(() => _query = '');
                            },
                          ),
                    filled: true,
                    isDense: true,
                  ),
                ),
              ),
              Expanded(
                child: rows.isEmpty
                    ? Center(
                        child: Text(
                          _query.isEmpty
                              ? 'Não existem dívidas em aberto.'
                              : 'Nenhuma dívida corresponde à procura.',
                          style: TextStyle(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: () async =>
                            ref.invalidate(_recordableDebtsProvider),
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 6, 12, 24),
                          itemCount: rows.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 6),
                          itemBuilder: (context, index) {
                            final row = rows[index];
                            return Card(
                              margin: EdgeInsets.zero,
                              child: ListTile(
                                onTap: () => _openPayment(row, currency),
                                leading: CircleAvatar(
                                  backgroundColor: Theme.of(context)
                                      .colorScheme
                                      .primaryContainer,
                                  child: const Icon(Icons.payments_outlined),
                                ),
                                title: Text(
                                  row['student_name']?.toString() ?? 'Aluno',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600),
                                ),
                                subtitle: Text(
                                  [
                                    row['document_number']?.toString(),
                                    row['guardian_name']?.toString(),
                                    'Vence ${formatIsoDate(row['due_date']?.toString())}',
                                  ]
                                      .whereType<String>()
                                      .where((value) => value.isNotEmpty)
                                      .join(' · '),
                                ),
                                trailing: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      currency.format(
                                        (row['outstanding'] as num?)
                                                ?.toDouble() ??
                                            0,
                                      ),
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w800),
                                    ),
                                    const SizedBox(height: 2),
                                    const Text('Em dívida',
                                        style: TextStyle(fontSize: 11)),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _RecordPaymentDialog extends ConsumerStatefulWidget {
  const _RecordPaymentDialog({required this.row, required this.currency});

  final Map<String, dynamic> row;
  final NumberFormat currency;

  @override
  ConsumerState<_RecordPaymentDialog> createState() =>
      _RecordPaymentDialogState();
}

class _RecordPaymentDialogState extends ConsumerState<_RecordPaymentDialog> {
  late final TextEditingController _amount;
  final _notes = TextEditingController();
  final _reference = TextEditingController();
  String _method = 'cash';
  DateTime _date = DateTime.now();
  String? _error;
  bool _submitting = false;
  String _idempotencyKey = _newKey();

  static String _newKey() =>
      'cellen-inperson-${DateTime.now().microsecondsSinceEpoch}';

  double get _outstanding =>
      (widget.row['outstanding'] as num?)?.toDouble() ?? 0;

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController(text: moneyText(_outstanding));
  }

  @override
  void dispose() {
    _amount.dispose();
    _notes.dispose();
    _reference.dispose();
    super.dispose();
  }

  String _iso(DateTime value) => '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (!mounted || picked == null) return;
    setState(() => _date = picked);
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final value = parseMoney(_amount.text);
    if (value <= 0) {
      setState(() => _error = 'Indique um valor positivo.');
      return;
    }
    if (value > _outstanding + 0.01) {
      setState(() => _error = 'O valor excede o saldo em dívida.');
      return;
    }
    setState(() {
      _error = null;
      _submitting = true;
    });
    try {
      await ref.read(apiClientProvider).post(
            '/finance/payments/record',
            data: {
              'document_id': widget.row['document_id']?.toString(),
              'amount': value,
              'payment_method': _method,
              'payment_date': _iso(_date),
              'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
              'reference': _reference.text.trim().isEmpty
                  ? null
                  : _reference.text.trim(),
              'idempotency_key': _idempotencyKey,
            },
            receiveTimeout: const Duration(seconds: 45),
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      final status = error is ApiException ? error.statusCode : null;
      // A 5xx can mean the payment reached the engine but its answer did
      // not; retry with the same key so nothing is charged twice. A 4xx was
      // definitively refused, so the next attempt is a new payment.
      if (status != null && status < 500) {
        _idempotencyKey = _newKey();
      }
      setState(() {
        _error = apiErrorMessage(error);
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    return AlertDialog(
      title: const Text('Registar pagamento'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              row['student_name']?.toString() ?? 'Aluno',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            Text(
              [
                row['document_number']?.toString(),
                'Em dívida ${widget.currency.format(_outstanding)}',
              ].whereType<String>().where((v) => v.isNotEmpty).join(' · '),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _amount,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\s]')),
              ],
              decoration: const InputDecoration(
                labelText: 'Valor recebido',
                prefixText: 'Kz ',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _method,
              decoration:
                  const InputDecoration(labelText: 'Forma de pagamento'),
              items: const [
                DropdownMenuItem(value: 'cash', child: Text('Dinheiro')),
                DropdownMenuItem(
                    value: 'transfer', child: Text('Transferência')),
                DropdownMenuItem(value: 'card', child: Text('Cartão')),
                DropdownMenuItem(value: 'check', child: Text('Cheque')),
                DropdownMenuItem(
                    value: 'mobile', child: Text('Multicaixa / Móvel')),
                DropdownMenuItem(value: 'other', child: Text('Outro')),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _method = value);
              },
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: _pickDate,
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Data do pagamento',
                  suffixIcon: Icon(Icons.calendar_today_outlined, size: 18),
                ),
                child: Text(DateFormat('dd/MM/yyyy').format(_date)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reference,
              decoration: const InputDecoration(
                labelText: 'Referência (opcional)',
                hintText: 'Nº do talão, transferência ou cheque',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Notas (opcional)',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12.5,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed:
              _submitting ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Registar'),
        ),
      ],
    );
  }
}
