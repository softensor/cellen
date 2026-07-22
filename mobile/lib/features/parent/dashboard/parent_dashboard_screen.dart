import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_client.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/models/caderneta.dart';
import '../../../core/models/child.dart';
import '../../../core/models/invoice.dart';
import '../../../core/models/school_terms.dart';
import '../../../core/providers/currency_provider.dart';
import '../../../core/theme/app_theme.dart';

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------
final parentChildrenProvider =
    FutureProvider.autoDispose<List<Child>>((ref) async {
  final api = ref.read(apiClientProvider);
  final data = await api.get('/children/my') as List;
  return data
      .map((e) => Child.fromJson(e as Map<String, dynamic>))
      .toList();
});

final parentRecentCadernetsProvider =
    FutureProvider.autoDispose<List<Caderneta>>((ref) async {
  final api = ref.read(apiClientProvider);
  final data = await api.get('/parent/cadernetas',
      queryParameters: {'limit': '5', 'ordering': '-report_date'}) as List;
  return data
      .map((e) => Caderneta.fromJson(e as Map<String, dynamic>))
      .toList();
});

final parentOutstandingInvoicesProvider =
    FutureProvider.autoDispose<List<Invoice>>((ref) async {
  final api = ref.read(apiClientProvider);
  final data = await api.get('/finance/parent/invoices') as List;
  return data
      .map((e) => Invoice.fromJson(e as Map<String, dynamic>))
      .where((i) => i.status != 'paid' && i.status != 'cancelled')
      .toList();
});

final parentUnreadMessagesProvider =
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
class ParentDashboardScreen extends ConsumerStatefulWidget {
  const ParentDashboardScreen({super.key});

  @override
  ConsumerState<ParentDashboardScreen> createState() =>
      _ParentDashboardScreenState();
}

class _ParentDashboardScreenState
    extends ConsumerState<ParentDashboardScreen> {
  bool _dismissedInvoiceBanner = false;

  @override
  Widget build(BuildContext context) {
    final auth = ref.read(authProvider);
    final childrenAsync = ref.watch(parentChildrenProvider);
    final cadernetasAsync = ref.watch(parentRecentCadernetsProvider);
    final invoicesAsync = ref.watch(parentOutstandingInvoicesProvider);
    final unreadAsync = ref.watch(parentUnreadMessagesProvider);
    final currency = ref.watch(currencyFormatProvider);
    final terms = SchoolTerms.of(ref.watch(schoolInfoProvider).valueOrNull);
    final now = DateTime.now();
    final isWide = MediaQuery.of(context).size.width >= 900;

    final hour = now.hour;
    final greeting = hour < 12
        ? 'Bom dia'
        : hour < 18
            ? 'Boa tarde'
            : 'Boa noite';

    void refresh() {
      ref.invalidate(parentChildrenProvider);
      ref.invalidate(parentRecentCadernetsProvider);
      ref.invalidate(parentOutstandingInvoicesProvider);
      ref.invalidate(parentUnreadMessagesProvider);
      setState(() => _dismissedInvoiceBanner = false);
    }

    return RefreshIndicator(
      onRefresh: () async => refresh(),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(isWide ? 32 : 16, 24, isWide ? 32 : 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Greeting ──
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$greeting, ${auth.username ?? 'Encarregado'}',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textPrimary,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        DateFormat('EEEE, d \'de\' MMMM', 'pt_PT').format(now),
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
            const SizedBox(height: 20),

            // ── Finance alert banner ──
            if (!_dismissedInvoiceBanner)
              invoicesAsync.when(
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
                data: (invoices) {
                  if (invoices.isEmpty) return const SizedBox.shrink();
                  final total = invoices.fold<double>(
                      0.0, (sum, i) => sum + i.totalAmount);
                  return Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: AppTheme.warning.withOpacity(0.4)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: AppTheme.warning.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.warning_amber_rounded,
                              color: AppTheme.warning, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${invoices.length} fatura(s) por pagar',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.warning,
                                    fontSize: 13),
                              ),
                              Text(
                                'Total: ${currency.format(total)}',
                                style: const TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close,
                              size: 18, color: AppTheme.textSecondary),
                          onPressed: () =>
                              setState(() => _dismissedInvoiceBanner = true),
                        ),
                      ],
                    ),
                  );
                },
              ),

            // ── Children cards ──
            Text(
              terms.isK12 ? 'Os Meus Educandos' : 'As Minhas Crianças',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            childrenAsync.when(
              loading: () => const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Text('Erro: $e'),
              ),
              data: (children) {
                if (children.isEmpty) {
                  return Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Center(
                      child: Text('Nenhum ${terms.student.toLowerCase()} associado',
                          style: const TextStyle(color: AppTheme.textSecondary)),
                    ),
                  );
                }
                return Column(
                  children: children
                      .map((child) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _ChildCard(child: child),
                          ))
                      .toList(),
                );
              },
            ),
            const SizedBox(height: 24),

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
                  child: _QuickLinkButton(
                    icon: Icons.chat_bubble_outline,
                    label: 'Mensagens',
                    color: AppTheme.secondary,
                    badge: unreadAsync.valueOrNull,
                    onTap: () => context.go('/messages'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _QuickLinkButton(
                    icon: Icons.photo_library_outlined,
                    label: 'Galeria',
                    color: AppTheme.success,
                    onTap: () => context.go('/photos'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _QuickLinkButton(
                    icon: Icons.menu_book_outlined,
                    label: 'Caderneta',
                    color: const Color(0xFF7C3AED),
                    onTap: () => context.go('/parent/caderneta'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),

            // ── Recent cadernetas ──
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Relatórios Recentes',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                TextButton(
                  onPressed: () => context.go('/parent/caderneta'),
                  child: const Text(
                    'Ver todos',
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
                          Text('Nenhum relatório disponível ainda',
                              style: TextStyle(
                                  color: AppTheme.textSecondary)),
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
                              DateFormat('dd/MM/yyyy').format(c.reportDate),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: AppTheme.textPrimary),
                            ),
                            subtitle: _buildRatingSummary(c),
                            trailing: const Icon(Icons.chevron_right,
                                size: 18, color: AppTheme.textSecondary),
                            onTap: () => context.go('/parent/caderneta'),
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

            // ── Invoices ──
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Faturas',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                TextButton(
                  onPressed: () => context.go('/parent/invoices'),
                  child: const Text('Ver todas',
                      style: TextStyle(color: AppTheme.primary, fontSize: 13, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            invoicesAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
              data: (invoices) {
                if (invoices.isEmpty) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: AppTheme.success.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.check_circle,
                              color: AppTheme.success, size: 20),
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'Sem faturas pendentes',
                          style: TextStyle(color: AppTheme.textSecondary),
                        ),
                      ],
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
                    children: invoices
                        .take(3)
                        .toList()
                        .asMap()
                        .entries
                        .map((entry) {
                      final isLast = entry.key ==
                          (invoices.length < 3 ? invoices.length - 1 : 2);
                      final inv = entry.value;
                      final isOverdue = inv.status == 'overdue';
                      return Column(
                        children: [
                          ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 4),
                            leading: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: AppTheme.warning.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.receipt_long,
                                  color: AppTheme.warning, size: 20),
                            ),
                            onTap: () => context.go('/parent/invoices'),
                            title: Text(
                              inv.description ?? inv.childName ?? 'Fatura',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: AppTheme.textPrimary),
                            ),
                            subtitle: Text(
                              currency.format(inv.totalAmount),
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.textSecondary),
                            ),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: isOverdue
                                    ? AppTheme.statusBg('overdue')
                                    : AppTheme.statusBg('pending'),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                isOverdue ? 'Em Atraso' : 'Pendente',
                                style: TextStyle(
                                    color: isOverdue
                                        ? AppTheme.statusText('overdue')
                                        : AppTheme.statusText('pending'),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
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

  Widget _buildRatingSummary(Caderneta c) {
    final parts = <String>[];
    if (c.lunchRating != null) parts.add('Almoço: ${c.lunchRating}');
    if (c.hadNap == true) parts.add('Dormiu');
    if (parts.isEmpty) return const Text('Ver detalhes');
    return Text(parts.join(' · '),
        style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary));
  }
}

// ---------------------------------------------------------------------------
// Widgets
// ---------------------------------------------------------------------------

class _ChildCard extends ConsumerWidget {
  final Child child;

  const _ChildCard({required this.child});

  void _showChildActions(BuildContext context, SchoolTerms terms) {
    final teacherLabel = terms.isK12 ? 'professor' : 'educador';
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                child.fullName,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
            const Divider(height: 1),
            _ActionTile(
              icon: Icons.menu_book_outlined,
              color: const Color(0xFF7C3AED),
              label: 'Caderneta',
              subtitle: 'Relatórios diários do $teacherLabel',
              onTap: () { Navigator.pop(context); context.go('/parent/caderneta'); },
            ),
            _ActionTile(
              icon: Icons.health_and_safety_outlined,
              color: AppTheme.success,
              label: 'Saúde',
              subtitle: 'Eventos de saúde e vacinas',
              onTap: () { Navigator.pop(context); context.go('/health'); },
            ),
            _ActionTile(
              icon: Icons.receipt_long_outlined,
              color: AppTheme.warning,
              label: 'Finanças',
              subtitle: 'Faturas e referências Multicaixa',
              onTap: () { Navigator.pop(context); context.go('/parent/invoices'); },
            ),
            _ActionTile(
              icon: Icons.assignment_outlined,
              color: AppTheme.primary,
              label: 'Autorizações',
              subtitle: 'Aprovações de passeios e levantamentos',
              onTap: () { Navigator.pop(context); context.go('/trip-authorizations'); },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final terms = SchoolTerms.of(ref.watch(schoolInfoProvider).valueOrNull);
    String? ageStr;
    if (child.birthDate != null) {
      final now = DateTime.now();
      final diff = now.difference(child.birthDate!);
      final years = (diff.inDays / 365.25).floor();
      final months = ((diff.inDays % 365.25) / 30.44).floor();
      if (years > 0) {
        ageStr = '$years ${years == 1 ? 'ano' : 'anos'}';
      } else {
        ageStr = '$months ${months == 1 ? 'mês' : 'meses'}';
      }
    }

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => _showChildActions(context, terms),
        borderRadius: BorderRadius.circular(12),
        child: Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          // Left accent border
          Container(
            width: 4,
            height: 76,
            decoration: const BoxDecoration(
              color: AppTheme.primary,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(12),
                bottomLeft: Radius.circular(12),
              ),
            ),
          ),
          const SizedBox(width: 16),
          _ChildAvatar(name: child.fullName, photoUrl: child.photoUrl),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    child.fullName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  if (child.turmaName != null)
                    Text(
                      child.turmaName!,
                      style: const TextStyle(
                          color: AppTheme.textSecondary, fontSize: 12),
                    ),
                  if (ageStr != null)
                    Text(
                      ageStr,
                      style: const TextStyle(
                          color: AppTheme.textSecondary, fontSize: 11),
                    ),
                ],
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(right: 16),
            child: Icon(Icons.chevron_right,
                color: AppTheme.textSecondary, size: 20),
          ),
        ],
      ),
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(label,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      subtitle: Text(subtitle,
          style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
      trailing: const Icon(Icons.chevron_right,
          size: 18, color: AppTheme.textSecondary),
      onTap: onTap,
    );
  }
}

class _ChildAvatar extends StatelessWidget {
  final String name;
  final String? photoUrl;

  const _ChildAvatar({required this.name, this.photoUrl});

  @override
  Widget build(BuildContext context) {
    if (photoUrl != null && photoUrl!.isNotEmpty) {
      return CircleAvatar(
        radius: 26,
        child: ClipOval(
          child: CachedNetworkImage(
            imageUrl: photoUrl!,
            width: 52,
            height: 52,
            fit: BoxFit.cover,
            errorWidget: (_, __, ___) => _initialsAvatar(),
          ),
        ),
      );
    }
    return _initialsAvatar();
  }

  Widget _initialsAvatar() {
    final initials = name.isNotEmpty
        ? name.trim().split(' ').take(2).map((w) => w[0]).join()
        : '?';
    return CircleAvatar(
      radius: 26,
      backgroundColor: AppTheme.primaryLight,
      child: Text(
        initials.toUpperCase(),
        style: const TextStyle(
          color: AppTheme.primary,
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
      ),
    );
  }
}

class _QuickLinkButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final int? badge;
  final VoidCallback onTap;

  const _QuickLinkButton({
    required this.icon,
    required this.label,
    required this.color,
    this.badge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(
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
                    top: -5,
                    right: -5,
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
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  color: AppTheme.textPrimary),
            ),
          ],
        ),
      ),
    );
  }
}
