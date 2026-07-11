import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_client.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/models/attendance.dart';

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------
final adminChildrenCountProvider =
    FutureProvider.autoDispose<int>((ref) async {
  final api = ref.read(apiClientProvider);
  final data = await api.get('/children');
  if (data is List) return data.length;
  if (data is Map) {
    return data['count'] as int? ?? data['total'] as int? ?? 0;
  }
  return 0;
});

final adminAttendanceTodayProvider =
    FutureProvider.autoDispose<AttendanceSummary>((ref) async {
  final api = ref.read(apiClientProvider);
  final data = await api.get('/attendance/today');
  if (data is Map<String, dynamic>) {
    return AttendanceSummary.fromJson(data);
  }
  if (data is List) {
    final records = data
        .map((e) => AttendanceRecord.fromJson(e as Map<String, dynamic>))
        .toList();
    final checkedIn =
        records.where((r) => r.status == 'present' || r.status == 'late').length;
    final absent =
        records.where((r) => r.status == 'absent').length;
    return AttendanceSummary(
      totalEnrolled: records.length,
      checkedIn: checkedIn,
      checkedOut: 0,
      absent: absent,
      records: records,
    );
  }
  return const AttendanceSummary(
      totalEnrolled: 0, checkedIn: 0, checkedOut: 0, absent: 0, records: []);
});

final adminUnreadNotifProvider =
    FutureProvider.autoDispose<int>((ref) async {
  final api = ref.read(apiClientProvider);
  final data = await api.get('/notifications/unread-count');
  if (data is Map) {
    return data['count'] as int? ?? data['unread_count'] as int? ?? 0;
  }
  if (data is int) return data;
  return 0;
});

final adminFinanceProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final api = ref.read(apiClientProvider);
  try {
    final data = await api.get('/finance/dashboard');
    if (data is Map<String, dynamic>) return data;
  } catch (_) {}
  return {};
});

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------
class AdminDashboardScreen extends ConsumerStatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  ConsumerState<AdminDashboardScreen> createState() =>
      _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends ConsumerState<AdminDashboardScreen> {
  @override
  Widget build(BuildContext context) {
    final auth = ref.read(authProvider);
    final childrenAsync = ref.watch(adminChildrenCountProvider);
    final attendanceAsync = ref.watch(adminAttendanceTodayProvider);
    final unreadAsync = ref.watch(adminUnreadNotifProvider);
    final financeAsync = ref.watch(adminFinanceProvider);

    final now = DateTime.now();
    final hour = now.hour;
    final greeting = hour < 12
        ? 'Bom dia'
        : hour < 18
            ? 'Boa tarde'
            : 'Boa noite';
    final dateStr = DateFormat('EEEE, d \'de\' MMMM yyyy', 'pt_PT').format(now);

    void refresh() {
      ref.invalidate(adminChildrenCountProvider);
      ref.invalidate(adminAttendanceTodayProvider);
      ref.invalidate(adminUnreadNotifProvider);
      ref.invalidate(adminFinanceProvider);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Cellen — ${auth.schoolId ?? 'Admin'}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () => context.push('/notifications'),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: refresh,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => refresh(),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Welcome card
              Card(
                elevation: 0,
                color: Theme.of(context).colorScheme.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$greeting, ${auth.username ?? 'Administrador'}!',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onPrimaryContainer,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              dateStr,
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onPrimaryContainer
                                    .withOpacity(0.75),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.admin_panel_settings,
                        size: 42,
                        color: Theme.of(context)
                            .colorScheme
                            .onPrimaryContainer
                            .withOpacity(0.6),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Quick stats 2x2 grid
              Text(
                'Resumo do Dia',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              GridView.count(
                crossAxisCount:
                    MediaQuery.of(context).size.width >= 600 ? 4 : 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 1.3,
                children: [
                  // Crianças Ativas
                  _StatCard(
                    label: 'Crianças Activas',
                    valueWidget: childrenAsync.when(
                      loading: () => const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                      error: (_, __) => const Icon(Icons.error, color: Colors.red, size: 20),
                      data: (count) => Text(
                        '$count',
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                    icon: Icons.child_care,
                    color: Colors.blue,
                    onTap: () => context.go('/admin/children'),
                  ),
                  // Presenças Hoje
                  _StatCard(
                    label: 'Presenças Hoje',
                    valueWidget: attendanceAsync.when(
                      loading: () => const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                      error: (_, __) =>
                          const Icon(Icons.error, color: Colors.red, size: 20),
                      data: (summary) => Text(
                        '${summary.checkedIn}/${summary.totalEnrolled}',
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                    icon: Icons.how_to_reg,
                    color: Colors.green,
                    onTap: () => context.push('/teacher/attendance'),
                  ),
                  // Faturas Pendentes
                  _StatCard(
                    label: 'Faturas Pendentes',
                    valueWidget: financeAsync.when(
                      loading: () => const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                      error: (_, __) =>
                          const Icon(Icons.error, color: Colors.red, size: 20),
                      data: (finance) {
                        final pending = finance['outstanding_invoices'] as int? ??
                            finance['pending_invoices'] as int? ?? 0;
                        return Text(
                          '$pending',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        );
                      },
                    ),
                    icon: Icons.receipt_long,
                    color: Colors.orange,
                    onTap: () => context.go('/admin/finance/invoices'),
                  ),
                  // Mensagens Não Lidas
                  _StatCard(
                    label: 'Não Lidas',
                    valueWidget: unreadAsync.when(
                      loading: () => const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                      error: (_, __) =>
                          const Icon(Icons.error, color: Colors.red, size: 20),
                      data: (count) => Text(
                        '$count',
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                    icon: Icons.chat_bubble_outline,
                    color: Colors.purple,
                    onTap: () => context.push('/messages'),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Quick Actions
              Text(
                'Ações Rápidas',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              GridView.count(
                crossAxisCount: 4,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 0.9,
                children: [
                  _QuickActionButton(
                    icon: Icons.how_to_reg,
                    label: 'Presenças',
                    color: Colors.green,
                    onTap: () => context.push('/teacher/attendance'),
                  ),
                  _QuickActionButton(
                    icon: Icons.receipt,
                    label: 'Faturas',
                    color: Colors.orange,
                    onTap: () => context.go('/admin/finance/invoices'),
                  ),
                  _QuickActionButton(
                    icon: Icons.warning_amber,
                    label: 'Ocorrências',
                    color: Colors.red,
                    onTap: () => context.push('/incidents'),
                  ),
                  _QuickActionButton(
                    icon: Icons.event,
                    label: 'Calendário',
                    color: Colors.purple,
                    onTap: () => context.push('/events'),
                  ),
                  _QuickActionButton(
                    icon: Icons.photo_library,
                    label: 'Galeria',
                    color: Colors.teal,
                    onTap: () => context.push('/photos'),
                  ),
                  _QuickActionButton(
                    icon: Icons.notifications,
                    label: 'Notificações',
                    color: Colors.blue,
                    onTap: () => context.push('/notifications'),
                  ),
                  _QuickActionButton(
                    icon: Icons.child_care,
                    label: 'Crianças',
                    color: Colors.indigo,
                    onTap: () => context.go('/admin/children'),
                  ),
                  _QuickActionButton(
                    icon: Icons.people,
                    label: 'Funcionários',
                    color: Colors.brown,
                    onTap: () => context.go('/admin/employees'),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Recent Attendance Activity
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Actividade Recente',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  TextButton(
                    onPressed: () => context.push('/teacher/attendance'),
                    child: const Text('Ver todas'),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              attendanceAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Text(
                  'Erro ao carregar actividade: $e',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error),
                ),
                data: (summary) {
                  final recent = summary.records.take(3).toList();
                  if (recent.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: Text('Sem registos de presença hoje',
                            style: TextStyle(color: Colors.grey)),
                      ),
                    );
                  }
                  return Column(
                    children: recent
                        .map((r) => _AttendanceActivityTile(record: r))
                        .toList(),
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

// ---------------------------------------------------------------------------
// Widgets
// ---------------------------------------------------------------------------

class _StatCard extends StatelessWidget {
  final String label;
  final Widget valueWidget;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _StatCard({
    required this.label,
    required this.valueWidget,
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
            color: Theme.of(context).colorScheme.outline.withOpacity(0.15)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: color.withOpacity(0.15),
                child: Icon(icon, color: color, size: 16),
              ),
              const Spacer(),
              valueWidget,
              const SizedBox(height: 2),
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 26),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: color.withOpacity(0.85)),
              textAlign: TextAlign.center,
              maxLines: 2,
            ),
          ],
        ),
      ),
    );
  }
}

class _AttendanceActivityTile extends StatelessWidget {
  final AttendanceRecord record;

  const _AttendanceActivityTile({required this.record});

  @override
  Widget build(BuildContext context) {
    final initials = record.childName.isNotEmpty
        ? record.childName.trim().split(' ').take(2).map((w) => w[0]).join()
        : '?';
    Color statusColor;
    String statusLabel;
    switch (record.status) {
      case 'present':
        statusColor = Colors.green;
        statusLabel = 'Presente';
        break;
      case 'late':
        statusColor = Colors.orange;
        statusLabel = 'Tarde';
        break;
      case 'absent':
        statusColor = Colors.red;
        statusLabel = 'Ausente';
        break;
      default:
        statusColor = Colors.grey;
        statusLabel = record.status;
    }

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        dense: true,
        leading: CircleAvatar(
          radius: 18,
          backgroundColor:
              Theme.of(context).colorScheme.primaryContainer,
          child: Text(
            initials.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
          ),
        ),
        title: Text(record.childName,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: record.checkInTime != null
            ? Text('Entrada: ${record.checkInTime}')
            : null,
        trailing: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: statusColor.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            statusLabel,
            style: TextStyle(
                color: statusColor,
                fontSize: 11,
                fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}
