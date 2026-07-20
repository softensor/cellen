import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_client.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/models/child.dart';
import '../../../core/models/invoice.dart';
import '../../../core/providers/currency_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../finance/credit_notes_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Models
// ─────────────────────────────────────────────────────────────────────────────

class FinanceSummary {
  final double totalIncome;
  final double totalExpenses;
  final double netPnl;
  final double outstanding;
  final int outstandingCount;
  final int overdueCount;

  const FinanceSummary({
    required this.totalIncome,
    required this.totalExpenses,
    required this.netPnl,
    required this.outstanding,
    required this.outstandingCount,
    required this.overdueCount,
  });

  factory FinanceSummary.fromJson(Map<String, dynamic> json) {
    final income = (json['total_revenue_month'] as num?)?.toDouble() ?? 0.0;
    final expenses = (json['total_expenses_month'] as num?)?.toDouble() ?? 0.0;
    final pending = (json['pending_invoices_count'] as num?)?.toInt() ?? 0;
    final overdue = (json['overdue_invoices_count'] as num?)?.toInt() ?? 0;
    return FinanceSummary(
      totalIncome: income,
      totalExpenses: expenses,
      netPnl: income - expenses,
      outstanding: (json['total_outstanding'] as num?)?.toDouble() ?? 0.0,
      outstandingCount: pending + overdue,
      overdueCount: overdue,
    );
  }
}

class _Contract {
  final String id;
  final String childId;
  final String? childName;
  final String? guardianId;
  final String? serviceName;
  final double unitPrice;
  final double ivaRate;
  final String billingCycle;
  final int dayOfMonth;
  final String startDate;
  final String? endDate;
  final bool isActive;
  final String status;
  final bool autoInvoice;
  final String? lastInvoicedMonth;
  final String? notes;

  const _Contract({
    required this.id,
    required this.childId,
    this.childName,
    this.guardianId,
    this.serviceName,
    required this.unitPrice,
    required this.ivaRate,
    required this.billingCycle,
    required this.dayOfMonth,
    required this.startDate,
    this.endDate,
    required this.isActive,
    required this.status,
    required this.autoInvoice,
    this.lastInvoicedMonth,
    this.notes,
  });

  factory _Contract.fromJson(Map<String, dynamic> json) {
    return _Contract(
      id: json['id']?.toString() ?? '',
      childId: json['child_id']?.toString() ?? '',
      childName: json['child_name'] as String?,
      guardianId: json['guardian_id']?.toString(),
      serviceName: json['service_name'] as String?,
      unitPrice: (json['unit_price'] as num?)?.toDouble() ?? 0.0,
      ivaRate: (json['iva_rate'] as num?)?.toDouble() ?? 0.0,
      billingCycle: json['billing_cycle'] as String? ?? 'monthly',
      dayOfMonth: (json['day_of_month'] as num?)?.toInt() ?? 1,
      startDate: json['start_date'] as String? ?? '',
      endDate: json['end_date'] as String?,
      isActive: json['is_active'] as bool? ?? true,
      status: json['status'] as String? ?? 'active',
      autoInvoice: json['auto_invoice'] as bool? ?? false,
      lastInvoicedMonth: json['last_invoiced_month'] as String?,
      notes: json['notes'] as String?,
    );
  }

  String get cycleLabel => switch (billingCycle) {
    'monthly' => 'Mensal',
    'quarterly' => 'Trimestral',
    'biannual' => 'Semestral',
    'annual' => 'Anual',
    _ => billingCycle,
  };
}

class _Expense {
  final String id;
  final String description;
  final double amount;
  final DateTime expenseDate;
  final String? categoryId;
  final String? categoryName;
  final String? notes;

  const _Expense({
    required this.id,
    required this.description,
    required this.amount,
    required this.expenseDate,
    this.categoryId,
    this.categoryName,
    this.notes,
  });

  factory _Expense.fromJson(Map<String, dynamic> json) {
    return _Expense(
      id: json['id']?.toString() ?? '',
      description: json['description'] as String? ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      expenseDate: json['expense_date'] != null
          ? DateTime.tryParse(json['expense_date'] as String) ?? DateTime.now()
          : DateTime.now(),
      categoryId: json['category_id']?.toString(),
      categoryName: json['category_name'] as String?,
      notes: json['notes'] as String?,
    );
  }
}

class _ExpenseCategory {
  final String id;
  final String name;
  const _ExpenseCategory({required this.id, required this.name});

  factory _ExpenseCategory.fromJson(Map<String, dynamic> json) =>
      _ExpenseCategory(
        id: json['id']?.toString() ?? '',
        name: json['name'] as String? ?? '',
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Providers
// ─────────────────────────────────────────────────────────────────────────────

final _summaryProvider = FutureProvider.autoDispose<FinanceSummary>((ref) async {
  final api = ref.read(apiClientProvider);
  final data = await api.get('/finance/summary');
  return FinanceSummary.fromJson(data as Map<String, dynamic>);
});

final _allInvoicesProvider = FutureProvider.autoDispose<List<Invoice>>((ref) async {
  final api = ref.read(apiClientProvider);
  final data = await api.get('/finance/invoices', queryParameters: {'limit': '100'}) as List;
  return data.map((e) => Invoice.fromJson(e as Map<String, dynamic>)).toList();
});

final _contractsHubProvider = FutureProvider.autoDispose<List<_Contract>>((ref) async {
  final api = ref.read(apiClientProvider);
  final data = await api.get('/finance/contracts') as List;
  return data.map((e) => _Contract.fromJson(e as Map<String, dynamic>)).toList();
});

final _expensesHubProvider = FutureProvider.autoDispose<List<_Expense>>((ref) async {
  final api = ref.read(apiClientProvider);
  final data = await api.get('/finance/expenses') as List;
  return data.map((e) => _Expense.fromJson(e as Map<String, dynamic>)).toList();
});

final _expenseCatsProvider = FutureProvider.autoDispose<List<_ExpenseCategory>>((ref) async {
  final api = ref.read(apiClientProvider);
  final data = await api.get('/finance/expense-categories') as List;
  return data.map((e) => _ExpenseCategory.fromJson(e as Map<String, dynamic>)).toList();
});

final _childrenHubProvider = FutureProvider.autoDispose<List<Child>>((ref) async {
  final api = ref.read(apiClientProvider);
  final data = await api.get('/children') as List;
  return data.map((e) => Child.fromJson(e as Map<String, dynamic>)).toList();
});

final _schoolYearsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final api = ref.read(apiClientProvider);
  final data = await api.get('/schools/school-years') as List;
  return data.map((e) => e as Map<String, dynamic>).toList();
});

// ─────────────────────────────────────────────────────────────────────────────
// Main Screen
// ─────────────────────────────────────────────────────────────────────────────

class FinanceDashboardScreen extends ConsumerStatefulWidget {
  const FinanceDashboardScreen({super.key});

  @override
  ConsumerState<FinanceDashboardScreen> createState() => _FinanceDashboardScreenState();
}

class _FinanceDashboardScreenState extends ConsumerState<FinanceDashboardScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  // Keys to call methods on tab children
  final _invoicesTabKey = GlobalKey<_InvoicesTabState>();
  final _contractsTabKey = GlobalKey<_ContractsTabState>();
  final _expensesTabKey = GlobalKey<_ExpensesTabState>();

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this);
    _tab.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  void _refreshAll() {
    ref.invalidate(_summaryProvider);
    ref.invalidate(_allInvoicesProvider);
    ref.invalidate(_contractsHubProvider);
    ref.invalidate(_expensesHubProvider);
  }

  Widget? _buildFab() {
    switch (_tab.index) {
      case 1:
        return FloatingActionButton.extended(
          onPressed: () => _invoicesTabKey.currentState?._showCreateInvoice(context),
          icon: const Icon(Icons.add),
          label: const Text('Nova Factura'),
        );
      case 2:
        return FloatingActionButton.extended(
          onPressed: () => _contractsTabKey.currentState?._showCreateContract(context),
          icon: const Icon(Icons.add),
          label: const Text('Novo Contrato'),
        );
      case 3:
        return FloatingActionButton.extended(
          onPressed: () => _expensesTabKey.currentState?._showAddExpense(context),
          icon: const Icon(Icons.add),
          label: const Text('Nova Despesa'),
        );
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Finanças'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
            onPressed: _refreshAll,
          ),
        ],
        bottom: TabBar(
          controller: _tab,
          isScrollable: false,
          tabs: const [
            Tab(icon: Icon(Icons.dashboard_outlined, size: 20), text: 'Geral'),
            Tab(icon: Icon(Icons.receipt_long_outlined, size: 20), text: 'Facturas'),
            Tab(icon: Icon(Icons.description_outlined, size: 20), text: 'Contratos'),
            Tab(icon: Icon(Icons.trending_down_outlined, size: 20), text: 'Despesas'),
          ],
        ),
      ),
      floatingActionButton: _buildFab(),
      body: TabBarView(
        controller: _tab,
        children: [
          _OverviewTab(onNavigate: (i) => _tab.animateTo(i)),
          _InvoicesTab(key: _invoicesTabKey, onRefreshSummary: () => ref.invalidate(_summaryProvider)),
          _ContractsTab(key: _contractsTabKey, onInvoiceGenerated: () {
            ref.invalidate(_allInvoicesProvider);
            ref.invalidate(_summaryProvider);
            _tab.animateTo(1);
          }),
          _ExpensesTab(key: _expensesTabKey),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab 0: Overview
// ─────────────────────────────────────────────────────────────────────────────

class _OverviewTab extends ConsumerWidget {
  final void Function(int tab) onNavigate;
  const _OverviewTab({required this.onNavigate});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(_summaryProvider);
    final invoicesAsync = ref.watch(_allInvoicesProvider);
    final currency = ref.watch(currencyFormatProvider);
    final monthLabel = DateFormat('MMMM yyyy', 'pt_PT').format(DateTime.now());

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(_summaryProvider);
        ref.invalidate(_allInvoicesProvider);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          // Month header
          Row(
            children: [
              const Icon(Icons.calendar_month, size: 16, color: AppTheme.textSecondary),
              const SizedBox(width: 6),
              Text(
                'Resumo de ${monthLabel[0].toUpperCase()}${monthLabel.substring(1)}',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: AppTheme.textSecondary,
                      letterSpacing: 0.3,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // KPI cards
          summaryAsync.when(
            loading: () => const _KpiSkeleton(),
            error: (e, _) => _ErrorCard(message: e.toString(), onRetry: () => ref.invalidate(_summaryProvider)),
            data: (s) => Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _KpiCard(
                        label: 'Receita do Mês',
                        value: currency.format(s.totalIncome),
                        icon: Icons.arrow_circle_down_outlined,
                        color: AppTheme.success,
                        onTap: () => onNavigate(1),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _KpiCard(
                        label: 'Despesas do Mês',
                        value: currency.format(s.totalExpenses),
                        icon: Icons.arrow_circle_up_outlined,
                        color: AppTheme.danger,
                        onTap: () => onNavigate(3),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _KpiCard(
                        label: 'Resultado',
                        value: currency.format(s.netPnl),
                        icon: Icons.account_balance_outlined,
                        color: s.netPnl >= 0 ? AppTheme.success : AppTheme.danger,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _KpiCard(
                        label: 'Por Cobrar',
                        value: currency.format(s.outstanding),
                        sublabel: '${s.outstandingCount} factura(s)',
                        icon: Icons.pending_actions_outlined,
                        color: s.overdueCount > 0 ? AppTheme.danger : Colors.orange,
                        badge: s.overdueCount > 0 ? '${s.overdueCount} em atraso' : null,
                        onTap: () => onNavigate(1),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Quick links
          Text('Ferramentas', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: AppTheme.textSecondary, letterSpacing: 0.5)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _QuickChip(icon: Icons.point_of_sale_outlined, label: 'Recibos', onTap: () => context.go('/admin/finance/receipts')),
              _QuickChip(icon: Icons.credit_score_outlined, label: 'Notas de Crédito', onTap: () => context.go('/admin/finance/credit-notes')),
              _QuickChip(icon: Icons.warning_amber_outlined, label: 'Devedores', onTap: () => context.go('/admin/finance/delinquent')),
              _QuickChip(icon: Icons.download_outlined, label: 'SAF-T AO', onTap: () => context.go('/admin/finance/saft')),
            ],
          ),

          const SizedBox(height: 24),

          // Recent invoices
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Facturas Recentes', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: AppTheme.textSecondary, letterSpacing: 0.5)),
              TextButton(onPressed: () => onNavigate(1), child: const Text('Ver todas')),
            ],
          ),
          const SizedBox(height: 6),

          invoicesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => _ErrorCard(message: e.toString(), onRetry: () => ref.invalidate(_allInvoicesProvider)),
            data: (invoices) {
              if (invoices.isEmpty) {
                return Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.receipt_long_outlined, size: 40, color: Theme.of(context).colorScheme.outlineVariant),
                      const SizedBox(height: 8),
                      Text('Nenhuma factura ainda', style: TextStyle(color: AppTheme.textSecondary)),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () => onNavigate(2),
                        icon: const Icon(Icons.description_outlined, size: 16),
                        label: const Text('Gerir Contratos'),
                      ),
                    ],
                  ),
                );
              }
              return Column(
                children: invoices.take(8).map((inv) => _InvoiceTile(
                  invoice: inv,
                  currency: currency,
                  onRecordPayment: (inv) => showDialog(
                    context: context,
                    builder: (_) => _RecordPaymentDialog(
                      invoice: inv,
                      onSuccess: () {
                        ref.invalidate(_allInvoicesProvider);
                        ref.invalidate(_summaryProvider);
                      },
                    ),
                  ),
                  onVoid: (inv) => showDialog(
                    context: context,
                    builder: (_) => VoidInvoiceDialog(
                      invoiceId: inv.id,
                      onVoided: () {
                        ref.invalidate(_allInvoicesProvider);
                        ref.invalidate(_summaryProvider);
                      },
                    ),
                  ),
                )).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab 1: Facturas
// ─────────────────────────────────────────────────────────────────────────────

class _InvoicesTab extends ConsumerStatefulWidget {
  final VoidCallback onRefreshSummary;
  const _InvoicesTab({super.key, required this.onRefreshSummary});

  @override
  ConsumerState<_InvoicesTab> createState() => _InvoicesTabState();
}

class _InvoicesTabState extends ConsumerState<_InvoicesTab> {
  String _statusFilter = 'all';

  void _refresh() {
    ref.invalidate(_allInvoicesProvider);
    widget.onRefreshSummary();
  }

  @override
  Widget build(BuildContext context) {
    final invoicesAsync = ref.watch(_allInvoicesProvider);
    final currency = ref.watch(currencyFormatProvider);

    return Column(
      children: [
        // Action bar
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _filterChip('all', 'Todas', invoicesAsync.valueOrNull?.length),
                      const SizedBox(width: 6),
                      _filterChip('pending', 'Pendentes', invoicesAsync.valueOrNull?.where((i) => i.status == 'pending').length),
                      const SizedBox(width: 6),
                      _filterChip('overdue', 'Em Atraso', invoicesAsync.valueOrNull?.where((i) => i.status == 'overdue').length),
                      const SizedBox(width: 6),
                      _filterChip('partially_paid', 'Parciais', invoicesAsync.valueOrNull?.where((i) => i.status == 'partially_paid').length),
                      const SizedBox(width: 6),
                      _filterChip('paid', 'Pagas', invoicesAsync.valueOrNull?.where((i) => i.status == 'paid').length),
                      const SizedBox(width: 6),
                      _filterChip('cancelled', 'Anuladas', invoicesAsync.valueOrNull?.where((i) => i.status == 'cancelled' || i.status == 'void').length),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                onPressed: () => _showBulkGenerate(context),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  visualDensity: VisualDensity.compact,
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.auto_awesome, size: 16),
                    SizedBox(width: 4),
                    Text('Gerar em Massa'),
                  ],
                ),
              ),
            ],
          ),
        ),

        Expanded(
          child: invoicesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => _ErrorCard(
              message: e.toString(),
              onRetry: _refresh,
            ),
            data: (invoices) {
              final filtered = _statusFilter == 'all'
                  ? invoices
                  : invoices.where((i) {
                      if (_statusFilter == 'cancelled') {
                        return i.status == 'cancelled' || i.status == 'void';
                      }
                      return i.status == _statusFilter;
                    }).toList();

              if (filtered.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.receipt_long_outlined, size: 56, color: Theme.of(context).colorScheme.outlineVariant),
                      const SizedBox(height: 12),
                      Text('Nenhuma factura', style: TextStyle(color: AppTheme.textSecondary)),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: () => _showCreateInvoice(context),
                        icon: const Icon(Icons.add),
                        label: const Text('Nova Factura'),
                      ),
                    ],
                  ),
                );
              }

              return RefreshIndicator(
                onRefresh: () async => _refresh(),
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 88),
                  itemCount: filtered.length,
                  itemBuilder: (ctx, i) {
                    final inv = filtered[i];
                    return _InvoiceTile(
                      invoice: inv,
                      currency: currency,
                      showDocNumber: true,
                      onRecordPayment: (inv) => showDialog(
                        context: ctx,
                        builder: (_) => _RecordPaymentDialog(
                          invoice: inv,
                          onSuccess: _refresh,
                        ),
                      ),
                      onVoid: (inv) => showDialog(
                        context: ctx,
                        builder: (_) => VoidInvoiceDialog(
                          invoiceId: inv.id,
                          onVoided: _refresh,
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
    );
  }

  Widget _filterChip(String value, String label, int? count) {
    final selected = _statusFilter == value;
    return FilterChip(
      label: Text(count != null && count > 0 ? '$label ($count)' : label),
      selected: selected,
      showCheckmark: false,
      selectedColor: Theme.of(context).colorScheme.primaryContainer,
      onSelected: (_) => setState(() => _statusFilter = value),
    );
  }

  void _showBulkGenerate(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => _BulkGenerateDialog(
        onSuccess: (count, warnings) {
          _refresh();
          _showBulkResult(context, count, warnings);
        },
      ),
    );
  }

  void _showBulkResult(BuildContext context, int count, List<dynamic> warnings) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Row(
          children: [
            Icon(count > 0 ? Icons.check_circle : Icons.info_outline,
                color: count > 0 ? AppTheme.success : Colors.orange),
            const SizedBox(width: 8),
            Text('Resultado da Geração'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$count factura(s) gerada(s) com sucesso.',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            if (warnings.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('${warnings.length} contrato(s) ignorado(s):',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
              const SizedBox(height: 6),
              ...warnings.take(5).map((w) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.warning_amber, size: 14, color: Colors.orange),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            '${w['child_name'] ?? 'Criança'}: ${w['reason'] ?? 'Erro'}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  )),
              if (warnings.length > 5)
                Text('... e ${warnings.length - 5} mais', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
            ],
          ],
        ),
        actions: [
          FilledButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
        ],
      ),
    );
  }

  void _showCreateInvoice(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _CreateInvoiceSheet(
        onCreated: () {
          _refresh();
          Navigator.pop(context);
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab 2: Contratos
// ─────────────────────────────────────────────────────────────────────────────

class _ContractsTab extends ConsumerStatefulWidget {
  final VoidCallback onInvoiceGenerated;
  const _ContractsTab({super.key, required this.onInvoiceGenerated});

  @override
  ConsumerState<_ContractsTab> createState() => _ContractsTabState();
}

class _ContractsTabState extends ConsumerState<_ContractsTab> {
  bool _showInactive = false;

  @override
  Widget build(BuildContext context) {
    final contractsAsync = ref.watch(_contractsHubProvider);
    final currency = ref.watch(currencyFormatProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: Row(
            children: [
              FilterChip(
                label: Text(_showInactive ? 'Todos' : 'Só Activos'),
                selected: !_showInactive,
                showCheckmark: false,
                selectedColor: Theme.of(context).colorScheme.primaryContainer,
                onSelected: (_) => setState(() => _showInactive = !_showInactive),
              ),
              const Spacer(),
              FilledButton.tonal(
                onPressed: () => _showBulkInvoice(context),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  visualDensity: VisualDensity.compact,
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.auto_awesome, size: 16),
                    SizedBox(width: 4),
                    Text('Gerar Todos'),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: contractsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => _ErrorCard(message: e.toString(), onRetry: () => ref.invalidate(_contractsHubProvider)),
            data: (contracts) {
              final displayed = _showInactive
                  ? contracts
                  : contracts.where((c) => c.isActive && c.status == 'active').toList();

              if (displayed.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.description_outlined, size: 56, color: Theme.of(context).colorScheme.outlineVariant),
                      const SizedBox(height: 12),
                      Text('Nenhum contrato activo', style: TextStyle(color: AppTheme.textSecondary)),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: () => _showCreateContract(context),
                        icon: const Icon(Icons.add),
                        label: const Text('Novo Contrato'),
                      ),
                    ],
                  ),
                );
              }

              return RefreshIndicator(
                onRefresh: () async => ref.invalidate(_contractsHubProvider),
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 88),
                  itemCount: displayed.length,
                  itemBuilder: (ctx, i) {
                    final c = displayed[i];
                    return _ContractCard(
                      contract: c,
                      currency: currency,
                      onGenerateInvoice: () => _generateSingleInvoice(ctx, c),
                      onEdit: () => _showEditContract(ctx, c),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _generateSingleInvoice(BuildContext context, _Contract c) async {
    try {
      final api = ref.read(apiClientProvider);
      await api.post('/finance/contracts/${c.id}/generate-invoice');
      widget.onInvoiceGenerated();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Factura gerada para ${c.childName ?? 'criança'}'),
            backgroundColor: AppTheme.success,
            action: SnackBarAction(
              label: 'Ver Facturas',
              textColor: Colors.white,
              onPressed: () {},
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e'), backgroundColor: AppTheme.danger),
        );
      }
    }
  }

  void _showBulkInvoice(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => _BulkGenerateDialog(
        onSuccess: (count, warnings) {
          ref.invalidate(_contractsHubProvider);
          widget.onInvoiceGenerated();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$count factura(s) gerada(s)${warnings.isNotEmpty ? ', ${warnings.length} ignorada(s)' : ''}'),
              backgroundColor: AppTheme.success,
            ),
          );
        },
      ),
    );
  }

  void _showCreateContract(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => _CreateContractDialog(
        onCreated: () => ref.invalidate(_contractsHubProvider),
      ),
    );
  }

  void _showEditContract(BuildContext context, _Contract c) {
    showDialog(
      context: context,
      builder: (_) => _EditContractDialog(
        contract: c,
        onUpdated: () => ref.invalidate(_contractsHubProvider),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab 3: Despesas
// ─────────────────────────────────────────────────────────────────────────────

class _ExpensesTab extends ConsumerStatefulWidget {
  const _ExpensesTab({super.key});

  @override
  ConsumerState<_ExpensesTab> createState() => _ExpensesTabState();
}

class _ExpensesTabState extends ConsumerState<_ExpensesTab> {
  void _showAddExpense(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _AddExpenseSheet(
        onAdded: () {
          ref.invalidate(_expensesHubProvider);
          ref.invalidate(_summaryProvider);
          Navigator.pop(context);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final expensesAsync = ref.watch(_expensesHubProvider);
    final currency = ref.watch(currencyFormatProvider);

    return expensesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorCard(message: e.toString(), onRetry: () => ref.invalidate(_expensesHubProvider)),
        data: (expenses) {
          if (expenses.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.receipt_long_outlined, size: 56, color: Theme.of(context).colorScheme.outlineVariant),
                  const SizedBox(height: 12),
                  Text('Nenhuma despesa registada', style: TextStyle(color: AppTheme.textSecondary)),
                ],
              ),
            );
          }

          // Group by date
          final grouped = <String, List<_Expense>>{};
          for (final e in expenses) {
            final key = DateFormat('dd/MM/yyyy').format(e.expenseDate);
            grouped.putIfAbsent(key, () => []).add(e);
          }
          final sortedKeys = grouped.keys.toList()
            ..sort((a, b) {
              final df = DateFormat('dd/MM/yyyy');
              return df.parse(b).compareTo(df.parse(a));
            });
          final totalMonth = expenses.fold<double>(0, (s, e) => s + e.amount);

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(_expensesHubProvider),
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFDE8E8),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.trending_down, color: AppTheme.danger),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Total de despesas', style: TextStyle(color: AppTheme.danger, fontSize: 12)),
                            Text(currency.format(totalMonth),
                                style: const TextStyle(color: AppTheme.danger, fontWeight: FontWeight.bold, fontSize: 18)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) {
                      final dateKey = sortedKeys[i];
                      final dayList = grouped[dateKey]!;
                      final dayTotal = dayList.fold<double>(0, (s, e) => s + e.amount);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(dateKey, style: Theme.of(ctx).textTheme.labelMedium?.copyWith(
                                    color: AppTheme.primary, fontWeight: FontWeight.bold)),
                                Text(currency.format(dayTotal), style: const TextStyle(color: AppTheme.danger, fontWeight: FontWeight.w600, fontSize: 12)),
                              ],
                            ),
                          ),
                          ...dayList.map((exp) => Card(
                                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                                child: ListTile(
                                  leading: _ExpenseCategoryIcon(category: exp.categoryName ?? exp.categoryId ?? ''),
                                  title: Text(exp.description, style: const TextStyle(fontWeight: FontWeight.w600)),
                                  subtitle: Text(exp.categoryName ?? exp.categoryId ?? '', style: const TextStyle(fontSize: 12)),
                                  trailing: Text(
                                    currency.format(exp.amount),
                                    style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.danger),
                                  ),
                                ),
                              )),
                        ],
                      );
                    },
                    childCount: sortedKeys.length,
                  ),
                ),
                const SliverPadding(padding: EdgeInsets.only(bottom: 88)),
              ],
            ),
          );
        },
      );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared Widgets
// ─────────────────────────────────────────────────────────────────────────────

class _KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final String? sublabel;
  final String? badge;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _KpiCard({
    required this.label,
    required this.value,
    this.sublabel,
    this.badge,
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).colorScheme.outline.withOpacity(0.2)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, color: color, size: 16),
                  ),
                  const Spacer(),
                  if (onTap != null) Icon(Icons.chevron_right, size: 16, color: Theme.of(context).colorScheme.outlineVariant),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                value,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 2),
              Text(label, style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
              if (sublabel != null) Text(sublabel!, style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
              if (badge != null) ...[
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.danger.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(badge!, style: const TextStyle(color: AppTheme.danger, fontSize: 10, fontWeight: FontWeight.w600)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _KpiSkeleton extends StatelessWidget {
  const _KpiSkeleton();
  @override
  Widget build(BuildContext context) {
    return const SizedBox(height: 140, child: Center(child: CircularProgressIndicator()));
  }
}

class _QuickChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _QuickChip({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Icon(icon, size: 16),
      label: Text(label),
      onPressed: onTap,
    );
  }
}

class _InvoiceTile extends StatelessWidget {
  final Invoice invoice;
  final NumberFormat currency;
  final bool showDocNumber;
  final void Function(Invoice) onRecordPayment;
  final void Function(Invoice) onVoid;

  const _InvoiceTile({
    required this.invoice,
    required this.currency,
    this.showDocNumber = false,
    required this.onRecordPayment,
    required this.onVoid,
  });

  @override
  Widget build(BuildContext context) {
    final inv = invoice;
    final canPay = inv.status != 'paid' && inv.status != 'cancelled' && inv.status != 'void';
    final canVoid = inv.status != 'void' && inv.status != 'cancelled';

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: inv.isOverdue
              ? AppTheme.danger.withOpacity(0.3)
              : Theme.of(context).colorScheme.outline.withOpacity(0.15),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: canPay ? () => onRecordPayment(inv) : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
          child: Row(
            children: [
              // Status indicator stripe
              Container(
                width: 3,
                height: 44,
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  color: _statusColor(inv.status),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            inv.childName ?? 'Criança',
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                          ),
                        ),
                        _StatusBadge(status: inv.status, label: inv.statusLabel),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (showDocNumber && inv.fullDocumentNumber != null) ...[
                          Text(
                            inv.fullDocumentNumber!,
                            style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary, fontFamily: 'monospace'),
                          ),
                          const Text(' · ', style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                        ],
                        Text(
                          DateFormat('MMMM yyyy', 'pt_PT').format(inv.referenceMonth),
                          style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                        ),
                        if (inv.dueDate != null) ...[
                          const Text(' · ', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                          Text(
                            'Vence ${DateFormat('dd/MM').format(inv.dueDate!)}',
                            style: TextStyle(
                              fontSize: 11,
                              color: inv.isOverdue ? AppTheme.danger : AppTheme.textSecondary,
                              fontWeight: inv.isOverdue ? FontWeight.w600 : FontWeight.normal,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (inv.amountPaid > 0 && inv.status == 'partially_paid')
                      Text(
                        'Pago: ${currency.format(inv.amountPaid)} | Saldo: ${currency.format(inv.balance)}',
                        style: const TextStyle(fontSize: 11, color: Colors.orange),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    currency.format(inv.totalAmount),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, size: 18),
                    padding: EdgeInsets.zero,
                    itemBuilder: (_) => [
                      if (canPay)
                        const PopupMenuItem(
                          value: 'pay',
                          child: Row(children: [Icon(Icons.payments_outlined, size: 18, color: AppTheme.success), SizedBox(width: 8), Text('Registar Pagamento')]),
                        ),
                      if (canVoid)
                        const PopupMenuItem(
                          value: 'void',
                          child: Row(children: [Icon(Icons.cancel_outlined, size: 18, color: AppTheme.danger), SizedBox(width: 8), Text('Anular')]),
                        ),
                    ],
                    onSelected: (action) {
                      if (action == 'pay') onRecordPayment(inv);
                      if (action == 'void') onVoid(inv);
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _statusColor(String status) {
    return switch (status) {
      'paid' => AppTheme.success,
      'overdue' => AppTheme.danger,
      'partially_paid' => Colors.orange,
      'cancelled' || 'void' => Colors.grey,
      _ => AppTheme.primary,
    };
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  final String label;
  const _StatusBadge({required this.status, required this.label});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'paid' => AppTheme.success,
      'overdue' => AppTheme.danger,
      'partially_paid' => Colors.orange,
      'cancelled' || 'void' => Colors.grey,
      _ => AppTheme.primary,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700)),
    );
  }
}

class _ContractCard extends StatelessWidget {
  final _Contract contract;
  final NumberFormat currency;
  final VoidCallback onGenerateInvoice;
  final VoidCallback onEdit;

  const _ContractCard({
    required this.contract,
    required this.currency,
    required this.onGenerateInvoice,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final c = contract;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: c.isActive && c.status == 'active'
              ? AppTheme.primary.withOpacity(0.2)
              : Theme.of(context).colorScheme.outline.withOpacity(0.15),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    c.childName ?? 'Criança',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ),
                _ContractStatusBadge(status: c.status, isActive: c.isActive),
                const SizedBox(width: 6),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, size: 18),
                  padding: EdgeInsets.zero,
                  itemBuilder: (_) => [
                    if (c.isActive && c.status == 'active')
                      const PopupMenuItem(
                        value: 'generate',
                        child: Row(children: [Icon(Icons.receipt_long, size: 18, color: AppTheme.primary), SizedBox(width: 8), Text('Gerar Factura')]),
                      ),
                    const PopupMenuItem(
                      value: 'edit',
                      child: Row(children: [Icon(Icons.edit_outlined, size: 18), SizedBox(width: 8), Text('Editar')]),
                    ),
                  ],
                  onSelected: (action) {
                    if (action == 'generate') onGenerateInvoice();
                    if (action == 'edit') onEdit();
                  },
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              c.serviceName ?? 'Mensalidade',
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  currency.format(c.unitPrice),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                if (c.ivaRate > 0)
                  Text(' +IVA ${c.ivaRate.toStringAsFixed(0)}%',
                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE0F2FE),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(c.cycleLabel,
                      style: const TextStyle(color: Color(0xFF0369A1), fontSize: 11, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.calendar_today_outlined, size: 12, color: AppTheme.textSecondary),
                const SizedBox(width: 4),
                Text('Desde ${c.startDate}', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                if (c.lastInvoicedMonth != null) ...[
                  const Text(' · ', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                  Text('Ult. factura: ${c.lastInvoicedMonth}',
                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                ],
                const Spacer(),
                if (c.isActive && c.status == 'active')
                  TextButton.icon(
                    onPressed: onGenerateInvoice,
                    icon: const Icon(Icons.receipt_long, size: 14),
                    label: const Text('Gerar Factura', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ContractStatusBadge extends StatelessWidget {
  final String status;
  final bool isActive;
  const _ContractStatusBadge({required this.status, required this.isActive});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'active' when isActive => ('Activo', AppTheme.success),
      'suspended' => ('Suspenso', Colors.orange),
      'terminated' => ('Terminado', Colors.grey),
      _ => ('Inactivo', Colors.grey),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700)),
    );
  }
}

class _ExpenseCategoryIcon extends StatelessWidget {
  final String category;
  const _ExpenseCategoryIcon({required this.category});

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (category) {
      'salary' => (Icons.people, Colors.blue),
      'utilities' => (Icons.bolt, Colors.orange),
      'food' => (Icons.restaurant, Colors.green),
      'supplies' => (Icons.inventory, Colors.purple),
      'maintenance' => (Icons.build, Colors.brown),
      _ => (Icons.receipt, Colors.grey),
    };
    return CircleAvatar(
      radius: 18,
      backgroundColor: color.withOpacity(0.15),
      child: Icon(icon, color: color, size: 18),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorCard({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppTheme.danger),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.textSecondary)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar Novamente'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Dialogs & Sheets
// ─────────────────────────────────────────────────────────────────────────────

// Record Payment Dialog
class _RecordPaymentDialog extends ConsumerStatefulWidget {
  final Invoice invoice;
  final VoidCallback onSuccess;

  const _RecordPaymentDialog({required this.invoice, required this.onSuccess});

  @override
  ConsumerState<_RecordPaymentDialog> createState() => _RecordPaymentDialogState();
}

class _RecordPaymentDialogState extends ConsumerState<_RecordPaymentDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountCtrl;
  final _notesCtrl = TextEditingController();
  DateTime _paymentDate = DateTime.now();
  String _paymentMethod = 'multicaixa_express';
  PlatformFile? _proofFile;
  bool _isLoading = false;
  String? _error;

  static const _methods = {
    'multicaixa_express': 'Multicaixa Express',
    'bank_transfer': 'Transferência Bancária',
    'cash': 'Numerário',
    'cheque': 'Cheque',
  };

  @override
  void initState() {
    super.initState();
    _amountCtrl = TextEditingController(text: widget.invoice.balance > 0
        ? widget.invoice.balance.toStringAsFixed(2)
        : widget.invoice.totalAmount.toStringAsFixed(2));
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

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _paymentDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) setState(() => _paymentDate = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final employeeId = ref.read(authProvider).employeeId;
    if (employeeId == null) {
      setState(() => _error = 'Utilizador não tem registo de funcionário associado');
      return;
    }
    if (widget.invoice.billingGuardianId == null) {
      setState(() => _error = 'Factura sem encarregado de educação associado');
      return;
    }

    setState(() { _isLoading = true; _error = null; });

    try {
      final api = ref.read(apiClientProvider);
      String? proofUrl;

      if (_proofFile != null && _proofFile!.bytes != null) {
        final result = await api.uploadBytes(
          '/finance/payment-proof',
          _proofFile!.bytes!,
          _proofFile!.name,
        ) as Map<String, dynamic>;
        proofUrl = result['url'] as String?;
      }

      final amount = double.tryParse(_amountCtrl.text) ?? 0.0;
      final dateStr = '${_paymentDate.year.toString().padLeft(4, '0')}-${_paymentDate.month.toString().padLeft(2, '0')}-${_paymentDate.day.toString().padLeft(2, '0')}';

      await api.post('/finance/payments', data: {
        'billing_guardian_id': widget.invoice.billingGuardianId,
        'target_invoice_ids': [widget.invoice.id],
        'amount': amount,
        'payment_date': dateStr,
        'payment_method': _paymentMethod,
        'received_by': employeeId,
        if (proofUrl != null) 'receipt_proof_url': proofUrl,
        if (_notesCtrl.text.trim().isNotEmpty) 'notes': _notesCtrl.text.trim(),
      });

      widget.onSuccess();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = ref.watch(currencyFormatProvider);
    final inv = widget.invoice;
    return AlertDialog(
      title: const Text('Registar Pagamento'),
      content: SizedBox(
        width: double.maxFinite,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Invoice info banner
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(inv.childName ?? 'Criança', style: const TextStyle(fontWeight: FontWeight.w700)),
                      if (inv.fullDocumentNumber != null)
                        Text(inv.fullDocumentNumber!, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Total: ${currency.format(inv.totalAmount)}', style: const TextStyle(fontSize: 12)),
                          if (inv.amountPaid > 0)
                            Text('Já pago: ${currency.format(inv.amountPaid)}',
                                style: const TextStyle(fontSize: 12, color: AppTheme.success)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Valor a Pagar (${currency.currencySymbol}) *',
                    prefixIcon: const Icon(Icons.monetization_on_outlined),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Obrigatório';
                    final d = double.tryParse(v);
                    if (d == null || d <= 0) return 'Valor inválido';
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
                    child: Text(DateFormat('dd/MM/yyyy').format(_paymentDate)),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _paymentMethod,
                  decoration: const InputDecoration(
                    labelText: 'Método de Pagamento *',
                    prefixIcon: Icon(Icons.payment),
                  ),
                  items: _methods.entries
                      .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                      .toList(),
                  onChanged: (v) => setState(() => _paymentMethod = v!),
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
                // Optional proof upload
                InkWell(
                  onTap: _isLoading ? null : _pickProof,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: _proofFile != null
                            ? AppTheme.primary
                            : Theme.of(context).colorScheme.outline.withOpacity(0.4),
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _proofFile == null ? Icons.attach_file : Icons.check_circle_outline,
                          color: _proofFile == null ? AppTheme.textSecondary : AppTheme.primary,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _proofFile == null ? 'Anexar comprovativo (opcional)' : _proofFile!.name,
                            style: TextStyle(
                              color: _proofFile == null ? AppTheme.textSecondary : AppTheme.primary,
                              fontSize: 13,
                              fontWeight: _proofFile != null ? FontWeight.w600 : FontWeight.normal,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFDE8E8),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: AppTheme.danger, size: 16),
                        const SizedBox(width: 6),
                        Expanded(child: Text(_error!, style: const TextStyle(color: AppTheme.danger, fontSize: 12))),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _isLoading ? null : () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: _isLoading ? null : _submit,
          child: _isLoading
              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Confirmar Pagamento'),
        ),
      ],
    );
  }
}

// Bulk Generate Dialog
class _BulkGenerateDialog extends ConsumerStatefulWidget {
  final void Function(int count, List<dynamic> warnings) onSuccess;
  const _BulkGenerateDialog({required this.onSuccess});

  @override
  ConsumerState<_BulkGenerateDialog> createState() => _BulkGenerateDialogState();
}

class _BulkGenerateDialogState extends ConsumerState<_BulkGenerateDialog> {
  DateTime _referenceMonth = DateTime.now();
  DateTime? _dueDate;
  String? _schoolYearId;
  bool _isLoading = false;
  String? _error;

  Future<void> _pickMonth() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _referenceMonth,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      helpText: 'Seleccionar mês de referência',
    );
    if (picked != null) setState(() => _referenceMonth = DateTime(picked.year, picked.month, 1));
  }

  Future<void> _pickDueDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? DateTime.now().add(const Duration(days: 15)),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) setState(() => _dueDate = picked);
  }

  Future<void> _submit() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final api = ref.read(apiClientProvider);
      final refStr = '${_referenceMonth.year.toString().padLeft(4, '0')}-${_referenceMonth.month.toString().padLeft(2, '0')}-01';
      final body = <String, dynamic>{'reference_month': refStr};
      if (_schoolYearId != null) body['school_year_id'] = _schoolYearId;
      if (_dueDate != null) {
        body['due_date'] = '${_dueDate!.year.toString().padLeft(4, '0')}-${_dueDate!.month.toString().padLeft(2, '0')}-${_dueDate!.day.toString().padLeft(2, '0')}';
      }

      final response = await api.post('/finance/invoices/bulk', data: body);
      final count = (response is Map) ? (response['created'] as int? ?? 0) : 0;
      final warnings = (response is Map) ? (response['warnings'] as List? ?? []) : [];

      if (mounted) Navigator.pop(context);
      widget.onSuccess(count, warnings);
    } catch (e) {
      setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final yearsAsync = ref.watch(_schoolYearsProvider);
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.auto_awesome, color: AppTheme.primary),
          SizedBox(width: 8),
          Text('Gerar Facturas em Massa'),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.primaryLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Gera facturas para todos os contratos activos com facturação automática activada.',
                  style: TextStyle(fontSize: 12, color: AppTheme.primary),
                ),
              ),
              const SizedBox(height: 14),
              // School year (optional)
              yearsAsync.when(
                loading: () => const LinearProgressIndicator(),
                error: (_, __) => const SizedBox.shrink(),
                data: (years) => years.isEmpty
                    ? const SizedBox.shrink()
                    : DropdownButtonFormField<String>(
                        value: _schoolYearId,
                        decoration: const InputDecoration(
                          labelText: 'Ano Lectivo (opcional)',
                          prefixIcon: Icon(Icons.school),
                          helperText: 'Para resolução de preços',
                        ),
                        items: [
                          const DropdownMenuItem(value: null, child: Text('Nenhum')),
                          ...years.map((y) => DropdownMenuItem(
                                value: y['id']?.toString(),
                                child: Text(y['year_label'] as String? ?? ''),
                              )),
                        ],
                        onChanged: (v) => setState(() => _schoolYearId = v),
                      ),
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: _pickMonth,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Mês de Referência *',
                    prefixIcon: Icon(Icons.date_range),
                  ),
                  child: Text(DateFormat('MMMM yyyy', 'pt_PT').format(_referenceMonth)),
                ),
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: _pickDueDate,
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'Data Limite de Pagamento',
                    prefixIcon: const Icon(Icons.event_available),
                    suffixIcon: _dueDate != null
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () => setState(() => _dueDate = null),
                          )
                        : null,
                  ),
                  child: Text(
                    _dueDate == null ? 'Não definida' : DateFormat('dd/MM/yyyy').format(_dueDate!),
                    style: TextStyle(color: _dueDate == null ? AppTheme.textSecondary : null),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: const Color(0xFFFDE8E8), borderRadius: BorderRadius.circular(8)),
                  child: Text(_error!, style: const TextStyle(color: AppTheme.danger, fontSize: 12)),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _isLoading ? null : () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: _isLoading ? null : _submit,
          child: _isLoading
              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Gerar Facturas'),
        ),
      ],
    );
  }
}

// Create Invoice Sheet
class _CreateInvoiceSheet extends ConsumerStatefulWidget {
  final VoidCallback onCreated;
  const _CreateInvoiceSheet({required this.onCreated});

  @override
  ConsumerState<_CreateInvoiceSheet> createState() => _CreateInvoiceSheetState();
}

class _CreateInvoiceSheetState extends ConsumerState<_CreateInvoiceSheet> {
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
    setState(() { _isLoading = true; _error = null; });
    try {
      final api = ref.read(apiClientProvider);
      final tuition = double.tryParse(_tuitionCtrl.text) ?? 0.0;
      final otherFees = double.tryParse(_otherFeesCtrl.text) ?? 0.0;
      final lines = <Map<String, dynamic>>[
        {'description': 'Mensalidade', 'quantity': 1, 'unit_price': tuition, 'iva_rate': 0},
        if (otherFees > 0) {'description': 'Outras taxas', 'quantity': 1, 'unit_price': otherFees, 'iva_rate': 0},
      ];
      final refStr = '${_referenceMonth.year.toString().padLeft(4, '0')}-${_referenceMonth.month.toString().padLeft(2, '0')}-01';
      final body = <String, dynamic>{
        'document_type': 'FT',
        'child_id': _selectedChildId,
        'reference_month': refStr,
        'lines': lines,
        if (_descCtrl.text.trim().isNotEmpty) 'description': _descCtrl.text.trim(),
        if (_dueDate != null) 'due_date': '${_dueDate!.year.toString().padLeft(4, '0')}-${_dueDate!.month.toString().padLeft(2, '0')}-${_dueDate!.day.toString().padLeft(2, '0')}',
      };
      await api.post('/finance/invoices', data: body);
      widget.onCreated();
    } catch (e) {
      setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final childrenAsync = ref.watch(_childrenHubProvider);
    final currency = ref.watch(currencyFormatProvider);

    return Padding(
      padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: MediaQuery.of(context).viewInsets.bottom + 24),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Nova Factura', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            childrenAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('Erro ao carregar crianças: $e', style: const TextStyle(color: AppTheme.danger)),
              data: (children) => DropdownButtonFormField<String>(
                value: _selectedChildId,
                decoration: const InputDecoration(labelText: 'Criança *', prefixIcon: Icon(Icons.child_care)),
                isExpanded: true,
                items: children.map((c) => DropdownMenuItem(value: c.id, child: Text(c.fullName))).toList(),
                onChanged: (v) => setState(() => _selectedChildId = v),
                validator: (v) => v == null ? 'Seleccione uma criança' : null,
              ),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _referenceMonth,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2035),
                  helpText: 'Mês de referência',
                );
                if (picked != null) setState(() => _referenceMonth = DateTime(picked.year, picked.month, 1));
              },
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'Mês de Referência *', prefixIcon: Icon(Icons.date_range)),
                child: Text(DateFormat('MMMM yyyy', 'pt_PT').format(_referenceMonth)),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _tuitionCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'Mensalidade (${currency.currencySymbol}) *', prefixIcon: const Icon(Icons.monetization_on_outlined)),
              validator: (v) => v == null || v.trim().isEmpty ? 'Obrigatório' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _otherFeesCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'Outras taxas (${currency.currencySymbol})', prefixIcon: const Icon(Icons.add_circle_outline)),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _dueDate ?? DateTime.now().add(const Duration(days: 15)),
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2035),
                );
                if (picked != null) setState(() => _dueDate = picked);
              },
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Data Limite (opcional)',
                  prefixIcon: const Icon(Icons.event_available),
                  suffixIcon: _dueDate != null
                      ? IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () => setState(() => _dueDate = null))
                      : null,
                ),
                child: Text(
                  _dueDate == null ? 'Não definida' : DateFormat('dd/MM/yyyy').format(_dueDate!),
                  style: TextStyle(color: _dueDate == null ? AppTheme.textSecondary : null),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _descCtrl,
              decoration: const InputDecoration(labelText: 'Descrição (opcional)', prefixIcon: Icon(Icons.notes)),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: const Color(0xFFFDE8E8), borderRadius: BorderRadius.circular(8)),
                child: Text(_error!, style: const TextStyle(color: AppTheme.danger, fontSize: 12)),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _isLoading ? null : _submit,
              child: _isLoading
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Criar Factura'),
            ),
          ],
        ),
      ),
    );
  }
}

// Create Contract Dialog
class _CreateContractDialog extends ConsumerStatefulWidget {
  final VoidCallback onCreated;
  const _CreateContractDialog({required this.onCreated});

  @override
  ConsumerState<_CreateContractDialog> createState() => _CreateContractDialogState();
}

class _CreateContractDialogState extends ConsumerState<_CreateContractDialog> {
  final _formKey = GlobalKey<FormState>();
  final _serviceCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  String? _childId;
  double _ivaRate = 0.0;
  String _billingCycle = 'monthly';
  DateTime _startDate = DateTime.now();
  bool _autoInvoice = true;
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _serviceCtrl.dispose();
    _amountCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_childId == null) {
      setState(() => _error = 'Seleccione uma criança');
      return;
    }
    setState(() { _isLoading = true; _error = null; });
    try {
      final api = ref.read(apiClientProvider);
      final startStr = '${_startDate.year.toString().padLeft(4, '0')}-${_startDate.month.toString().padLeft(2, '0')}-${_startDate.day.toString().padLeft(2, '0')}';
      await api.post('/finance/contracts', data: {
        'child_id': _childId,
        'service_name': _serviceCtrl.text.trim(),
        'unit_price': double.tryParse(_amountCtrl.text) ?? 0.0,
        'iva_rate': _ivaRate,
        'billing_cycle': _billingCycle,
        'start_date': startStr,
        'auto_invoice': _autoInvoice,
        if (_notesCtrl.text.trim().isNotEmpty) 'notes': _notesCtrl.text.trim(),
      });
      widget.onCreated();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final childrenAsync = ref.watch(_childrenHubProvider);
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
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Text('Erro: $e'),
                  data: (children) => DropdownButtonFormField<String>(
                    value: _childId,
                    decoration: const InputDecoration(labelText: 'Criança *', prefixIcon: Icon(Icons.child_care)),
                    isExpanded: true,
                    items: children.map((c) => DropdownMenuItem(value: c.id, child: Text(c.fullName))).toList(),
                    onChanged: (v) => setState(() => _childId = v),
                    validator: (v) => v == null ? 'Seleccione uma criança' : null,
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _serviceCtrl,
                  decoration: const InputDecoration(labelText: 'Descrição do Serviço *', prefixIcon: Icon(Icons.work_outline)),
                  validator: (v) => v == null || v.trim().isEmpty ? 'Obrigatório' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Valor (Kz) *', prefixIcon: Icon(Icons.monetization_on_outlined)),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Obrigatório';
                    if (double.tryParse(v) == null) return 'Valor inválido';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<double>(
                  value: _ivaRate,
                  decoration: const InputDecoration(labelText: 'IVA', prefixIcon: Icon(Icons.percent)),
                  items: const [
                    DropdownMenuItem(value: 0.0, child: Text('0% (Isento)')),
                    DropdownMenuItem(value: 14.0, child: Text('14%')),
                  ],
                  onChanged: (v) => setState(() => _ivaRate = v ?? 0.0),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _billingCycle,
                  decoration: const InputDecoration(labelText: 'Ciclo de Facturação', prefixIcon: Icon(Icons.repeat)),
                  items: const [
                    DropdownMenuItem(value: 'monthly', child: Text('Mensal')),
                    DropdownMenuItem(value: 'quarterly', child: Text('Trimestral')),
                    DropdownMenuItem(value: 'biannual', child: Text('Semestral')),
                    DropdownMenuItem(value: 'annual', child: Text('Anual')),
                  ],
                  onChanged: (v) => setState(() => _billingCycle = v ?? 'monthly'),
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _startDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2030),
                    );
                    if (picked != null) setState(() => _startDate = picked);
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'Data de Início', prefixIcon: Icon(Icons.calendar_today)),
                    child: Text(DateFormat('dd/MM/yyyy').format(_startDate)),
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  title: const Text('Facturação automática'),
                  subtitle: const Text('Incluir nas gerações em massa', style: TextStyle(fontSize: 12)),
                  value: _autoInvoice,
                  onChanged: (v) => setState(() => _autoInvoice = v),
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _notesCtrl,
                  decoration: const InputDecoration(labelText: 'Notas (opcional)', prefixIcon: Icon(Icons.notes)),
                  maxLines: 2,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: const Color(0xFFFDE8E8), borderRadius: BorderRadius.circular(8)),
                    child: Text(_error!, style: const TextStyle(color: AppTheme.danger, fontSize: 12)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        FilledButton(
          onPressed: _isLoading ? null : _submit,
          child: _isLoading
              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Criar Contrato'),
        ),
      ],
    );
  }
}

// Edit Contract Dialog
class _EditContractDialog extends ConsumerStatefulWidget {
  final _Contract contract;
  final VoidCallback onUpdated;
  const _EditContractDialog({required this.contract, required this.onUpdated});

  @override
  ConsumerState<_EditContractDialog> createState() => _EditContractDialogState();
}

class _EditContractDialogState extends ConsumerState<_EditContractDialog> {
  late final TextEditingController _amountCtrl;
  late final TextEditingController _serviceCtrl;
  late String _status;
  bool _autoInvoice = true;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _amountCtrl = TextEditingController(text: widget.contract.unitPrice.toStringAsFixed(2));
    _serviceCtrl = TextEditingController(text: widget.contract.serviceName ?? '');
    _status = widget.contract.status;
    _autoInvoice = widget.contract.autoInvoice;
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _serviceCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final api = ref.read(apiClientProvider);
      await api.patch('/finance/contracts/${widget.contract.id}', data: {
        'service_name': _serviceCtrl.text.trim(),
        'unit_price': double.tryParse(_amountCtrl.text) ?? widget.contract.unitPrice,
        'status': _status,
        'auto_invoice': _autoInvoice,
      });
      widget.onUpdated();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Editar Contrato — ${widget.contract.childName ?? 'Criança'}'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _serviceCtrl,
              decoration: const InputDecoration(labelText: 'Descrição do Serviço'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Valor (Kz)', prefixIcon: Icon(Icons.monetization_on_outlined)),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _status,
              decoration: const InputDecoration(labelText: 'Estado'),
              items: const [
                DropdownMenuItem(value: 'active', child: Text('Activo')),
                DropdownMenuItem(value: 'suspended', child: Text('Suspenso')),
                DropdownMenuItem(value: 'terminated', child: Text('Terminado')),
              ],
              onChanged: (v) => setState(() => _status = v ?? 'active'),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              title: const Text('Facturação automática'),
              value: _autoInvoice,
              onChanged: (v) => setState(() => _autoInvoice = v),
              contentPadding: EdgeInsets.zero,
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: const Color(0xFFFDE8E8), borderRadius: BorderRadius.circular(8)),
                child: Text(_error!, style: const TextStyle(color: AppTheme.danger, fontSize: 12)),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        FilledButton(
          onPressed: _isLoading ? null : _submit,
          child: _isLoading
              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Guardar'),
        ),
      ],
    );
  }
}

// Add Expense Sheet
class _AddExpenseSheet extends ConsumerStatefulWidget {
  final VoidCallback onAdded;
  const _AddExpenseSheet({required this.onAdded});

  @override
  ConsumerState<_AddExpenseSheet> createState() => _AddExpenseSheetState();
}

class _AddExpenseSheetState extends ConsumerState<_AddExpenseSheet> {
  final _formKey = GlobalKey<FormState>();
  final _descCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  String? _categoryId;
  DateTime _expenseDate = DateTime.now();
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _descCtrl.dispose();
    _amountCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_categoryId == null) {
      setState(() => _error = 'Seleccione uma categoria');
      return;
    }
    setState(() { _isLoading = true; _error = null; });
    try {
      final api = ref.read(apiClientProvider);
      final dateStr = '${_expenseDate.year.toString().padLeft(4, '0')}-${_expenseDate.month.toString().padLeft(2, '0')}-${_expenseDate.day.toString().padLeft(2, '0')}';
      await api.post('/finance/expenses', data: {
        'description': _descCtrl.text.trim(),
        'amount': double.tryParse(_amountCtrl.text) ?? 0.0,
        'category_id': _categoryId,
        'expense_date': dateStr,
        if (_notesCtrl.text.trim().isNotEmpty) 'notes': _notesCtrl.text.trim(),
      });
      widget.onAdded();
    } catch (e) {
      setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final catsAsync = ref.watch(_expenseCatsProvider);
    final currency = ref.watch(currencyFormatProvider);

    return Padding(
      padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: MediaQuery.of(context).viewInsets.bottom + 24),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Nova Despesa', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            catsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('Erro ao carregar categorias: $e', style: const TextStyle(color: AppTheme.danger)),
              data: (cats) => DropdownButtonFormField<String>(
                value: _categoryId,
                decoration: const InputDecoration(labelText: 'Categoria *', prefixIcon: Icon(Icons.category_outlined)),
                isExpanded: true,
                items: cats.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))).toList(),
                onChanged: (v) => setState(() => _categoryId = v),
                validator: (v) => v == null ? 'Seleccione uma categoria' : null,
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _descCtrl,
              decoration: const InputDecoration(labelText: 'Descrição *', prefixIcon: Icon(Icons.notes)),
              validator: (v) => v == null || v.trim().isEmpty ? 'Obrigatório' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Valor (${currency.currencySymbol}) *',
                prefixIcon: const Icon(Icons.monetization_on_outlined),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Obrigatório';
                if (double.tryParse(v) == null) return 'Valor inválido';
                return null;
              },
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _expenseDate,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now().add(const Duration(days: 1)),
                );
                if (picked != null) setState(() => _expenseDate = picked);
              },
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'Data', prefixIcon: Icon(Icons.calendar_today)),
                child: Text(DateFormat('dd/MM/yyyy').format(_expenseDate)),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notesCtrl,
              decoration: const InputDecoration(labelText: 'Notas (opcional)', prefixIcon: Icon(Icons.edit_note)),
              maxLines: 2,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: const Color(0xFFFDE8E8), borderRadius: BorderRadius.circular(8)),
                child: Text(_error!, style: const TextStyle(color: AppTheme.danger, fontSize: 12)),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _isLoading ? null : _submit,
              child: _isLoading
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Registar Despesa'),
            ),
          ],
        ),
      ),
    );
  }
}
