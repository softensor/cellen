import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_client.dart';
import '../../../core/providers/currency_provider.dart';
import '../../../core/widgets/app_error_widget.dart';
import 'fee_automation_common.dart';

final _dashboardProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final data =
      await ref.read(apiClientProvider).get('/billing/dashboard') as Map;
  return Map<String, dynamic>.from(data);
});

const _bucketLabels = <String, String>{
  'current': 'Em dia',
  'bucket_0_30': '0–30 dias',
  'bucket_31_60': '31–60 dias',
  'bucket_61_90': '61–90 dias',
  'bucket_90_plus': '+90 dias',
};

String _debtRoute({bool overdue = false, String? bucket, String? service}) {
  final params = <String, String>{
    if (overdue) 'overdue': '1',
    if (bucket != null) 'bucket': bucket,
    if (service != null) 'service': service,
  };
  final query = Uri(queryParameters: params).query;
  return '/admin/finance/debt-control${query.isEmpty ? '' : '?$query'}';
}

/// The finance home: one answer for debts, billing and collections, from
/// whichever engine owns the school. The FinReg is invisible here; its
/// documents drive the numbers without ever being exposed as a destination.
///
/// Every number is a door: the KPIs, the aging chips and the service rows
/// open the filtered documents behind them, so nobody has to leave a figure
/// "frozen" and hunt for the matching list somewhere else.
class FinanceHomeScreen extends ConsumerWidget {
  const FinanceHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboard = ref.watch(_dashboardProvider);
    final currency = ref.watch(currencyFormatProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Painel Financeiro'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(_dashboardProvider),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(_dashboardProvider),
        child: dashboard.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => ListView(
            children: [
              const SizedBox(height: 80),
              AppErrorWidget(
                error: error,
                onRetry: () => ref.invalidate(_dashboardProvider),
              ),
            ],
          ),
          data: (data) => _DashboardBody(data: data, currency: currency),
        ),
      ),
    );
  }
}

class _DashboardBody extends StatelessWidget {
  const _DashboardBody({required this.data, required this.currency});

  final Map<String, dynamic> data;
  final NumberFormat currency;

  Map<String, dynamic> get _debts =>
      Map<String, dynamic>.from((data['debts'] as Map?) ?? const {});
  Map<String, dynamic> get _sales =>
      Map<String, dynamic>.from((data['sales'] as Map?) ?? const {});
  Map<String, dynamic> get _collections =>
      Map<String, dynamic>.from((data['collections'] as Map?) ?? const {});
  Map<String, dynamic> get _period =>
      Map<String, dynamic>.from((data['period'] as Map?) ?? const {});

  double _money(Map<String, dynamic> source, String key) =>
      (source[key] as num?)?.toDouble() ?? 0;

  String get _modeLabel => data['mode'] == 'internal' ? 'Interno' : 'FinReg';

  void _openCollections(BuildContext context) {
    final methods = ((_collections['by_method'] as List?) ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Cobrado no período',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                currency.format(_money(_collections, 'total_collected')),
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              if (methods.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('Sem pagamentos registados no período.'),
                )
              else
                for (final method in methods)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.payments_outlined),
                    title: Text(
                      _methodLabel(method['payment_method']?.toString()),
                    ),
                    trailing: Text(
                      currency
                          .format((method['total'] as num?)?.toDouble() ?? 0),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.verified_outlined),
                title: const Text('Abrir comprovativos de pagamento'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(context).pop();
                  context.push('/admin/finance/payment-proofs');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final buckets =
        Map<String, dynamic>.from((_debts['by_bucket'] as Map?) ?? const {});
    // Zero-amount buckets are noise: keep the aging strip to what exists,
    // oldest first.
    final visibleBuckets = [
      for (final key in _bucketLabels.keys)
        if ((buckets[key] as num?)?.toDouble() != null &&
            (buckets[key] as num?)!.toDouble() > 0)
          (key, (buckets[key] as num).toDouble()),
    ];
    final services = ((_debts['by_service'] as List?) ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
    final month =
        Map<String, dynamic>.from((data['month'] as Map?) ?? const {});
    final internal = data['mode'] == 'internal';
    final periodLabel = _period.isEmpty
        ? 'Este mês'
        : '${formatIsoDate(_period['from'] as String?)} – '
            '${formatIsoDate(_period['to'] as String?)}';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (month.isNotEmpty) ...[
          _MonthStatusCard(month: month, currency: currency),
          const SizedBox(height: 16),
        ],
        Row(
          children: [
            Expanded(
              child: Text(
                'Resumo de $periodLabel',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            Chip(
              avatar: const Icon(Icons.verified_outlined, size: 16),
              label: Text('Motor: $_modeLabel'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _KpiGrid(children: [
          _Kpi(
            icon: Icons.account_balance_wallet_outlined,
            label: 'Em dívida',
            value: currency.format(_money(_debts, 'total_outstanding')),
            detail: '${_debts['count'] ?? 0} documento(s)',
            semanticsLabel: 'Em dívida. Abrir todos os documentos em aberto.',
            onTap: () => context.push(_debtRoute()),
          ),
          _Kpi(
            icon: Icons.warning_amber_outlined,
            label: 'Em atraso',
            value: currency.format(_money(_debts, 'total_overdue')),
            detail: 'Vencidos até hoje',
            highlight: true,
            semanticsLabel: 'Em atraso. Abrir os documentos vencidos.',
            onTap: () => context.push(_debtRoute(overdue: true)),
          ),
          _Kpi(
            icon: Icons.receipt_long_outlined,
            label: 'Facturado no período',
            value: currency.format(_money(_sales, 'total_gross')),
            detail: '${_sales['invoice_count'] ?? 0} documento(s)',
            semanticsLabel:
                'Facturado no período. Abrir o relatório por serviço.',
            onTap: () => context.push('/admin/finance/service-report'),
          ),
          _Kpi(
            icon: Icons.savings_outlined,
            label: 'Cobrado no período',
            value: currency.format(_money(_collections, 'total_collected')),
            detail: '${_collections['payment_count'] ?? 0} pagamento(s)',
            semanticsLabel:
                'Cobrado no período. Ver a repartição por método de pagamento.',
            onTap: () => _openCollections(context),
          ),
        ]),
        const SizedBox(height: 20),
        Text('Dívida por antiguidade',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        if (visibleBuckets.isEmpty)
          Text(
            'Sem dívida em aberto.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in visibleBuckets)
                _BucketChip(
                  label: _bucketLabels[entry.$1] ?? entry.$1,
                  amount: currency.format(entry.$2),
                  onTap: () => context.push(_debtRoute(bucket: entry.$1)),
                ),
            ],
          ),
        const SizedBox(height: 20),
        Text('Ações rápidas',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        _QuickActions(actions: const [
          (
            icon: Icons.warning_amber_outlined,
            title: 'Controlo de dívidas',
            route: '/admin/finance/debt-control',
          ),
          (
            icon: Icons.receipt_long_outlined,
            title: 'Comprovativos de pagamento',
            route: '/admin/finance/payment-proofs',
          ),
          (
            icon: Icons.notifications_active_outlined,
            title: 'Lembretes de cobrança',
            route: '/admin/finance/reminders',
          ),
          (
            icon: Icons.qr_code_2_outlined,
            title: 'Pagamentos por referência',
            route: '/admin/finance/principia-pay',
          ),
        ]),
        if (internal) ...[
          const SizedBox(height: 20),
          _InternalShortcuts(onOpenLegacy: () {
            context.push('/admin/finance/legacy');
          }),
        ],
        if (services.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text('Dívida por serviço',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          for (final service in services.take(10))
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.sell_outlined),
              title: Text(service['service_label']?.toString() ??
                  service['service']?.toString() ??
                  'Outros'),
              subtitle: Text('${service['documents'] ?? 0} documento(s)'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    currency.format(
                        (service['outstanding'] as num?)?.toDouble() ?? 0),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right, size: 18),
                ],
              ),
              onTap: () {
                final key = service['service']?.toString() ??
                    service['service_label']?.toString();
                if (key == null || key.isEmpty) return;
                context.push(_debtRoute(service: key));
              },
            ),
        ],
      ],
    );
  }

  String _methodLabel(String? method) {
    return switch (method) {
      'cash' => 'Numerário',
      'mobile' => 'Pagamento móvel',
      'transfer' => 'Transferência',
      'multicaixa' => 'Multicaixa',
      'card' => 'Cartão',
      'cheque' => 'Cheque',
      null || '' => 'Outros',
      _ => method,
    };
  }
}

class _KpiGrid extends StatelessWidget {
  const _KpiGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final columns = constraints.maxWidth >= 720 ? 4 : 2;
      final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final child in children) SizedBox(width: width, child: child),
        ],
      );
    });
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi({
    required this.icon,
    required this.label,
    required this.value,
    required this.detail,
    this.highlight = false,
    this.onTap,
    this.semanticsLabel,
  });

  final IconData icon;
  final String label;
  final String value;
  final String detail;
  final bool highlight;
  final VoidCallback? onTap;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent =
        highlight ? theme.colorScheme.error : theme.colorScheme.primary;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Semantics(
          button: onTap != null,
          label: semanticsLabel,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, color: accent, size: 20),
                    const Spacer(),
                    if (onTap != null)
                      Icon(Icons.chevron_right,
                          size: 18, color: theme.colorScheme.onSurfaceVariant),
                  ],
                ),
                const SizedBox(height: 8),
                Text(label,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                const SizedBox(height: 2),
                Text(value,
                    style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: highlight ? accent : null)),
                Text(detail,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BucketChip extends StatelessWidget {
  const _BucketChip({
    required this.label,
    required this.amount,
    required this.onTap,
  });

  final String label;
  final String amount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text('$label · $amount'),
      visualDensity: VisualDensity.compact,
      tooltip: 'Ver documentos em $label',
      onPressed: onTap,
    );
  }
}

/// The month's own state, first thing on the home.
///
/// A director opens finance to answer one question — "did this month's
/// debts get generated?" — so the answer sits above every figure: the month
/// by name, whether it ran, what it produced, when it is due, and the one
/// button that starts it. Everything else on the page is analysis of a
/// decision already taken here.
class _MonthStatusCard extends StatelessWidget {
  const _MonthStatusCard({required this.month, required this.currency});

  final Map<String, dynamic> month;
  final NumberFormat currency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = billingMonthLabel(
        month['billing_month'] as String? ?? billingMonthKey());
    final generated = month['generated'] == true;
    final status = month['status']?.toString();
    final failedRun = status == 'partial_failed' || status == 'failed';
    final due = month['due_date'] as String?;
    final autoGenerate = month['auto_generate'] == true;
    final students = month['students'];
    final total = (month['total'] as num?)?.toDouble();
    final failedCount = (month['failed'] as num?)?.toInt() ?? 0;
    final accent =
        failedRun ? theme.colorScheme.error : theme.colorScheme.primary;
    final details = <String>[
      if (students != null) '$students ${students == 1 ? 'aluno' : 'alunos'}',
      if (total != null) currency.format(total),
      if (due != null) 'vence a ${formatIsoDate(due)}',
    ];
    return Card(
      elevation: 0,
      color: (failedRun
              ? theme.colorScheme.errorContainer
              : theme.colorScheme.primaryContainer)
          .withOpacity(0.4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: accent.withAlpha(70)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  generated
                      ? (failedRun
                          ? Icons.error_outline
                          : Icons.event_available_outlined)
                      : Icons.event_busy_outlined,
                  color: accent,
                  size: 22,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    generated
                        ? '$label · dívidas geradas'
                        : '$label · dívidas por gerar',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              generated
                  ? (details.isEmpty
                      ? 'Sem detalhes da execução.'
                      : details.join(' · '))
                  : (due != null
                      ? 'vence a ${formatIsoDate(due)}'
                      : 'Defina a política de propinas para saber a data de vencimento.'),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            if (failedRun && failedCount > 0) ...[
              const SizedBox(height: 4),
              Text(
                '$failedCount falhadas — ver execução',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error),
              ),
            ],
            if (autoGenerate) ...[
              const SizedBox(height: 6),
              Chip(
                avatar: const Icon(Icons.autorenew, size: 14),
                label: const Text('geração automática ligada'),
                visualDensity: VisualDensity.compact,
              ),
            ],
            const SizedBox(height: 10),
            if (!generated)
              FilledButton.icon(
                onPressed: () => context.push('/admin/finance/billing-run'),
                icon: const Icon(Icons.bolt_outlined),
                label: const Text('Gerar dívidas do mês'),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () =>
                        context.push('/admin/finance/debt-control'),
                    icon: const Icon(Icons.warning_amber_outlined),
                    label: const Text('Ver dívidas'),
                  ),
                  TextButton.icon(
                    onPressed: () => context.push('/admin/finance/billing-run'),
                    icon: const Icon(Icons.receipt_long_outlined),
                    label: const Text('Ver execução'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

typedef _QuickAction = ({IconData icon, String title, String route});

/// The four daily doors, after the month card and the numbers have said
/// what they have to say.
class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.actions});

  final List<_QuickAction> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(builder: (context, constraints) {
      final columns = constraints.maxWidth >= 720 ? 4 : 2;
      final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final action in actions)
            SizedBox(
              width: width,
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => context.push(action.route),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Icon(action.icon,
                            size: 20, color: theme.colorScheme.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            action.title,
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    });
  }
}

typedef _Shortcut = ({IconData icon, String label, String route});

/// Internal-mode schools have no tabs: this home is their whole finance
/// area, so every workflow is one shortcut away, grouped by intent.
class _InternalShortcuts extends StatelessWidget {
  const _InternalShortcuts({required this.onOpenLegacy});

  final VoidCallback onOpenLegacy;

  static const _debts = <_Shortcut>[
    (
      icon: Icons.bolt_outlined,
      label: 'Gerar dívidas do mês',
      route: '/admin/finance/billing-run',
    ),
    (
      icon: Icons.warning_amber_outlined,
      label: 'Controlo de dívidas',
      route: '/admin/finance/debt-control',
    ),
    (
      icon: Icons.gavel_outlined,
      label: 'Multas por atraso',
      route: '/admin/finance/late-fees',
    ),
    (
      icon: Icons.calendar_month_outlined,
      label: 'Acordos de pagamento',
      route: '/admin/finance/payment-plans',
    ),
    (
      icon: Icons.notifications_active_outlined,
      label: 'Lembretes de cobrança',
      route: '/admin/finance/reminders',
    ),
    (
      icon: Icons.account_balance_wallet_outlined,
      label: 'Créditos dos encarregados',
      route: '/admin/finance/credits',
    ),
  ];

  static const _payments = <_Shortcut>[
    (
      icon: Icons.qr_code_2_outlined,
      label: 'Pagamentos por referência',
      route: '/admin/finance/principia-pay',
    ),
    (
      icon: Icons.point_of_sale_outlined,
      label: 'Referências Multicaixa',
      route: '/admin/finance/payment-references',
    ),
    (
      icon: Icons.receipt_long_outlined,
      label: 'Comprovativos de pagamento',
      route: '/admin/finance/payment-proofs',
    ),
    (
      icon: Icons.savings_outlined,
      label: 'Fecho de caixa',
      route: '/admin/finance/cash-sessions',
    ),
    (
      icon: Icons.shopping_cart_outlined,
      label: 'Despesas',
      route: '/admin/finance/expenses',
    ),
    (
      icon: Icons.description_outlined,
      label: 'Extrato de contas',
      route: '/admin/finance/statements',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Atalhos',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        _shortcutGroup(context, 'Dívidas', _debts),
        const SizedBox(height: 12),
        _shortcutGroup(context, 'Pagamentos e contas', _payments),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('Facturação interna'),
            subtitle: const Text(
                'Facturas, notas de crédito, recibos e SAF-T do motor interno.'),
            trailing: const Icon(Icons.chevron_right),
            onTap: onOpenLegacy,
          ),
        ),
      ],
    );
  }

  Widget _shortcutGroup(
      BuildContext context, String title, List<_Shortcut> shortcuts) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final shortcut in shortcuts)
              ActionChip(
                avatar: Icon(shortcut.icon, size: 18),
                label: Text(shortcut.label),
                visualDensity: VisualDensity.compact,
                onPressed: () => context.push(shortcut.route),
              ),
          ],
        ),
      ],
    );
  }
}
