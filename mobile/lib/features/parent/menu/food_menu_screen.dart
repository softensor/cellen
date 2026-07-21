import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_client.dart';
import '../../../core/models/food.dart';
import '../../../core/widgets/app_error_widget.dart';

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------
final weeklyMenuProvider =
    FutureProvider.autoDispose<List<FoodMenu>>((ref) async {
  final api = ref.read(apiClientProvider);
  final data = await api.get('/food/menus') as List;
  final menus = data
      .map((e) => FoodMenu.fromJson(e as Map<String, dynamic>))
      .toList();
  // Sort newest first
  menus.sort((a, b) => a.startDate.compareTo(b.startDate));
  return menus;
});

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------
class FoodMenuScreen extends ConsumerStatefulWidget {
  const FoodMenuScreen({super.key});

  @override
  ConsumerState<FoodMenuScreen> createState() => _FoodMenuScreenState();
}

class _FoodMenuScreenState extends ConsumerState<FoodMenuScreen> {
  int _menuIndex = 0;
  List<FoodMenu>? _menus;

  // Pick the menu closest to today when data first loads
  void _initIndex(List<FoodMenu> menus) {
    final now = DateTime.now();
    int best = menus.length - 1; // default: most recent
    for (int i = 0; i < menus.length; i++) {
      if (!menus[i].endDate.isBefore(now)) {
        best = i;
        break;
      }
    }
    _menuIndex = best.clamp(0, menus.length - 1);
    _menus = menus;
  }

  @override
  Widget build(BuildContext context) {
    final menuAsync = ref.watch(weeklyMenuProvider);

    return menuAsync.when(
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('Ementa da Semana')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: const Text('Ementa da Semana')),
        body: AppErrorWidget(
            error: e, onRetry: () => ref.invalidate(weeklyMenuProvider)),
      ),
      data: (menus) {
        if (menus.isEmpty) {
          return Scaffold(
            appBar: AppBar(title: const Text('Ementa da Semana')),
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.restaurant_menu,
                      size: 64,
                      color: Theme.of(context).colorScheme.outlineVariant),
                  const SizedBox(height: 16),
                  Text(
                    'Ementa não disponível',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          );
        }

        // Initialise index only on first load (or if menus changed)
        if (_menus == null || _menus!.length != menus.length) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _initIndex(menus));
          });
          // Use sensible default while scheduling
          final clampedIndex = _menuIndex.clamp(0, menus.length - 1);
          return _buildScaffold(context, menus, clampedIndex);
        }

        return _buildScaffold(
            context, menus, _menuIndex.clamp(0, menus.length - 1));
      },
    );
  }

  Widget _buildScaffold(
      BuildContext context, List<FoodMenu> menus, int index) {
    final menu = menus[index];
    final df = DateFormat('d/M');
    final weekLabel =
        '${df.format(menu.startDate)} – ${df.format(menu.endDate)}';

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Ementa da Semana',
                style: TextStyle(fontSize: 17)),
            Text(weekLabel,
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withOpacity(0.6))),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            tooltip: 'Semana anterior',
            onPressed: index > 0
                ? () => setState(() => _menuIndex = index - 1)
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Semana seguinte',
            onPressed: index < menus.length - 1
                ? () => setState(() => _menuIndex = index + 1)
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() => _menus = null);
              ref.invalidate(weeklyMenuProvider);
            },
          ),
        ],
      ),
      body: _WeeklyMenuView(menu: menu),
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
    // Default to today's weekday tab if it falls within the menu week
    int initialTab = 0;
    final monday =
        menu.startDate.subtract(Duration(days: menu.startDate.weekday - 1));
    for (int i = 0; i < 5; i++) {
      final tabDate = monday.add(Duration(days: i));
      if (tabDate.year == now.year &&
          tabDate.month == now.month &&
          tabDate.day == now.day) {
        initialTab = i;
        break;
      }
    }

    return DefaultTabController(
      length: 5,
      initialIndex: initialTab,
      child: Column(
        children: [
          TabBar(
            tabs: List.generate(5, (i) {
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
        return component ?? '';
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
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.circle, size: 6, color: color.withOpacity(0.7)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (entry.foodName != null &&
                            entry.foodName!.isNotEmpty)
                          Text(
                            entry.foodName!,
                            style: const TextStyle(
                                fontWeight: FontWeight.w500, fontSize: 14),
                          ),
                        if (entry.mealComponent != null)
                          Text(
                            _componentLabel(entry.mealComponent),
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                        if (entry.foodName == null &&
                            entry.mealComponent == null)
                          const Text('—'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
