import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/models/child.dart';

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------
class MealOrder {
  final String id;
  final String childId;
  final String? childName;
  final String orderDate;
  final String mealType;
  final bool ordered;

  const MealOrder({
    required this.id,
    required this.childId,
    this.childName,
    required this.orderDate,
    required this.mealType,
    required this.ordered,
  });

  factory MealOrder.fromJson(Map<String, dynamic> json) => MealOrder(
        id: json['id']?.toString() ?? '',
        childId: json['child_id']?.toString() ?? '',
        childName: json['child_name'] as String?,
        orderDate: json['order_date'] as String? ?? '',
        mealType: json['meal_type'] as String? ?? 'lunch',
        ordered: json['ordered'] as bool? ?? true,
      );
}

class DailyMealCount {
  final String orderDate;
  final String mealType;
  final int total;

  const DailyMealCount({
    required this.orderDate,
    required this.mealType,
    required this.total,
  });

  factory DailyMealCount.fromJson(Map<String, dynamic> json) => DailyMealCount(
        orderDate: json['order_date'] as String? ?? '',
        mealType: json['meal_type'] as String? ?? 'lunch',
        total: json['total'] as int? ?? 0,
      );
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

// Week range helpers
DateTime _weekStart(DateTime ref) {
  final d = ref.subtract(Duration(days: ref.weekday - 1));
  return DateTime(d.year, d.month, d.day);
}

DateTime _weekEnd(DateTime ref) => _weekStart(ref).add(const Duration(days: 6));

String _fmt(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

final _selectedWeekProvider = StateProvider<DateTime>((ref) => DateTime.now());

final mealOrdersProvider =
    FutureProvider.autoDispose.family<List<MealOrder>, DateTime>((ref, week) async {
  final api = ref.read(apiClientProvider);
  final from = _fmt(_weekStart(week));
  final to = _fmt(_weekEnd(week));
  final data = await api
      .get('/pickup-authorizations/meal-orders?date_from=$from&date_to=$to') as List;
  return data.map((e) => MealOrder.fromJson(e as Map<String, dynamic>)).toList();
});

final dailyMealCountsProvider =
    FutureProvider.autoDispose.family<List<DailyMealCount>, DateTime>((ref, week) async {
  final api = ref.read(apiClientProvider);
  final from = _fmt(_weekStart(week));
  final to = _fmt(_weekEnd(week));
  final data = await api
      .get('/pickup-authorizations/meal-orders/daily-counts?date_from=$from&date_to=$to') as List;
  return data.map((e) => DailyMealCount.fromJson(e as Map<String, dynamic>)).toList();
});

final childrenMealProvider =
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
class MealOrdersScreen extends ConsumerWidget {
  const MealOrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final isStaff = !auth.isParent;

    return isStaff ? const _StaffMealView() : const _ParentMealView();
  }
}

// ---------------------------------------------------------------------------
// Parent view — weekly toggle grid
// ---------------------------------------------------------------------------
class _ParentMealView extends ConsumerStatefulWidget {
  const _ParentMealView();

  @override
  ConsumerState<_ParentMealView> createState() => _ParentMealViewState();
}

class _ParentMealViewState extends ConsumerState<_ParentMealView> {
  String? _selectedChildId;
  final Set<String> _loading = {};

  @override
  Widget build(BuildContext context) {
    final week = ref.watch(_selectedWeekProvider);
    final weekStart = _weekStart(week);
    final childrenAsync = ref.watch(childrenMealProvider);
    final ordersAsync = ref.watch(mealOrdersProvider(week));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Refeições'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(mealOrdersProvider(week)),
          ),
        ],
      ),
      body: Column(
        children: [
          // Week navigation
          _WeekSelector(
            week: week,
            onPrev: () => ref
                .read(_selectedWeekProvider.notifier)
                .state = week.subtract(const Duration(days: 7)),
            onNext: () => ref
                .read(_selectedWeekProvider.notifier)
                .state = week.add(const Duration(days: 7)),
          ),
          // Child filter
          childrenAsync.maybeWhen(
            data: (children) {
              if (children.length > 1) {
                if (_selectedChildId == null && children.isNotEmpty) {
                  WidgetsBinding.instance.addPostFrameCallback(
                      (_) => setState(() => _selectedChildId = children.first.id));
                }
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: DropdownButtonFormField<String>(
                    value: _selectedChildId,
                    decoration: const InputDecoration(
                      labelText: 'Criança',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: children
                        .map((c) => DropdownMenuItem(value: c.id, child: Text(c.fullName)))
                        .toList(),
                    onChanged: (v) => setState(() => _selectedChildId = v),
                  ),
                );
              } else if (children.isNotEmpty && _selectedChildId == null) {
                WidgetsBinding.instance.addPostFrameCallback(
                    (_) => setState(() => _selectedChildId = children.first.id));
              }
              return const SizedBox.shrink();
            },
            orElse: () => const SizedBox.shrink(),
          ),
          const SizedBox(height: 8),
          // Weekday headers
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const SizedBox(width: 80),
                ...List.generate(5, (i) {
                  final day = weekStart.add(Duration(days: i));
                  final isToday = _fmt(day) == _fmt(DateTime.now());
                  return Expanded(
                    child: Column(
                      children: [
                        Text(
                          _weekdayShort(i),
                          style: TextStyle(
                            fontSize: 11,
                            color: isToday
                                ? Theme.of(context).colorScheme.primary
                                : Colors.grey,
                          ),
                        ),
                        Text(
                          '${day.day}',
                          style: TextStyle(
                            fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                            color: isToday
                                ? Theme.of(context).colorScheme.primary
                                : null,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: ordersAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text(e.toString())),
              data: (orders) {
                final childOrders = _selectedChildId == null
                    ? orders
                    : orders.where((o) => o.childId == _selectedChildId).toList();

                // Build ordered map: date -> mealType -> order
                final orderMap = <String, Map<String, MealOrder>>{};
                for (final o in childOrders) {
                  orderMap.putIfAbsent(o.orderDate, () {})[o.mealType] = o;
                }

                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: _mealTypes.map((mealType) {
                    return _MealTypeRow(
                      mealType: mealType,
                      weekStart: weekStart,
                      orderMap: orderMap,
                      childId: _selectedChildId,
                      loading: _loading,
                      onToggle: (date, currentlyOrdered) async {
                        if (_selectedChildId == null) return;
                        final key = '${date}_$mealType';
                        setState(() => _loading.add(key));
                        try {
                          final api = ref.read(apiClientProvider);
                          await api.post('/pickup-authorizations/meal-orders', data: {
                            'child_id': _selectedChildId,
                            'order_date': date,
                            'meal_type': mealType,
                            'ordered': !currentlyOrdered,
                          });
                          ref.invalidate(mealOrdersProvider(week));
                        } finally {
                          if (mounted) setState(() => _loading.remove(key));
                        }
                      },
                    );
                  }).toList(),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

const _mealTypes = ['breakfast', 'lunch', 'snack'];

String _mealTypeLabel(String type) => switch (type) {
      'breakfast' => 'Pequeno-Almoço',
      'lunch' => 'Almoço',
      'snack' => 'Lanche',
      _ => type,
    };

String _weekdayShort(int i) =>
    ['Seg', 'Ter', 'Qua', 'Qui', 'Sex'][i];

class _MealTypeRow extends StatelessWidget {
  final String mealType;
  final DateTime weekStart;
  final Map<String, Map<String, MealOrder>> orderMap;
  final String? childId;
  final Set<String> loading;
  final Future<void> Function(String date, bool currentlyOrdered) onToggle;

  const _MealTypeRow({
    required this.mealType,
    required this.weekStart,
    required this.orderMap,
    required this.childId,
    required this.loading,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              _mealTypeLabel(mealType),
              style: const TextStyle(fontSize: 12),
            ),
          ),
          ...List.generate(5, (i) {
            final day = weekStart.add(Duration(days: i));
            final dateStr = _fmt(day);
            final order = orderMap[dateStr]?[mealType];
            final isOrdered = order?.ordered ?? false;
            final key = '${dateStr}_$mealType';
            final isLoading = loading.contains(key);
            final isPast = day.isBefore(DateTime.now().subtract(const Duration(days: 1)));

            return Expanded(
              child: Center(
                child: isLoading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : GestureDetector(
                        onTap: isPast || childId == null
                            ? null
                            : () => onToggle(dateStr, isOrdered),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: isOrdered
                                ? Theme.of(context).colorScheme.primary
                                : isPast
                                    ? Colors.grey.shade100
                                    : Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            isOrdered ? Icons.check : Icons.close,
                            size: 18,
                            color: isOrdered
                                ? Colors.white
                                : isPast
                                    ? Colors.grey.shade400
                                    : Colors.grey.shade500,
                          ),
                        ),
                      ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Staff view — daily counts
// ---------------------------------------------------------------------------
class _StaffMealView extends ConsumerWidget {
  const _StaffMealView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final week = ref.watch(_selectedWeekProvider);
    final countsAsync = ref.watch(dailyMealCountsProvider(week));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Refeições — Contagens'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(dailyMealCountsProvider(week)),
          ),
        ],
      ),
      body: Column(
        children: [
          _WeekSelector(
            week: week,
            onPrev: () => ref
                .read(_selectedWeekProvider.notifier)
                .state = week.subtract(const Duration(days: 7)),
            onNext: () => ref
                .read(_selectedWeekProvider.notifier)
                .state = week.add(const Duration(days: 7)),
          ),
          Expanded(
            child: countsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text(e.toString())),
              data: (counts) {
                if (counts.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.restaurant_menu,
                            size: 64,
                            color: Theme.of(context).colorScheme.outlineVariant),
                        const SizedBox(height: 16),
                        Text(
                          'Sem refeições encomendadas esta semana',
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  );
                }

                // Group by date
                final weekStart = _weekStart(week);
                final grouped = <String, Map<String, int>>{};
                for (var i = 0; i < 5; i++) {
                  final d = _fmt(weekStart.add(Duration(days: i)));
                  grouped[d] = {};
                }
                for (final c in counts) {
                  grouped.putIfAbsent(c.orderDate, () {})[c.mealType] = c.total;
                }

                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: grouped.entries.map((entry) {
                    final day = DateTime.parse(entry.key);
                    final dayLabel =
                        '${_weekdayFull(day.weekday - 1)}, ${day.day}/${day.month}';
                    final totals = entry.value;
                    final grandTotal = totals.values.fold(0, (a, b) => a + b);

                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(dayLabel,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold, fontSize: 15)),
                                if (grandTotal > 0)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primaryContainer,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      'Total: $grandTotal',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onPrimaryContainer,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            if (grandTotal == 0)
                              const Padding(
                                padding: EdgeInsets.only(top: 8),
                                child: Text('Sem encomendas',
                                    style: TextStyle(color: Colors.grey)),
                              )
                            else
                              ...(_mealTypes.map((mt) {
                                final count = totals[mt] ?? 0;
                                if (count == 0) return const SizedBox.shrink();
                                return Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Row(
                                    children: [
                                      Icon(_mealIcon(mt),
                                          size: 18,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary),
                                      const SizedBox(width: 8),
                                      Text(_mealTypeLabel(mt),
                                          style: const TextStyle(fontSize: 13)),
                                      const Spacer(),
                                      Text(
                                        '$count refeições',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13),
                                      ),
                                    ],
                                  ),
                                );
                              })),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

IconData _mealIcon(String type) => switch (type) {
      'breakfast' => Icons.free_breakfast,
      'lunch' => Icons.lunch_dining,
      'snack' => Icons.coffee,
      _ => Icons.restaurant,
    };

String _weekdayFull(int i) =>
    ['Segunda', 'Terça', 'Quarta', 'Quinta', 'Sexta'][i];

// ---------------------------------------------------------------------------
// Shared week selector widget
// ---------------------------------------------------------------------------
class _WeekSelector extends StatelessWidget {
  final DateTime week;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  const _WeekSelector(
      {required this.week, required this.onPrev, required this.onNext});

  @override
  Widget build(BuildContext context) {
    final start = _weekStart(week);
    final end = _weekEnd(week);
    final label =
        '${start.day}/${start.month} – ${end.day}/${end.month}/${end.year}';

    return Container(
      color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: onPrev,
            visualDensity: VisualDensity.compact,
          ),
          Expanded(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: onNext,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}
