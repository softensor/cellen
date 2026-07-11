import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_client.dart';
import '../../../core/models/food.dart';

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------
final weeklyMenuProvider =
    FutureProvider.autoDispose<List<FoodMenuItem>>((ref) async {
  final api = ref.read(apiClientProvider);
  // Get the current week's menu
  final now = DateTime.now();
  final startOfWeek =
      now.subtract(Duration(days: now.weekday - 1));
  final endOfWeek = startOfWeek.add(const Duration(days: 6));

  final startStr =
      '${startOfWeek.year.toString().padLeft(4, '0')}-${startOfWeek.month.toString().padLeft(2, '0')}-${startOfWeek.day.toString().padLeft(2, '0')}';
  final endStr =
      '${endOfWeek.year.toString().padLeft(4, '0')}-${endOfWeek.month.toString().padLeft(2, '0')}-${endOfWeek.day.toString().padLeft(2, '0')}';

  final data = await api.get('/food/menus',
      queryParameters: {
        'date_from': startStr,
        'date_to': endStr,
        'ordering': 'menu_date',
      }) as List;
  return data
      .map((e) => FoodMenuItem.fromJson(e as Map<String, dynamic>))
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
        data: (menuItems) {
          if (menuItems.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.restaurant_menu,
                      size: 64,
                      color:
                          Theme.of(context).colorScheme.outlineVariant),
                  const SizedBox(height: 16),
                  Text(
                    'Ementa não disponível esta semana',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            );
          }

          // Build tabs for Mon–Fri
          final now = DateTime.now();
          final startOfWeek =
              now.subtract(Duration(days: now.weekday - 1));

          // Build a map from weekday (1=Mon) to menu item
          final menuByDay = <int, FoodMenuItem>{};
          for (final item in menuItems) {
            menuByDay[item.menuDate.weekday] = item;
          }

          const dayNames = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex'];
          final tabDays = List.generate(5, (i) {
            final date = startOfWeek.add(Duration(days: i));
            return (
              label: dayNames[i],
              date: date,
              item: menuByDay[i + 1],
            );
          });

          return DefaultTabController(
            length: 5,
            initialIndex: (now.weekday - 1).clamp(0, 4),
            child: Column(
              children: [
                TabBar(
                  tabs: tabDays.map((d) {
                    final isToday =
                        d.date.day == now.day &&
                            d.date.month == now.month &&
                            d.date.year == now.year;
                    return Tab(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            d.label,
                            style: TextStyle(
                              fontWeight: isToday
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                          Text(
                            DateFormat('d/M').format(d.date),
                            style: const TextStyle(fontSize: 10),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
                Expanded(
                  child: TabBarView(
                    children: tabDays.map((d) {
                      return _DayMenuView(
                          item: d.item,
                          date: d.date);
                    }).toList(),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Day Menu View
// ---------------------------------------------------------------------------
class _DayMenuView extends StatelessWidget {
  final FoodMenuItem? item;
  final DateTime date;

  const _DayMenuView({this.item, required this.date});

  @override
  Widget build(BuildContext context) {
    final dateStr =
        DateFormat('EEEE, d \'de\' MMMM', 'pt_PT').format(date);

    if (item == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.no_food,
                size: 48,
                color: Theme.of(context).colorScheme.outlineVariant),
            const SizedBox(height: 16),
            Text(
              'Ementa não disponível para este dia',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            dateStr,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
          ),
          const SizedBox(height: 16),

          // Pequeno-almoço
          if (item!.breakfast != null && item!.breakfast!.isNotEmpty) ...[
            _MealSection(
              icon: Icons.free_breakfast,
              title: 'Pequeno-almoço',
              color: Colors.orange,
              items: [item!.breakfast!],
            ),
            const SizedBox(height: 16),
          ],

          // Almoço
          _MealSection(
            icon: Icons.lunch_dining,
            title: 'Almoço',
            color: Colors.teal,
            items: [
              if (item!.lunchSoup != null && item!.lunchSoup!.isNotEmpty)
                'Sopa: ${item!.lunchSoup}',
              if (item!.lunchMain != null && item!.lunchMain!.isNotEmpty)
                'Prato: ${item!.lunchMain}',
              if (item!.lunchDessert != null &&
                  item!.lunchDessert!.isNotEmpty)
                'Sobremesa: ${item!.lunchDessert}',
              if (item!.lunchDrink != null && item!.lunchDrink!.isNotEmpty)
                'Bebida: ${item!.lunchDrink}',
            ],
          ),
          const SizedBox(height: 16),

          // Lanche
          if (item!.snack != null && item!.snack!.isNotEmpty) ...[
            _MealSection(
              icon: Icons.cookie,
              title: 'Lanche',
              color: Colors.purple,
              items: [item!.snack!],
            ),
            const SizedBox(height: 16),
          ],

          // Notes
          if (item!.notes != null && item!.notes!.isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline,
                      size: 16,
                      color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(child: Text(item!.notes!)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MealSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;
  final List<String> items;

  const _MealSection({
    required this.icon,
    required this.title,
    required this.color,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: color, width: 4),
        ),
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
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.circle,
                      size: 6,
                      color: color.withOpacity(0.7)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(item)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
