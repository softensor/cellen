import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_client.dart';
import '../../../core/models/employee.dart';

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------
final employeesProvider =
    FutureProvider.autoDispose<List<Employee>>((ref) async {
  final api = ref.read(apiClientProvider);
  final data = await api.get('/employees') as List;
  return data
      .map((e) => Employee.fromJson(e as Map<String, dynamic>))
      .toList();
});

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------
class EmployeesListScreen extends ConsumerStatefulWidget {
  const EmployeesListScreen({super.key});

  @override
  ConsumerState<EmployeesListScreen> createState() =>
      _EmployeesListScreenState();
}

class _EmployeesListScreenState extends ConsumerState<EmployeesListScreen> {
  String _filter = 'all'; // all, teacher, staff, admin

  @override
  Widget build(BuildContext context) {
    final employeesAsync = ref.watch(employeesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Funcionários'),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/admin/employees/new'),
        tooltip: 'Adicionar Funcionário',
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          // Filter chips
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _FilterChip(
                    label: 'Todos',
                    selected: _filter == 'all',
                    onSelected: (_) => setState(() => _filter = 'all'),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: 'Educadores',
                    selected: _filter == 'teacher',
                    onSelected: (_) =>
                        setState(() => _filter = 'teacher'),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: 'Auxiliares',
                    selected: _filter == 'staff',
                    onSelected: (_) => setState(() => _filter = 'staff'),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: 'Admin',
                    selected: _filter == 'admin',
                    onSelected: (_) => setState(() => _filter = 'admin'),
                  ),
                ],
              ),
            ),
          ),

          Expanded(
            child: employeesAsync.when(
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
                      onPressed: () => ref.invalidate(employeesProvider),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Tentar novamente'),
                    ),
                  ],
                ),
              ),
              data: (employees) {
                final filtered = _filter == 'all'
                    ? employees
                    : employees
                        .where((e) => e.employeeType == _filter)
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
                          'Nenhum funcionário encontrado',
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
                      ref.invalidate(employeesProvider),
                  child: ListView.builder(
                    padding: const EdgeInsets.only(bottom: 88),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final emp = filtered[index];
                      return _EmployeeTile(employee: emp);
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

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final ValueChanged<bool> onSelected;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: onSelected,
      showCheckmark: false,
      selectedColor: Theme.of(context).colorScheme.primaryContainer,
    );
  }
}

class _EmployeeTile extends StatelessWidget {
  final Employee employee;
  const _EmployeeTile({required this.employee});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: _EmployeeAvatar(
            photoUrl: employee.photoUrl, name: employee.fullName),
        title: Text(
          employee.fullName,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (employee.position != null) Text(employee.position!),
            const SizedBox(height: 4),
            _TypeChip(type: employee.employeeType, label: employee.employeeTypeLabel),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!employee.isActive)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text('Inactivo',
                    style: TextStyle(fontSize: 11, color: Colors.grey)),
              ),
            const Icon(Icons.chevron_right),
          ],
        ),
        onTap: () =>
            context.push('/admin/employees/${employee.id}/edit'),
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  final String type;
  final String label;
  const _TypeChip({required this.type, required this.label});

  @override
  Widget build(BuildContext context) {
    Color color;
    switch (type) {
      case 'teacher':
        color = Colors.blue;
        break;
      case 'admin':
        color = Colors.purple;
        break;
      default:
        color = Colors.teal;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
            color: color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _EmployeeAvatar extends StatelessWidget {
  final String? photoUrl;
  final String name;
  const _EmployeeAvatar({this.photoUrl, required this.name});

  @override
  Widget build(BuildContext context) {
    if (photoUrl != null && photoUrl!.isNotEmpty) {
      return CircleAvatar(
        radius: 24,
        backgroundImage: NetworkImage(
            '$kMediaBase${photoUrl!.startsWith('/') ? photoUrl! : '/$photoUrl'}'),
        onBackgroundImageError: (_, __) {},
      );
    }
    final initials = name.isNotEmpty
        ? name.trim().split(' ').take(2).map((w) => w[0]).join()
        : '?';
    return CircleAvatar(
      radius: 24,
      backgroundColor:
          Theme.of(context).colorScheme.secondaryContainer,
      child: Text(
        initials.toUpperCase(),
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSecondaryContainer,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
