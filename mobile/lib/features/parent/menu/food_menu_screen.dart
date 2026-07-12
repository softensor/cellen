import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_client.dart';
import '../../../core/models/food.dart';

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------
final weeklyMenuProvider =
    FutureProvider.autoDispose<List<FoodMenu>>((ref) async {
  final api = ref.read(apiClientProvider);
  final data = await api.get('/food/menus') as List;
  return data
      .map((e) => FoodMenu.fromJson(e as Map<String, dynamic>))
      .toList();
});

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------
class FoodMenuScreen extends ConsumerWidget {
  const FoodMenuScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final menuAsync = ref.watch(weeklyMenuProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ementa da Semana'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(weeklyMenuProvider),
          ),
        ],
      ),
      body: menuAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 8),
              Text(e.toString()),
              TextButton(
                onPressed: () => ref.invalidate(weeklyMenuProvider),
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
                  Text(
                    'Ementa não disponível esta semana',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            );
          }

          // Use the first menu returned (most relevant)
          final menu = menus.first;
          return _WeeklyMenuView(menu: menu);
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Weekly Menu View — tabs Mon–Fri
// ---------------------------------------------------------------------------
class _WeeklyMenuView extends StatelessWidget {
  final FoodMenu menu;

  const _WeeklyMenuView({required this.menu});

  @override
  Widget build(BuildContext context) {
    const dayNames = ['Segunda', 'Terça', 'Quarta', 'Quinta', 'Sexta'];
    const dayShort = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex'];

    // Group entries by day_of_week (1–5)
    final byDay = <int, List<FoodMenuItemEntry>>{};
    for (final entry in menu.items) {
      if (entry.dayOfWeek >= 1 && entry.dayOfWeek <= 5) {
        byDay.putIfAbsent(entry.dayOfWeek, () => []).add(entry);
      }
    }

    final now = DateTime.now();
    final initialTab = (now.weekday - 1).clamp(0, 4);

    return DefaultTabController(
      length: 5,
      initialIndex: initialTab,
      child: Column(
        children: [
          TabBar(
            tabs: List.generate(5, (i) {
              // Compute the actual date for this weekday in the menu's week
              final monday = menu.startDate.subtract(
                  Duration(days: menu.startDate.weekday - 1));
              final tabDate = monday.add(Duration(days: i));
              final isToday = tabDate.year == now.year &&
                  tabDate.month == now.month &&
                  tabDate.day == now.day;
              return Tab(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      dayShort[i],
                      style: TextStyle(
                        fontWeight:
                            isToday ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    Text(
                      DateFormat('d/M').format(tabDate),
                      style: const TextStyle(fontSize: 10),
                    ),
                  ],
                ),
              );
            }),
          ),
          Expanded(
            child: TabBarView(
              children: List.generate(5, (i) {
                final dayNum = i + 1;
                final entries = byDay[dayNum] ?? [];
                return _DayView(
                  dayName: dayNames[i],
                  entries: entries,
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Single-day view
// ---------------------------------------------------------------------------
class _DayView extends StatelessWidget {
  final String dayName;
  final List<FoodMenuItemEntry> entries;

  const _DayView({required this.dayName, required this.entries});

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.no_food,
                size: 48,
                color: Theme.of(context).colorScheme.outlineVariant),
            const SizedBox(height: 16),
            Text(
              'Ementa não disponível para $dayName',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      );
    }

    // Group by meal type
    final byMealType = <String, List<FoodMenuItemEntry>>{};
    for (final e in entries) {
      byMealType.putIfAbsent(e.mealType, () => []).add(e);
    }

    const mealOrder = ['breakfast', 'lunch', 'snack'];
    const mealLabels = {
      'breakfast': 'Pequeno-almoço',
      'lunch': 'Almoço',
      'snack': 'Lanche',
    };
    const mealIcons = {
      'breakfast': Icons.free_breakfast,
      'lunch': Icons.lunch_dining,
      'snack': Icons.cookie,
    };
    const mealColors = {
      'breakfast': Colors.orange,
      'lunch': Colors.teal,
      'snack': Colors.purple,
    };

    // Build ordered list of present meal types
    final orderedTypes = [
      ...mealOrder.where((t) => byMealType.containsKey(t)),
      ...byMealType.keys.where((t) => !mealOrder.contains(t)),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final mealType in orderedTypes) ...[
            _MealSection(
              icon: mealIcons[mealType] ?? Icons.restaurant,
              title: mealLabels[mealType] ?? mealType,
              color: mealColors[mealType] ?? Colors.grey,
              entries: byMealType[mealType]!,
            ),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Meal section card
// ---------------------------------------------------------------------------
class _MealSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;
  final List<FoodMenuItemEntry> entries;

  const _MealSection({
    required this.icon,
    required this.title,
    required this.color,
    required this.entries,
  });

  String _componentLabel(String? component) {
    switch (component) {
      case 'sopa':
        return 'Sopa';
      case 'prato':
        return 'Prato';
      case 'sobremesa':
        return 'Sobremesa';
      case 'drink':
        return 'Bebida';
      default:
        return component ?? '—';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: color, width: 4)),
        color: color.withOpacity(0.05),
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(8),
          bottomRight: Radius.circular(8),
        ),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final entry in entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.circle, size: 6, color: color.withOpacity(0.7)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_componentLabel(entry.mealComponent)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
