import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_client.dart';
import '../../../core/providers/currency_provider.dart';
import '../../../core/theme/app_theme.dart';

final _paymentRefsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final api = ref.read(apiClientProvider);
  final data = await api.get('/finance/payment-references') as List;
  return data.cast<Map<String, dynamic>>();
});

class PaymentReferencesScreen extends ConsumerStatefulWidget {
  const PaymentReferencesScreen({super.key});

  @override
  ConsumerState<PaymentReferencesScreen> createState() => _PaymentReferencesScreenState();
}

class _PaymentReferencesScreenState extends ConsumerState<PaymentReferencesScreen> {
  String _filter = 'active';

  @override
  Widget build(BuildContext context) {
    final refsAsync = ref.watch(_paymentRefsProvider);
    final currency = ref.watch(currencyFormatProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Referências Multicaixa'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: () => ref.invalidate(_paymentRefsProvider)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreate(context),
        icon: const Icon(Icons.add),
        label: const Text('Nova Referência'),
      ),
      body: refsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(e.toString(), style: const TextStyle(color: AppTheme.danger))),
        data: (refs) {
          final filtered = _filter == 'all' ? refs : refs.where((r) => r['status'] == _filter).toList();
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    _chip('all', 'Todas'),
                    const SizedBox(width: 8),
                    _chip('active', 'Activas'),
                    const SizedBox(width: 8),
                    _chip('paid', 'Pagas'),
                    const SizedBox(width: 8),
                    _chip('expired', 'Expiradas'),
                    const SizedBox(width: 8),
                    _chip('cancelled', 'Canceladas'),
                  ]),
                ),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? const Center(child: Text('Nenhuma referência encontrada', style: TextStyle(color: AppTheme.textSecondary)))
                    : RefreshIndicator(
                        onRefresh: () async => ref.invalidate(_paymentRefsProvider),
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 100),
                          itemCount: filtered.length,
                          itemBuilder: (_, i) => _RefCard(
                            ref_: filtered[i],
                            currency: currency,
                            onChanged: () => ref.invalidate(_paymentRefsProvider),
                          ),
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _chip(String value, String label) => FilterChip(
    label: Text(label),
    selected: _filter == value,
    showCheckmark: false,
    selectedColor: Theme.of(context).colorScheme.primaryContainer,
    onSelected: (_) => setState(() => _filter = value),
  );

  void _showCreate(BuildContext context) {
    showDialog(useRootNavigator: false, 
      context: context,
      builder: (_) => _CreateRefDialog(onCreated: () => ref.invalidate(_paymentRefsProvider)),
    );
  }
}

class _RefCard extends ConsumerStatefulWidget {
  final Map<String, dynamic> ref_;
  final NumberFormat currency;
  final VoidCallback onChanged;
  const _RefCard({required this.ref_, required this.currency, required this.onChanged});

  @override
  ConsumerState<_RefCard> createState() => _RefCardState();
}

class _RefCardState extends ConsumerState<_RefCard> {
  @override
  Widget build(BuildContext context) {
    final r = widget.ref_;
    final status = r['status'] as String? ?? 'active';
    final isActive = status == 'active';
    final color = switch (status) {
      'active' => AppTheme.primary,
      'paid' => AppTheme.success,
      'expired' || 'cancelled' => Colors.grey,
      _ => AppTheme.textSecondary,
    };
    final amount = (r['amount'] as num?)?.toDouble();

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: color.withOpacity(0.25))),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
                child: Text(status.toUpperCase(), style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
              const Spacer(),
              if (isActive)
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, size: 18),
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'markpaid', child: Row(children: [Icon(Icons.check_circle_outline, size: 18, color: AppTheme.success), SizedBox(width: 8), Text('Marcar como Paga')])),
                    const PopupMenuItem(value: 'cancel', child: Row(children: [Icon(Icons.cancel_outlined, size: 18, color: AppTheme.danger), SizedBox(width: 8), Text('Cancelar', style: TextStyle(color: AppTheme.danger))])),
                  ],
                  onSelected: (action) {
                    if (action == 'markpaid') _showMarkPaid(context);
                    if (action == 'cancel') _cancel(context);
                  },
                ),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.person_outline, size: 14, color: AppTheme.textSecondary),
              const SizedBox(width: 4),
              Expanded(child: Text(r['guardian_name'] as String? ?? '—', style: const TextStyle(fontWeight: FontWeight.w700))),
            ]),
            const SizedBox(height: 4),
            Row(
              children: [
                _infoChip('Entidade', r['entity'] as String? ?? '—'),
                const SizedBox(width: 8),
                _infoChip('Referência', r['reference'] as String? ?? '—'),
                if (amount != null) ...[
                  const SizedBox(width: 8),
                  _infoChip('Valor', widget.currency.format(amount)),
                ],
              ],
            ),
            if (r['expires_at'] != null) ...[
              const SizedBox(height: 4),
              Text('Expira: ${r['expires_at']}', style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _infoChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(6)),
      child: Column(
        children: [
          Text(label, style: const TextStyle(fontSize: 9, color: AppTheme.textSecondary)),
          Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
        ],
      ),
    );
  }

  void _showMarkPaid(BuildContext context) {
    final amountCtrl = TextEditingController(text: ((widget.ref_['amount'] as num?)?.toDouble() ?? 0).toStringAsFixed(2));
    DateTime payDate = DateTime.now();
    showDialog(useRootNavigator: false, 
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Marcar como Paga'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Valor Recebido *'),
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: () async {
                  final p = await showDatePicker(context: ctx, initialDate: payDate, firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 1)));
                  if (p != null) setS(() => payDate = p);
                },
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'Data de Pagamento'),
                  child: Text(DateFormat('dd/MM/yyyy').format(payDate)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () async {
                try {
                  final api = ref.read(apiClientProvider);
                  await api.post('/finance/payment-references/${widget.ref_['id']}/mark-paid', data: {
                    'amount': double.tryParse(amountCtrl.text) ?? 0.0,
                    'payment_date': '${payDate.year}-${payDate.month.toString().padLeft(2,'0')}-${payDate.day.toString().padLeft(2,'0')}',
                  });
                  if (ctx.mounted) Navigator.pop(ctx);
                  widget.onChanged();
                } catch (e) {
                  if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Erro: $e'), backgroundColor: AppTheme.danger));
                }
              },
              child: const Text('Confirmar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _cancel(BuildContext context) async {
    final confirmed = await showDialog<bool>(useRootNavigator: false, 
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cancelar Referência'),
        content: const Text('Confirma o cancelamento desta referência de pagamento?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Não')),
          FilledButton(onPressed: () => Navigator.pop(context, true), style: FilledButton.styleFrom(backgroundColor: AppTheme.danger), child: const Text('Cancelar')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final api = ref.read(apiClientProvider);
      await api.post('/finance/payment-references/${widget.ref_['id']}/cancel');
      widget.onChanged();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e'), backgroundColor: AppTheme.danger));
    }
  }
}

// ─── Create Reference Dialog ──────────────────────────────────────────────────

class _CreateRefDialog extends ConsumerStatefulWidget {
  final VoidCallback onCreated;
  const _CreateRefDialog({required this.onCreated});

  @override
  ConsumerState<_CreateRefDialog> createState() => _CreateRefDialogState();
}

class _CreateRefDialogState extends ConsumerState<_CreateRefDialog> {
  final _entityCtrl = TextEditingController();
  final _refCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  String? _selectedGuardianId;
  String? _selectedInvoiceId;
  List<Map<String, dynamic>> _guardians = [];
  List<Map<String, dynamic>> _invoices = [];
  DateTime? _expiresAt;
  bool _loading = true;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadGuardians();
  }

  @override
  void dispose() {
    _entityCtrl.dispose(); _refCtrl.dispose(); _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadGuardians() async {
    try {
      final api = ref.read(apiClientProvider);
      final data = await api.get('/guardians') as List;
      setState(() { _guardians = data.cast<Map<String, dynamic>>(); _loading = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _loadInvoices(String guardianId) async {
    try {
      final api = ref.read(apiClientProvider);
      final data = await api.get('/finance/invoices', queryParameters: {'billing_guardian_id': guardianId}) as List;
      setState(() => _invoices = data.cast<Map<String, dynamic>>().where((i) => i['status'] != 'paid' && i['status'] != 'cancelled').toList());
    } catch (_) {}
  }

  Future<void> _create() async {
    if (_entityCtrl.text.trim().isEmpty || _refCtrl.text.trim().isEmpty || _selectedGuardianId == null) {
      setState(() => _error = 'Preencha os campos obrigatórios');
      return;
    }
    setState(() { _submitting = true; _error = null; });
    try {
      final api = ref.read(apiClientProvider);
      await api.post('/finance/payment-references', data: {
        'billing_guardian_id': _selectedGuardianId,
        if (_selectedInvoiceId != null) 'invoice_id': _selectedInvoiceId,
        'entity': _entityCtrl.text.trim(),
        'reference': _refCtrl.text.trim(),
        'provider': 'manual',
        if (_amountCtrl.text.trim().isNotEmpty) 'amount': double.tryParse(_amountCtrl.text),
        if (_expiresAt != null) 'expires_at': '${_expiresAt!.year}-${_expiresAt!.month.toString().padLeft(2,'0')}-${_expiresAt!.day.toString().padLeft(2,'0')}T23:59:59',
      });
      widget.onCreated();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() { _error = e.toString(); _submitting = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nova Referência Multicaixa'),
      content: SizedBox(
        width: 380,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      value: _selectedGuardianId,
                      decoration: const InputDecoration(labelText: 'Encarregado *'),
                      isExpanded: true,
                      items: _guardians.map((g) => DropdownMenuItem(value: g['id']?.toString(), child: Text('${g['first_name'] ?? ''} ${g['last_name'] ?? ''}'.trim(), overflow: TextOverflow.ellipsis))).toList(),
                      onChanged: (v) {
                        setState(() { _selectedGuardianId = v; _selectedInvoiceId = null; _invoices = []; });
                        if (v != null) _loadInvoices(v);
                      },
                    ),
                    const SizedBox(height: 10),
                    if (_invoices.isNotEmpty)
                      DropdownButtonFormField<String>(
                        value: _selectedInvoiceId,
                        decoration: const InputDecoration(labelText: 'Factura (opcional)'),
                        isExpanded: true,
                        items: [
                          const DropdownMenuItem(value: null, child: Text('Sem factura específica')),
                          ..._invoices.map((i) => DropdownMenuItem(
                            value: i['id']?.toString(),
                            child: Text('${i['full_document_number'] ?? ''} — ${NumberFormat.simpleCurrency(name: 'AOA').format((i['balance'] as num?)?.toDouble() ?? 0)}', overflow: TextOverflow.ellipsis),
                          )),
                        ],
                        onChanged: (v) {
                          setState(() => _selectedInvoiceId = v);
                          if (v != null) {
                            final inv = _invoices.where((i) => i['id']?.toString() == v).firstOrNull;
                            if (inv != null) _amountCtrl.text = ((inv['balance'] as num?)?.toDouble() ?? 0).toStringAsFixed(2);
                          }
                        },
                      ),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(child: TextFormField(controller: _entityCtrl, decoration: const InputDecoration(labelText: 'Entidade *'), keyboardType: TextInputType.number)),
                      const SizedBox(width: 10),
                      Expanded(child: TextFormField(controller: _refCtrl, decoration: const InputDecoration(labelText: 'Referência *'), keyboardType: TextInputType.number)),
                    ]),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _amountCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Valor (opcional)', helperText: 'Vazio = montante em aberto'),
                    ),
                    const SizedBox(height: 10),
                    InkWell(
                      onTap: () async {
                        final p = await showDatePicker(context: context, initialDate: _expiresAt ?? DateTime.now().add(const Duration(days: 30)), firstDate: DateTime.now(), lastDate: DateTime(2030));
                        if (p != null) setState(() => _expiresAt = p);
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(labelText: 'Data de Validade'),
                        child: Text(_expiresAt != null ? DateFormat('dd/MM/yyyy').format(_expiresAt!) : 'Não definida', style: TextStyle(color: _expiresAt == null ? AppTheme.textSecondary : null)),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      Text(_error!, style: const TextStyle(color: AppTheme.danger, fontSize: 12)),
                    ],
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(onPressed: _submitting ? null : () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: _submitting ? null : _create,
          child: _submitting ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Criar'),
        ),
      ],
    );
  }
}
