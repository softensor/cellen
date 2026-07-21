import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_client.dart';
import '../../../core/providers/currency_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_error_widget.dart';

final _paymentPlansProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final api = ref.read(apiClientProvider);
  final data = await api.get('/finance/payment-plans') as List;
  return data.cast<Map<String, dynamic>>();
});

class PaymentPlansScreen extends ConsumerStatefulWidget {
  const PaymentPlansScreen({super.key});

  @override
  ConsumerState<PaymentPlansScreen> createState() => _PaymentPlansScreenState();
}

class _PaymentPlansScreenState extends ConsumerState<PaymentPlansScreen> {
  String _filter = 'all';

  @override
  Widget build(BuildContext context) {
    final plansAsync = ref.watch(_paymentPlansProvider);
    final currency = ref.watch(currencyFormatProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Planos de Pagamento'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: () => ref.invalidate(_paymentPlansProvider)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreatePlan(context),
        icon: const Icon(Icons.add),
        label: const Text('Novo Plano'),
      ),
      body: plansAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AppErrorWidget(error: e, onRetry: () => ref.invalidate(_paymentPlansProvider)),
        data: (plans) {
          final filtered = _filter == 'all' ? plans : plans.where((p) => p['status'] == _filter).toList();
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    _chip('all', 'Todos'),
                    const SizedBox(width: 8),
                    _chip('active', 'Activos'),
                    const SizedBox(width: 8),
                    _chip('completed', 'Concluídos'),
                    const SizedBox(width: 8),
                    _chip('breached', 'Incumprimento'),
                    const SizedBox(width: 8),
                    _chip('cancelled', 'Cancelados'),
                  ]),
                ),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? const Center(child: Text('Nenhum plano encontrado', style: TextStyle(color: AppTheme.textSecondary)))
                    : RefreshIndicator(
                        onRefresh: () async => ref.invalidate(_paymentPlansProvider),
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 100),
                          itemCount: filtered.length,
                          itemBuilder: (_, i) => _PlanCard(
                            plan: filtered[i],
                            currency: currency,
                            onChanged: () => ref.invalidate(_paymentPlansProvider),
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

  void _showCreatePlan(BuildContext context) {
    showDialog(useRootNavigator: false, 
      context: context,
      builder: (_) => _CreatePlanDialog(onCreated: () => ref.invalidate(_paymentPlansProvider)),
    );
  }
}

// ─── Plan Card ───────────────────────────────────────────────────────────────

class _PlanCard extends ConsumerStatefulWidget {
  final Map<String, dynamic> plan;
  final NumberFormat currency;
  final VoidCallback onChanged;
  const _PlanCard({required this.plan, required this.currency, required this.onChanged});

  @override
  ConsumerState<_PlanCard> createState() => _PlanCardState();
}

class _PlanCardState extends ConsumerState<_PlanCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final plan = widget.plan;
    final status = plan['status'] as String? ?? 'active';
    final color = _statusColor(status);
    final total = (plan['total_amount'] as num?)?.toDouble() ?? 0;
    final installments = (plan['installments'] as List? ?? []).cast<Map<String, dynamic>>();
    final metCount = installments.where((i) => i['status'] == 'met').length;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: color.withOpacity(0.3))),
      child: Column(
        children: [
          ListTile(
            leading: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
              child: Icon(Icons.event_repeat_outlined, color: color, size: 20),
            ),
            title: Text(plan['guardian_name'] as String? ?? '—', style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(
              '${widget.currency.format(total)} · $metCount/${installments.length} prestações',
              style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _StatusBadge(status: status),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, size: 18),
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'cancel', child: Row(children: [Icon(Icons.cancel_outlined, size: 18, color: AppTheme.danger), SizedBox(width: 8), Text('Cancelar Plano', style: TextStyle(color: AppTheme.danger))])),
                  ],
                  onSelected: (action) {
                    if (action == 'cancel') _cancel(context);
                  },
                ),
                IconButton(
                  icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
                  onPressed: () => setState(() => _expanded = !_expanded),
                ),
              ],
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                children: installments.map((inst) => _InstallmentRow(
                  inst: inst,
                  currency: widget.currency,
                  planId: plan['id']?.toString() ?? '',
                  onChanged: widget.onChanged,
                )).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _cancel(BuildContext context) async {
    final confirmed = await showDialog<bool>(useRootNavigator: false, 
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cancelar Plano'),
        content: const Text('Tem a certeza que deseja cancelar este plano de pagamento?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Não')),
          FilledButton(onPressed: () => Navigator.pop(context, true), style: FilledButton.styleFrom(backgroundColor: AppTheme.danger), child: const Text('Cancelar Plano')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final api = ref.read(apiClientProvider);
      await api.patch('/finance/payment-plans/${widget.plan['id']}', data: {'status': 'cancelled'});
      widget.onChanged();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e'), backgroundColor: AppTheme.danger));
    }
  }

  Color _statusColor(String s) => switch (s) {
    'active' => AppTheme.primary,
    'completed' => AppTheme.success,
    'breached' => AppTheme.danger,
    _ => Colors.grey,
  };
}

class _InstallmentRow extends ConsumerStatefulWidget {
  final Map<String, dynamic> inst;
  final NumberFormat currency;
  final String planId;
  final VoidCallback onChanged;
  const _InstallmentRow({required this.inst, required this.currency, required this.planId, required this.onChanged});

  @override
  ConsumerState<_InstallmentRow> createState() => _InstallmentRowState();
}

class _InstallmentRowState extends ConsumerState<_InstallmentRow> {
  bool _marking = false;

  @override
  Widget build(BuildContext context) {
    final inst = widget.inst;
    final status = inst['status'] as String? ?? 'pending';
    final isMet = status == 'met';
    final isMissed = status == 'missed';

    return ListTile(
      dense: true,
      leading: Icon(
        isMet ? Icons.check_circle : isMissed ? Icons.cancel : Icons.radio_button_unchecked,
        color: isMet ? AppTheme.success : isMissed ? AppTheme.danger : AppTheme.textSecondary,
        size: 20,
      ),
      title: Text(
        'Prestação ${inst['installment_number'] ?? ''} — ${inst['due_date'] ?? ''}',
        style: const TextStyle(fontSize: 13),
      ),
      subtitle: Text(widget.currency.format((inst['amount'] as num?)?.toDouble() ?? 0), style: const TextStyle(fontSize: 12)),
      trailing: !isMet
          ? TextButton(
              onPressed: _marking ? null : () => _markMet(context),
              child: _marking
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Marcar Paga', style: TextStyle(fontSize: 12)),
            )
          : null,
    );
  }

  Future<void> _markMet(BuildContext context) async {
    // Ask for payment method before recording
    String method = 'bank_transfer';
    final picked = await showDialog<String>(useRootNavigator: false, 
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Método de Pagamento'),
        children: [
          SimpleDialogOption(onPressed: () => Navigator.pop(context, 'bank_transfer'), child: const Text('Transferência Bancária')),
          SimpleDialogOption(onPressed: () => Navigator.pop(context, 'cash'),          child: const Text('Numerário')),
          SimpleDialogOption(onPressed: () => Navigator.pop(context, 'multicaixa_ref'), child: const Text('Multicaixa / ATM')),
          SimpleDialogOption(onPressed: () => Navigator.pop(context, 'multicaixa_express'), child: const Text('Multicaixa Express')),
          SimpleDialogOption(onPressed: () => Navigator.pop(context, 'check'),         child: const Text('Cheque')),
          SimpleDialogOption(onPressed: () => Navigator.pop(context, 'other'),         child: const Text('Outro')),
        ],
      ),
    );
    if (picked == null) return;
    method = picked;

    setState(() => _marking = true);
    try {
      final api = ref.read(apiClientProvider);
      await api.post(
        '/finance/payment-plans/${widget.planId}/installments/${widget.inst['id']}/mark-met',
        data: {'payment_method': method},
      );
      widget.onChanged();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e'), backgroundColor: AppTheme.danger));
      setState(() => _marking = false);
    }
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'active' => ('Activo', AppTheme.primary),
      'completed' => ('Concluído', AppTheme.success),
      'breached' => ('Incumprimento', AppTheme.danger),
      'cancelled' => ('Cancelado', Colors.grey),
      _ => (status, Colors.grey),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }
}

// ─── Create Plan Dialog ───────────────────────────────────────────────────────

class _CreatePlanDialog extends ConsumerStatefulWidget {
  final VoidCallback onCreated;
  const _CreatePlanDialog({required this.onCreated});

  @override
  ConsumerState<_CreatePlanDialog> createState() => _CreatePlanDialogState();
}

class _CreatePlanDialogState extends ConsumerState<_CreatePlanDialog> {
  List<Map<String, dynamic>> _guardians = [];
  List<Map<String, dynamic>> _invoices = [];
  String? _selectedGuardianId;
  final List<String> _selectedInvoiceIds = [];
  final List<Map<String, dynamic>> _installments = [];
  bool _loadingGuardians = true;
  bool _loadingInvoices = false;
  bool _submitting = false;
  String? _error;
  int _page = 0; // 0=guardian, 1=invoices, 2=installments

  @override
  void initState() {
    super.initState();
    _loadGuardians();
  }

  Future<void> _loadGuardians() async {
    try {
      final api = ref.read(apiClientProvider);
      final data = await api.get('/guardians') as List;
      setState(() { _guardians = data.cast<Map<String, dynamic>>(); _loadingGuardians = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _loadingGuardians = false; });
    }
  }

  Future<void> _loadInvoices(String guardianId) async {
    setState(() { _loadingInvoices = true; _invoices = []; });
    try {
      final api = ref.read(apiClientProvider);
      final data = await api.get('/finance/invoices', queryParameters: {
        'billing_guardian_id': guardianId,
        'status': 'overdue',
      }) as List;
      setState(() { _invoices = data.cast<Map<String, dynamic>>(); _loadingInvoices = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _loadingInvoices = false; });
    }
  }

  double get _totalBalance {
    return _invoices.where((i) => _selectedInvoiceIds.contains(i['id']?.toString())).fold(0.0, (sum, i) => sum + ((i['balance'] as num?)?.toDouble() ?? 0));
  }

  Future<void> _submit() async {
    if (_selectedGuardianId == null || _selectedInvoiceIds.isEmpty || _installments.isEmpty) return;
    setState(() { _submitting = true; _error = null; });
    try {
      final api = ref.read(apiClientProvider);
      await api.post('/finance/payment-plans', data: {
        'billing_guardian_id': _selectedGuardianId,
        'invoice_ids': _selectedInvoiceIds,
        'installments': _installments,
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
      title: Text(['Seleccionar Encarregado', 'Seleccionar Facturas', 'Definir Prestações'][_page]),
      content: SizedBox(
        width: 400,
        child: _buildPage(),
      ),
      actions: [
        if (_page > 0) TextButton(onPressed: () => setState(() => _page--), child: const Text('Anterior')),
        TextButton(onPressed: _submitting ? null : () => Navigator.pop(context), child: const Text('Cancelar')),
        if (_page < 2)
          FilledButton(
            onPressed: _canNext() ? _nextPage : null,
            child: const Text('Próximo'),
          )
        else
          FilledButton(
            onPressed: _submitting ? null : _submit,
            child: _submitting ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Criar Plano'),
          ),
      ],
    );
  }

  bool _canNext() {
    if (_page == 0) return _selectedGuardianId != null;
    if (_page == 1) return _selectedInvoiceIds.isNotEmpty;
    return _installments.isNotEmpty;
  }

  void _nextPage() {
    if (_page == 0 && _selectedGuardianId != null) {
      _loadInvoices(_selectedGuardianId!);
    }
    setState(() { _page++; });
  }

  Widget _buildPage() {
    if (_page == 0) return _buildGuardianPage();
    if (_page == 1) return _buildInvoicesPage();
    return _buildInstallmentsPage();
  }

  Widget _buildGuardianPage() {
    if (_loadingGuardians) return const Center(child: CircularProgressIndicator());
    return DropdownButtonFormField<String>(
      value: _selectedGuardianId,
      decoration: const InputDecoration(labelText: 'Encarregado *'),
      isExpanded: true,
      items: _guardians.map((g) => DropdownMenuItem(
        value: g['id']?.toString(),
        child: Text('${g['first_name'] ?? ''} ${g['last_name'] ?? ''}'.trim(), overflow: TextOverflow.ellipsis),
      )).toList(),
      onChanged: (v) => setState(() => _selectedGuardianId = v),
    );
  }

  Widget _buildInvoicesPage() {
    if (_loadingInvoices) return const Center(child: CircularProgressIndicator());
    if (_invoices.isEmpty) return const Text('Sem facturas em atraso para este encarregado', style: TextStyle(color: AppTheme.textSecondary));
    final currency = NumberFormat.simpleCurrency(name: 'AOA');
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Seleccione as facturas a incluir no plano:', style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
        const SizedBox(height: 8),
        ..._invoices.map((inv) {
          final id = inv['id']?.toString() ?? '';
          final selected = _selectedInvoiceIds.contains(id);
          return CheckboxListTile(
            dense: true,
            value: selected,
            title: Text(inv['full_document_number'] as String? ?? '', style: const TextStyle(fontSize: 13)),
            subtitle: Text(currency.format((inv['balance'] as num?)?.toDouble() ?? 0)),
            onChanged: (v) => setState(() {
              if (v == true) _selectedInvoiceIds.add(id);
              else _selectedInvoiceIds.remove(id);
            }),
          );
        }),
        const Divider(),
        Text('Total: ${currency.format(_totalBalance)}', style: const TextStyle(fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildInstallmentsPage() {
    final currency = NumberFormat.simpleCurrency(name: 'AOA');
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Total a dividir: ${currency.format(_totalBalance)}', style: const TextStyle(fontWeight: FontWeight.w600, color: AppTheme.primary)),
        const SizedBox(height: 8),
        ..._installments.asMap().entries.map((e) => ListTile(
          dense: true,
          title: Text('Prestação ${e.key + 1}: ${currency.format(e.value['amount'])} em ${e.value['due_date']}'),
          trailing: IconButton(icon: const Icon(Icons.delete_outline, size: 18, color: AppTheme.danger), onPressed: () => setState(() => _installments.removeAt(e.key))),
        )),
        TextButton.icon(
          onPressed: () => _addInstallment(context),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Adicionar Prestação'),
        ),
        if (_error != null) Text(_error!, style: const TextStyle(color: AppTheme.danger, fontSize: 12)),
      ],
    );
  }

  void _addInstallment(BuildContext context) {
    final amountCtrl = TextEditingController();
    DateTime dueDate = DateTime.now().add(const Duration(days: 30));
    showDialog(useRootNavigator: false, 
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Nova Prestação'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(controller: amountCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Valor *')),
              const SizedBox(height: 12),
              InkWell(
                onTap: () async {
                  final p = await showDatePicker(context: ctx, initialDate: dueDate, firstDate: DateTime.now(), lastDate: DateTime(2030));
                  if (p != null) setS(() => dueDate = p);
                },
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'Data Limite'),
                  child: Text(DateFormat('dd/MM/yyyy').format(dueDate)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () {
                final amount = double.tryParse(amountCtrl.text) ?? 0;
                if (amount <= 0) return;
                Navigator.pop(ctx);
                setState(() => _installments.add({
                  'amount': amount,
                  'due_date': '${dueDate.year.toString().padLeft(4, '0')}-${dueDate.month.toString().padLeft(2, '0')}-${dueDate.day.toString().padLeft(2, '0')}',
                }));
              },
              child: const Text('Adicionar'),
            ),
          ],
        ),
      ),
    );
  }
}
