import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/models/child.dart';

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------
class PickupAuth {
  final String id;
  final String childId;
  final String? childName;
  final String authorizedName;
  final String? relationship;
  final String? phone;
  final String? idCardNumber;
  final String? notes;
  final bool isActive;

  const PickupAuth({
    required this.id,
    required this.childId,
    this.childName,
    required this.authorizedName,
    this.relationship,
    this.phone,
    this.idCardNumber,
    this.notes,
    required this.isActive,
  });

  factory PickupAuth.fromJson(Map<String, dynamic> json) => PickupAuth(
        id: json['id']?.toString() ?? '',
        childId: json['child_id']?.toString() ?? '',
        childName: json['child_name'] as String?,
        authorizedName: json['authorized_name'] as String? ?? '',
        relationship: json['relationship'] as String?,
        phone: json['phone'] as String?,
        idCardNumber: json['id_card_number'] as String?,
        notes: json['notes'] as String?,
        isActive: json['is_active'] as bool? ?? true,
      );
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------
final pickupAuthsProvider =
    FutureProvider.autoDispose<List<PickupAuth>>((ref) async {
  final api = ref.read(apiClientProvider);
  final data = await api.get('/pickup-authorizations') as List;
  return data.map((e) => PickupAuth.fromJson(e as Map<String, dynamic>)).toList();
});

final childrenForPickupProvider =
    FutureProvider.autoDispose<List<Child>>((ref) async {
  final api = ref.read(apiClientProvider);
  final auth = ref.read(authProvider);
  final endpoint = auth.isParent ? '/children/my' : '/children';
  final data = await api.get(endpoint) as List;
  return data.map((e) => Child.fromJson(e as Map<String, dynamic>)).toList();
});

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------
class PickupAuthorizationsScreen extends ConsumerStatefulWidget {
  const PickupAuthorizationsScreen({super.key});

  @override
  ConsumerState<PickupAuthorizationsScreen> createState() =>
      _PickupAuthorizationsScreenState();
}

class _PickupAuthorizationsScreenState
    extends ConsumerState<PickupAuthorizationsScreen> {
  String? _childFilter;

  @override
  Widget build(BuildContext context) {
    final authsAsync = ref.watch(pickupAuthsProvider);
    final childrenAsync = ref.watch(childrenForPickupProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Autorizações de Levantamento'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(pickupAuthsProvider),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddDialog(context),
        icon: const Icon(Icons.person_add),
        label: const Text('Adicionar'),
      ),
      body: Column(
        children: [
          // Child filter
          childrenAsync.maybeWhen(
            data: (children) => children.length > 1
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: DropdownButtonFormField<String?>(
                      value: _childFilter,
                      decoration: const InputDecoration(
                        labelText: 'Filtrar por criança',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        const DropdownMenuItem(
                            value: null, child: Text('Todas')),
                        ...children.map((c) => DropdownMenuItem(
                            value: c.id, child: Text(c.fullName))),
                      ],
                      onChanged: (v) => setState(() => _childFilter = v),
                    ),
                  )
                : const SizedBox.shrink(),
            orElse: () => const SizedBox.shrink(),
          ),
          Expanded(
            child: authsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
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
                      onPressed: () => ref.invalidate(pickupAuthsProvider),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Tentar novamente'),
                    ),
                  ],
                ),
              ),
              data: (auths) {
                final filtered = _childFilter == null
                    ? auths
                    : auths
                        .where((a) => a.childId == _childFilter)
                        .toList();

                if (filtered.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.people_outline,
                            size: 64,
                            color: Theme.of(context)
                                .colorScheme
                                .outlineVariant),
                        const SizedBox(height: 16),
                        Text(
                          'Nenhuma pessoa autorizada registada',
                          style: Theme.of(context)
                              .textTheme
                              .bodyLarge
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Adicione pessoas autorizadas a levantar crianças',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 13, color: Colors.grey),
                        ),
                      ],
                    ),
                  );
                }

                // Group by child
                final grouped = <String, List<PickupAuth>>{};
                for (final a in filtered) {
                  grouped.putIfAbsent(a.childId, () => []).add(a);
                }

                return RefreshIndicator(
                  onRefresh: () async =>
                      ref.invalidate(pickupAuthsProvider),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                    children: grouped.entries.map((entry) {
                      final childName =
                          entry.value.first.childName ?? 'Criança';
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(
                                left: 4, bottom: 6, top: 8),
                            child: Text(
                              childName,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary,
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                          ),
                          ...entry.value.map((auth) => _PickupCard(
                                auth: auth,
                                onChanged: () =>
                                    ref.invalidate(pickupAuthsProvider),
                              )),
                        ],
                      );
                    }).toList(),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddDialog(BuildContext context) async {
    final childrenState = ref.read(childrenForPickupProvider);
    final children = childrenState.valueOrNull ?? [];
    await showDialog(
      context: context,
      builder: (_) => _AddPickupDialog(
        children: children,
        onAdded: () => ref.invalidate(pickupAuthsProvider),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pickup card
// ---------------------------------------------------------------------------
class _PickupCard extends ConsumerWidget {
  final PickupAuth auth;
  final VoidCallback onChanged;

  const _PickupCard({required this.auth, required this.onChanged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: auth.isActive
              ? Theme.of(context).colorScheme.primaryContainer
              : Colors.grey.shade200,
          child: Icon(
            Icons.person,
            color: auth.isActive
                ? Theme.of(context).colorScheme.onPrimaryContainer
                : Colors.grey,
          ),
        ),
        title: Text(
          auth.authorizedName,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: auth.isActive ? null : Colors.grey,
            decoration:
                auth.isActive ? null : TextDecoration.lineThrough,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (auth.relationship != null)
              Text(auth.relationship!,
                  style: const TextStyle(fontSize: 12)),
            if (auth.phone != null)
              Row(
                children: [
                  const Icon(Icons.phone, size: 12, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(auth.phone!,
                      style: const TextStyle(fontSize: 12)),
                ],
              ),
            if (auth.idCardNumber != null)
              Row(
                children: [
                  const Icon(Icons.badge, size: 12, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text('BI: ${auth.idCardNumber!}',
                      style: const TextStyle(fontSize: 12)),
                ],
              ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (action) async {
            final api = ref.read(apiClientProvider);
            if (action == 'toggle') {
              await api.patch('/pickup-authorizations/${auth.id}',
                  data: {'is_active': !auth.isActive});
              onChanged();
            } else if (action == 'delete') {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Remover Autorização'),
                  content: Text(
                      'Remover ${auth.authorizedName} da lista de autorizados?'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancelar')),
                    TextButton(
                      style: TextButton.styleFrom(
                          foregroundColor: Colors.red),
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Remover'),
                    ),
                  ],
                ),
              );
              if (confirmed == true) {
                await api.delete('/pickup-authorizations/${auth.id}');
                onChanged();
              }
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'toggle',
              child: Text(
                  auth.isActive ? 'Desactivar' : 'Activar'),
            ),
            const PopupMenuItem(
              value: 'delete',
              child: Text('Remover',
                  style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Add dialog
// ---------------------------------------------------------------------------
class _AddPickupDialog extends ConsumerStatefulWidget {
  final List<Child> children;
  final VoidCallback onAdded;

  const _AddPickupDialog(
      {required this.children, required this.onAdded});

  @override
  ConsumerState<_AddPickupDialog> createState() =>
      _AddPickupDialogState();
}

class _AddPickupDialogState extends ConsumerState<_AddPickupDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _idCardCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  String? _selectedChildId;
  String? _relationship;
  bool _isLoading = false;
  String? _error;

  static const _relationships = [
    'Pai', 'Mãe', 'Avô/Avó', 'Tio/Tia', 'Irmão/Irmã',
    'Vizinho(a)', 'Amigo(a) da família', 'Outro',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.children.length == 1) {
      _selectedChildId = widget.children.first.id;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _idCardCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedChildId == null) {
      setState(() => _error = 'Seleccione uma criança');
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      await api.post('/pickup-authorizations', data: {
        'child_id': _selectedChildId,
        'authorized_name': _nameCtrl.text.trim(),
        if (_relationship != null) 'relationship': _relationship,
        if (_phoneCtrl.text.trim().isNotEmpty)
          'phone': _phoneCtrl.text.trim(),
        if (_idCardCtrl.text.trim().isNotEmpty)
          'id_card_number': _idCardCtrl.text.trim(),
        if (_notesCtrl.text.trim().isNotEmpty)
          'notes': _notesCtrl.text.trim(),
      });
      widget.onAdded();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Adicionar Pessoa Autorizada'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_error != null)
                  Container(
                    padding: const EdgeInsets.all(10),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8)),
                    child: Text(_error!,
                        style:
                            TextStyle(color: Colors.red.shade800)),
                  ),
                if (widget.children.length > 1)
                  DropdownButtonFormField<String>(
                    value: _selectedChildId,
                    decoration: const InputDecoration(
                        labelText: 'Criança *',
                        border: OutlineInputBorder()),
                    items: widget.children
                        .map((c) => DropdownMenuItem(
                            value: c.id, child: Text(c.fullName)))
                        .toList(),
                    onChanged: (v) =>
                        setState(() => _selectedChildId = v),
                    validator: (v) =>
                        v == null ? 'Obrigatório' : null,
                  ),
                if (widget.children.length > 1)
                  const SizedBox(height: 12),
                TextFormField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Nome completo *',
                      border: OutlineInputBorder()),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Obrigatório'
                      : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _relationship,
                  decoration: const InputDecoration(
                      labelText: 'Parentesco / Relação',
                      border: OutlineInputBorder()),
                  items: _relationships
                      .map((r) =>
                          DropdownMenuItem(value: r, child: Text(r)))
                      .toList(),
                  onChanged: (v) =>
                      setState(() => _relationship = v),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phoneCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Telemóvel',
                      border: OutlineInputBorder()),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _idCardCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Nº Bilhete de Identidade',
                      border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _notesCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Notas',
                      border: OutlineInputBorder()),
                  maxLines: 2,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _isLoading ? null : _submit,
          child: _isLoading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Text('Adicionar'),
        ),
      ],
    );
  }
}
