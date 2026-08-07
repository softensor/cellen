import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';

final _pendingParentPaymentsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final rows = await ref.read(apiClientProvider).get('/finance/payments',
      queryParameters: {'status': 'pending_review', 'limit': '100'}) as List;
  return rows
      .map((value) => Map<String, dynamic>.from(value as Map))
      .toList();
});

class ParentPaymentReviewScreen extends ConsumerWidget {
  const ParentPaymentReviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final payments = ref.watch(_pendingParentPaymentsProvider);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Comprovativos dos encarregados',
                      style: Theme.of(context).textTheme.headlineSmall),
                  const Text(
                      'A aprovação confirma o pagamento no Finreg e disponibiliza o recibo oficial.'),
                ],
              ),
            ),
            IconButton(
                tooltip: 'Atualizar',
                onPressed: () =>
                    ref.invalidate(_pendingParentPaymentsProvider),
                icon: const Icon(Icons.refresh)),
          ]),
          const SizedBox(height: 16),
          Expanded(
            child: payments.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(child: Text(error.toString())),
              data: (rows) => rows.isEmpty
                  ? const Center(
                      child: Text('Não existem comprovativos por analisar.'))
                  : ListView.separated(
                      itemCount: rows.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) =>
                          _PaymentReviewTile(payment: rows[index]),
                    ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _PaymentReviewTile extends ConsumerStatefulWidget {
  const _PaymentReviewTile({required this.payment});
  final Map<String, dynamic> payment;

  @override
  ConsumerState<_PaymentReviewTile> createState() =>
      _PaymentReviewTileState();
}

class _PaymentReviewTileState extends ConsumerState<_PaymentReviewTile> {
  bool busy = false;

  Future<void> _approve() async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Aprovar comprovativo?'),
        content: const Text(
            'O pagamento será confirmado no Finreg. Depois da confirmação, o recibo oficial ficará disponível ao encarregado.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Aprovar')),
        ],
      ),
    );
    if (accepted != true) return;
    await _perform('/finance/payments/${widget.payment['id']}/approve', {});
  }

  Future<void> _reject() async {
    final reason = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rejeitar comprovativo'),
        content: TextField(
          controller: reason,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(labelText: 'Motivo'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Rejeitar')),
        ],
      ),
    );
    if (accepted != true || reason.text.trim().isEmpty) return;
    await _perform('/finance/payments/${widget.payment['id']}/reject',
        {'reason': reason.text.trim()});
  }

  Future<void> _perform(String path, Map<String, dynamic> data) async {
    setState(() => busy = true);
    try {
      await ref.read(apiClientProvider).post(path, data: data);
      ref.invalidate(_pendingParentPaymentsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Operação concluída.')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
        setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final payment = widget.payment;
    final amount = (payment['amount'] as num?)?.toStringAsFixed(2) ?? '—';
    return ListTile(
      leading: const CircleAvatar(child: Icon(Icons.upload_file_outlined)),
      title: Text('$amount AOA · ${payment['payment_method'] ?? '—'}'),
      subtitle: Text([
        if (payment['payment_date'] != null) payment['payment_date'].toString(),
        if (payment['notes'] != null) payment['notes'].toString(),
        if (payment['receipt_proof_url'] != null) 'Comprovativo anexado',
      ].join(' · ')),
      trailing: busy
          ? const SizedBox.square(
              dimension: 24, child: CircularProgressIndicator())
          : Wrap(spacing: 8, children: [
              OutlinedButton(
                  onPressed: _reject, child: const Text('Rejeitar')),
              FilledButton(
                  onPressed: _approve, child: const Text('Aprovar')),
            ]),
    );
  }
}
