import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_client.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/models/attendance.dart';
import '../../../core/models/caderneta.dart';
import '../../../core/models/child.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_stat_card.dart';

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------
final teacherAttendanceTodayProvider =
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
    final checkedOut = records
        .where((r) => r.checkOutTime != null && r.checkOutTime!.isNotEmpty)
        .length;
    final absent = records.where((r) => r.status == 'absent').length;
    return AttendanceSummary(
      totalEnrolled: records.length,
      checkedIn: checkedIn,
      checkedOut: checkedOut,
      absent: absent,
      records: records,
    );
  }
  return const AttendanceSummary(
      totalEnrolled: 0, checkedIn: 0, checkedOut: 0, absent: 0, records: []);
});

final teacherRecentCadernetsProvider =
    FutureProvider.autoDispose<List<Caderneta>>((ref) async {
  final api = ref.read(apiClientProvider);
  final data = await api.get('/cadernetas/my',
      queryParameters: {'limit': '5', 'ordering': '-report_date'}) as List;
  return data
      .map((e) => Caderneta.fromJson(e as Map<String, dynamic>))
      .toList();
});

final teacherChildrenProvider =
    FutureProvider.autoDispose<List<Child>>((ref) async {
  final api = ref.read(apiClientProvider);
  final data = await api.get('/children/my') as List;
  return data
      .map((e) => Child.fromJson(e as Map<String, dynamic>))
      .toList();
});

final teacherUnreadMsgProvider =
    FutureProvider.autoDispose<int>((ref) async {
  final api = ref.read(apiClientProvider);
  final data = await api.get('/notifications/unread-count');
  if (data is Map) {
    return data['count'] as int? ?? data['unread_count'] as int? ?? 0;
  }
  if (data is int) return data;
  return 0;
});

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------
class TeacherDashboardScreen extends ConsumerStatefulWidget {
  const TeacherDashboardScreen({super.key});

  @override
  ConsumerState<TeacherDashboardScreen> createState() =>
      _TeacherDashboardScreenState();
}

class _TeacherDashboardScreenState
    extends ConsumerState<TeacherDashboardScreen> {
  @override
  Widget build(BuildContext context) {
    final auth = ref.read(authProvider);
    final attendanceAsync = ref.watch(teacherAttendanceTodayProvider);
    final cadernetasAsync = ref.watch(teacherRecentCadernetsProvider);
    final childrenAsync = ref.watch(teacherChildrenProvider);
    final unreadAsync = ref.watch(teacherUnreadMsgProvider);
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
        DateFormat('EEEE, d \'de\' MMMM', 'pt_PT').format(now);

    void refresh() {
      ref.invalidate(teacherAttendanceTodayProvider);
      ref.invalidate(teacherRecentCadernetsProvider);
      ref.invalidate(teacherChildrenProvider);
      ref.invalidate(teacherUnreadMsgProvider);
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
                        '$greeting, ${auth.username ?? 'Educador(a)'}',
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

            // ── Stat cards ──
            const Text(
              'Presenças de Hoje',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            attendanceAsync.when(
              loading: () => GridView.count(
                crossAxisCount: isWide ? 3 : 3,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: isWide ? 1.8 : 1.3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: const [
                  AppStatCard(label: 'Total', value: '...', icon: Icons.people, color: AppTheme.primary),
                  AppStatCard(label: 'Presentes', value: '...', icon: Icons.check_circle, color: AppTheme.success),
                  AppStatCard(label: 'Ausentes', value: '...', icon: Icons.cancel, color: AppTheme.danger),
                ],
              ),
              error: (_, __) => Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.border),
                ),
                child: const Text('Erro ao carregar presenças',
                    style: TextStyle(color: AppTheme.danger)),
              ),
              data: (s) => GridView.count(
                crossAxisCount: isWide ? 3 : 3,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: isWide ? 1.8 : 1.3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  AppStatCard(
                    label: 'Total',
                    value: '${s.totalEnrolled}',
                    icon: Icons.people,
                    color: AppTheme.primary,
                    onTap: () => context.go('/teacher/attendance'),
                  ),
                  AppStatCard(
                    label: 'Presentes',
                    value: '${s.checkedIn}',
                    icon: Icons.check_circle,
                    color: AppTheme.success,
                    onTap: () => context.go('/teacher/attendance'),
                  ),
                  AppStatCard(
                    label: 'Ausentes',
                    value: '${s.absent}',
                    icon: Icons.cancel,
                    color: AppTheme.danger,
                    onTap: () => context.go('/teacher/attendance'),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── View attendance button ──
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => context.go('/teacher/attendance'),
                icon: const Icon(Icons.fact_check_outlined, size: 18),
                label: const Text('Gerir Presenças'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.primary,
                  side: const BorderSide(color: AppTheme.primary),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
            ),

            const SizedBox(height: 28),

            // ── Quick links ──
            const Text(
              'Acesso Rápido',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _QuickLinkTile(
                    icon: Icons.menu_book_outlined,
                    label: 'Caderneta',
                    subtitle: 'Novo relatório',
                    color: const Color(0xFF7C3AED),
                    onTap: () => context.go('/teacher/caderneta/new'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: unreadAsync.when(
                    loading: () => _QuickLinkTile(
                      icon: Icons.chat_bubble_outline,
                      label: 'Mensagens',
                      subtitle: 'A carregar...',
                      color: AppTheme.secondary,
                      onTap: () => context.go('/messages'),
                    ),
                    error: (_, __) => _QuickLinkTile(
                      icon: Icons.chat_bubble_outline,
                      label: 'Mensagens',
                      subtitle: 'Abrir',
                      color: AppTheme.secondary,
                      onTap: () => context.go('/messages'),
                    ),
                    data: (count) => _QuickLinkTile(
                      icon: Icons.chat_bubble_outline,
                      label: 'Mensagens',
                      subtitle: count > 0
                          ? '$count não lida(s)'
                          : 'Sem novas mensagens',
                      color: AppTheme.secondary,
                      badge: count > 0 ? count : null,
                      onTap: () => context.go('/messages'),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 28),

            // ── My Children ──
            const Text(
              'As Minhas Crianças',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            childrenAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('Erro: $e',
                  style: TextStyle(color: theme.colorScheme.error)),
              data: (children) {
                if (children.isEmpty) {
                  return Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: const Center(
                      child: Text('Nenhuma criança atribuída.',
                          style: TextStyle(color: AppTheme.textSecondary)),
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
                    children: children
                        .take(8)
                        .toList()
                        .asMap()
                        .entries
                        .map((entry) {
                      final isLast = entry.key == (children.length < 8 ? children.length - 1 : 7);
                      final child = entry.value;
                      final initials = child.fullName.isNotEmpty
                          ? child.fullName.trim().split(' ').take(2).map((w) => w[0]).join()
                          : '?';
                      return Column(
                        children: [
                          ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 4),
                            leading: CircleAvatar(
                              radius: 18,
                              backgroundColor: AppTheme.primaryLight,
                              child: Text(
                                initials.toUpperCase(),
                                style: const TextStyle(
                                  color: AppTheme.primary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            title: Text(
                              child.fullName,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: AppTheme.textPrimary),
                            ),
                            subtitle: child.turmaName != null
                                ? Text(child.turmaName!,
                                    style: const TextStyle(
                                        fontSize: 12,
                                        color: AppTheme.textSecondary))
                                : null,
                          ),
                          if (!isLast)
                            const Divider(height: 1, color: AppTheme.border),
                        ],
                      );
                    }).toList(),
                  ),
                );
              },
            ),

            const SizedBox(height: 28),

            // ── Recent cadernetas ──
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Cadernetas Recentes',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                TextButton(
                  onPressed: () => context.go('/teacher/caderneta'),
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
            cadernetasAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('Erro: $e'),
              data: (cadernetas) {
                if (cadernetas.isEmpty) {
                  return Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: const Center(
                      child: Column(
                        children: [
                          Icon(Icons.menu_book_outlined,
                              size: 48, color: AppTheme.border),
                          SizedBox(height: 8),
                          Text('Nenhuma caderneta preenchida ainda',
                              style: TextStyle(color: AppTheme.textSecondary)),
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
                    children: cadernetas
                        .asMap()
                        .entries
                        .map((entry) {
                      final isLast = entry.key == cadernetas.length - 1;
                      final c = entry.value;
                      return Column(
                        children: [
                          ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 4),
                            leading: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: const Color(0xFF7C3AED).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.menu_book_outlined,
                                  color: Color(0xFF7C3AED), size: 20),
                            ),
                            title: Text(
                              c.childName ??
                                  'Criança ${c.childId.substring(0, 6)}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: AppTheme.textPrimary),
                            ),
                            subtitle: Text(
                              DateFormat('dd/MM/yyyy').format(c.reportDate),
                              style: const TextStyle(
                                  fontSize: 12, color: AppTheme.textSecondary),
                            ),
                            trailing: _RatingBadge(
                                rating: c.lunchRating ?? c.breakfastRating),
                            onTap: () => context
                                .go('/teacher/caderneta/${c.id}/edit'),
                          ),
                          if (!isLast)
                            const Divider(height: 1, color: AppTheme.border),
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

class _QuickLinkTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final int? badge;
  final VoidCallback onTap;

  const _QuickLinkTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    this.badge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.border),
        ),
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                if (badge != null && badge! > 0)
                  Positioned(
                    top: -4,
                    right: -4,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        color: AppTheme.danger,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        badge! > 9 ? '9+' : '$badge',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: AppTheme.textPrimary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                        fontSize: 12, color: AppTheme.textSecondary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right,
                size: 18, color: AppTheme.textSecondary),
          ],
        ),
      ),
    );
  }
}

class _RatingBadge extends StatelessWidget {
  final String? rating;

  const _RatingBadge({this.rating});

  @override
  Widget build(BuildContext context) {
    if (rating == null) return const SizedBox.shrink();
    Color color;
    switch (rating) {
      case 'Muito Bem':
        color = AppTheme.success;
        break;
      case 'Bem':
        color = const Color(0xFF0369A1);
        break;
      case 'Mal':
        color = AppTheme.danger;
        break;
      default:
        color = AppTheme.textSecondary;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        rating!,
        style: TextStyle(
            color: color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}
