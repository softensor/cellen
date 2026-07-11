import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_client.dart';
import '../../../core/auth/auth_provider.dart';

// ---------------------------------------------------------------------------
// Data model for dashboard stats
// ---------------------------------------------------------------------------
class DashboardStats {
  final int totalChildren;
  final int totalEmployees;
  final double monthlyRevenue;
  final int outstandingInvoices;
  final double outstandingAmount;

  const DashboardStats({
    required this.totalChildren,
    required this.totalEmployees,
    required this.monthlyRevenue,
    required this.outstandingInvoices,
    required this.outstandingAmount,
  });

  factory DashboardStats.fromJson(Map<String, dynamic> json) {
    return DashboardStats(
      totalChildren: json['total_children'] as int? ?? 0,
      totalEmployees: json['total_employees'] as int? ?? 0,
      monthlyRevenue: (json['monthly_revenue'] as num?)?.toDouble() ?? 0.0,
      outstandingInvoices: json['outstanding_invoices'] as int? ?? 0,
      outstandingAmount:
          (json['outstanding_amount'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------
final dashboardStatsProvider =
    FutureProvider.autoDispose<DashboardStats>((ref) async {
  final api = ref.read(apiClientProvider);
  final data = await api.get('/schools/me/stats');
  return DashboardStats.fromJson(data as Map<String, dynamic>);
});

class _ActivityItem {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;

  const _ActivityItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
  });
}

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------
class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(dashboardStatsProvider);
    final auth = ref.read(authProvider);
    final currency = NumberFormat.currency(locale: 'pt_PT', symbol: '€');
    final now = DateTime.now();
    final monthLabel = DateFormat('MMMM yyyy', 'pt_PT').format(now);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
            onPressed: () => ref.invalidate(dashboardStatsProvider),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(dashboardStatsProvider),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Greeting
              Text(
                'Bem-vindo, ${auth.username ?? 'Administrador'}!',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              Text(
                DateFormat('EEEE, d \'de\' MMMM yyyy', 'pt_PT').format(now),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 24),

              // Stats title
              Text(
                'Resumo — $monthLabel',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 12),

              // Stats grid
              statsAsync.when(
                loading: () => const SizedBox(
                  height: 200,
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => _ErrorCard(
                  message: e.toString(),
                  onRetry: () => ref.invalidate(dashboardStatsProvider),
                ),
                data: (stats) => GridView.count(
                  crossAxisCount:
                      MediaQuery.of(context).size.width >= 600 ? 4 : 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _StatCard(
                      label: 'Crianças',
                      value: '${stats.totalChildren}',
                      icon: Icons.child_care,
                      color: Colors.blue,
                      onTap: () => context.go('/admin/children'),
                    ),
                    _StatCard(
                      label: 'Funcionários',
                      value: '${stats.totalEmployees}',
                      icon: Icons.people,
                      color: Colors.green,
                      onTap: () => context.go('/admin/employees'),
                    ),
                    _StatCard(
                      label: 'Receita (mês)',
                      value: currency.format(stats.monthlyRevenue),
                      icon: Icons.account_balance_wallet,
                      color: Colors.teal,
                      onTap: () => context.go('/admin/finance'),
                    ),
                    _StatCard(
                      label: 'Em Atraso',
                      value: '${stats.outstandingInvoices}',
                      sublabel: currency.format(stats.outstandingAmount),
                      icon: Icons.warning_amber,
                      color: Colors.orange,
                      onTap: () => context.go('/admin/finance/invoices'),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Quick actions
              Text(
                'Ações Rápidas',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _QuickActionChip(
                    label: 'Nova Criança',
                    icon: Icons.add,
                    onPressed: () => context.push('/admin/children/new'),
                  ),
                  _QuickActionChip(
                    label: 'Novo Funcionário',
                    icon: Icons.person_add,
                    onPressed: () => context.push('/admin/employees/new'),
                  ),
                  _QuickActionChip(
                    label: 'Nova Factura',
                    icon: Icons.receipt,
                    onPressed: () => context.go('/admin/finance/invoices'),
                  ),
                  _QuickActionChip(
                    label: 'Ausências',
                    icon: Icons.event_busy,
                    onPressed: () => context.go('/admin/absences'),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Recent activity placeholder
              Text(
                'Actividade Recente',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 12),

              ..._recentActivity.map(
                (item) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: item.color.withOpacity(0.15),
                      child: Icon(item.icon, color: item.color, size: 20),
                    ),
                    title: Text(item.title),
                    subtitle: Text(item.subtitle),
                    dense: true,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static final _recentActivity = [
    _ActivityItem(
      title: 'Pagamento registado',
      subtitle: 'Factura #2024-001 — Criança: Ana Silva',
      icon: Icons.payments,
      color: Colors.green,
    ),
    _ActivityItem(
      title: 'Nova matrícula',
      subtitle: 'Carlos Ferreira inscrito na Sala Amarela',
      icon: Icons.how_to_reg,
      color: Colors.blue,
    ),
    _ActivityItem(
      title: 'Caderneta preenchida',
      subtitle: 'Educadora Mariana — 3 crianças',
      icon: Icons.book,
      color: Colors.purple,
    ),
    _ActivityItem(
      title: 'Ausência registada',
      subtitle: 'João Pereira — dia 10/07/2026',
      icon: Icons.event_busy,
      color: Colors.orange,
    ),
  ];
}

// ---------------------------------------------------------------------------
// Helper widgets
// ---------------------------------------------------------------------------

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final String? sublabel;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _StatCard({
    required this.label,
    required this.value,
    this.sublabel,
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: color.withOpacity(0.15),
                child: Icon(icon, color: color, size: 20),
              ),
              const Spacer(),
              Text(
                value,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              if (sublabel != null)
                Text(
                  sublabel!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickActionChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  const _QuickActionChip({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Icon(icon, size: 18),
      label: Text(label),
      onPressed: onPressed,
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorCard({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(Icons.error_outline,
                color: Theme.of(context).colorScheme.error, size: 40),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }
}
