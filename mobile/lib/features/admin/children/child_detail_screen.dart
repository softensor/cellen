import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_client.dart';
import '../../../core/models/child.dart';
import '../../../core/models/guardian.dart';
import '../../../core/models/caderneta.dart';
import '../../../core/models/invoice.dart';
import 'children_list_screen.dart' show childrenProvider;

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------
final childProvider =
    FutureProvider.autoDispose.family<Child, String>((ref, id) async {
  final api = ref.read(apiClientProvider);
  final data = await api.get('/children/$id');
  return Child.fromJson(data as Map<String, dynamic>);
});

final childGuardiansProvider =
    FutureProvider.autoDispose.family<List<Guardian>, String>((ref, id) async {
  final api = ref.read(apiClientProvider);
  final data = await api.get('/children/$id/guardians') as List;
  return data
      .map((e) => Guardian.fromJson(e as Map<String, dynamic>))
      .toList();
});

final childCadernetasProvider =
    FutureProvider.autoDispose.family<List<Caderneta>, String>((ref, id) async {
  final api = ref.read(apiClientProvider);
  final data = await api.get('/children/$id/cadernetas') as List;
  return data
      .map((e) => Caderneta.fromJson(e as Map<String, dynamic>))
      .toList();
});

final childInvoicesProvider =
    FutureProvider.autoDispose.family<List<Invoice>, String>((ref, id) async {
  final api = ref.read(apiClientProvider);
  final data = await api.get('/children/$id/invoices') as List;
  return data
      .map((e) => Invoice.fromJson(e as Map<String, dynamic>))
      .toList();
});

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------
class ChildDetailScreen extends ConsumerWidget {
  final String id;

  const ChildDetailScreen({super.key, required this.id});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final childAsync = ref.watch(childProvider(id));

    return childAsync.when(
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('Criança')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: const Text('Criança')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 8),
              Text(e.toString()),
              TextButton(
                onPressed: () => ref.invalidate(childProvider(id)),
                child: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
      ),
      data: (child) => _ChildDetailView(child: child),
    );
  }
}

class _ChildDetailView extends ConsumerWidget {
  final Child child;

  const _ChildDetailView({required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(child.fullName),
          actions: [
            IconButton(
              icon: const Icon(Icons.edit),
              tooltip: 'Editar',
              onPressed: () =>
                  context.push('/admin/children/${child.id}/edit'),
            ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Informação'),
              Tab(text: 'Encarregados'),
              Tab(text: 'Caderneta'),
              Tab(text: 'Facturas'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _InfoTab(child: child),
            _GuardiansTab(childId: child.id),
            _CadernetaTab(childId: child.id),
            _InvoicesTab(childId: child.id),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Info Tab
// ---------------------------------------------------------------------------
class _InfoTab extends StatelessWidget {
  final Child child;
  const _InfoTab({required this.child});

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd/MM/yyyy');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Photo + name header
          Center(
            child: Column(
              children: [
                _ChildPhotoAvatar(
                    photoUrl: child.photoUrl,
                    name: child.fullName,
                    radius: 48),
                const SizedBox(height: 12),
                Text(
                  child.fullName,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                if (child.turmaName != null)
                  Chip(
                    label: Text(child.turmaName!),
                    avatar: const Icon(Icons.school, size: 16),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          _SectionTitle('Dados Pessoais'),
          _InfoRow('Cédula', child.cedula),
          if (child.birthDate != null)
            _InfoRow('Data de Nascimento', df.format(child.birthDate!)),
          _InfoRow('Sexo', child.sexLabel),
          if (!child.isActive)
            _InfoRow('Estado', 'Inactivo'),

          if (child.specialNeeds != null &&
              child.specialNeeds!.isNotEmpty) ...[
            const SizedBox(height: 16),
            _SectionTitle('Necessidades Especiais'),
            Text(child.specialNeeds!),
          ],

          if (child.medicalPrescription != null &&
              child.medicalPrescription!.isNotEmpty) ...[
            const SizedBox(height: 16),
            _SectionTitle('Prescrição Médica'),
            Text(child.medicalPrescription!),
          ],

          if (child.address != null && child.address!.isNotEmpty) ...[
            const SizedBox(height: 16),
            _SectionTitle('Morada'),
            _InfoRow('Endereço', child.address!),
            if (child.addressCity != null)
              _InfoRow('Cidade', child.addressCity!),
            if (child.addressPostalCode != null)
              _InfoRow('Código Postal', child.addressPostalCode!),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Guardians Tab
// ---------------------------------------------------------------------------
class _GuardiansTab extends ConsumerWidget {
  final String childId;
  const _GuardiansTab({required this.childId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final guardiansAsync = ref.watch(childGuardiansProvider(childId));
    return guardiansAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Erro: $e'),
            TextButton(
              onPressed: () =>
                  ref.invalidate(childGuardiansProvider(childId)),
              child: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
      data: (guardians) {
        if (guardians.isEmpty) {
          return const Center(
            child: Text('Nenhum encarregado registado'),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: guardians.length,
          itemBuilder: (context, i) {
            final g = guardians[i];
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(child: Text(g.fullName[0])),
                title: Text(g.fullName),
                subtitle: Text(g.relationshipLabel),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (g.isPrimary)
                      const Chip(
                          label: Text('Principal',
                              style: TextStyle(fontSize: 11))),
                    if (g.authorizedPickup)
                      const Text('Autorizado recolha',
                          style: TextStyle(fontSize: 11, color: Colors.green)),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Caderneta Tab
// ---------------------------------------------------------------------------
class _CadernetaTab extends ConsumerWidget {
  final String childId;
  const _CadernetaTab({required this.childId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(childCadernetasProvider(childId));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Erro: $e')),
      data: (cadernetas) {
        if (cadernetas.isEmpty) {
          return const Center(
              child: Text('Nenhuma caderneta registada'));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: cadernetas.length,
          itemBuilder: (context, i) {
            final c = cadernetas[i];
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: const Icon(Icons.book),
                title: Text(DateFormat('dd/MM/yyyy').format(c.reportDate)),
                subtitle: Text(
                  [
                    if (c.breakfastRating != null)
                      'Pequeno-almoço: ${c.breakfastRating}',
                    if (c.lunchRating != null) 'Almoço: ${c.lunchRating}',
                  ].join(' · '),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Invoices Tab
// ---------------------------------------------------------------------------
class _InvoicesTab extends ConsumerWidget {
  final String childId;
  const _InvoicesTab({required this.childId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(childInvoicesProvider(childId));
    final currency = NumberFormat.currency(locale: 'pt_PT', symbol: '€');

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Erro: $e')),
      data: (invoices) {
        if (invoices.isEmpty) {
          return const Center(child: Text('Nenhuma factura encontrada'));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: invoices.length,
          itemBuilder: (context, i) {
            final inv = invoices[i];
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(
                    DateFormat('MMMM yyyy', 'pt_PT')
                        .format(inv.referenceMonth),
                    style:
                        const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(currency.format(inv.totalAmount)),
                trailing: _StatusChip(status: inv.status, label: inv.statusLabel),
              ),
            );
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Shared widgets
// ---------------------------------------------------------------------------

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 160,
            child: Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  final String label;
  const _StatusChip({required this.status, required this.label});

  @override
  Widget build(BuildContext context) {
    Color color;
    switch (status) {
      case 'paid':
        color = Colors.green;
        break;
      case 'overdue':
        color = Colors.red;
        break;
      case 'partially_paid':
        color = Colors.orange;
        break;
      case 'cancelled':
        color = Colors.grey;
        break;
      default:
        color = Colors.blue;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        label,
        style:
            TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _ChildPhotoAvatar extends StatelessWidget {
  final String? photoUrl;
  final String name;
  final double radius;
  const _ChildPhotoAvatar(
      {this.photoUrl, required this.name, this.radius = 24});

  @override
  Widget build(BuildContext context) {
    if (photoUrl != null && photoUrl!.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundImage: NetworkImage(
            '$kMediaBase${photoUrl!.startsWith('/') ? photoUrl! : '/$photoUrl'}'),
        onBackgroundImageError: (_, __) {},
      );
    }
    final initials = name.isNotEmpty
        ? name.trim().split(' ').take(2).map((w) => w[0]).join()
        : '?';
    return CircleAvatar(
      radius: radius,
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      child: Text(
        initials.toUpperCase(),
        style: TextStyle(
          color: Theme.of(context).colorScheme.onPrimaryContainer,
          fontWeight: FontWeight.bold,
          fontSize: radius * 0.6,
        ),
      ),
    );
  }
}
