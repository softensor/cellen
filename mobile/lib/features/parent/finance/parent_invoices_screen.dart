import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_client.dart';
import '../../../core/providers/currency_provider.dart';
import '../../../core/widgets/app_error_widget.dart';

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------

class ParentInvoice {
  final String id;
  final String childId;
  final String childName;
  final DateTime referenceMonth;
  final double totalAmount;
  final String status;
  final DateTime? dueDate;
  final String? multicaixaEntity;
  final String? multicaixaRef;
  final double amountPaid;
  final double balance;
  final String? proofStatus; // pending_review | approved | rejected | null
  final String? rejectionReason;

  const ParentInvoice({
    required this.id,
    required this.childId,
    required this.childName,
    required this.referenceMonth,
    required this.totalAmount,
    required this.status,
    this.dueDate,
    this.multicaixaEntity,
    this.multicaixaRef,
    required this.amountPaid,
    required this.balance,
    this.proofStatus,
    this.rejectionReason,
  });

  factory ParentInvoice.fromJson(Map<String, dynamic> json) {
    // Extract proof status and rejection reason from the most recent proof
    final proofs = json['payment_proofs'] as List?;
    String? proofStatus;
    String? rejectionReason;
    if (proofs != null && proofs.isNotEmpty) {
      final lastProof = proofs.last as Map<String, dynamic>;
      proofStatus = lastProof['status'] as String?;
      if (proofStatus == 'rejected') {
        final notes = lastProof['notes'] as String? ?? '';
        rejectionReason = notes.startsWith('[REJEITADO] ')
            ? notes.substring('[REJEITADO] '.length)
            : notes.isNotEmpty ? notes : null;
      }
    }
    return ParentInvoice(
      id: json['id']?.toString() ?? '',
      childId: json['child_id']?.toString() ?? '',
      childName: json['child_name'] as String? ?? 'Desconhecido',
      referenceMonth: json['reference_month'] != null
          ? DateTime.tryParse(json['reference_month'] as String) ?? DateTime.now()
          : DateTime.now(),
      totalAmount: (json['gross_total'] as num?)?.toDouble() ??
          (json['total_amount'] as num?)?.toDouble() ?? 0.0,
      status: json['status'] as String? ?? 'pending',
      dueDate: json['due_date'] != null
          ? DateTime.tryParse(json['due_date'] as String)
          : null,
      multicaixaEntity: json['multicaixa_entity'] as String?,
      multicaixaRef: json['multicaixa_ref'] as String?,
      amountPaid: (json['amount_paid'] as num?)?.toDouble() ?? 0.0,
      balance: (json['balance'] as num?)?.toDouble() ?? 0.0,
      proofStatus: proofStatus,
      rejectionReason: rejectionReason,
    );
  }

  String get statusLabel {
    switch (status) {
      case 'paid':
        return 'Pago';
      case 'pending':
        return 'Pendente';
      case 'partially_paid':
        return 'Parcialmente Pago';
      case 'cancelled':
        return 'Cancelado';
      case 'overdue':
        return 'Em Atraso';
      default:
        return status;
    }
  }

  Color get statusColor {
    switch (status) {
      case 'paid':
        return Colors.green;
      case 'overdue':
        return Colors.red;
      case 'partially_paid':
        return Colors.orange;
      case 'cancelled':
        return Colors.grey;
      default:
        return Colors.orange;
    }
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final parentInvoicesProvider =
    FutureProvider.autoDispose<List<ParentInvoice>>((ref) async {
  final api = ref.read(apiClientProvider);
  final data = await api.get('/finance/parent/invoices') as List;
  return data
      .map((e) => ParentInvoice.fromJson(e as Map<String, dynamic>))
      .toList();
});

final _parentCreditProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final api = ref.read(apiClientProvider);
  final data = await api.get('/finance/parent/credits');
  return (data as Map<String, dynamic>?) ?? {};
});

final _parentPaymentRefsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final api = ref.read(apiClientProvider);
  final data = await api.get('/finance/parent/payment-references') as List;
  return data.cast<Map<String, dynamic>>();
});

final _parentReceiptsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final api = ref.read(apiClientProvider);
  final data = await api.get('/finance/parent/receipts') as List;
  return data.cast<Map<String, dynamic>>();
});

final _parentStatementProvider = FutureProvider.autoDispose<Map<String, dynamic>?>((ref) async {
  final api = ref.read(apiClientProvider);
  try {
    final data = await api.get('/finance/parent/statement');
    return data as Map<String, dynamic>?;
  } catch (_) {
    return null;
  }
});

// Fetch guardian profile to check NIF (spec 20.26.2)
final _parentProfileProvider = FutureProvider.autoDispose<Map<String, dynamic>?>((ref) async {
  final api = ref.read(apiClientProvider);
  try {
    final data = await api.get('/guardians/me');
    return data as Map<String, dynamic>?;
  } catch (_) {
    return null;
  }
});

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class ParentInvoicesScreen extends ConsumerStatefulWidget {
  const ParentInvoicesScreen({super.key});

  @override
  ConsumerState<ParentInvoicesScreen> createState() =>
      _ParentInvoicesScreenState();
}

class _ParentInvoicesScreenState extends ConsumerState<ParentInvoicesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  String _statusFilter = 'all';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final invoicesAsync = ref.watch(parentInvoicesProvider);
    final currency = ref.watch(currencyFormatProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Finanças'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Faturas'),
            Tab(text: 'Extrato'),
            Tab(text: 'Recibos'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // ── Tab 0: Faturas ─────────────────────────────────────────────
          Column(
            children: [
              const _NifPromptBanner(),
              _CreditBalanceBanner(currency: currency),
              _ActiveRefsBanner(currency: currency),
              // Filter chips
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
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
                    ],
                  ),
                ),
              ),
              Expanded(
                child: invoicesAsync.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, _) => AppErrorWidget(error: e, onRetry: () => ref.invalidate(parentInvoicesProvider)),
                  data: (invoices) {
                    final filtered = _statusFilter == 'all'
                        ? invoices
                        : invoices.where((i) => i.status == _statusFilter).toList();

                    if (filtered.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.receipt_long, size: 64, color: Theme.of(context).colorScheme.outlineVariant),
                            const SizedBox(height: 16),
                            Text('Nenhuma fatura encontrada',
                                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
                          ],
                        ),
                      );
                    }

                    return RefreshIndicator(
                      onRefresh: () async {
                        ref.invalidate(parentInvoicesProvider);
                        ref.invalidate(_parentCreditProvider);
                      },
                      child: ListView.builder(
                        padding: const EdgeInsets.only(bottom: 32),
                        itemCount: filtered.length,
                        itemBuilder: (context, i) => _InvoiceCard(
                          invoice: filtered[i],
                          currency: currency,
                          onPaymentSubmitted: () => ref.invalidate(parentInvoicesProvider),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),

          // ── Tab 1: Extrato ─────────────────────────────────────────────
          _StatementTab(currency: currency),

          // ── Tab 2: Recibos ─────────────────────────────────────────────
          _ReceiptsTab(currency: currency),

        ],
      ),
    );
  }

  Widget _buildFilterChip(String value, String label) {
    return FilterChip(
      label: Text(label),
      selected: _statusFilter == value,
      showCheckmark: false,
      selectedColor: Theme.of(context).colorScheme.primaryContainer,
      onSelected: (_) => setState(() => _statusFilter = value),
    );
  }
}

// NIF missing prompt (spec 20.26.2)
class _NifPromptBanner extends ConsumerWidget {
  const _NifPromptBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(_parentProfileProvider);
    return profileAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (profile) {
        if (profile == null) return const SizedBox.shrink();
        final nif = profile['nif'] as String?;
        if (nif != null && nif.trim().isNotEmpty) return const SizedBox.shrink();
        return Container(
          margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.orange.withOpacity(0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.orange.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              const Icon(Icons.badge_outlined, color: Colors.orange, size: 20),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('NIF não registado', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Colors.orange)),
                    Text('Para emissão de facturas em seu nome, actualize o seu NIF no perfil.', style: TextStyle(fontSize: 11, color: Colors.orange)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// Active payment references banner
class _ActiveRefsBanner extends ConsumerWidget {
  final NumberFormat currency;
  const _ActiveRefsBanner({required this.currency});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final refsAsync = ref.watch(_parentPaymentRefsProvider);
    return refsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (refs) {
        final active = refs.where((r) => r['status'] == 'active').toList();
        if (active.isEmpty) return const SizedBox.shrink();
        return Container(
          margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF005B9A).withOpacity(0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF005B9A).withOpacity(0.25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.payment, color: Color(0xFF005B9A), size: 16),
                  SizedBox(width: 6),
                  Text('Referências Multicaixa Activas', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: Color(0xFF005B9A))),
                ],
              ),
              const SizedBox(height: 8),
              ...active.map((r) {
                final entity = r['entity'] as String? ?? r['multicaixa_entity'] as String? ?? '—';
                final refNum = r['reference'] as String? ?? r['multicaixa_ref'] as String? ?? '—';
                final amount = (r['amount'] as num?)?.toDouble();
                final expires = r['expires_at'] as String? ?? '';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Expanded(child: Text('Entidade $entity · Ref $refNum', style: const TextStyle(fontSize: 12, fontFamily: 'monospace'))),
                      if (amount != null) Text(currency.format(amount), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      if (expires.isNotEmpty) Text(' · Exp $expires', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                    ],
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }
}

// Credit balance banner shown at top of Faturas tab
class _CreditBalanceBanner extends ConsumerWidget {
  final NumberFormat currency;
  const _CreditBalanceBanner({required this.currency});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final creditAsync = ref.watch(_parentCreditProvider);
    return creditAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (data) {
        final balance = (data['balance'] as num?)?.toDouble() ?? 0;
        if (balance <= 0) return const SizedBox.shrink();
        return Container(
          margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.green.withOpacity(0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.green.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              const Icon(Icons.savings_outlined, color: Colors.green, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Crédito Disponível', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                    Text(currency.format(balance), style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// Statement tab
class _StatementTab extends ConsumerWidget {
  final NumberFormat currency;
  const _StatementTab({required this.currency});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statementAsync = ref.watch(_parentStatementProvider);
    return statementAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => AppErrorWidget(error: e, onRetry: () => ref.invalidate(_parentStatementProvider)),
      data: (statement) {
        if (statement == null) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.receipt_long_outlined, size: 56, color: Colors.grey),
                SizedBox(height: 12),
                Text('Extrato não disponível', style: TextStyle(color: Colors.grey)),
              ],
            ),
          );
        }
        final totalInvoiced = (statement['total_invoiced'] as num?)?.toDouble() ?? 0;
        final totalSettled = (statement['total_settled'] as num?)?.toDouble() ?? 0;
        final balance = (statement['current_balance'] as num?)?.toDouble() ?? 0;
        final creditBalance = (statement['credit_balance'] as num?)?.toDouble() ?? 0;
        final movements = (statement['movements'] as List? ?? []).cast<Map<String, dynamic>>();
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(_parentStatementProvider),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Resumo da Conta', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 10),
                    _summaryRow(context, 'Total Facturado', currency.format(totalInvoiced), Colors.blue),
                    _summaryRow(context, 'Total Pago', currency.format(totalSettled), Colors.green),
                    _summaryRow(context, 'Saldo em Dívida', currency.format(balance), balance > 0 ? Colors.red : Colors.green),
                    if (creditBalance > 0) _summaryRow(context, 'Crédito Disponível', currency.format(creditBalance), Colors.green),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text('Movimentos', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: Colors.grey)),
              const SizedBox(height: 8),
              if (movements.isEmpty)
                const Text('Sem movimentos', style: TextStyle(color: Colors.grey))
              else
                ...movements.map((m) {
                  final type = m['type'] as String? ?? '';
                  final desc = m['description'] as String? ?? type;
                  final date = m['date'] as String? ?? '';
                  double _safeNum(dynamic v) => v == null ? 0 : (v is num ? v.toDouble() : double.tryParse(v.toString()) ?? 0);
                  final debit = _safeNum(m['debit']);
                  final credit = _safeNum(m['credit']);
                  final runningBalance = m['running_balance'] != null ? _safeNum(m['running_balance']) : null;
                  final isDebit = debit > 0;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      border: Border(left: BorderSide(width: 3, color: isDebit ? Colors.red : Colors.green)),
                      color: isDebit ? Colors.red.withOpacity(0.03) : Colors.green.withOpacity(0.03),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(desc, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                              Text(date, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              isDebit ? '+${currency.format(debit)}' : '-${currency.format(credit)}',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: isDebit ? Colors.red : Colors.green),
                            ),
                            if (runningBalance != null)
                              Text('Saldo: ${currency.format(runningBalance)}', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                          ],
                        ),
                      ],
                    ),
                  );
                }),
            ],
          ),
        );
      },
    );
  }

  Widget _summaryRow(BuildContext context, String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 13)),
        ],
      ),
    );
  }
}

void _showReceiptDetail(BuildContext context, Map<String, dynamic> r, NumberFormat currency) {
  final docNum = r['full_document_number'] as String? ?? '—';
  final rawDate = r['invoice_date'] as String? ?? r['system_entry_date'] as String? ?? '';
  String dateLabel = rawDate;
  try { dateLabel = rawDate.isNotEmpty ? rawDate.substring(0, 10) : ''; } catch (_) {}
  final amount = (r['gross_total'] as num?)?.toDouble() ?? 0;
  final customerName = r['customer_name'] as String?;
  final customerNif = r['customer_nif'] as String?;
  final status = r['status'] as String? ?? '';
  showModalBottomSheet(
    context: context,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (_) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.receipt_long_outlined, color: Colors.green, size: 28),
            const SizedBox(width: 10),
            Text(docNum, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, fontFamily: 'monospace')),
            const Spacer(),
            if (status.isNotEmpty) Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
              child: Text(status.toUpperCase(), style: const TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.bold)),
            ),
          ]),
          const Divider(height: 20),
          if (customerName != null) _detailRow('Cliente', customerName),
          if (customerNif != null) _detailRow('NIF', customerNif),
          _detailRow('Data', dateLabel),
          _detailRow('Valor', currency.format(amount)),
        ],
      ),
    ),
  );
}

Widget _detailRow(String label, String value) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 4),
  child: Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
      Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
    ],
  ),
);

// Receipts tab
class _ReceiptsTab extends ConsumerWidget {
  final NumberFormat currency;
  const _ReceiptsTab({required this.currency});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final receiptsAsync = ref.watch(_parentReceiptsProvider);
    return receiptsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => AppErrorWidget(error: e, onRetry: () => ref.invalidate(_parentReceiptsProvider)),
      data: (receipts) {
        if (receipts.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.receipt_outlined, size: 56, color: Colors.grey),
                SizedBox(height: 12),
                Text('Nenhum recibo disponível', style: TextStyle(color: Colors.grey)),
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(_parentReceiptsProvider),
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
            itemCount: receipts.length,
            itemBuilder: (_, i) {
              final r = receipts[i];
              final docNum = r['full_document_number'] as String? ?? r['document_number'] as String? ?? '—';
              final rawDate = r['invoice_date'] as String? ?? r['system_entry_date'] as String? ?? '';
              String dateLabel = rawDate;
              try { dateLabel = rawDate.isNotEmpty ? rawDate.substring(0, 10) : ''; } catch (_) {}
              final amount = (r['gross_total'] as num?)?.toDouble() ?? 0;
              final customerName = r['customer_name'] as String?;
              final status = r['status'] as String? ?? '';
              return Card(
                margin: const EdgeInsets.only(bottom: 6),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(color: Colors.grey.shade200),
                ),
                child: ListTile(
                  dense: true,
                  onTap: () => _showReceiptDetail(context, r, currency),
                  leading: const Icon(Icons.receipt_long_outlined, color: Colors.green),
                  title: Text(docNum, style: const TextStyle(fontWeight: FontWeight.w700, fontFamily: 'monospace', fontSize: 13)),
                  subtitle: Text(customerName != null ? '$customerName · $dateLabel' : dateLabel, style: const TextStyle(fontSize: 11)),
                  trailing: Text(currency.format(amount), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Invoice Card
// ---------------------------------------------------------------------------

class _InvoiceCard extends ConsumerWidget {
  final ParentInvoice invoice;
  final NumberFormat currency;
  final VoidCallback onPaymentSubmitted;

  const _InvoiceCard({
    required this.invoice,
    required this.currency,
    required this.onPaymentSubmitted,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final monthLabel =
        DateFormat('MMMM yyyy', 'pt_PT').format(invoice.referenceMonth);
    final canPay = invoice.status != 'paid' && invoice.status != 'cancelled';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row: child name + status chip
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        invoice.childName,
                        style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        monthLabel,
                        style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                _StatusBadge(
                    label: invoice.statusLabel,
                    color: invoice.statusColor),
              ],
            ),

            const SizedBox(height: 12),

            // Amount row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Valor total',
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant)),
                Text(
                  currency.format(invoice.totalAmount),
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),

            if (invoice.amountPaid > 0 && invoice.status != 'paid') ...[
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Em falta',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.orange)),
                  Text(
                    currency.format(invoice.balance),
                    style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600, color: Colors.orange),
                  ),
                ],
              ),
            ],

            if (invoice.dueDate != null) ...[
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Data limite',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                  Text(
                    DateFormat('dd/MM/yyyy').format(invoice.dueDate!),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: invoice.status == 'overdue'
                          ? Colors.red
                          : null,
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 16),

            // Multicaixa payment section
            if (invoice.multicaixaRef != null &&
                invoice.multicaixaEntity != null) ...[
              Row(
                children: [
                  const Icon(Icons.payment, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Pagar via Multicaixa',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _MulticaixaReceiptBox(
                entidade: invoice.multicaixaEntity!,
                referencia: invoice.multicaixaRef!,
                montante: currency.format(invoice.balance > 0
                    ? invoice.balance
                    : invoice.totalAmount),
              ),
            ] else ...[
              Row(
                children: [
                  Icon(Icons.info_outline,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Referência de pagamento não disponível',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ],

            // Proof status indicator
            if (invoice.proofStatus != null) ...[
              const SizedBox(height: 12),
              _ProofStatusBanner(status: invoice.proofStatus!, rejectionReason: invoice.rejectionReason),
            ],

            // Submit payment button
            if (canPay && invoice.proofStatus != 'pending_review') ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _showPaymentDialog(context, ref),
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: const Text('Enviar Comprovativo de Pagamento'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _showPaymentDialog(BuildContext context, WidgetRef ref) async {
    await showDialog(useRootNavigator: false, 
      context: context,
      builder: (_) => _SubmitPaymentDialog(
        invoice: invoice,
        currency: currency,
        onSubmitted: onPaymentSubmitted,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Proof Status Banner
// ---------------------------------------------------------------------------
class _ProofStatusBanner extends StatelessWidget {
  final String status;
  final String? rejectionReason;
  const _ProofStatusBanner({required this.status, this.rejectionReason});

  @override
  Widget build(BuildContext context) {
    final (color, icon, label) = switch (status) {
      'pending_review' => (Colors.orange, Icons.hourglass_top_outlined, 'Comprovativo em análise'),
      'approved'       => (Colors.green,  Icons.check_circle_outline,    'Comprovativo aprovado'),
      'rejected'       => (Colors.red,    Icons.cancel_outlined,          'Comprovativo rejeitado — envie novo'),
      _                => (Colors.grey,   Icons.info_outline,              status),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600))),
            ],
          ),
          if (status == 'rejected' && rejectionReason != null && rejectionReason!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 26),
              child: Text('Motivo: $rejectionReason', style: TextStyle(color: color, fontSize: 11)),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Submit Payment Dialog
// ---------------------------------------------------------------------------
class _SubmitPaymentDialog extends ConsumerStatefulWidget {
  final ParentInvoice invoice;
  final NumberFormat currency;
  final VoidCallback onSubmitted;

  const _SubmitPaymentDialog({
    required this.invoice,
    required this.currency,
    required this.onSubmitted,
  });

  @override
  ConsumerState<_SubmitPaymentDialog> createState() =>
      _SubmitPaymentDialogState();
}

class _SubmitPaymentDialogState extends ConsumerState<_SubmitPaymentDialog> {
  final _amountCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  PlatformFile? _proofFile;
  String _paymentMethod = 'multicaixa_ref';
  bool _isLoading = false;
  String? _error;

  static const _paymentMethods = {
    'multicaixa_ref': 'Multicaixa / ATM',
    'bank_transfer': 'Transferência Bancária',
    'multicaixa_express': 'Multicaixa Express',
    'other': 'Outro',
  };

  @override
  void initState() {
    super.initState();
    final balance = widget.invoice.balance > 0
        ? widget.invoice.balance
        : widget.invoice.totalAmount;
    _amountCtrl.text = balance.toStringAsFixed(2);
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickProof() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
      withData: true,
    );
    if (result != null && result.files.isNotEmpty) {
      setState(() => _proofFile = result.files.first);
    }
  }

  Future<void> _submit() async {
    final amount = double.tryParse(_amountCtrl.text.replaceAll(',', '.'));
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Valor inválido');
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final api = ref.read(apiClientProvider);

      // 1. Upload proof if provided (optional)
      String? proofUrl;
      if (_proofFile != null && _proofFile!.bytes != null) {
        final uploadResult = await api.uploadBytes(
          '/finance/payment-proof',
          _proofFile!.bytes!,
          _proofFile!.name,
        );
        proofUrl = uploadResult['url'] as String?;
      }

      // 2. Submit payment proof for admin review
      await api.post('/finance/parent/submit-payment', data: {
        'invoice_id': widget.invoice.id,
        'amount': amount,
        'payment_method': _paymentMethod,
        if (proofUrl != null) 'receipt_proof_url': proofUrl,
        if (_notesCtrl.text.trim().isNotEmpty)
          'notes': _notesCtrl.text.trim(),
      });

      widget.onSubmitted();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Comprovativo enviado com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('Enviar Comprovativo'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Invoice info
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.invoice.childName,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text(
                      DateFormat('MMMM yyyy', 'pt_PT')
                          .format(widget.invoice.referenceMonth),
                      style: TextStyle(
                          fontSize: 13,
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Amount
              TextFormField(
                controller: _amountCtrl,
                decoration: const InputDecoration(
                  labelText: 'Valor pago (Kz)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.monetization_on_outlined),
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 12),

              // Payment method
              DropdownButtonFormField<String>(
                value: _paymentMethod,
                decoration: const InputDecoration(
                  labelText: 'Método de pagamento',
                  border: OutlineInputBorder(),
                ),
                items: _paymentMethods.entries
                    .map((e) =>
                        DropdownMenuItem(value: e.key, child: Text(e.value)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _paymentMethod = v);
                },
              ),
              const SizedBox(height: 12),

              // Proof of payment picker
              OutlinedButton.icon(
                onPressed: _pickProof,
                icon: Icon(
                  _proofFile == null
                      ? Icons.camera_alt_outlined
                      : Icons.check_circle,
                  color: _proofFile == null ? null : Colors.green,
                ),
                label: Text(
                  _proofFile == null
                      ? 'Anexar comprovativo (opcional) — imagem ou PDF'
                      : _proofFile!.name,
                  style: TextStyle(
                    color: _proofFile == null ? null : Colors.green,
                    fontWeight:
                        _proofFile != null ? FontWeight.w600 : null,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                  alignment: Alignment.centerLeft,
                  side: BorderSide(
                    color: _proofFile == null
                        ? theme.colorScheme.outline
                        : Colors.green,
                    width: _proofFile == null ? 1 : 1.5,
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Notes
              TextFormField(
                controller: _notesCtrl,
                decoration: const InputDecoration(
                  labelText: 'Observações (opcional)',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),

              if (_error != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(_error!,
                      style: TextStyle(color: Colors.red.shade800)),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _isLoading ? null : _submit,
          child: _isLoading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Text('Enviar'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Multicaixa receipt box
// ---------------------------------------------------------------------------

class _MulticaixaReceiptBox extends StatelessWidget {
  final String entidade;
  final String referencia;
  final String montante;

  const _MulticaixaReceiptBox({
    required this.entidade,
    required this.referencia,
    required this.montante,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const borderColor = Color(0xFF005B9A); // Multicaixa brand blue

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor.withOpacity(0.4), width: 1.5),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        children: [
          // Header
          Row(
            children: [
              const Icon(Icons.atm, color: borderColor, size: 20),
              const SizedBox(width: 8),
              Text(
                'ATM / Multicaixa Express',
                style: theme.textTheme.labelMedium?.copyWith(
                    color: borderColor, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, color: Color(0x33005B9A)),
          const SizedBox(height: 14),
          _ReceiptRow(label: 'Entidade', value: entidade),
          const SizedBox(height: 10),
          _ReceiptRow(label: 'Referência', value: referencia),
          const SizedBox(height: 10),
          _ReceiptRow(label: 'Montante', value: montante, bold: true),
        ],
      ),
    );
  }
}

class _ReceiptRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;

  const _ReceiptRow({
    required this.label,
    required this.value,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant),
        ),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: bold ? FontWeight.bold : FontWeight.w600,
            letterSpacing: bold ? null : 1.4,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Status badge
// ---------------------------------------------------------------------------

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
            color: color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}
