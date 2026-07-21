import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_client.dart';
import '../../core/models/child.dart';
import '../../core/providers/currency_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_error_widget.dart';

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------
class Contract {
  final String id;
  final String childId;
  final String? childName;
  final String? guardianId;
  final String serviceName;
  final double unitPrice;
  final double ivaRate;
  final String billingCycle;
  final int dayOfMonth;
  final String startDate;
  final String? endDate;
  final bool isActive;
  final bool autoInvoice;
  final String? lastInvoicedMonth;

  const Contract({
    required this.id,
    required this.childId,
    this.childName,
    this.guardianId,
    required this.serviceName,
    required this.unitPrice,
    required this.ivaRate,
    required this.billingCycle,
    required this.dayOfMonth,
    required this.startDate,
    this.endDate,
    required this.isActive,
    required this.autoInvoice,
    this.lastInvoicedMonth,
  });

  factory Contract.fromJson(Map<String, dynamic> json) {
    return Contract(
      id: json['id']?.toString() ?? '',
      childId: json['child_id']?.toString() ?? '',
      childName: json['child_name'] as String?,
      guardianId: json['guardian_id']?.toString(),
      serviceName: json['service_name'] as String? ?? '',
      unitPrice: (json['unit_price'] as num?)?.toDouble() ?? 0.0,
      ivaRate: (json['iva_rate'] as num?)?.toDouble() ?? 0.0,
      billingCycle: json['billing_cycle'] as String? ?? 'monthly',
      dayOfMonth: (json['day_of_month'] as num?)?.toInt() ?? 1,
      startDate: json['start_date'] as String? ?? '',
      endDate: json['end_date'] as String?,
      isActive: json['is_active'] as bool? ?? true,
      autoInvoice: json['auto_invoice'] as bool? ?? false,
      lastInvoicedMonth: json['last_invoiced_month'] as String?,
    );
  }
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------
final contractsProvider =
    FutureProvider.autoDispose<List<Contract>>((ref) async {
  final api = ref.read(apiClientProvider);
  final data = await api.get('/finance/contracts') as List;
  return data.map((e) => Contract.fromJson(e as Map<String, dynamic>)).toList();
});

final childrenForContractProvider =
    FutureProvider.autoDispose<List<Child>>((ref) async {
  final api = ref.read(apiClientProvider);
  final data = await api.get('/children') as List;
  return data.map((e) => Child.fromJson(e as Map<String, dynamic>)).toList();
});

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------
class ContractsScreen extends ConsumerWidget {
  const ContractsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contractsAsync = ref.watch(contractsProvider);
    final currency = ref.watch(currencyFormatProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Contratos'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
            onPressed: () => ref.invalidate(contractsProvider),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateDialog(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Novo Contrato'),
      ),
      body: contractsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AppErrorWidget(error: e, onRetry: () => ref.invalidate(contractsProvider)),
        data: (contracts) {
          if (contracts.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.description_outlined,
                      size: 64, color: Colors.grey.shade400),
                  const SizedBox(height: 16),
                  Text('Nenhum contrato encontrado',
                      style: TextStyle(color: AppTheme.textSecondary)),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(contractsProvider),
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
              itemCount: contracts.length,
              itemBuilder: (context, i) {
                final c = contracts[i];
                return _ContractCard(
                  contract: c,
                  currency: currency,
                  onGenerateInvoice: () async {
                    try {
                      await ref
                          .read(apiClientProvider)
                          .post('/finance/contracts/${c.id}/generate-invoice');
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Factura gerada com sucesso')),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Erro: $e')),
                        );
                      }
                    }
                  },
                );
              },
            ),
          );
        },
      ),
    );
  }

  void _showCreateDialog(BuildContext context, WidgetRef ref) {
    showDialog(useRootNavigator: false, 
      context: context,
      builder: (_) => _CreateContractDialog(
        onCreated: () => ref.invalidate(contractsProvider),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Contract card
// ---------------------------------------------------------------------------
class _ContractCard extends StatelessWidget {
  final Contract contract;
  final NumberFormat currency;
  final VoidCallback onGenerateInvoice;

  const _ContractCard({
    required this.contract,
    required this.currency,
    required this.onGenerateInvoice,
  });

  String _cycleLabel(String cycle) => switch (cycle) {
        'monthly' => 'Mensal',
        'quarterly' => 'Trimestral',
        'biannual' => 'Semestral',
        'annual' => 'Anual',
        _ => cycle,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    contract.childName ?? 'Criança',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: contract.isActive
                        ? AppTheme.statusBg('present')
                        : AppTheme.statusBg('absent'),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    contract.isActive ? 'Activo' : 'Inactivo',
                    style: TextStyle(
                      color: contract.isActive
                          ? AppTheme.statusText('present')
                          : AppTheme.statusText('absent'),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(contract.serviceName,
                style: TextStyle(color: AppTheme.textSecondary)),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  currency.format(contract.unitPrice),
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16),
                ),
                Text(
                  ' + IVA ${contract.ivaRate.toStringAsFixed(0)}%',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE0F2FE),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _cycleLabel(contract.billingCycle),
                    style: const TextStyle(
                        color: Color(0xFF0369A1),
                        fontSize: 11,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text('Desde ${contract.startDate}',
                    style: TextStyle(
                        color: AppTheme.textSecondary, fontSize: 12)),
                const Spacer(),
                TextButton.icon(
                  onPressed: onGenerateInvoice,
                  icon: const Icon(Icons.receipt_long, size: 16),
                  label: const Text('Gerar Factura'),
                  style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Create Contract Dialog
// ---------------------------------------------------------------------------
class _CreateContractDialog extends ConsumerStatefulWidget {
  final VoidCallback onCreated;
  const _CreateContractDialog({required this.onCreated});

  @override
  ConsumerState<_CreateContractDialog> createState() =>
      _CreateContractDialogState();
}

class _CreateContractDialogState extends ConsumerState<_CreateContractDialog> {
  final _formKey = GlobalKey<FormState>();
  final _serviceNameCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  String? _selectedChildId;
  double _ivaRate = 14.0;
  String _billingCycle = 'monthly';
  int _dayOfMonth = 1;
  DateTime _startDate = DateTime.now();
  bool _autoInvoice = true;
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _serviceNameCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedChildId == null) {
      setState(() => _error = 'Seleccione uma criança');
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      final start =
          '${_startDate.year.toString().padLeft(4, '0')}-${_startDate.month.toString().padLeft(2, '0')}-${_startDate.day.toString().padLeft(2, '0')}';
      await api.post('/finance/contracts', data: {
        'child_id': _selectedChildId,
        'service_name': _serviceNameCtrl.text.trim(),
        'unit_price': double.tryParse(_amountCtrl.text) ?? 0.0,
        'iva_rate': _ivaRate,
        'billing_cycle': _billingCycle,
        'day_of_month': _dayOfMonth,
        'start_date': start,
        'auto_invoice': _autoInvoice,
      });
      widget.onCreated();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) setState(() => _startDate = picked);
  }

  @override
  Widget build(BuildContext context) {
    final childrenAsync = ref.watch(childrenForContractProvider);

    return AlertDialog(
      title: const Text('Novo Contrato'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                childrenAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Text('Erro: $e'),
                  data: (children) => DropdownButtonFormField<String>(
                    value: _selectedChildId,
                    decoration: const InputDecoration(labelText: 'Criança *'),
                    isExpanded: true,
                    items: children
                        .map((c) => DropdownMenuItem(
                            value: c.id, child: Text(c.fullName)))
                        .toList(),
                    onChanged: (v) => setState(() => _selectedChildId = v),
                    validator: (v) =>
                        v == null ? 'Seleccione uma criança' : null,
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _serviceNameCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Serviço *'),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Obrigatório' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _amountCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Valor (Kz) *'),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Obrigatório' : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<double>(
                  value: _ivaRate,
                  decoration: const InputDecoration(labelText: 'IVA'),
                  items: const [
                    DropdownMenuItem(value: 14.0, child: Text('14%')),
                    DropdownMenuItem(value: 0.0, child: Text('0% (Isento)')),
                  ],
                  onChanged: (v) => setState(() => _ivaRate = v ?? 14.0),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _billingCycle,
                  decoration: const InputDecoration(labelText: 'Ciclo'),
                  items: const [
                    DropdownMenuItem(value: 'monthly', child: Text('Mensal')),
                    DropdownMenuItem(
                        value: 'quarterly', child: Text('Trimestral')),
                    DropdownMenuItem(
                        value: 'biannual', child: Text('Semestral')),
                    DropdownMenuItem(value: 'annual', child: Text('Anual')),
                  ],
                  onChanged: (v) =>
                      setState(() => _billingCycle = v ?? 'monthly'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  value: _dayOfMonth,
                  decoration: const InputDecoration(labelText: 'Dia do mês'),
                  items: List.generate(
                      28,
                      (i) => DropdownMenuItem(
                          value: i + 1, child: Text('${i + 1}'))).toList(),
                  onChanged: (v) => setState(() => _dayOfMonth = v ?? 1),
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: _pickStartDate,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                        labelText: 'Data de início'),
                    child: Text(
                        DateFormat('dd/MM/yyyy').format(_startDate)),
                  ),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  title: const Text('Facturação automática'),
                  value: _autoInvoice,
                  onChanged: (v) => setState(() => _autoInvoice = v),
                  contentPadding: EdgeInsets.zero,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!,
                      style: const TextStyle(color: AppTheme.danger)),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _isLoading ? null : _submit,
          child: _isLoading
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child:
                      CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Criar Contrato'),
        ),
      ],
    );
  }
}
