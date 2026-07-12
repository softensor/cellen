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
class _GuardiansTab extends ConsumerStatefulWidget {
  final String childId;
  const _GuardiansTab({required this.childId});

  @override
  ConsumerState<_GuardiansTab> createState() => _GuardiansTabState();
}

class _GuardiansTabState extends ConsumerState<_GuardiansTab> {
  static const _relationships = [
    ('father', 'Pai'),
    ('mother', 'Mãe'),
    ('grandparent', 'Avô/Avó'),
    ('legal_guardian', 'Tutor Legal'),
    ('sibling', 'Irmão/Irmã'),
    ('uncle_aunt', 'Tio/Tia'),
    ('other', 'Outro'),
  ];

  Future<void> _showLinkDialog() async {
    // Load all school guardians
    final api = ref.read(apiClientProvider);
    List allGuardians = [];
    try {
      allGuardians = await api.get('/guardians') as List;
    } catch (_) {
      return;
    }

    if (!mounted) return;

    String? selectedGuardianId;
    String selectedRelationship = 'father';
    bool isPrimary = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Ligar Encarregado'),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                      labelText: 'Encarregado *',
                      border: OutlineInputBorder()),
                  items: allGuardians
                      .map((g) => DropdownMenuItem<String>(
                            value: g['id'].toString(),
                            child: Text(
                                '${g['first_name']} ${g['last_name']}'),
                          ))
                      .toList(),
                  onChanged: (v) => setS(() => selectedGuardianId = v),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: selectedRelationship,
                  decoration: const InputDecoration(
                      labelText: 'Parentesco',
                      border: OutlineInputBorder()),
                  items: _relationships
                      .map((r) => DropdownMenuItem(
                          value: r.$1, child: Text(r.$2)))
                      .toList(),
                  onChanged: (v) =>
                      setS(() => selectedRelationship = v!),
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  value: isPrimary,
                  onChanged: (v) => setS(() => isPrimary = v!),
                  title: const Text('Contacto principal'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: selectedGuardianId == null
                  ? null
                  : () async {
                      try {
                        await api.post(
                          '/guardians/$selectedGuardianId/children',
                          data: {
                            'child_id': widget.childId,
                            'relationship_type': selectedRelationship,
                            'is_primary_contact': isPrimary,
                          },
                        );
                        ref.invalidate(childGuardiansProvider(widget.childId));
                        if (mounted) Navigator.pop(ctx);
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(e.toString())));
                        }
                      }
                    },
              child: const Text('Ligar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _unlink(String guardianId, String guardianName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remover ligação'),
        content: Text('Remover $guardianName desta criança?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final api = ref.read(apiClientProvider);
      try {
        await api.delete('/guardians/$guardianId/children/${widget.childId}');
        ref.invalidate(childGuardiansProvider(widget.childId));
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(e.toString())));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final guardiansAsync = ref.watch(childGuardiansProvider(widget.childId));
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showLinkDialog,
        icon: const Icon(Icons.person_add),
        label: const Text('Ligar Encarregado'),
      ),
      body: guardiansAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Erro: $e'),
              TextButton(
                onPressed: () =>
                    ref.invalidate(childGuardiansProvider(widget.childId)),
                child: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
        data: (guardians) {
          if (guardians.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.people_outline,
                      size: 64,
                      color: Theme.of(context).colorScheme.outlineVariant),
                  const SizedBox(height: 16),
                  const Text('Nenhum encarregado ligado'),
                  const SizedBox(height: 8),
                  const Text('Use o botão abaixo para ligar um encarregado',
                      style: TextStyle(color: Colors.grey, fontSize: 13)),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
            itemCount: guardians.length,
            itemBuilder: (context, i) {
              final g = guardians[i];
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: CircleAvatar(child: Text(g.fullName[0])),
                  title: Text(g.fullName),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(g.relationshipLabel),
                      if (g.phone != null)
                        Text(g.phone!,
                            style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (g.isPrimary)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .primaryContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text('Principal',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onPrimaryContainer)),
                        ),
                      IconButton(
                        icon: const Icon(Icons.link_off,
                            color: Colors.red, size: 20),
                        tooltip: 'Remover ligação',
                        onPressed: () => _unlink(g.id, g.fullName),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
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
