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

/// The finance home: one answer for debts, billing and collections, from
/// whichever engine owns the school. The FinReg is invisible here; its
/// documents drive the numbers without ever being exposed as a destination.
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final buckets =
        Map<String, dynamic>.from((_debts['by_bucket'] as Map?) ?? const {});
    final services = ((_debts['by_service'] as List?) ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
    final periodLabel = _period.isEmpty
        ? 'Este mês'
        : '${formatIsoDate(_period['from'] as String?)} – '
            '${formatIsoDate(_period['to'] as String?)}';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
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
          ),
          _Kpi(
            icon: Icons.warning_amber_outlined,
            label: 'Em atraso',
            value: currency.format(_money(_debts, 'total_overdue')),
            detail: 'Vencidos até hoje',
            highlight: true,
          ),
          _Kpi(
            icon: Icons.receipt_long_outlined,
            label: 'Facturado no período',
            value: currency.format(_money(_sales, 'total_gross')),
            detail: '${_sales['invoice_count'] ?? 0} documento(s)',
          ),
          _Kpi(
            icon: Icons.savings_outlined,
            label: 'Cobrado no período',
            value: currency.format(_money(_collections, 'total_collected')),
            detail: '${_collections['payment_count'] ?? 0} pagamento(s)',
          ),
        ]),
        const SizedBox(height: 20),
        Text('Dívida por antiguidade',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final entry in buckets.entries)
              _BucketChip(
                label: entry.key,
                amount: currency.format((entry.value as num?)?.toDouble() ?? 0),
              ),
          ],
        ),
        const SizedBox(height: 20),
        Text('Ações',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        const _ActionTile(
          icon: Icons.bolt_outlined,
          title: 'Gerar dívidas do mês',
          subtitle: 'Calcula propinas, modalidades, transporte e descontos.',
          route: '/admin/finance/billing-run',
        ),
        const _ActionTile(
          icon: Icons.warning_amber_outlined,
          title: 'Controlo de dívidas',
          subtitle: 'Por aluno, por serviço e com antiguidade.',
          route: '/admin/finance/debt-control',
        ),
        const _ActionTile(
          icon: Icons.bar_chart_outlined,
          title: 'Relatório por serviço',
          subtitle: 'Quanto cada serviço facturou no período.',
          route: '/admin/finance/service-report',
        ),
        const _ActionTile(
          icon: Icons.qr_code_2_outlined,
          title: 'Pagamentos por referência',
          subtitle: 'Ligações com a principia-pay e referências emitidas.',
          route: '/admin/finance/principia-pay',
        ),
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
              trailing: Text(
                currency
                    .format((service['outstanding'] as num?)?.toDouble() ?? 0),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ],
    );
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
  });

  final IconData icon;
  final String label;
  final String value;
  final String detail;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent =
        highlight ? theme.colorScheme.error : theme.colorScheme.primary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: accent, size: 20),
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
    );
  }
}

class _BucketChip extends StatelessWidget {
  const _BucketChip({required this.label, required this.amount});

  final String label;
  final String amount;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text('$label · $amount'),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.route,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String route;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(child: Icon(icon, size: 20)),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push(route),
      ),
    );
  }
}
