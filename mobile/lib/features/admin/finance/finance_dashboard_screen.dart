import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_client.dart';
import '../../../core/models/invoice.dart';

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------
class FinanceSummary {
  final double totalIncome;
  final double totalExpenses;
  final double netPnl;
  final double outstanding;
  final int outstandingCount;

  const FinanceSummary({
    required this.totalIncome,
    required this.totalExpenses,
    required this.netPnl,
    required this.outstanding,
    required this.outstandingCount,
  });

  factory FinanceSummary.fromJson(Map<String, dynamic> json) {
    return FinanceSummary(
      totalIncome: (json['total_income'] as num?)?.toDouble() ?? 0.0,
      totalExpenses: (json['total_expenses'] as num?)?.toDouble() ?? 0.0,
      netPnl: (json['net_pnl'] as num?)?.toDouble() ?? 0.0,
      outstanding: (json['outstanding_amount'] as num?)?.toDouble() ?? 0.0,
      outstandingCount: json['outstanding_count'] as int? ?? 0,
    );
  }
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------
final financeSummaryProvider =
    FutureProvider.autoDispose<FinanceSummary>((ref) async {
  final api = ref.read(apiClientProvider);
  final data = await api.get('/finance/summary');
  return FinanceSummary.fromJson(data as Map<String, dynamic>);
});

final recentInvoicesProvider =
    FutureProvider.autoDispose<List<Invoice>>((ref) async {
  final api = ref.read(apiClientProvider);
  final data =
      await api.get('/finance/invoices', queryParameters: {'limit': '10', 'ordering': '-invoice_date'})
          as List;
  return data
      .map((e) => Invoice.fromJson(e as Map<String, dynamic>))
      .toList();
});

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------
class FinanceDashboardScreen extends ConsumerWidget {
  const FinanceDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(financeSummaryProvider);
    final recentAsync = ref.watch(recentInvoicesProvider);
    final currency = NumberFormat.currency(locale: 'pt_PT', symbol: '€');
    final now = DateTime.now();
    final monthLabel = DateFormat('MMMM yyyy', 'pt_PT').format(now);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Finanças'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(financeSummaryProvider);
              ref.invalidate(recentInvoicesProvider);
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(financeSummaryProvider);
          ref.invalidate(recentInvoicesProvider);
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Resumo — $monthLabel',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 12),

              summaryAsync.when(
                loading: () => const SizedBox(
                  height: 140,
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('Erro ao carregar: $e'),
                  ),
                ),
                data: (summary) => Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _SummaryCard(
                            label: 'Receita',
                            value: currency.format(summary.totalIncome),
                            icon: Icons.arrow_downward,
                            color: Colors.green,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _SummaryCard(
                            label: 'Despesas',
                            value: currency.format(summary.totalExpenses),
                            icon: Icons.arrow_upward,
                            color: Colors.red,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _SummaryCard(
                            label: 'Resultado',
                            value: currency.format(summary.netPnl),
                            icon: Icons.account_balance,
                            color: summary.netPnl >= 0
                                ? Colors.teal
                                : Colors.red,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _SummaryCard(
                            label: 'Por Cobrar',
                            value: currency.format(summary.outstanding),
                            sublabel: '${summary.outstandingCount} facturas',
                            icon: Icons.pending_actions,
                            color: Colors.orange,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Quick actions
              Text(
                'Acções Rápidas',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          context.go('/admin/finance/invoices'),
                      icon: const Icon(Icons.receipt),
                      label: const Text('Facturas'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          context.go('/admin/finance/expenses'),
                      icon: const Icon(Icons.receipt_long),
                      label: const Text('Despesas'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          context.go('/admin/finance/contracts'),
                      icon: const Icon(Icons.description_outlined),
                      label: const Text('Contratos'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          context.go('/admin/finance/receipts'),
                      icon: const Icon(Icons.point_of_sale_outlined),
                      label: const Text('Recibos'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          context.go('/admin/finance/credit-notes'),
                      icon: const Icon(Icons.undo_outlined),
                      label: const Text('Notas Crédito'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          context.go('/admin/finance/delinquent'),
                      icon: const Icon(Icons.warning_amber_outlined),
                      label: const Text('Devedores'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => context.go('/admin/finance/saft'),
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('Exportar SAF-T AO'),
                ),
              ),

              const SizedBox(height: 24),

              // Recent invoices
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Facturas Recentes',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  TextButton(
                    onPressed: () =>
                        context.go('/admin/finance/invoices'),
                    child: const Text('Ver todas'),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              recentAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Text('Erro: $e'),
                data: (invoices) {
                  if (invoices.isEmpty) {
                    return const Center(
                        child: Text('Nenhuma factura encontrada'));
                  }
                  return Column(
                    children: invoices.take(10).map((inv) {
                      return Card(
                        margin: const EdgeInsets.only(bottom: 6),
                        child: ListTile(
                          dense: true,
                          title: Text(
                            inv.childName ??
                                'Criança ${inv.childId.substring(0, 6)}',
                            style: const TextStyle(
                                fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                              DateFormat('MMMM yyyy', 'pt_PT')
                                  .format(inv.referenceMonth)),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                currency.format(inv.totalAmount),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(width: 8),
                              _StatusChip(
                                  status: inv.status,
                                  label: inv.statusLabel),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final String? sublabel;
  final IconData icon;
  final Color color;

  const _SummaryCard({
    required this.label,
    required this.value,
    this.sublabel,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            if (sublabel != null)
              Text(
                sublabel!,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12),
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
      child: Text(
        label,
        style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w600),
      ),
    );
  }
}
