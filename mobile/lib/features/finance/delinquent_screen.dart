import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_client.dart';
import '../../core/providers/currency_provider.dart';
import '../../core/theme/app_theme.dart';

// ---------------------------------------------------------------------------
// Model (guardian-grouped)
// ---------------------------------------------------------------------------
class DelinquentItem {
  final String? guardianId;
  final String guardianName;
  final int invoiceCount;
  final double totalOverdue;
  final double bucket0_30;
  final double bucket31_60;
  final double bucket61_90;
  final double bucket90Plus;

  const DelinquentItem({
    this.guardianId,
    required this.guardianName,
    required this.invoiceCount,
    required this.totalOverdue,
    required this.bucket0_30,
    required this.bucket31_60,
    required this.bucket61_90,
    required this.bucket90Plus,
  });

  factory DelinquentItem.fromJson(Map<String, dynamic> json) {
    return DelinquentItem(
      guardianId: json['guardian_id'] as String?,
      guardianName: json['guardian_name'] as String? ?? 'Desconhecido',
      invoiceCount: (json['invoice_count'] as num?)?.toInt() ?? 0,
      totalOverdue: (json['total_overdue'] as num?)?.toDouble() ?? 0.0,
      bucket0_30: (json['bucket_0_30'] as num?)?.toDouble() ?? 0.0,
      bucket31_60: (json['bucket_31_60'] as num?)?.toDouble() ?? 0.0,
      bucket61_90: (json['bucket_61_90'] as num?)?.toDouble() ?? 0.0,
      bucket90Plus: (json['bucket_90_plus'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------
final delinquentProvider =
    FutureProvider.autoDispose<List<DelinquentItem>>((ref) async {
  final api = ref.read(apiClientProvider);
  final data = await api.get('/finance/reports/delinquent') as List;
  return data
      .map((e) => DelinquentItem.fromJson(e as Map<String, dynamic>))
      .toList();
});

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------
class DelinquentScreen extends ConsumerWidget {
  const DelinquentScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final delinquentAsync = ref.watch(delinquentProvider);
    final currency = ref.watch(currencyFormatProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Contas em Atraso'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(delinquentProvider),
          ),
        ],
      ),
      body: delinquentAsync.when(
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
                onPressed: () => ref.invalidate(delinquentProvider),
                icon: const Icon(Icons.refresh),
                label: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
        data: (items) {
          if (items.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle_outline,
                      size: 64, color: Colors.green.shade400),
                  const SizedBox(height: 16),
                  const Text('Nenhuma conta em atraso!',
                      style: TextStyle(
                          color: AppTheme.success,
                          fontWeight: FontWeight.w600,
                          fontSize: 16)),
                ],
              ),
            );
          }

          final totalAmount =
              items.fold<double>(0, (sum, i) => sum + i.totalOverdue);

          return Column(
            children: [
              // Summary banner
              Container(
                margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFDE8E8),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFCA5A5)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        color: AppTheme.danger, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${items.length} responsável${items.length != 1 ? 'eis' : ''} em atraso',
                            style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: AppTheme.danger,
                                fontSize: 15),
                          ),
                          Text(
                            'Total: ${currency.format(totalAmount)}',
                            style: const TextStyle(
                                color: AppTheme.danger,
                                fontWeight: FontWeight.w600,
                                fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async => ref.invalidate(delinquentProvider),
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                    itemCount: items.length,
                    itemBuilder: (context, i) {
                      final item = items[i];
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
                                      item.guardianName,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15),
                                    ),
                                  ),
                                  Text(
                                    '${item.invoiceCount} factura${item.invoiceCount != 1 ? 's' : ''}',
                                    style: const TextStyle(
                                        color: AppTheme.textSecondary,
                                        fontSize: 12),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Total em atraso',
                                      style: TextStyle(
                                          color: AppTheme.textSecondary,
                                          fontSize: 13)),
                                  Text(
                                    currency.format(item.totalOverdue),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                        color: AppTheme.danger),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              // Aging buckets
                              _AgingRow(
                                  label: '0–30 dias',
                                  amount: item.bucket0_30,
                                  currency: currency),
                              _AgingRow(
                                  label: '31–60 dias',
                                  amount: item.bucket31_60,
                                  currency: currency),
                              _AgingRow(
                                  label: '61–90 dias',
                                  amount: item.bucket61_90,
                                  currency: currency),
                              _AgingRow(
                                  label: '+90 dias',
                                  amount: item.bucket90Plus,
                                  currency: currency,
                                  highlight: true),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AgingRow extends StatelessWidget {
  final String label;
  final double amount;
  final NumberFormat currency;
  final bool highlight;

  const _AgingRow({
    required this.label,
    required this.amount,
    required this.currency,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    if (amount <= 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 12,
                  color: highlight ? AppTheme.danger : AppTheme.textSecondary)),
          Text(currency.format(amount),
              style: TextStyle(
                  fontSize: 12,
                  fontWeight:
                      highlight ? FontWeight.bold : FontWeight.normal,
                  color: highlight ? AppTheme.danger : AppTheme.textSecondary)),
        ],
      ),
    );
  }
}
