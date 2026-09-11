import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/api/api_client.dart';
import '../../../core/providers/currency_provider.dart';

final internalPaymentsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final rows = await ref
      .read(apiClientProvider)
      .get('/finance/internal-payments') as List;
  return rows.map((row) => Map<String, dynamic>.from(row as Map)).toList();
});

class InternalPaymentsScreen extends ConsumerWidget {
  const InternalPaymentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final payments = ref.watch(internalPaymentsProvider);
    final money = ref.watch(currencyFormatProvider);
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Controlo de pagamentos'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: () => ref.invalidate(internalPaymentsProvider),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final created = await showDialog<bool>(
            context: context,
            builder: (_) => const _CreateInternalPaymentDialog(),
          );
          if (created == true) ref.invalidate(internalPaymentsProvider);
        },
        icon: const Icon(Icons.add),
        label: const Text('Nova cobrança'),
      ),
      body: Column(children: [
        Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Row(children: [
            Icon(Icons.info_outline),
            SizedBox(width: 10),
            Expanded(
                child: Text(
              'Registo interno sem valor fiscal. Não gera factura, recibo, numeração fiscal ou lançamento no Finreg.',
            )),
          ]),
        ),
        Expanded(
          child: payments.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(child: Text(error.toString())),
            data: (rows) => rows.isEmpty
                ? const Center(
                    child: Text('Nenhuma cobrança interna registada.'))
                : RefreshIndicator(
                    onRefresh: () async =>
                        ref.invalidate(internalPaymentsProvider),
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                      itemCount: rows.length,
                      itemBuilder: (_, index) => _PaymentCard(
                        payment: rows[index],
                        amount: money.format(
                            double.tryParse(rows[index]['amount'].toString()) ??
                                0),
                        onChanged: () =>
                            ref.invalidate(internalPaymentsProvider),
                      ),
                    ),
                  ),
          ),
        ),
      ]),
    );
  }
}

class _PaymentCard extends ConsumerWidget {
  const _PaymentCard(
      {required this.payment, required this.amount, required this.onChanged});
  final Map<String, dynamic> payment;
  final String amount;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = payment['status']?.toString() ?? 'pending';
    final proof = payment['proof_url']?.toString();
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(
                child: Icon(payment['category'] == 'enrollment'
                    ? Icons.school_outlined
                    : Icons.receipt_long_outlined)),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(payment['guardian_name']?.toString() ?? 'Cobrança geral',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(payment['description']?.toString() ?? ''),
                  if ((payment['child_name']?.toString() ?? '').isNotEmpty)
                    Text('Aluno: ${payment['child_name']}'),
                ])),
            Text(amount, style: const TextStyle(fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 10),
          Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _StatusChip(status: status),
                if (payment['due_date'] != null)
                  Text('Vence: ${payment['due_date']}'),
                if (payment['payment_date'] != null)
                  Text('Pago em: ${payment['payment_date']}'),
                if (payment['payment_method'] != null)
                  Text(_methodLabel(payment['payment_method'].toString())),
              ]),
          if ((payment['review_note']?.toString() ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Observação: ${payment['review_note']}'),
          ],
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            if (proof != null && proof.isNotEmpty)
              TextButton.icon(
                onPressed: () => launchUrl(
                  Uri.parse(
                      proof.startsWith('/') ? '$kMediaBase$proof' : proof),
                  mode: LaunchMode.externalApplication,
                ),
                icon: const Icon(Icons.attach_file),
                label: const Text('Ver comprovativo'),
              ),
            if (status == 'pending' || status == 'rejected')
              FilledButton.tonalIcon(
                onPressed: () async {
                  final done = await showDialog<bool>(
                      context: context,
                      builder: (_) => _SubmitProofDialog(
                          paymentId: payment['id'].toString()));
                  if (done == true) onChanged();
                },
                icon: const Icon(Icons.upload_file),
                label: Text(status == 'rejected'
                    ? 'Submeter novamente'
                    : 'Registar pagamento'),
              ),
            if (status == 'proof_submitted') ...[
              FilledButton.icon(
                onPressed: () => _review(context, ref, 'confirm'),
                icon: const Icon(Icons.check),
                label: const Text('Confirmar'),
              ),
              OutlinedButton.icon(
                onPressed: () => _review(context, ref, 'reject'),
                icon: const Icon(Icons.close),
                label: const Text('Rejeitar'),
              ),
            ],
          ]),
        ]),
      ),
    );
  }

  Future<void> _review(
      BuildContext context, WidgetRef ref, String action) async {
    final note = TextEditingController();
    final accepted = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
              title: Text(action == 'confirm'
                  ? 'Confirmar pagamento?'
                  : 'Rejeitar comprovativo?'),
              content: TextField(
                  controller: note,
                  maxLines: 2,
                  decoration: const InputDecoration(
                      labelText: 'Observação (opcional)')),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('Cancelar')),
                FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child:
                        Text(action == 'confirm' ? 'Confirmar' : 'Rejeitar')),
              ],
            ));
    if (accepted != true || !context.mounted) return;
    try {
      await ref.read(apiClientProvider).patch(
        '/finance/internal-payments/${payment['id']}/review',
        data: {
          'action': action,
          if (note.text.trim().isNotEmpty) 'note': note.text.trim()
        },
      );
      onChanged();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(action == 'confirm'
              ? 'Pagamento confirmado.'
              : 'Comprovativo rejeitado.'),
        ));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      }
    } finally {
      note.dispose();
    }
  }
}

class _SubmitProofDialog extends ConsumerStatefulWidget {
  const _SubmitProofDialog({required this.paymentId});
  final String paymentId;
  @override
  ConsumerState<_SubmitProofDialog> createState() => _SubmitProofDialogState();
}

class _SubmitProofDialogState extends ConsumerState<_SubmitProofDialog> {
  PlatformFile? _file;
  String _method = 'transfer';
  DateTime _date = DateTime.now();
  final _notes = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['jpg', 'jpeg', 'png', 'pdf'],
        withData: true);
    if (result != null && result.files.isNotEmpty) {
      setState(() => _file = result.files.first);
    }
  }

  Future<void> _submit() async {
    if (_file?.bytes == null) {
      setState(() => _error = 'Seleccione um comprovativo.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      final uploaded = await api.uploadBytes(
          '/finance/internal-payments/proof', _file!.bytes!, _file!.name);
      await api.patch('/finance/internal-payments/${widget.paymentId}/submit',
          data: {
            'proof_url': uploaded['url'],
            'payment_method': _method,
            'payment_date': DateFormat('yyyy-MM-dd').format(_date),
            if (_notes.text.trim().isNotEmpty) 'notes': _notes.text.trim(),
          });
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = error.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Registar pagamento'),
        content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String>(
                  initialValue: _method,
                  decoration: const InputDecoration(labelText: 'Método'),
                  items: const {
                    'cash': 'Numerário',
                    'transfer': 'Transferência',
                    'card': 'Cartão',
                    'check': 'Cheque',
                    'mobile': 'Pagamento móvel',
                    'multicaixa': 'Multicaixa',
                    'other': 'Outro',
                  }
                      .entries
                      .map((e) =>
                          DropdownMenuItem(value: e.key, child: Text(e.value)))
                      .toList(),
                  onChanged: (value) => setState(() => _method = value!)),
              const SizedBox(height: 12),
              ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.calendar_today),
                  title: const Text('Data do pagamento'),
                  subtitle: Text(DateFormat('dd/MM/yyyy').format(_date)),
                  onTap: () async {
                    final value = await showDatePicker(
                        context: context,
                        initialDate: _date,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2050));
                    if (value != null) setState(() => _date = value);
                  }),
              OutlinedButton.icon(
                  onPressed: _busy ? null : _pick,
                  icon: const Icon(Icons.attach_file),
                  label: Text(_file?.name ?? 'Seleccionar comprovativo *')),
              const SizedBox(height: 8),
              TextField(
                  controller: _notes,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Notas')),
              if (_error != null)
                Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error))),
            ])),
        actions: [
          TextButton(
              onPressed: _busy ? null : () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: _busy ? null : _submit,
              child: Text(_busy ? 'A guardar…' : 'Submeter')),
        ],
      );
}

class _CreateInternalPaymentDialog extends ConsumerStatefulWidget {
  const _CreateInternalPaymentDialog();
  @override
  ConsumerState<_CreateInternalPaymentDialog> createState() =>
      _CreateInternalPaymentDialogState();
}

class _CreateInternalPaymentDialogState
    extends ConsumerState<_CreateInternalPaymentDialog> {
  final _description = TextEditingController();
  final _amount = TextEditingController();
  final _notes = TextEditingController();
  String? _guardianId;
  String? _childId;
  String? _itemId;
  DateTime? _dueDate;
  bool _busy = false;
  String? _error;
  late final Future<Map<String, dynamic>> _options;

  @override
  void initState() {
    super.initState();
    _options = ref
        .read(apiClientProvider)
        .get('/finance/internal-payments/options')
        .then((value) => Map<String, dynamic>.from(value as Map));
  }

  @override
  void dispose() {
    _description.dispose();
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amount.text.trim().replaceAll(',', '.'));
    if (_itemId == null && _description.text.trim().isEmpty) {
      setState(() => _error = 'Seleccione um item ou indique a descrição.');
      return;
    }
    if (_itemId == null && (amount == null || amount <= 0)) {
      setState(() => _error = 'Indique um valor válido.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(apiClientProvider)
          .post('/finance/internal-payments', data: {
        if (_guardianId != null) 'billing_guardian_id': _guardianId,
        if (_childId != null) 'child_id': _childId,
        if (_itemId != null) 'billing_item_id': _itemId,
        if (_description.text.trim().isNotEmpty)
          'description': _description.text.trim(),
        if (amount != null && amount > 0) 'amount': amount,
        if (_dueDate != null)
          'due_date': DateFormat('yyyy-MM-dd').format(_dueDate!),
        if (_notes.text.trim().isNotEmpty) 'notes': _notes.text.trim(),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = error.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Nova cobrança interna'),
        content: SizedBox(
            width: 460,
            child: FutureBuilder<Map<String, dynamic>>(
              future: _options,
              builder: (_, snapshot) {
                if (snapshot.hasError) {
                  return SizedBox(
                    height: 120,
                    child: Center(
                      child: Text('Erro ao carregar opções: ${snapshot.error}'),
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const SizedBox(
                      height: 120,
                      child: Center(child: CircularProgressIndicator()));
                }
                final guardians = (snapshot.data!['guardians'] as List)
                    .map((e) => Map<String, dynamic>.from(e as Map))
                    .toList();
                final children = (snapshot.data!['children'] as List)
                    .map((e) => Map<String, dynamic>.from(e as Map))
                    .toList();
                final items = (snapshot.data!['billing_items'] as List)
                    .map((e) => Map<String, dynamic>.from(e as Map))
                    .toList();
                final payerChildren = _guardianId == null
                    ? children
                    : children.where((child) {
                        final ids = (child['guardian_ids'] as List? ?? const [])
                            .map((id) => id.toString());
                        return ids.contains(_guardianId);
                      }).toList();
                return SingleChildScrollView(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                  DropdownButtonFormField<String>(
                      initialValue: _guardianId,
                      decoration: const InputDecoration(
                          labelText: 'Encarregado pagador (opcional)'),
                      items: [
                        const DropdownMenuItem<String>(
                            value: '', child: Text('Cobrança geral')),
                        ...guardians.map((guardian) => DropdownMenuItem(
                            value: guardian['id'].toString(),
                            child: Text(guardian['name'].toString())))
                      ],
                      onChanged: (value) => setState(() {
                            _guardianId =
                                value == null || value.isEmpty ? null : value;
                            final childStillLinked = children.any((child) {
                              final ids =
                                  (child['guardian_ids'] as List? ?? const [])
                                      .map((id) => id.toString());
                              return child['id'].toString() == _childId &&
                                  (_guardianId == null ||
                                      ids.contains(_guardianId));
                            });
                            if (!childStillLinked) {
                              _childId = null;
                            }
                          })),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                      key: ValueKey('$_guardianId:$_childId'),
                      initialValue: _childId,
                      decoration: const InputDecoration(
                          labelText: 'Aluno relacionado (opcional)'),
                      items: [
                        const DropdownMenuItem<String>(
                            value: '', child: Text('Sem aluno associado')),
                        ...payerChildren.map((c) => DropdownMenuItem(
                            value: c['id'].toString(),
                            child: Text(c['name'].toString())))
                      ],
                      onChanged: (value) => setState(() => _childId =
                          value == null || value.isEmpty ? null : value)),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                      initialValue: _itemId,
                      decoration: const InputDecoration(
                          labelText: 'Item de cobrança (opcional)'),
                      items: [
                        const DropdownMenuItem<String>(
                            value: '', child: Text('Sem item predefinido')),
                        ...items.map((item) => DropdownMenuItem(
                            value: item['id'].toString(),
                            child: Text(item['name'].toString())))
                      ],
                      onChanged: (value) {
                        setState(() {
                          _itemId =
                              value == null || value.isEmpty ? null : value;
                          if (_itemId != null) {
                            final item = items.firstWhere(
                                (entry) => entry['id'].toString() == _itemId);
                            _description.text = item['name']?.toString() ?? '';
                            _amount.text = item['unit_price']?.toString() ?? '';
                          }
                        });
                      }),
                  const SizedBox(height: 12),
                  TextField(
                      controller: _description,
                      decoration:
                          const InputDecoration(labelText: 'Descrição *')),
                  const SizedBox(height: 12),
                  TextField(
                      controller: _amount,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                          labelText: 'Valor *', suffixText: 'Kz')),
                  const SizedBox(height: 8),
                  ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.event),
                      title: const Text('Data de vencimento (opcional)'),
                      subtitle: Text(_dueDate == null
                          ? 'Sem vencimento'
                          : DateFormat('dd/MM/yyyy').format(_dueDate!)),
                      onTap: () async {
                        final value = await showDatePicker(
                            context: context,
                            initialDate: _dueDate ?? DateTime.now(),
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2050));
                        if (value != null) setState(() => _dueDate = value);
                      }),
                  TextField(
                      controller: _notes,
                      maxLines: 2,
                      decoration: const InputDecoration(labelText: 'Notas')),
                  if (_error != null)
                    Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(_error!,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error))),
                ]));
              },
            )),
        actions: [
          TextButton(
              onPressed: _busy ? null : () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: _busy ? null : _save,
              child: Text(_busy ? 'A guardar…' : 'Criar')),
        ],
      );
}

String _methodLabel(String method) =>
    const {
      'cash': 'Numerário',
      'transfer': 'Transferência',
      'card': 'Cartão',
      'check': 'Cheque',
      'mobile': 'Pagamento móvel',
      'multicaixa': 'Multicaixa',
      'other': 'Outro',
    }[method] ??
    method;

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status;
  @override
  Widget build(BuildContext context) {
    final values = switch (status) {
      'paid' => ('Pago', Colors.green),
      'proof_submitted' => ('Comprovativo em análise', Colors.blue),
      'rejected' => ('Rejeitado', Colors.red),
      _ => ('Pendente', Colors.orange),
    };
    return Chip(
        label: Text(values.$1),
        side: BorderSide.none,
        backgroundColor: values.$2.withValues(alpha: .12),
        labelStyle: TextStyle(color: values.$2, fontWeight: FontWeight.w600));
  }
}
