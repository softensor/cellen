import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_client.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/models/child.dart';
import '../../../core/models/caderneta.dart';
import '../../../core/models/invoice.dart';

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------
final parentChildrenProvider =
    FutureProvider.autoDispose<List<Child>>((ref) async {
  final api = ref.read(apiClientProvider);
  final data = await api.get('/parent/children') as List;
  return data
      .map((e) => Child.fromJson(e as Map<String, dynamic>))
      .toList();
});

final parentRecentCadernetsProvider =
    FutureProvider.autoDispose<List<Caderneta>>((ref) async {
  final api = ref.read(apiClientProvider);
  final data = await api.get('/parent/cadernetas',
      queryParameters: {'limit': '3', 'ordering': '-report_date'}) as List;
  return data
      .map((e) => Caderneta.fromJson(e as Map<String, dynamic>))
      .toList();
});

final parentOutstandingInvoicesProvider =
    FutureProvider.autoDispose<List<Invoice>>((ref) async {
  final api = ref.read(apiClientProvider);
  final data = await api.get('/parent/invoices',
      queryParameters: {'status': 'pending,overdue'}) as List;
  return data
      .map((e) => Invoice.fromJson(e as Map<String, dynamic>))
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
  @override
  Widget build(BuildContext context) {
    final auth = ref.read(authProvider);
    final childrenAsync = ref.watch(parentChildrenProvider);
    final cadernetasAsync = ref.watch(parentRecentCadernetsProvider);
    final invoicesAsync = ref.watch(parentOutstandingInvoicesProvider);
    final unreadAsync = ref.watch(parentUnreadMessagesProvider);
    final currency = NumberFormat.currency(locale: 'pt_PT', symbol: '€');
    final now = DateTime.now();

    void refresh() {
      ref.invalidate(parentChildrenProvider);
      ref.invalidate(parentRecentCadernetsProvider);
      ref.invalidate(parentOutstandingInvoicesProvider);
      ref.invalidate(parentUnreadMessagesProvider);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Início'),
        actions: [
          unreadAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
            data: (count) => Stack(
              children: [
                IconButton(
                  icon: const Icon(Icons.notifications_outlined),
                  onPressed: () => context.push('/notifications'),
                ),
                if (count > 0)
                  Positioned(
                    right: 6,
                    top: 6,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      constraints:
                          const BoxConstraints(minWidth: 16, minHeight: 16),
                      child: Text(
                        count > 99 ? '99+' : '$count',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
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
              // Greeting
              Text(
                'Olá, ${auth.username ?? 'Encarregado'}!',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              Text(
                DateFormat('EEEE, d \'de\' MMMM', 'pt_PT').format(now),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color:
                          Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 16),

              // Children cards
              childrenAsync.when(
                loading: () => const SizedBox(
                  height: 120,
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('Erro: $e'),
                  ),
                ),
                data: (children) {
                  if (children.isEmpty) {
                    return const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('Nenhuma criança associada'),
                      ),
                    );
                  }
                  return Column(
                    children: children
                        .map((child) => _ChildCard(child: child))
                        .toList(),
                  );
                },
              ),
              const SizedBox(height: 16),

              // Outstanding invoices banner
              invoicesAsync.when(
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
                data: (invoices) {
                  if (invoices.isEmpty) return const SizedBox.shrink();
                  final total = invoices.fold<double>(
                      0.0, (sum, i) => sum + i.totalAmount);
                  return Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.orange.shade300),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber,
                            color: Colors.orange),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${invoices.length} fatura(s) por pagar',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.orange),
                              ),
                              Text(
                                'Total: ${currency.format(total)}',
                                style:
                                    const TextStyle(color: Colors.orange),
                              ),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: () => context.push('/messages'),
                          child: const Text('Ver'),
                        ),
                      ],
                    ),
                  );
                },
              ),

              // Quick links row
              Row(
                children: [
                  Expanded(
                    child: _QuickLinkCard(
                      icon: Icons.book,
                      label: 'Caderneta',
                      color: Colors.purple,
                      onTap: () => context.go('/parent/caderneta'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _QuickLinkCard(
                      icon: Icons.chat_bubble_outline,
                      label: 'Mensagens',
                      color: Colors.blue,
                      badge: unreadAsync.valueOrNull,
                      onTap: () => context.push('/messages'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _QuickLinkCard(
                      icon: Icons.photo_library,
                      label: 'Galeria',
                      color: Colors.teal,
                      onTap: () => context.push('/photos'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Recent cadernetas
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Relatórios Recentes',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  TextButton(
                    onPressed: () => context.go('/parent/caderneta'),
                    child: const Text('Ver todos'),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              cadernetasAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Text('Erro: $e'),
                data: (cadernetas) {
                  if (cadernetas.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                          child: Text(
                              'Nenhum relatório disponível ainda',
                              style: TextStyle(color: Colors.grey))),
                    );
                  }
                  return Column(
                    children: cadernetas.map((c) {
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Theme.of(context)
                                .colorScheme
                                .secondaryContainer,
                            child: Icon(Icons.book,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSecondaryContainer,
                                size: 18),
                          ),
                          title: Text(
                            DateFormat('dd/MM/yyyy')
                                .format(c.reportDate),
                            style: const TextStyle(
                                fontWeight: FontWeight.w600),
                          ),
                          subtitle: _buildRatingSummary(c),
                          trailing:
                              const Icon(Icons.chevron_right, size: 18),
                          onTap: () => context.go('/parent/caderneta'),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),

              const SizedBox(height: 24),

              // Faturas section
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Faturas',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              invoicesAsync.when(
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
                data: (invoices) {
                  if (invoices.isEmpty) {
                    return Card(
                      elevation: 0,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle,
                                color: Colors.green),
                            const SizedBox(width: 12),
                            Text(
                              'Sem faturas pendentes',
                              style: TextStyle(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  return Column(
                    children: invoices.take(2).map((inv) {
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor:
                                Colors.orange.withOpacity(0.15),
                            child: const Icon(Icons.receipt,
                                color: Colors.orange, size: 18),
                          ),
                          title: Text(
                            inv.description ?? inv.childName ?? 'Fatura',
                            style: const TextStyle(
                                fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(currency.format(inv.totalAmount)),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              inv.status == 'overdue' ? 'Em Atraso' : 'Pendente',
                              style: const TextStyle(
                                  color: Colors.orange,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600),
                            ),
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

  Widget _buildRatingSummary(Caderneta c) {
    final parts = <String>[];
    if (c.lunchRating != null) parts.add('Almoço: ${c.lunchRating}');
    if (c.hadNap == true) parts.add('Dormiu');
    if (parts.isEmpty) return const Text('Ver detalhes');
    return Text(parts.join(' · '), style: const TextStyle(fontSize: 12));
  }
}

// ---------------------------------------------------------------------------
// Widgets
// ---------------------------------------------------------------------------

class _ChildCard extends StatelessWidget {
  final Child child;

  const _ChildCard({required this.child});

  @override
  Widget build(BuildContext context) {
    // Calculate age
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

    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.primaryContainer,
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            _ChildAvatar(name: child.fullName, photoUrl: child.photoUrl),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    child.fullName,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context)
                              .colorScheme
                              .onPrimaryContainer,
                        ),
                  ),
                  if (child.turmaName != null)
                    Text(
                      child.turmaName!,
                      style: TextStyle(
                        color: Theme.of(context)
                            .colorScheme
                            .onPrimaryContainer
                            .withOpacity(0.75),
                        fontSize: 13,
                      ),
                    ),
                  if (ageStr != null)
                    Text(
                      ageStr,
                      style: TextStyle(
                        color: Theme.of(context)
                            .colorScheme
                            .onPrimaryContainer
                            .withOpacity(0.6),
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
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
        radius: 28,
        child: ClipOval(
          child: CachedNetworkImage(
            imageUrl: photoUrl!,
            width: 56,
            height: 56,
            fit: BoxFit.cover,
            errorWidget: (_, __, ___) => _initialsAvatar(context, 28),
          ),
        ),
      );
    }
    return _initialsAvatar(context, 28);
  }

  Widget _initialsAvatar(BuildContext context, double radius) {
    final initials = name.isNotEmpty
        ? name.trim().split(' ').take(2).map((w) => w[0]).join()
        : '?';
    return CircleAvatar(
      radius: radius,
      backgroundColor: Theme.of(context)
          .colorScheme
          .onPrimaryContainer
          .withOpacity(0.2),
      child: Text(
        initials.toUpperCase(),
        style: TextStyle(
          color: Theme.of(context).colorScheme.onPrimaryContainer,
          fontWeight: FontWeight.bold,
          fontSize: radius * 0.55,
        ),
      ),
    );
  }
}

class _QuickLinkCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final int? badge;
  final VoidCallback onTap;

  const _QuickLinkCard({
    required this.icon,
    required this.label,
    required this.color,
    this.badge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
            color: Theme.of(context).colorScheme.outline.withOpacity(0.15)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(icon, size: 28, color: color),
                  if (badge != null && badge! > 0)
                    Positioned(
                      top: -6,
                      right: -10,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(
                          color: Colors.red,
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
                    fontWeight: FontWeight.w600, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
