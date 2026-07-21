import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_client.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/models/child.dart';
import '../../../core/models/invoice.dart';
import '../../../core/providers/currency_provider.dart';
import '../../finance/credit_notes_screen.dart';

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------
final invoicesProvider =
    FutureProvider.autoDispose<List<Invoice>>((ref) async {
  final api = ref.read(apiClientProvider);
  final data = await api.get('/finance/invoices',
      queryParameters: {'ordering': '-invoice_date'}) as List;
  return data
      .map((e) => Invoice.fromJson(e as Map<String, dynamic>))
      .toList();
});

final childrenForInvoiceProvider =
    FutureProvider.autoDispose<List<Child>>((ref) async {
  final api = ref.read(apiClientProvider);
  final data = await api.get('/children') as List;
  return data
      .map((e) => Child.fromJson(e as Map<String, dynamic>))
      .toList();
});

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------
class InvoicesScreen extends ConsumerStatefulWidget {
  const InvoicesScreen({super.key});

  @override
  ConsumerState<InvoicesScreen> createState() => _InvoicesScreenState();
}

class _InvoicesScreenState extends ConsumerState<InvoicesScreen> {
  String _statusFilter = 'all';

  @override
  Widget build(BuildContext context) {
    final invoicesAsync = ref.watch(invoicesProvider);
    final currency = ref.watch(currencyFormatProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Facturas'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'bulk_generate') {
                _showBulkGenerateDialog(context);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'bulk_generate',
                child: Row(
                  children: [
                    Icon(Icons.auto_awesome, size: 20),
                    SizedBox(width: 8),
                    Text('Gerar Facturas em Massa'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCreateInvoiceSheet(context),
        tooltip: 'Nova Factura',
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          // Filter chips
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildFilterChip('all', 'Todas'),
                  const SizedBox(width: 8),
                  _buildFilterChip('pending', 'Pendentes'),
                  const SizedBox(width: 8),
                  _buildFilterChip('paid', 'Pagas'),
                  const SizedBox(width: 8),
                  _buildFilterChip('overdue', 'Em Atraso'),
                  const SizedBox(width: 8),
                  _buildFilterChip('cancelled', 'Canceladas'),
                ],
              ),
            ),
          ),

          Expanded(
            child: invoicesAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline,
                        size: 48, color: Colors.red),
                    const SizedBox(height: 8),
                    Text(e.toString(), textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () => ref.invalidate(invoicesProvider),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Tentar novamente'),
                    ),
                  ],
                ),
              ),
              data: (invoices) {
                final filtered = _statusFilter == 'all'
                    ? invoices
                    : invoices
                        .where((i) => i.status == _statusFilter)
                        .toList();

                if (filtered.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.receipt_long,
                            size: 64,
                            color: Theme.of(context)
                                .colorScheme
                                .outlineVariant),
                        const SizedBox(height: 16),
                        Text(
                          'Nenhuma factura encontrada',
                          style: Theme.of(context)
                              .textTheme
                              .bodyLarge
                              ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant),
                        ),
                      ],
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async =>
                      ref.invalidate(invoicesProvider),
                  child: ListView.builder(
                    padding: const EdgeInsets.only(bottom: 88),
                    itemCount: filtered.length,
                    itemBuilder: (context, i) {
                      final inv = filtered[i];
                      return Card(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          onTap: (inv.status != 'paid' &&
                                  inv.status != 'cancelled' &&
                                  inv.status != 'void')
                              ? () => _showRecordPaymentDialog(context, inv)
                              : null,
                          title: Text(
                            inv.childName ??
                                'Criança ${inv.childId.substring(0, 8)}',
                            style: const TextStyle(
                                fontWeight: FontWeight.w600),
                          ),
                          subtitle: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Text(
                                  'Ref: ${DateFormat('MMMM yyyy', 'pt_PT').format(inv.referenceMonth)}'),
                              if (inv.dueDate != null)
                                Text(
                                  'Vence: ${DateFormat('dd/MM/yyyy').format(inv.dueDate!)}',
                                  style: TextStyle(
                                    color: inv.isOverdue
                                        ? Colors.red
                                        : null,
                                    fontSize: 12,
                                  ),
                                ),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Column(
                                mainAxisAlignment:
                                    MainAxisAlignment.center,
                                crossAxisAlignment:
                                    CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    currency.format(inv.totalAmount),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 4),
                                  _StatusChip(
                                      status: inv.status,
                                      label: inv.statusLabel),
                                ],
                              ),
                              const SizedBox(width: 4),
                              // Action menu per invoice
                              PopupMenuButton<String>(
                                icon: const Icon(Icons.more_vert,
                                    size: 18),
                                padding: EdgeInsets.zero,
                                onSelected: (action) {
                                  if (action == 'pay') {
                                    _showRecordPaymentDialog(
                                        context, inv);
                                  } else if (action == 'void') {
                                    _showVoidConfirmation(
                                        context, inv);
                                  }
                                },
                                itemBuilder: (_) => [
                                  if (inv.status != 'paid' &&
                                      inv.status != 'cancelled' &&
                                      inv.status != 'void')
                                    const PopupMenuItem(
                                      value: 'pay',
                                      child: Row(
                                        children: [
                                          Icon(Icons.payments_outlined,
                                              size: 18,
                                              color: Colors.green),
                                          SizedBox(width: 8),
                                          Text('Pagar'),
                                        ],
                                      ),
                                    ),
                                  if (inv.status != 'void' &&
                                      inv.status != 'cancelled')
                                    const PopupMenuItem(
                                      value: 'void',
                                      child: Row(
                                        children: [
                                          Icon(Icons.cancel_outlined,
                                              size: 18,
                                              color: Colors.red),
                                          SizedBox(width: 8),
                                          Text('Anular'),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String value, String label) {
    return FilterChip(
      label: Text(label),
      selected: _statusFilter == value,
      showCheckmark: false,
      selectedColor:
          Theme.of(context).colorScheme.primaryContainer,
      onSelected: (_) => setState(() => _statusFilter = value),
    );
  }

  void _showCreateInvoiceSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CreateInvoiceSheet(
        onCreated: () {
          ref.invalidate(invoicesProvider);
          Navigator.pop(context);
        },
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Task 1: Record Payment dialog
  // -------------------------------------------------------------------------
  void _showRecordPaymentDialog(BuildContext context, Invoice inv) {
    showDialog(useRootNavigator: false, 
      context: context,
      builder: (_) => _RecordPaymentDialog(
        invoice: inv,
        onSuccess: () => ref.invalidate(invoicesProvider),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Task 5: Void invoice — opens VoidInvoiceDialog which collects a reason
  // -------------------------------------------------------------------------
  void _showVoidConfirmation(BuildContext context, Invoice inv) {
    showDialog(useRootNavigator: false, 
      context: context,
      builder: (_) => VoidInvoiceDialog(
        invoiceId: inv.id,
        onVoided: () => ref.invalidate(invoicesProvider),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Task 4: Bulk generate dialog
  // -------------------------------------------------------------------------
  void _showBulkGenerateDialog(BuildContext context) {
    showDialog(useRootNavigator: false, 
      context: context,
      builder: (_) => _BulkGenerateDialog(
        onSuccess: (count) {
          ref.invalidate(invoicesProvider);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content:
                    Text('$count factura(s) gerada(s) com sucesso')),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Task 1: Record Payment dialog
// ---------------------------------------------------------------------------
class _RecordPaymentDialog extends ConsumerStatefulWidget {
  final Invoice invoice;
  final VoidCallback onSuccess;

  const _RecordPaymentDialog(
      {required this.invoice, required this.onSuccess});

  @override
  ConsumerState<_RecordPaymentDialog> createState() =>
      _RecordPaymentDialogState();
}

class _RecordPaymentDialogState
    extends ConsumerState<_RecordPaymentDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountCtrl;
  final _notesCtrl = TextEditingController();
  DateTime _paymentDate = DateTime.now();
  String _paymentMethod = 'multicaixa_express';
  XFile? _proofFile;
  bool _isLoading = false;
  String? _error;

  static const _paymentMethods = {
    'multicaixa_express': 'Multicaixa Express',
    'bank_transfer': 'Transferência Bancária',
    'cash': 'Numerário',
    'cheque': 'Cheque',
  };

  @override
  void initState() {
    super.initState();
    _amountCtrl = TextEditingController(
        text: widget.invoice.totalAmount.toStringAsFixed(2));
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickProof() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (file != null) setState(() => _proofFile = file);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_proofFile == null) {
      setState(() => _error = 'Comprovativo de pagamento obrigatório.');
      return;
    }

    final employeeId = ref.read(authProvider).employeeId;
    if (employeeId == null) {
      setState(() => _error = 'Funcionário não associado a esta conta');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final api = ref.read(apiClientProvider);

      // 1. Upload proof first
      final uploadResult = await api.uploadFile(
        '/finance/payment-proof',
        _proofFile!,
        fieldName: 'file',
      ) as Map<String, dynamic>;
      final proofUrl = uploadResult['url'] as String;

      // 2. Create payment
      final amount = double.tryParse(_amountCtrl.text) ?? 0.0;
      final dateStr =
          '${_paymentDate.year.toString().padLeft(4, '0')}-${_paymentDate.month.toString().padLeft(2, '0')}-${_paymentDate.day.toString().padLeft(2, '0')}';

      if (widget.invoice.billingGuardianId == null) {
        setState(() {
          _error = 'Esta factura não tem encarregado de educação associado';
          _isLoading = false;
        });
        return;
      }

      await api.post('/finance/payments', data: {
        'billing_guardian_id': widget.invoice.billingGuardianId,
        'target_invoice_ids': [widget.invoice.id],
        'amount': amount,
        'payment_date': dateStr,
        'payment_method': _paymentMethod,
        'received_by': employeeId,
        'receipt_proof_url': proofUrl,
        if (_notesCtrl.text.trim().isNotEmpty)
          'notes': _notesCtrl.text.trim(),
      });

      widget.onSuccess();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _paymentDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) setState(() => _paymentDate = picked);
  }

  @override
  Widget build(BuildContext context) {
    final currency = ref.watch(currencyFormatProvider);
    return AlertDialog(
      title: const Text('Registar Pagamento'),
      content: SizedBox(
        width: double.maxFinite,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true),
                decoration: InputDecoration(
                  labelText: 'Valor (${currency.currencySymbol}) *',
                  prefixIcon: const Icon(Icons.monetization_on_outlined),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty)
                    return 'Campo obrigatório';
                  if (double.tryParse(v) == null)
                    return 'Valor inválido';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: _pickDate,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Data de Pagamento',
                    prefixIcon: Icon(Icons.calendar_today),
                  ),
                  child: Text(
                      DateFormat('dd/MM/yyyy').format(_paymentDate)),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _paymentMethod,
                decoration: const InputDecoration(
                  labelText: 'Método de Pagamento *',
                  prefixIcon: Icon(Icons.payment),
                ),
                items: _paymentMethods.entries
                    .map((e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(e.value),
                        ))
                    .toList(),
                onChanged: (v) =>
                    setState(() => _paymentMethod = v!),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notesCtrl,
                decoration: const InputDecoration(
                  labelText: 'Notas (opcional)',
                  prefixIcon: Icon(Icons.notes),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              // Mandatory proof of payment
              InkWell(
                onTap: _isLoading ? null : _pickProof,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 14),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: _proofFile == null
                          ? Theme.of(context).colorScheme.error
                          : Theme.of(context).colorScheme.primary,
                      width: _proofFile == null ? 1 : 1.5,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _proofFile == null
                            ? Icons.attach_file
                            : Icons.check_circle_outline,
                        color: _proofFile == null
                            ? Theme.of(context).colorScheme.error
                            : Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Comprovativo *',
                              style: TextStyle(
                                fontSize: 12,
                                color: _proofFile == null
                                    ? Theme.of(context).colorScheme.error
                                    : Theme.of(context).colorScheme.primary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _proofFile == null
                                  ? 'Anexar recibo ou transferência'
                                  : _proofFile!.name,
                              style: TextStyle(
                                fontSize: 13,
                                color: _proofFile == null
                                    ? Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant
                                    : Theme.of(context).colorScheme.primary,
                                fontWeight: _proofFile != null
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _isLoading ? null : _submit,
          child: _isLoading
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Text('Confirmar'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Task 4: Bulk generate invoices dialog
// ---------------------------------------------------------------------------
class _BulkGenerateDialog extends ConsumerStatefulWidget {
  final void Function(int count) onSuccess;

  const _BulkGenerateDialog({required this.onSuccess});

  @override
  ConsumerState<_BulkGenerateDialog> createState() =>
      _BulkGenerateDialogState();
}

class _BulkGenerateDialogState
    extends ConsumerState<_BulkGenerateDialog> {
  final _formKey = GlobalKey<FormState>();
  DateTime _referenceMonth = DateTime.now();
  DateTime? _dueDate;
  String? _selectedSchoolYearId;
  bool _isLoading = false;
  bool _loadingYears = true;
  String? _error;
  List<Map<String, dynamic>> _schoolYears = [];

  @override
  void initState() {
    super.initState();
    _loadSchoolYears();
  }

  Future<void> _loadSchoolYears() async {
    try {
      final api = ref.read(apiClientProvider);
      final data =
          await api.get('/schools/school-years') as List;
      setState(() {
        _schoolYears = data
            .map((e) => e as Map<String, dynamic>)
            .toList();
        _loadingYears = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Erro ao carregar anos lectivos: $e';
        _loadingYears = false;
      });
    }
  }

  Future<void> _pickReferenceMonth() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _referenceMonth,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      helpText: 'Seleccionar mês de referência',
    );
    if (picked != null) {
      setState(() =>
          _referenceMonth = DateTime(picked.year, picked.month, 1));
    }
  }

  Future<void> _pickDueDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) setState(() => _dueDate = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedSchoolYearId == null) {
      setState(() => _error = 'Seleccione um ano lectivo');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final api = ref.read(apiClientProvider);
      final refMonthStr =
          '${_referenceMonth.year.toString().padLeft(4, '0')}-${_referenceMonth.month.toString().padLeft(2, '0')}-01';

      final body = <String, dynamic>{
        'school_year_id': _selectedSchoolYearId,
        'reference_month': refMonthStr,
      };
      if (_dueDate != null) {
        body['due_date'] =
            '${_dueDate!.year.toString().padLeft(4, '0')}-${_dueDate!.month.toString().padLeft(2, '0')}-${_dueDate!.day.toString().padLeft(2, '0')}';
      }

      final response =
          await api.post('/finance/invoices/bulk', data: body);

      final count = (response is Map)
          ? (response['created'] as int? ?? 0)
          : 0;

      if (mounted) Navigator.pop(context);
      widget.onSuccess(count);
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Gerar Facturas em Massa'),
      content: SizedBox(
        width: double.maxFinite,
        child: _loadingYears
            ? const SizedBox(
                height: 80,
                child: Center(child: CircularProgressIndicator()))
            : Form(
                key: _formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButtonFormField<String>(
                        value: _selectedSchoolYearId,
                        decoration: const InputDecoration(
                          labelText: 'Ano Lectivo *',
                          prefixIcon: Icon(Icons.school),
                        ),
                        items: _schoolYears
                            .map((y) => DropdownMenuItem(
                                  value:
                                      y['id']?.toString() ?? '',
                                  child: Text(
                                      y['year_label'] as String? ??
                                          ''),
                                ))
                            .toList(),
                        onChanged: (v) => setState(
                            () => _selectedSchoolYearId = v),
                        validator: (v) => v == null
                            ? 'Seleccione um ano lectivo'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      InkWell(
                        onTap: _pickReferenceMonth,
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Mês de Referência *',
                            prefixIcon: Icon(Icons.date_range),
                          ),
                          child: Text(DateFormat('MMMM yyyy', 'pt_PT')
                              .format(_referenceMonth)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      InkWell(
                        onTap: _pickDueDate,
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Data Limite (opcional)',
                            prefixIcon:
                                Icon(Icons.event_available),
                          ),
                          child: Text(_dueDate == null
                              ? 'Não definida'
                              : DateFormat('dd/MM/yyyy')
                                  .format(_dueDate!)),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Os preços são obtidos automaticamente dos contratos activos.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(_error!,
                            style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .error)),
                      ],
                    ],
                  ),
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _isLoading ? null : _submit,
          child: _isLoading
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Text('Gerar'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Create Invoice bottom sheet
// ---------------------------------------------------------------------------
class _CreateInvoiceSheet extends ConsumerStatefulWidget {
  final VoidCallback onCreated;
  const _CreateInvoiceSheet({required this.onCreated});

  @override
  ConsumerState<_CreateInvoiceSheet> createState() =>
      _CreateInvoiceSheetState();
}

class _CreateInvoiceSheetState
    extends ConsumerState<_CreateInvoiceSheet> {
  final _formKey = GlobalKey<FormState>();
  final _tuitionCtrl = TextEditingController();
  final _otherFeesCtrl = TextEditingController(text: '0');
  final _descCtrl = TextEditingController();
  String? _selectedChildId;
  DateTime _referenceMonth = DateTime.now();
  DateTime? _dueDate;
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _tuitionCtrl.dispose();
    _otherFeesCtrl.dispose();
    _descCtrl.dispose();
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
      final tuition = double.tryParse(_tuitionCtrl.text) ?? 0.0;
      final otherFees =
          double.tryParse(_otherFeesCtrl.text) ?? 0.0;
      final employeeId = ref.read(authProvider).employeeId;
      if (employeeId == null) {
        setState(() {
          _error =
              'Utilizador não tem registo de funcionário associado';
          _isLoading = false;
        });
        return;
      }
      final lines = <Map<String, dynamic>>[
        {
          'description': 'Mensalidade',
          'quantity': 1,
          'unit_price': tuition,
          'iva_rate': 0,
        },
        if (otherFees > 0)
          {
            'description': 'Outras taxas',
            'quantity': 1,
            'unit_price': otherFees,
            'iva_rate': 0,
          },
      ];

      await api.post('/finance/invoices', data: {
        'document_type': 'FT',
        'child_id': _selectedChildId,
        'reference_month':
            '${_referenceMonth.year.toString().padLeft(4, '0')}-${_referenceMonth.month.toString().padLeft(2, '0')}-01',
        'lines': lines,
        if (_descCtrl.text.trim().isNotEmpty)
          'description': _descCtrl.text.trim(),
        if (_dueDate != null)
          'due_date':
              '${_dueDate!.year.toString().padLeft(4, '0')}-${_dueDate!.month.toString().padLeft(2, '0')}-${_dueDate!.day.toString().padLeft(2, '0')}',
      });
      widget.onCreated();
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final childrenAsync = ref.watch(childrenForInvoiceProvider);
    final currency = ref.watch(currencyFormatProvider);

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Nova Factura',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),

            childrenAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('Erro: $e'),
              data: (children) =>
                  DropdownButtonFormField<String>(
                value: _selectedChildId,
                decoration: const InputDecoration(
                  labelText: 'Criança *',
                  prefixIcon: Icon(Icons.child_care),
                ),
                items: children
                    .map((c) => DropdownMenuItem(
                          value: c.id,
                          child: Text(c.fullName),
                        ))
                    .toList(),
                onChanged: (v) =>
                    setState(() => _selectedChildId = v),
                validator: (v) =>
                    v == null ? 'Seleccione uma criança' : null,
              ),
            ),
            const SizedBox(height: 12),

            TextFormField(
              controller: _tuitionCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                  decimal: true),
              decoration: InputDecoration(
                labelText: 'Mensalidade (${currency.currencySymbol}) *',
                prefixIcon: const Icon(Icons.monetization_on_outlined),
              ),
              validator: (v) =>
                  v == null || v.trim().isEmpty
                      ? 'Campo obrigatório'
                      : null,
            ),
            const SizedBox(height: 12),

            TextFormField(
              controller: _otherFeesCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                  decimal: true),
              decoration: InputDecoration(
                labelText: 'Outras taxas (${currency.currencySymbol})',
                prefixIcon: const Icon(Icons.add_circle_outline),
              ),
            ),
            const SizedBox(height: 12),

            TextFormField(
              controller: _descCtrl,
              decoration: const InputDecoration(
                labelText: 'Descrição (opcional)',
                prefixIcon: Icon(Icons.notes),
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style: TextStyle(
                      color:
                          Theme.of(context).colorScheme.error)),
            ],

            const SizedBox(height: 16),
            FilledButton(
              onPressed: _isLoading ? null : _submit,
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white))
                  : const Text('Criar Factura'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  final String label;
  const _StatusChip({required this.status, required this.label});

  @override
  Widget build(BuildContext context) {
    Color color;
    switch (status) {
      case 'paid':
        color = Colors.green;
        break;
      case 'overdue':
        color = Colors.red;
        break;
      case 'partially_paid':
        color = Colors.orange;
        break;
      case 'cancelled':
      case 'void':
        color = Colors.grey;
        break;
      default:
        color = Colors.blue;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(label,
          style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600)),
    );
  }
}
