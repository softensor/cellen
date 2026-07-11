import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/app_theme.dart';

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------
class DelinquentItem {
  final String childName;
  final String? guardianName;
  final String? guardianMobile;
  final String invoiceNumber;
  final double amount;
  final int daysOverdue;
  final String dueDate;

  const DelinquentItem({
    required this.childName,
    this.guardianName,
    this.guardianMobile,
    required this.invoiceNumber,
    required this.amount,
    required this.daysOverdue,
    required this.dueDate,
  });

  factory DelinquentItem.fromJson(Map<String, dynamic> json) {
    return DelinquentItem(
      childName: json['child_name'] as String? ?? '',
      guardianName: json['guardian_name'] as String?,
      guardianMobile: json['guardian_mobile'] as String?,
      invoiceNumber: json['invoice_number'] as String? ??
          json['full_document_number'] as String? ?? '',
      amount: (json['amount'] as num?)?.toDouble() ??
          (json['total_amount'] as num?)?.toDouble() ?? 0.0,
      daysOverdue: (json['days_overdue'] as num?)?.toInt() ?? 0,
      dueDate: json['due_date'] as String? ?? '',
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
    final currency = NumberFormat.currency(locale: 'pt_PT', symbol: 'Kz');

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
              items.fold<double>(0, (sum, i) => sum + i.amount);

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
                            '${items.length} conta${items.length != 1 ? 's' : ''} em atraso',
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
                      final dueDateStr = item.dueDate.isNotEmpty
                          ? (() {
                              try {
                                return DateFormat('dd/MM/yyyy')
                                    .format(DateTime.parse(item.dueDate));
                              } catch (_) {
                                return item.dueDate;
                              }
                            })()
                          : '';
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
                                      item.childName,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFDE8E8),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      '${item.daysOverdue} dias',
                                      style: const TextStyle(
                                          color: AppTheme.danger,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700),
                                    ),
                                  ),
                                ],
                              ),
                              if (item.guardianName != null) ...[
                                const SizedBox(height: 4),
                                GestureDetector(
                                  onTap: item.guardianMobile != null
                                      ? () {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(SnackBar(
                                            content: Text(
                                                'Ligar para ${item.guardianMobile}'),
                                          ));
                                        }
                                      : null,
                                  child: Row(
                                    children: [
                                      const Icon(Icons.person_outline,
                                          size: 14,
                                          color: AppTheme.textSecondary),
                                      const SizedBox(width: 4),
                                      Text(
                                        item.guardianName!,
                                        style: const TextStyle(
                                            color: AppTheme.textSecondary,
                                            fontSize: 13),
                                      ),
                                      if (item.guardianMobile != null) ...[
                                        const SizedBox(width: 8),
                                        const Icon(Icons.phone,
                                            size: 14,
                                            color: AppTheme.primary),
                                        const SizedBox(width: 2),
                                        Text(
                                          item.guardianMobile!,
                                          style: const TextStyle(
                                              color: AppTheme.primary,
                                              fontSize: 13,
                                              decoration:
                                                  TextDecoration.underline),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Factura: ${item.invoiceNumber}',
                                          style: const TextStyle(
                                              fontSize: 12,
                                              color: AppTheme.textSecondary),
                                        ),
                                        if (dueDateStr.isNotEmpty)
                                          Text(
                                            'Venceu: $dueDateStr',
                                            style: const TextStyle(
                                                fontSize: 12,
                                                color: AppTheme.danger),
                                          ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    currency.format(item.amount),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                        color: AppTheme.danger),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerRight,
                                child: OutlinedButton.icon(
                                  onPressed: () {
                                    ScaffoldMessenger.of(context)
                                        .showSnackBar(SnackBar(
                                      content: Text(
                                          'Lembrete enviado para ${item.guardianName ?? item.childName}'),
                                    ));
                                  },
                                  icon: const Icon(Icons.notifications_active_outlined,
                                      size: 16),
                                  label: const Text('Lembrar'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppTheme.warning,
                                    side: const BorderSide(
                                        color: AppTheme.warning),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 6),
                                  ),
                                ),
                              ),
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
