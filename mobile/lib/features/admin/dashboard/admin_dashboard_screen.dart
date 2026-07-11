import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_client.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/models/attendance.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_stat_card.dart';

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
    final absent = records.where((r) => r.status == 'absent').length;
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
    final theme = Theme.of(context);
    final isWide = MediaQuery.of(context).size.width >= 900;

    final now = DateTime.now();
    final hour = now.hour;
    final greeting = hour < 12
        ? 'Bom dia'
        : hour < 18
            ? 'Boa tarde'
            : 'Boa noite';
    final dateStr =
        DateFormat('EEEE, d \'de\' MMMM yyyy', 'pt_PT').format(now);

    void refresh() {
      ref.invalidate(adminChildrenCountProvider);
      ref.invalidate(adminAttendanceTodayProvider);
      ref.invalidate(adminUnreadNotifProvider);
      ref.invalidate(adminFinanceProvider);
    }

    return RefreshIndicator(
      onRefresh: () async => refresh(),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(isWide ? 32 : 16, 24, isWide ? 32 : 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Greeting row ──
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$greeting, ${auth.username ?? 'Administrador'}',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textPrimary,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        dateStr,
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, color: AppTheme.textSecondary),
                  onPressed: refresh,
                  tooltip: 'Actualizar',
                ),
              ],
            ),
            const SizedBox(height: 24),

            // ── Stat cards section ──
            const Text(
              'Resumo do Dia',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: isWide ? 4 : 2,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: isWide ? 1.5 : 1.3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                childrenAsync.when(
                  loading: () => AppStatCard(
                    label: 'Crianças Activas',
                    value: '...',
                    icon: Icons.child_care,
                    color: AppTheme.primary,
                    onTap: () => context.go('/admin/children'),
                  ),
                  error: (_, __) => AppStatCard(
                    label: 'Crianças Activas',
                    value: '-',
                    icon: Icons.child_care,
                    color: AppTheme.primary,
                  ),
                  data: (count) => AppStatCard(
                    label: 'Crianças Activas',
                    value: '$count',
                    icon: Icons.child_care,
                    color: AppTheme.primary,
                    onTap: () => context.go('/admin/children'),
                  ),
                ),
                attendanceAsync.when(
                  loading: () => AppStatCard(
                    label: 'Presenças Hoje',
                    value: '...',
                    icon: Icons.fact_check,
                    color: AppTheme.success,
                  ),
                  error: (_, __) => AppStatCard(
                    label: 'Presenças Hoje',
                    value: '-',
                    icon: Icons.fact_check,
                    color: AppTheme.success,
                  ),
                  data: (s) => AppStatCard(
                    label: 'Presenças Hoje',
                    value: '${s.checkedIn}/${s.totalEnrolled}',
                    icon: Icons.fact_check,
                    color: AppTheme.success,
                    onTap: () => context.go('/teacher/attendance'),
                  ),
                ),
                financeAsync.when(
                  loading: () => AppStatCard(
                    label: 'Faturas Pendentes',
                    value: '...',
                    icon: Icons.receipt_long,
                    color: AppTheme.warning,
                  ),
                  error: (_, __) => AppStatCard(
                    label: 'Faturas Pendentes',
                    value: '-',
                    icon: Icons.receipt_long,
                    color: AppTheme.warning,
                  ),
                  data: (finance) {
                    final pending =
                        finance['outstanding_invoices'] as int? ??
                            finance['pending_invoices'] as int? ??
                            finance['pending_invoices_count'] as int? ??
                            0;
                    return AppStatCard(
                      label: 'Faturas Pendentes',
                      value: '$pending',
                      icon: Icons.receipt_long,
                      color: AppTheme.warning,
                      onTap: () => context.go('/admin/finance/invoices'),
                    );
                  },
                ),
                unreadAsync.when(
                  loading: () => AppStatCard(
                    label: 'Não Lidas',
                    value: '...',
                    icon: Icons.notifications,
                    color: AppTheme.danger,
                  ),
                  error: (_, __) => AppStatCard(
                    label: 'Não Lidas',
                    value: '-',
                    icon: Icons.notifications,
                    color: AppTheme.danger,
                  ),
                  data: (count) => AppStatCard(
                    label: 'Não Lidas',
                    value: '$count',
                    icon: Icons.notifications,
                    color: AppTheme.danger,
                    onTap: () => context.go('/notifications'),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 28),

            // ── Quick Actions ──
            const Text(
              'Acções Rápidas',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _QuickAction(
                  icon: Icons.fact_check,
                  label: 'Presenças',
                  onTap: () => context.go('/teacher/attendance'),
                ),
                _QuickAction(
                  icon: Icons.receipt_long,
                  label: 'Nova Fatura',
                  onTap: () => context.go('/admin/finance/invoices'),
                ),
                _QuickAction(
                  icon: Icons.report,
                  label: 'Ocorrências',
                  onTap: () => context.go('/incidents'),
                ),
                _QuickAction(
                  icon: Icons.calendar_month,
                  label: 'Calendário',
                  onTap: () => context.go('/events'),
                ),
                _QuickAction(
                  icon: Icons.people,
                  label: 'Crianças',
                  onTap: () => context.go('/admin/children'),
                ),
                _QuickAction(
                  icon: Icons.badge,
                  label: 'Funcionários',
                  onTap: () => context.go('/admin/employees'),
                ),
              ],
            ),

            const SizedBox(height: 28),

            // ── Recent Activity ──
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Actividade Recente',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                TextButton(
                  onPressed: () => context.go('/teacher/attendance'),
                  child: const Text(
                    'Ver todas',
                    style: TextStyle(
                      color: AppTheme.primary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            attendanceAsync.when(
              loading: () => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: CircularProgressIndicator(),
                  )),
              error: (e, _) => Text(
                'Erro ao carregar actividade: $e',
                style: TextStyle(color: theme.colorScheme.error),
              ),
              data: (summary) {
                final recent = summary.records.take(5).toList();
                if (recent.isEmpty) {
                  return Container(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Center(
                      child: Column(
                        children: [
                          const Icon(Icons.fact_check_outlined,
                              size: 48, color: AppTheme.border),
                          const SizedBox(height: 12),
                          const Text(
                            'Sem registos de presença hoje',
                            style: TextStyle(color: AppTheme.textSecondary),
                          ),
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: refresh,
                            child: const Text('Actualizar'),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Column(
                    children: recent
                        .asMap()
                        .entries
                        .map((entry) {
                      final isLast = entry.key == recent.length - 1;
                      return Column(
                        children: [
                          _AttendanceActivityTile(record: entry.value),
                          if (!isLast)
                            const Divider(
                                height: 1,
                                color: AppTheme.border),
                        ],
                      );
                    }).toList(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Widgets
// ---------------------------------------------------------------------------

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppTheme.textPrimary,
        side: const BorderSide(color: AppTheme.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
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

    final bgColor = AppTheme.statusBg(record.status);
    final textColor = AppTheme.statusText(record.status);
    final statusLabel = AppTheme.statusLabel(record.status);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: AppTheme.primaryLight,
            child: Text(
              initials.toUpperCase(),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppTheme.primary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(record.childName,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: AppTheme.textPrimary)),
                if (record.checkInTime != null)
                  Text('Entrada: ${record.checkInTime}',
                      style: const TextStyle(
                          fontSize: 12, color: AppTheme.textSecondary)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              statusLabel,
              style: TextStyle(
                  color: textColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
