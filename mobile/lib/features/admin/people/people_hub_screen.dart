import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_client.dart';
import '../../../core/theme/app_theme.dart';

// ---------------------------------------------------------------------------
// Counts provider (summary for hub cards)
// ---------------------------------------------------------------------------
final _peopleSummaryProvider = FutureProvider.autoDispose<Map<String, int>>((ref) async {
  final api = ref.read(apiClientProvider);
  final results = await Future.wait([
    api.get('/children') as Future,
    api.get('/guardians') as Future,
    api.get('/employees') as Future,
    api.get('/academic/enrollments', queryParameters: {'limit': '1000'}) as Future,
  ]);
  return {
    'children': (results[0] as List).length,
    'guardians': (results[1] as List).length,
    'employees': (results[2] as List).length,
    'enrollments': (results[3] as List).length,
  };
});

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------
class PeopleHubScreen extends ConsumerWidget {
  const PeopleHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(_peopleSummaryProvider);

    final items = [
      _HubItem(
        icon: Icons.child_care_outlined,
        selectedIcon: Icons.child_care,
        color: Colors.blue,
        label: 'Crianças',
        description: 'Gerir perfis das crianças matriculadas',
        countKey: 'children',
        path: '/admin/children',
        fab: _HubFab(
          icon: Icons.person_add_outlined,
          label: 'Nova Criança',
          path: '/admin/children/new',
        ),
      ),
      _HubItem(
        icon: Icons.people_outline,
        selectedIcon: Icons.people,
        color: Colors.green,
        label: 'Encarregados',
        description: 'Responsáveis e contactos de emergência',
        countKey: 'guardians',
        path: '/admin/guardians',
        fab: _HubFab(
          icon: Icons.person_add_outlined,
          label: 'Novo Encarregado',
          path: '/admin/guardians/new',
        ),
      ),
      _HubItem(
        icon: Icons.badge_outlined,
        selectedIcon: Icons.badge,
        color: Colors.purple,
        label: 'Funcionários',
        description: 'Educadores, auxiliares e pessoal administrativo',
        countKey: 'employees',
        path: '/admin/employees',
        fab: _HubFab(
          icon: Icons.person_add_outlined,
          label: 'Novo Funcionário',
          path: '/admin/employees/new',
        ),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pessoas'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(_peopleSummaryProvider),
          ),
        ],
      ),
      body: summaryAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => _HubGrid(items: items, counts: const {}),
        data: (counts) => _HubGrid(items: items, counts: counts),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared hub grid
// ---------------------------------------------------------------------------
class _HubFab {
  final IconData icon;
  final String label;
  final String path;
  const _HubFab({required this.icon, required this.label, required this.path});
}

class _HubItem {
  final IconData icon;
  final IconData selectedIcon;
  final Color color;
  final String label;
  final String description;
  final String countKey;
  final String path;
  final _HubFab? fab;

  const _HubItem({
    required this.icon,
    required this.selectedIcon,
    required this.color,
    required this.label,
    required this.description,
    required this.countKey,
    required this.path,
    required this.fab,
  });
}

class _HubGrid extends StatelessWidget {
  final List<_HubItem> items;
  final Map<String, int> counts;

  const _HubGrid({required this.items, required this.counts});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 340,
        mainAxisExtent: 210,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final item = items[i];
        final count = counts[item.countKey];
        return _HubCard(item: item, count: count);
      },
    );
  }
}

class _HubCard extends StatelessWidget {
  final _HubItem item;
  final int? count;

  const _HubCard({required this.item, this.count});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: item.color.withAlpha(60), width: 1.5),
      ),
      child: InkWell(
        onTap: () => context.push(item.path),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: item.color.withAlpha(25),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(item.icon, color: item.color, size: 26),
                  ),
                  const Spacer(),
                  if (count != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: item.color.withAlpha(25),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '$count',
                        style: TextStyle(
                          color: item.color,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Text(item.label,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 4),
              Text(item.description,
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
              const Spacer(),
              if (item.fab != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => context.push(item.fab!.path),
                    icon: Icon(item.fab!.icon, size: 16),
                    label: Text(item.fab!.label, style: const TextStyle(fontSize: 12)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
