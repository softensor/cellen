import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_client.dart';

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------
class Guardian {
  final String id;
  final String firstName;
  final String? middleName;
  final String lastName;
  final String? mobile;
  final String? email;
  final String? profession;
  final String? idCardNumber;

  const Guardian({
    required this.id,
    required this.firstName,
    this.middleName,
    required this.lastName,
    this.mobile,
    this.email,
    this.profession,
    this.idCardNumber,
  });

  String get fullName => [firstName, middleName, lastName]
      .where((p) => p != null && p.isNotEmpty)
      .join(' ');

  String get initials {
    final parts = fullName.trim().split(' ');
    return parts.length >= 2
        ? '${parts.first[0]}${parts.last[0]}'.toUpperCase()
        : fullName.isNotEmpty
            ? fullName[0].toUpperCase()
            : '?';
  }

  factory Guardian.fromJson(Map<String, dynamic> json) => Guardian(
        id: json['id']?.toString() ?? '',
        firstName: json['first_name'] as String? ?? '',
        middleName: json['middle_name'] as String?,
        lastName: json['last_name'] as String? ?? '',
        mobile: json['mobile_first'] as String?,
        email: json['email'] as String?,
        profession: json['profession'] as String?,
        idCardNumber: json['id_card_number'] as String?,
      );
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------
final guardiansProvider =
    FutureProvider.autoDispose<List<Guardian>>((ref) async {
  final api = ref.read(apiClientProvider);
  final data = await api.get('/guardians') as List;
  return data
      .map((e) => Guardian.fromJson(e as Map<String, dynamic>))
      .toList();
});

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------
class GuardiansListScreen extends ConsumerStatefulWidget {
  const GuardiansListScreen({super.key});

  @override
  ConsumerState<GuardiansListScreen> createState() =>
      _GuardiansListScreenState();
}

class _GuardiansListScreenState extends ConsumerState<GuardiansListScreen> {
  final _searchCtrl = TextEditingController();
  String _search = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final guardiansAsync = ref.watch(guardiansProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Encarregados'),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final created = await context.push<bool>('/admin/guardians/new');
          if (created == true) ref.invalidate(guardiansProvider);
        },
        tooltip: 'Adicionar Encarregado',
        child: const Icon(Icons.person_add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Pesquisar encarregado...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _search.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _search = '');
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _search = v.toLowerCase()),
            ),
          ),
          Expanded(
            child: guardiansAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline,
                        size: 48, color: Colors.red),
                    const SizedBox(height: 8),
                    Text(e.toString(), textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () => ref.invalidate(guardiansProvider),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Tentar novamente'),
                    ),
                  ],
                ),
              ),
              data: (guardians) {
                final filtered = _search.isEmpty
                    ? guardians
                    : guardians
                        .where((g) =>
                            g.fullName.toLowerCase().contains(_search) ||
                            (g.email?.toLowerCase().contains(_search) ??
                                false) ||
                            (g.mobile?.contains(_search) ?? false))
                        .toList();

                if (filtered.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.people,
                            size: 64,
                            color: Theme.of(context)
                                .colorScheme
                                .outlineVariant),
                        const SizedBox(height: 16),
                        Text(
                          'Nenhum encarregado encontrado',
                          style: Theme.of(context)
                              .textTheme
                              .bodyLarge
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async =>
                      ref.invalidate(guardiansProvider),
                  child: ListView.builder(
                    padding: const EdgeInsets.only(bottom: 88),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final g = filtered[index];
                      return _GuardianTile(
                        guardian: g,
                        onDeleted: () => ref.invalidate(guardiansProvider),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tile
// ---------------------------------------------------------------------------
class _GuardianTile extends ConsumerWidget {
  final Guardian guardian;
  final VoidCallback onDeleted;

  const _GuardianTile({required this.guardian, required this.onDeleted});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          radius: 24,
          backgroundColor:
              Theme.of(context).colorScheme.secondaryContainer,
          child: Text(
            guardian.initials,
            style: TextStyle(
              color:
                  Theme.of(context).colorScheme.onSecondaryContainer,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(
          guardian.fullName,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (guardian.mobile != null && guardian.mobile!.isNotEmpty)
              Row(
                children: [
                  const Icon(Icons.phone, size: 13, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(guardian.mobile!,
                      style: const TextStyle(fontSize: 13)),
                ],
              ),
            if (guardian.email != null && guardian.email!.isNotEmpty)
              Row(
                children: [
                  const Icon(Icons.email, size: 13, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(guardian.email!,
                      style: const TextStyle(fontSize: 13)),
                ],
              ),
            if (guardian.profession != null &&
                guardian.profession!.isNotEmpty)
              Text(guardian.profession!,
                  style: const TextStyle(
                      fontSize: 12, color: Colors.grey)),
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (action) async {
            if (action == 'edit') {
              final updated = await context
                  .push<bool>('/admin/guardians/${guardian.id}/edit');
              if (updated == true) onDeleted();
            } else if (action == 'delete') {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Eliminar Encarregado'),
                  content: Text(
                      'Tem a certeza que deseja eliminar ${guardian.fullName}?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancelar'),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(
                          foregroundColor: Colors.red),
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Eliminar'),
                    ),
                  ],
                ),
              );
              if (confirmed == true && context.mounted) {
                try {
                  final api = ref.read(apiClientProvider);
                  await api.delete('/guardians/${guardian.id}');
                  onDeleted();
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text('Erro ao eliminar: $e'),
                          backgroundColor: Colors.red),
                    );
                  }
                }
              }
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'edit', child: Text('Editar')),
            const PopupMenuItem(
                value: 'delete',
                child:
                    Text('Eliminar', style: TextStyle(color: Colors.red))),
          ],
        ),
        onTap: () async {
          final updated = await context
              .push<bool>('/admin/guardians/${guardian.id}/edit');
          if (updated == true) onDeleted();
        },
      ),
    );
  }
}
