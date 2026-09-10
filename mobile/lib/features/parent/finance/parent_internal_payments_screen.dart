import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/api/api_client.dart';
import '../../../core/providers/currency_provider.dart';
import 'parent_invoices_screen.dart';

final _parentPaymentModeProvider =
    FutureProvider.autoDispose<String>((ref) async {
  final data =
      await ref.read(apiClientProvider).get('/finance/parent/payment-mode');
  return (data as Map)['mode']?.toString() ?? 'internal';
});

final _parentInternalPaymentsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final rows = await ref
      .read(apiClientProvider)
      .get('/finance/parent/internal-payments') as List;
  return rows.map((row) => Map<String, dynamic>.from(row as Map)).toList();
});

class ParentFinanceHostScreen extends ConsumerWidget {
  const ParentFinanceHostScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(_parentPaymentModeProvider).when(
          loading: () =>
              const Scaffold(body: Center(child: CircularProgressIndicator())),
          error: (error, _) => Scaffold(
            appBar: AppBar(title: const Text('Pagamentos')),
            body: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(error.toString(), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => ref.invalidate(_parentPaymentModeProvider),
                icon: const Icon(Icons.refresh),
                label: const Text('Tentar novamente'),
              ),
            ])),
          ),
          data: (mode) => mode == 'finreg'
              ? const ParentInvoicesScreen()
              : const _ParentInternalPaymentsScreen(),
        );
  }
}

class _ParentInternalPaymentsScreen extends ConsumerWidget {
  const _ParentInternalPaymentsScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final payments = ref.watch(_parentInternalPaymentsProvider);
    final money = ref.watch(currencyFormatProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pagamentos'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: () => ref.invalidate(_parentInternalPaymentsProvider),
            icon: const Icon(Icons.refresh),
          ),
        ],
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
              'Estas cobranças servem para controlo interno da escola e não são facturas nem recibos fiscais.',
            )),
          ]),
        ),
        Expanded(
            child: payments.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(child: Text(error.toString())),
          data: (rows) => rows.isEmpty
              ? const Center(child: Text('Não existem pagamentos pendentes.'))
              : RefreshIndicator(
                  onRefresh: () async =>
                      ref.invalidate(_parentInternalPaymentsProvider),
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: rows.length,
                    itemBuilder: (_, index) => _ParentPaymentCard(
                      payment: rows[index],
                      amount: money.format(
                        double.tryParse(rows[index]['amount'].toString()) ?? 0,
                      ),
                      onChanged: () =>
                          ref.invalidate(_parentInternalPaymentsProvider),
                    ),
                  ),
                ),
        )),
      ]),
    );
  }
}

class _ParentPaymentCard extends StatelessWidget {
  const _ParentPaymentCard({
    required this.payment,
    required this.amount,
    required this.onChanged,
  });

  final Map<String, dynamic> payment;
  final String amount;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
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
                    : Icons.payments_outlined)),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(payment['description']?.toString() ?? '',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(payment['child_name']?.toString() ?? ''),
                ])),
            Text(amount, style: const TextStyle(fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 10),
          Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _ParentStatusChip(status: status),
                if (payment['due_date'] != null)
                  Text('Vencimento: ${payment['due_date']}'),
                if (payment['payment_date'] != null)
                  Text('Pago em: ${payment['payment_date']}'),
              ]),
          if (status == 'rejected' &&
              (payment['review_note']?.toString() ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Motivo: ${payment['review_note']}',
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
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
              FilledButton.icon(
                onPressed: () async {
                  final submitted = await showDialog<bool>(
                    context: context,
                    builder: (_) =>
                        _ParentProofDialog(paymentId: payment['id'].toString()),
                  );
                  if (submitted == true) onChanged();
                },
                icon: const Icon(Icons.upload_file),
                label: Text(status == 'rejected'
                    ? 'Enviar novo comprovativo'
                    : 'Enviar comprovativo'),
              ),
          ]),
        ]),
      ),
    );
  }
}

class _ParentProofDialog extends ConsumerStatefulWidget {
  const _ParentProofDialog({required this.paymentId});
  final String paymentId;

  @override
  ConsumerState<_ParentProofDialog> createState() => _ParentProofDialogState();
}

class _ParentProofDialogState extends ConsumerState<_ParentProofDialog> {
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
      withData: true,
    );
    if (result != null && result.files.isNotEmpty) {
      setState(() => _file = result.files.first);
    }
  }

  Future<void> _submit() async {
    if (_file?.bytes == null) {
      setState(() => _error = 'Seleccione o comprovativo.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      final uploaded = await api.uploadBytes(
        '/finance/parent/internal-payments/proof',
        _file!.bytes!,
        _file!.name,
      );
      await api.patch(
        '/finance/parent/internal-payments/${widget.paymentId}/submit',
        data: {
          'proof_url': uploaded['url'],
          'payment_method': _method,
          'payment_date': DateFormat('yyyy-MM-dd').format(_date),
          if (_notes.text.trim().isNotEmpty) 'notes': _notes.text.trim(),
        },
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted)
        setState(() {
          _busy = false;
          _error = error.toString();
        });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Enviar comprovativo'),
        content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
                child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: _method,
                  decoration:
                      const InputDecoration(labelText: 'Método de pagamento'),
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
                      .map((entry) => DropdownMenuItem(
                            value: entry.key,
                            child: Text(entry.value),
                          ))
                      .toList(),
                  onChanged: (value) => setState(() => _method = value!),
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.calendar_today),
                  title: const Text('Data do pagamento'),
                  subtitle: Text(DateFormat('dd/MM/yyyy').format(_date)),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _date,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2050),
                    );
                    if (picked != null) setState(() => _date = picked);
                  },
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _pick,
                  icon: const Icon(Icons.attach_file),
                  label: Text(_file?.name ?? 'Seleccionar comprovativo *'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _notes,
                  maxLines: 2,
                  decoration:
                      const InputDecoration(labelText: 'Observação (opcional)'),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                  ),
              ],
            ))),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: Text(_busy ? 'A enviar…' : 'Enviar'),
          ),
        ],
      );
}

class _ParentStatusChip extends StatelessWidget {
  const _ParentStatusChip({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final value = switch (status) {
      'paid' => ('Pago', Colors.green),
      'proof_submitted' => ('Em análise pela escola', Colors.blue),
      'rejected' => ('Comprovativo rejeitado', Colors.red),
      _ => ('Pendente', Colors.orange),
    };
    return Chip(
      label: Text(value.$1),
      side: BorderSide.none,
      backgroundColor: value.$2.withOpacity(.12),
      labelStyle: TextStyle(color: value.$2, fontWeight: FontWeight.w600),
    );
  }
}
