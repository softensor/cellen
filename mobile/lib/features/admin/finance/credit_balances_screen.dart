import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_client.dart';
import '../../../core/providers/currency_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_error_widget.dart';

final _creditGuardiansProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final api = ref.read(apiClientProvider);
  final data = await api.get('/finance/credits') as List;
  return data.cast<Map<String, dynamic>>();
});

class CreditBalancesScreen extends ConsumerWidget {
  const CreditBalancesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final guardiansAsync = ref.watch(_creditGuardiansProvider);
    final currency = ref.watch(currencyFormatProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Créditos de Encarregados'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: () => ref.invalidate(_creditGuardiansProvider)),
        ],
      ),
      body: guardiansAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AppErrorWidget(error: e, onRetry: () => ref.invalidate(_creditGuardiansProvider)),
        data: (guardians) {
          if (guardians.isEmpty) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.savings_outlined, size: 64, color: AppTheme.textSecondary),
                  SizedBox(height: 12),
                  Text('Nenhum encarregado com crédito', style: TextStyle(color: AppTheme.textSecondary)),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(_creditGuardiansProvider),
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
              itemCount: guardians.length,
              itemBuilder: (_, i) => _CreditGuardianCard(
                guardian: guardians[i],
                currency: currency,
                onChanged: () => ref.invalidate(_creditGuardiansProvider),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CreditGuardianCard extends ConsumerWidget {
  final Map<String, dynamic> guardian;
  final NumberFormat currency;
  final VoidCallback onChanged;
  const _CreditGuardianCard({required this.guardian, required this.currency, required this.onChanged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balance = (guardian['credit_balance'] as num?)?.toDouble() ?? 0;
    final name = guardian['name'] as String? ?? guardian['guardian_name'] as String? ?? '—';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: AppTheme.success.withOpacity(0.3))),
      child: ListTile(
        leading: Container(
          width: 40, height: 40,
          decoration: BoxDecoration(color: AppTheme.success.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
          child: const Icon(Icons.savings_outlined, color: AppTheme.success, size: 20),
        ),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(currency.format(balance), style: const TextStyle(color: AppTheme.success, fontWeight: FontWeight.w600)),
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'detail', child: Row(children: [Icon(Icons.list_outlined, size: 18), SizedBox(width: 8), Text('Ver Movimentos')])),
            const PopupMenuItem(value: 'apply', child: Row(children: [Icon(Icons.arrow_forward_outlined, size: 18), SizedBox(width: 8), Text('Aplicar a Factura')])),
            const PopupMenuItem(value: 'refund', child: Row(children: [Icon(Icons.undo_outlined, size: 18, color: AppTheme.danger), SizedBox(width: 8), Text('Reembolsar', style: TextStyle(color: AppTheme.danger))])),
          ],
          onSelected: (action) {
            final guardianId = guardian['billing_guardian_id']?.toString() ?? guardian['id']?.toString() ?? '';
            if (action == 'detail') {
              showDialog(useRootNavigator: false, context: context, builder: (_) => _CreditDetailDialog(guardianId: guardianId, name: name, ref: ref));
            } else if (action == 'apply') {
              showDialog(useRootNavigator: false, context: context, builder: (_) => _ApplyCreditDialog(guardianId: guardianId, balance: balance, currency: currency, onApplied: onChanged));
            } else if (action == 'refund') {
              showDialog(useRootNavigator: false, context: context, builder: (_) => _RefundCreditDialog(guardianId: guardianId, balance: balance, currency: currency, onRefunded: onChanged));
            }
          },
        ),
      ),
    );
  }
}

// ─── Detail Dialog ───────────────────────────────────────────────────────────

class _CreditDetailDialog extends ConsumerStatefulWidget {
  final String guardianId;
  final String name;
  final WidgetRef ref;
  const _CreditDetailDialog({required this.guardianId, required this.name, required this.ref});

  @override
  ConsumerState<_CreditDetailDialog> createState() => _CreditDetailDialogState();
}

class _CreditDetailDialogState extends ConsumerState<_CreditDetailDialog> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final api = ref.read(apiClientProvider);
      final data = await api.get('/finance/credits/${widget.guardianId}') as Map<String, dynamic>;
      setState(() { _data = data; _loading = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.simpleCurrency(name: 'AOA');
    return AlertDialog(
      title: Text('Crédito — ${widget.name}'),
      content: SizedBox(
        width: 380,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Text(_error!, style: const TextStyle(color: AppTheme.danger))
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: AppTheme.success.withOpacity(0.08), borderRadius: BorderRadius.circular(8)),
                        child: Text(
                          'Saldo: ${currency.format((_data?['credit_balance'] as num?)?.toDouble() ?? 0)}',
                          style: const TextStyle(color: AppTheme.success, fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text('Entradas:', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                      const SizedBox(height: 4),
                      ...(_data?['entries'] as List? ?? []).map((e) {
                        final entry = e as Map<String, dynamic>;
                        return ListTile(
                          dense: true,
                          title: Text(entry['source'] as String? ?? '', style: const TextStyle(fontSize: 13)),
                          subtitle: Text(entry['created_at'] as String? ?? '', style: const TextStyle(fontSize: 11)),
                          trailing: Text(currency.format((entry['amount_remaining'] as num?)?.toDouble() ?? 0), style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.success, fontSize: 13)),
                        );
                      }),
                    ],
                  ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fechar'))],
    );
  }
}

// ─── Apply Credit Dialog ─────────────────────────────────────────────────────

class _ApplyCreditDialog extends ConsumerStatefulWidget {
  final String guardianId;
  final double balance;
  final NumberFormat currency;
  final VoidCallback onApplied;
  const _ApplyCreditDialog({required this.guardianId, required this.balance, required this.currency, required this.onApplied});

  @override
  ConsumerState<_ApplyCreditDialog> createState() => _ApplyCreditDialogState();
}

class _ApplyCreditDialogState extends ConsumerState<_ApplyCreditDialog> {
  List<Map<String, dynamic>> _invoices = [];
  String? _selectedInvoiceId;
  final _amountCtrl = TextEditingController();
  bool _loading = true;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final api = ref.read(apiClientProvider);
      final data = await api.get('/finance/invoices', queryParameters: {
        'billing_guardian_id': widget.guardianId,
        'status': 'pending',
      }) as List;
      setState(() {
        _invoices = data.cast<Map<String, dynamic>>().where((i) => i['status'] != 'paid' && i['status'] != 'cancelled').toList();
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _apply() async {
    if (_selectedInvoiceId == null) {
      setState(() => _error = 'Seleccione uma factura');
      return;
    }
    final amount = double.tryParse(_amountCtrl.text) ?? 0;
    if (amount <= 0) {
      setState(() => _error = 'Insira um valor válido');
      return;
    }
    setState(() { _submitting = true; _error = null; });
    try {
      final api = ref.read(apiClientProvider);
      await api.post('/finance/credits/apply', data: {
        'billing_guardian_id': widget.guardianId,
        'invoice_id': _selectedInvoiceId,
        'amount': amount,
      });
      widget.onApplied();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() { _error = e.toString(); _submitting = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Aplicar Crédito a Factura'),
      content: SizedBox(
        width: 360,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Saldo disponível: ${widget.currency.format(widget.balance)}', style: const TextStyle(color: AppTheme.success, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),
                  if (_invoices.isEmpty)
                    const Text('Sem facturas pendentes para este encarregado', style: TextStyle(color: AppTheme.textSecondary))
                  else ...[
                    DropdownButtonFormField<String>(
                      value: _selectedInvoiceId,
                      decoration: const InputDecoration(labelText: 'Factura *'),
                      isExpanded: true,
                      items: _invoices.map((inv) => DropdownMenuItem(
                        value: inv['id']?.toString(),
                        child: Text('${inv['full_document_number'] ?? ''} — ${NumberFormat.simpleCurrency(name: 'AOA').format((inv['balance'] as num?)?.toDouble() ?? 0)}', overflow: TextOverflow.ellipsis),
                      )).toList(),
                      onChanged: (v) {
                        setState(() { _selectedInvoiceId = v; });
                        final inv = _invoices.where((i) => i['id']?.toString() == v).firstOrNull;
                        if (inv != null) _amountCtrl.text = ((inv['balance'] as num?)?.toDouble() ?? 0).toStringAsFixed(2);
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _amountCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Valor a Aplicar *', prefixIcon: Icon(Icons.monetization_on_outlined)),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(_error!, style: const TextStyle(color: AppTheme.danger, fontSize: 12)),
                  ],
                ],
              ),
      ),
      actions: [
        TextButton(onPressed: _submitting ? null : () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: (_submitting || _invoices.isEmpty) ? null : _apply,
          child: _submitting ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Aplicar'),
        ),
      ],
    );
  }
}

// ─── Refund Credit Dialog ────────────────────────────────────────────────────

class _RefundCreditDialog extends ConsumerStatefulWidget {
  final String guardianId;
  final double balance;
  final NumberFormat currency;
  final VoidCallback onRefunded;
  const _RefundCreditDialog({required this.guardianId, required this.balance, required this.currency, required this.onRefunded});

  @override
  ConsumerState<_RefundCreditDialog> createState() => _RefundCreditDialogState();
}

class _RefundCreditDialogState extends ConsumerState<_RefundCreditDialog> {
  final _amountCtrl = TextEditingController();
  final _methodCtrl = TextEditingController();
  final _refCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _amountCtrl.text = widget.balance.toStringAsFixed(2);
  }

  @override
  void dispose() {
    _amountCtrl.dispose(); _methodCtrl.dispose(); _refCtrl.dispose(); _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _refund() async {
    final amount = double.tryParse(_amountCtrl.text) ?? 0;
    if (amount <= 0) { setState(() => _error = 'Valor inválido'); return; }
    if (amount > widget.balance) { setState(() => _error = 'Valor superior ao saldo disponível'); return; }
    setState(() { _loading = true; _error = null; });
    try {
      final api = ref.read(apiClientProvider);
      await api.post('/finance/credits/${widget.guardianId}/refund', data: {
        'amount': amount,
        'refund_method': _methodCtrl.text.trim().isEmpty ? 'bank_transfer' : _methodCtrl.text.trim(),
        if (_refCtrl.text.trim().isNotEmpty) 'reference': _refCtrl.text.trim(),
        if (_notesCtrl.text.trim().isNotEmpty) 'notes': _notesCtrl.text.trim(),
      });
      widget.onRefunded();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Reembolsar Crédito'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Saldo disponível: ${widget.currency.format(widget.balance)}', style: const TextStyle(color: AppTheme.success, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            TextFormField(controller: _amountCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Valor a Reembolsar *')),
            const SizedBox(height: 10),
            TextFormField(controller: _methodCtrl, decoration: const InputDecoration(labelText: 'Método', hintText: 'Ex: Transferência Bancária')),
            const SizedBox(height: 10),
            TextFormField(controller: _refCtrl, decoration: const InputDecoration(labelText: 'Referência Externa')),
            const SizedBox(height: 10),
            TextFormField(controller: _notesCtrl, decoration: const InputDecoration(labelText: 'Notas'), maxLines: 2),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: const TextStyle(color: AppTheme.danger, fontSize: 12)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _loading ? null : () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: _loading ? null : _refund,
          style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
          child: _loading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Reembolsar'),
        ),
      ],
    );
  }
}
