import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_client.dart';
import '../../../core/models/food.dart';

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

final adminMenusProvider = FutureProvider.autoDispose<List<FoodMenu>>((ref) async {
  final api = ref.read(apiClientProvider);
  final data = await api.get('/food/menus') as List;
  return data.map((e) => FoodMenu.fromJson(e as Map<String, dynamic>)).toList();
});

final adminFoodsProvider = FutureProvider.autoDispose<List<_FoodItem>>((ref) async {
  final api = ref.read(apiClientProvider);
  final data = await api.get('/food/foods') as List;
  return data.map((e) => _FoodItem.fromJson(e as Map<String, dynamic>)).toList();
});

// ---------------------------------------------------------------------------
// Simple models for this screen
// ---------------------------------------------------------------------------

class _FoodItem {
  final String id;
  final String name;
  final String? foodType;

  const _FoodItem({required this.id, required this.name, this.foodType});

  factory _FoodItem.fromJson(Map<String, dynamic> json) => _FoodItem(
        id: json['id']?.toString() ?? '',
        name: json['name'] as String? ?? '',
        foodType: json['food_type'] as String?,
      );

  @override
  String toString() => name;
}

// ---------------------------------------------------------------------------
// Main screen
// ---------------------------------------------------------------------------

class AdminFoodScreen extends ConsumerWidget {
  const AdminFoodScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final menusAsync = ref.watch(adminMenusProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ementas Semanais'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(adminMenusProvider),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateMenuDialog(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Nova Ementa'),
      ),
      body: menusAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 8),
              Text(e.toString()),
              TextButton(
                onPressed: () => ref.invalidate(adminMenusProvider),
                child: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
        data: (menus) {
          if (menus.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.restaurant_menu,
                      size: 64,
                      color: Theme.of(context).colorScheme.outlineVariant),
                  const SizedBox(height: 16),
                  const Text('Nenhuma ementa criada'),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: () => _showCreateMenuDialog(context, ref),
                    icon: const Icon(Icons.add),
                    label: const Text('Criar Ementa'),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
            itemCount: menus.length,
            itemBuilder: (context, i) {
              return _MenuCard(
                menu: menus[i],
                onManage: () => _openMenuDetail(context, ref, menus[i]),
                onDelete: () => _deleteMenu(context, ref, menus[i].id),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _showCreateMenuDialog(BuildContext context, WidgetRef ref) async {
    await showDialog(
      context: context,
      builder: (ctx) => _CreateMenuDialog(
        onCreated: () => ref.invalidate(adminMenusProvider),
      ),
    );
  }

  void _openMenuDetail(BuildContext context, WidgetRef ref, FoodMenu menu) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _MenuDetailPage(menu: menu, onChanged: () => ref.invalidate(adminMenusProvider)),
      ),
    );
  }

  Future<void> _deleteMenu(BuildContext context, WidgetRef ref, String menuId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar Ementa'),
        content: const Text('Tem a certeza que deseja eliminar esta ementa e todos os seus itens?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(apiClientProvider).delete('/food/menus/$menuId');
      ref.invalidate(adminMenusProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ementa eliminada')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e')),
        );
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Menu card
// ---------------------------------------------------------------------------

class _MenuCard extends StatelessWidget {
  final FoodMenu menu;
  final VoidCallback onManage;
  final VoidCallback onDelete;

  const _MenuCard({required this.menu, required this.onManage, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('d MMM yyyy', 'pt_PT');
    final isActive = DateTime.now().isAfter(menu.startDate) &&
        DateTime.now().isBefore(menu.endDate.add(const Duration(days: 1)));

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onManage,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: isActive
                      ? Colors.green.withOpacity(0.12)
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.restaurant_menu,
                  color: isActive ? Colors.green : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          menu.level.isNotEmpty ? menu.level.toUpperCase() : 'Geral',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(width: 8),
                        if (isActive)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.green.withOpacity(0.4)),
                            ),
                            child: const Text(
                              'Activa',
                              style: TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.w600),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${df.format(menu.startDate)} — ${df.format(menu.endDate)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Text(
                      '${menu.items.length} item(s)',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'manage') onManage();
                  if (v == 'delete') onDelete();
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'manage', child: Text('Gerir itens')),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text('Eliminar', style: TextStyle(color: Colors.red)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Create menu dialog
// ---------------------------------------------------------------------------

class _CreateMenuDialog extends ConsumerStatefulWidget {
  final VoidCallback onCreated;
  const _CreateMenuDialog({required this.onCreated});

  @override
  ConsumerState<_CreateMenuDialog> createState() => _CreateMenuDialogState();
}

class _CreateMenuDialogState extends ConsumerState<_CreateMenuDialog> {
  final _levelCtrl = TextEditingController(text: 'Jardim');
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now().add(const Duration(days: 6));
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _levelCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isStart}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _startDate : _endDate,
      firstDate: DateTime(2024),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
          if (_endDate.isBefore(_startDate)) _endDate = _startDate.add(const Duration(days: 6));
        } else {
          _endDate = picked;
        }
      });
    }
  }

  Future<void> _create() async {
    setState(() { _loading = true; _error = null; });
    try {
      final df = DateFormat('yyyy-MM-dd');
      await ref.read(apiClientProvider).post('/food/menus', data: {
        'level': _levelCtrl.text.trim(),
        'start_date': df.format(_startDate),
        'end_date': df.format(_endDate),
        'items': [],
      });
      widget.onCreated();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('d MMM yyyy', 'pt_PT');
    return AlertDialog(
      title: const Text('Nova Ementa'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer)),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _levelCtrl,
              decoration: const InputDecoration(
                labelText: 'Nível / Turma',
                hintText: 'ex: Jardim, Pré-escolar, Geral',
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => _pickDate(isStart: true),
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Data início',
                        suffixIcon: Icon(Icons.calendar_today, size: 18),
                      ),
                      child: Text(df.format(_startDate)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: InkWell(
                    onTap: () => _pickDate(isStart: false),
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Data fim',
                        suffixIcon: Icon(Icons.calendar_today, size: 18),
                      ),
                      child: Text(df.format(_endDate)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _loading ? null : _create,
          child: _loading
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Criar'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Menu detail page — add / remove items
// ---------------------------------------------------------------------------

class _MenuDetailPage extends ConsumerStatefulWidget {
  final FoodMenu menu;
  final VoidCallback onChanged;

  const _MenuDetailPage({required this.menu, required this.onChanged});

  @override
  ConsumerState<_MenuDetailPage> createState() => _MenuDetailPageState();
}

class _MenuDetailPageState extends ConsumerState<_MenuDetailPage> {
  late List<FoodMenuItemEntry> _items;

  @override
  void initState() {
    super.initState();
    _items = List.from(widget.menu.items);
  }

  static const _dayNames = ['Segunda', 'Terça', 'Quarta', 'Quinta', 'Sexta'];
  static const _mealTypes = ['breakfast', 'lunch', 'snack'];
  static const _mealLabels = {'breakfast': 'Pequeno-almoço', 'lunch': 'Almoço', 'snack': 'Lanche'};
  static const _components = ['sopa', 'prato', 'sobremesa', 'drink'];
  static const _componentLabels = {
    'sopa': 'Sopa',
    'prato': 'Prato',
    'sobremesa': 'Sobremesa',
    'drink': 'Bebida',
  };

  Future<void> _addItem() async {
    final foodsAsync = ref.read(adminFoodsProvider);
    final foods = foodsAsync.valueOrNull ?? [];

    if (foods.isEmpty) {
      // Try loading
      ref.invalidate(adminFoodsProvider);
    }

    int selectedDay = 1;
    String selectedMealType = 'lunch';
    String? selectedComponent;
    _FoodItem? selectedFood;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Adicionar Item'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  value: selectedDay,
                  decoration: const InputDecoration(labelText: 'Dia da semana'),
                  items: List.generate(5, (i) => DropdownMenuItem(
                    value: i + 1,
                    child: Text(_dayNames[i]),
                  )),
                  onChanged: (v) => setS(() => selectedDay = v!),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: selectedMealType,
                  decoration: const InputDecoration(labelText: 'Refeição'),
                  items: _mealTypes.map((t) => DropdownMenuItem(
                    value: t,
                    child: Text(_mealLabels[t] ?? t),
                  )).toList(),
                  onChanged: (v) => setS(() => selectedMealType = v!),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  value: selectedComponent,
                  decoration: const InputDecoration(labelText: 'Componente (opcional)'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('—')),
                    ..._components.map((c) => DropdownMenuItem(
                      value: c,
                      child: Text(_componentLabels[c] ?? c),
                    )),
                  ],
                  onChanged: (v) => setS(() => selectedComponent = v),
                ),
                const SizedBox(height: 12),
                Consumer(
                  builder: (_, ref2, __) {
                    final foodsA = ref2.watch(adminFoodsProvider);
                    return foodsA.when(
                      loading: () => const LinearProgressIndicator(),
                      error: (e, _) => Text('Erro ao carregar alimentos: $e',
                          style: const TextStyle(color: Colors.red)),
                      data: (items) => DropdownButtonFormField<_FoodItem>(
                        value: selectedFood,
                        decoration: const InputDecoration(labelText: 'Alimento'),
                        items: items.map((f) => DropdownMenuItem(
                          value: f,
                          child: Text(f.name),
                        )).toList(),
                        onChanged: (v) => setS(() => selectedFood = v),
                      ),
                    );
                  },
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
              onPressed: selectedFood == null ? null : () async {
                try {
                  await ref.read(apiClientProvider).post(
                    '/food/menus/${widget.menu.id}/items',
                    data: {
                      'day_of_week': selectedDay,
                      'meal_type': selectedMealType,
                      'meal_component': selectedComponent,
                      'food_id': selectedFood!.id,
                    },
                  );
                  if (ctx.mounted) Navigator.pop(ctx, true);
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(content: Text('Erro: $e')),
                    );
                  }
                }
              },
              child: const Text('Adicionar'),
            ),
          ],
        ),
      ),
    );

    // Reload detail from server
    await _reload();
  }

  Future<void> _reload() async {
    try {
      final data = await ref.read(apiClientProvider).get('/food/menus/${widget.menu.id}')
          as Map<String, dynamic>;
      final updated = FoodMenu.fromJson(data);
      setState(() => _items = List.from(updated.items));
      widget.onChanged();
    } catch (_) {}
  }

  Future<void> _addFood() async {
    final nameCtrl = TextEditingController();
    String selectedType = 'lunch';
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Novo Alimento'),
          content: SizedBox(
            width: 300,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nome do alimento',
                    hintText: 'ex: Arroz com Frango',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: selectedType,
                  decoration: const InputDecoration(labelText: 'Tipo'),
                  items: const [
                    DropdownMenuItem(value: 'breakfast', child: Text('Pequeno-almoço')),
                    DropdownMenuItem(value: 'lunch', child: Text('Almoço')),
                    DropdownMenuItem(value: 'snack', child: Text('Lanche')),
                    DropdownMenuItem(value: 'other', child: Text('Outro')),
                  ],
                  onChanged: (v) => setS(() => selectedType = v!),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty) return;
                try {
                  await ref.read(apiClientProvider).post('/food/foods', data: {
                    'name': nameCtrl.text.trim(),
                    'food_type': selectedType,
                  });
                  ref.invalidate(adminFoodsProvider);
                  if (ctx.mounted) Navigator.pop(ctx);
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Erro: $e')));
                  }
                }
              },
              child: const Text('Criar'),
            ),
          ],
        ),
      ),
    );
    nameCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('d MMM yyyy', 'pt_PT');

    // Group items by day
    final byDay = <int, List<FoodMenuItemEntry>>{};
    for (final item in _items) {
      byDay.putIfAbsent(item.dayOfWeek, () => []).add(item);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.menu.level.isNotEmpty ? widget.menu.level : 'Ementa'),
        actions: [
          TextButton.icon(
            onPressed: _addFood,
            icon: const Icon(Icons.restaurant),
            label: const Text('Novo Alimento'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addItem,
        icon: const Icon(Icons.add),
        label: const Text('Adicionar Item'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(Icons.date_range, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    '${df.format(widget.menu.startDate)} — ${df.format(widget.menu.endDate)}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const Spacer(),
                  Text('${_items.length} item(s)',
                      style: Theme.of(context).textTheme.labelSmall),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (_items.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  children: [
                    Icon(Icons.no_food,
                        size: 48,
                        color: Theme.of(context).colorScheme.outlineVariant),
                    const SizedBox(height: 12),
                    const Text('Nenhum item na ementa.'),
                    const SizedBox(height: 4),
                    const Text(
                      'Adicione alimentos para cada dia e refeição.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            )
          else
            for (int day = 1; day <= 5; day++) ...[
              if (byDay.containsKey(day)) ...[
                Text(
                  _dayNames[day - 1],
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 6),
                ...byDay[day]!.map((item) => Card(
                      margin: const EdgeInsets.only(bottom: 4),
                      child: ListTile(
                        dense: true,
                        leading: Icon(
                          item.mealType == 'breakfast'
                              ? Icons.free_breakfast
                              : item.mealType == 'snack'
                                  ? Icons.cookie
                                  : Icons.lunch_dining,
                          color: item.mealType == 'breakfast'
                              ? Colors.orange
                              : item.mealType == 'snack'
                                  ? Colors.purple
                                  : Colors.teal,
                          size: 20,
                        ),
                        title: Text(_mealLabels[item.mealType] ?? item.mealType),
                        subtitle: item.mealComponent != null
                            ? Text(_componentLabels[item.mealComponent] ?? item.mealComponent!)
                            : null,
                      ),
                    )),
                const SizedBox(height: 12),
              ],
            ],
        ],
      ),
    );
  }
}
