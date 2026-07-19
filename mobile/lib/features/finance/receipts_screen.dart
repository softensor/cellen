import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_client.dart';
import '../../core/providers/currency_provider.dart';
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
      amount: (json['gross_total'] as num?)?.toDouble() ?? 0.0,
      issuedAt: json['system_entry_date'] as String? ?? '',
      nifCliente: json['customer_nif'] as String?,
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
    final currency = ref.watch(currencyFormatProvider);

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

}

