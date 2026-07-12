import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/app_theme.dart';

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------
class Receipt {
  final String id;
  final String fullDocumentNumber;
  final String? paymentId;
  final String? invoiceId;
  final double amount;
  final String issuedAt;
  final String? nifCliente;

  const Receipt({
    required this.id,
    required this.fullDocumentNumber,
    this.paymentId,
    this.invoiceId,
    required this.amount,
    required this.issuedAt,
    this.nifCliente,
  });

  factory Receipt.fromJson(Map<String, dynamic> json) {
    return Receipt(
      id: json['id']?.toString() ?? '',
      fullDocumentNumber:
          json['full_document_number'] as String? ?? json['document_number'] as String? ?? '',
      paymentId: json['payment_id']?.toString(),
      invoiceId: json['invoice_id']?.toString(),
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      issuedAt: json['issued_at'] as String? ?? '',
      nifCliente: json['nif_cliente'] as String?,
    );
  }
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------
final receiptsProvider =
    FutureProvider.autoDispose<List<Receipt>>((ref) async {
  final api = ref.read(apiClientProvider);
  final data = await api.get('/finance/receipts') as List;
  return data.map((e) => Receipt.fromJson(e as Map<String, dynamic>)).toList();
});

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------
class ReceiptsScreen extends ConsumerWidget {
  const ReceiptsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final receiptsAsync = ref.watch(receiptsProvider);
    final currency = NumberFormat.currency(locale: 'pt_PT', symbol: 'Kz');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Recibos'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(receiptsProvider),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateDialog(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Novo Recibo'),
      ),
      body: receiptsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: AppTheme.danger),
              const SizedBox(height: 8),
              Text(e.toString(), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => ref.invalidate(receiptsProvider),
                icon: const Icon(Icons.refresh),
                label: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
        data: (receipts) {
          if (receipts.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.receipt_outlined,
                      size: 64, color: Colors.grey.shade400),
                  const SizedBox(height: 16),
                  const Text('Nenhum recibo encontrado',
                      style: TextStyle(color: AppTheme.textSecondary)),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(receiptsProvider),
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
              itemCount: receipts.length,
              itemBuilder: (context, i) {
                final r = receipts[i];
                final dateStr = r.issuedAt.isNotEmpty
                    ? (() {
                        try {
                          return DateFormat('dd/MM/yyyy')
                              .format(DateTime.parse(r.issuedAt));
                        } catch (_) {
                          return r.issuedAt;
                        }
                      })()
                    : '';
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFFDEF7EC),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.receipt,
                          color: AppTheme.success, size: 22),
                    ),
                    title: Text(
                      r.fullDocumentNumber,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                    subtitle: Text(dateStr,
                        style: const TextStyle(
                            color: AppTheme.textSecondary, fontSize: 12)),
                    trailing: Text(
                      currency.format(r.amount),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  void _showCreateDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (_) => _CreateReceiptDialog(
        onCreated: () => ref.invalidate(receiptsProvider),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Payment model for picker
// ---------------------------------------------------------------------------
class _PaymentEntry {
  final String id;
  final double amount;
  final String paymentDate;
  final String? paymentMethod;

  const _PaymentEntry({
    required this.id,
    required this.amount,
    required this.paymentDate,
    this.paymentMethod,
  });

  factory _PaymentEntry.fromJson(Map<String, dynamic> json) => _PaymentEntry(
        id: json['id']?.toString() ?? '',
        amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
        paymentDate: json['payment_date'] as String? ?? '',
        paymentMethod: json['payment_method'] as String?,
      );

  String get label {
    final currency = NumberFormat.currency(locale: 'pt_PT', symbol: 'Kz');
    final dateStr = paymentDate.isNotEmpty
        ? (() {
            try {
              return DateFormat('dd/MM/yyyy').format(DateTime.parse(paymentDate));
            } catch (_) {
              return paymentDate;
            }
          })()
        : '';
    return '$dateStr — ${currency.format(amount)}${paymentMethod != null ? ' ($paymentMethod)' : ''}';
  }
}

// ---------------------------------------------------------------------------
// Create Receipt Dialog
// ---------------------------------------------------------------------------
class _CreateReceiptDialog extends ConsumerStatefulWidget {
  final VoidCallback onCreated;
  const _CreateReceiptDialog({required this.onCreated});

  @override
  ConsumerState<_CreateReceiptDialog> createState() =>
      _CreateReceiptDialogState();
}

class _CreateReceiptDialogState extends ConsumerState<_CreateReceiptDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nifCtrl = TextEditingController();
  List<_PaymentEntry> _payments = [];
  String? _selectedPaymentId;
  bool _loadingPayments = true;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPayments();
  }

  @override
  void dispose() {
    _nifCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPayments() async {
    try {
      final api = ref.read(apiClientProvider);
      final data = await api.get('/finance/payments', queryParameters: {'limit': '100'}) as List;
      if (mounted) {
        setState(() {
          _payments = data
              .map((e) => _PaymentEntry.fromJson(e as Map<String, dynamic>))
              .toList();
          _loadingPayments = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadingPayments = false);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedPaymentId == null) {
      setState(() => _error = 'Seleccione um pagamento');
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      await api.post('/finance/receipts', data: {
        'payment_id': _selectedPaymentId,
        if (_nifCtrl.text.trim().isNotEmpty) 'nif_cliente': _nifCtrl.text.trim(),
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

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Novo Recibo'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_loadingPayments)
                const Center(child: CircularProgressIndicator())
              else
                DropdownButtonFormField<String>(
                  value: _selectedPaymentId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Pagamento *'),
                  items: _payments
                      .map((p) => DropdownMenuItem(
                            value: p.id,
                            child: Text(p.label,
                                overflow: TextOverflow.ellipsis),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _selectedPaymentId = v),
                  validator: (v) =>
                      v == null ? 'Seleccione um pagamento' : null,
                ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nifCtrl,
                decoration: const InputDecoration(
                    labelText: 'NIF do cliente (opcional)'),
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
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Text('Criar Recibo'),
        ),
      ],
    );
  }
}
