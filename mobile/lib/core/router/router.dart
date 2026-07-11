import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/auth/auth_state.dart';
import '../../features/auth/login_screen.dart';
import '../../features/admin/dashboard/admin_dashboard_screen.dart';
import '../../features/admin/children/children_list_screen.dart';
import '../../features/admin/children/child_detail_screen.dart';
import '../../features/admin/children/child_form_screen.dart';
import '../../features/admin/employees/employees_list_screen.dart';
import '../../features/admin/employees/employee_form_screen.dart';
import '../../features/admin/finance/finance_dashboard_screen.dart';
import '../../features/admin/finance/invoices_screen.dart';
import '../../features/admin/finance/expenses_screen.dart';
import '../../features/admin/academic/turmas_screen.dart';
import '../../features/admin/academic/enrollments_screen.dart';
import '../../features/admin/absences/absences_screen.dart';
import '../../features/teacher/dashboard/teacher_dashboard_screen.dart';
import '../../features/teacher/caderneta/caderneta_list_screen.dart';
import '../../features/teacher/caderneta/caderneta_form_screen.dart';
import '../../features/parent/dashboard/parent_dashboard_screen.dart';
import '../../features/parent/caderneta/child_caderneta_screen.dart';
import '../../features/parent/menu/food_menu_screen.dart';

// ---------------------------------------------------------------------------
// Shell Widgets
// ---------------------------------------------------------------------------

class AdminShell extends ConsumerStatefulWidget {
  final Widget child;
  const AdminShell({super.key, required this.child});

  @override
  ConsumerState<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends ConsumerState<AdminShell> {
  int _selectedIndex = 0;

  static const _routes = [
    '/admin',
    '/admin/children',
    '/admin/employees',
    '/admin/finance',
    '/admin/academic/turmas',
    '/admin/absences',
  ];

  static const _destinations = [
    (icon: Icons.dashboard, label: 'Dashboard'),
    (icon: Icons.child_care, label: 'Crianças'),
    (icon: Icons.people, label: 'Funcionários'),
    (icon: Icons.account_balance_wallet, label: 'Finanças'),
    (icon: Icons.school, label: 'Turmas'),
    (icon: Icons.event_busy, label: 'Ausências'),
  ];

  void _onDestinationSelected(int index) {
    setState(() => _selectedIndex = index);
    context.go(_routes[index]);
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 600;
    final auth = ref.read(authProvider);

    if (isWide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _selectedIndex,
              onDestinationSelected: _onDestinationSelected,
              labelType: NavigationRailLabelType.all,
              leading: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Column(
                  children: [
                    const CircleAvatar(
                      radius: 20,
                      child: Icon(Icons.person),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      auth.username ?? 'Admin',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
              trailing: Expanded(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: IconButton(
                      icon: const Icon(Icons.logout),
                      tooltip: 'Sair',
                      onPressed: () =>
                          ref.read(authProvider.notifier).logout(),
                    ),
                  ),
                ),
              ),
              destinations: _destinations
                  .map(
                    (d) => NavigationRailDestination(
                      icon: Icon(d.icon),
                      label: Text(d.label),
                    ),
                  )
                  .toList(),
            ),
            const VerticalDivider(thickness: 1, width: 1),
            Expanded(child: widget.child),
          ],
        ),
      );
    } else {
      return Scaffold(
        body: widget.child,
        bottomNavigationBar: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: _onDestinationSelected,
          destinations: _destinations
              .map(
                (d) => NavigationDestination(
                  icon: Icon(d.icon),
                  label: d.label,
                ),
              )
              .toList(),
        ),
      );
    }
  }
}

// ---------------------------------------------------------------------------

class TeacherShell extends ConsumerStatefulWidget {
  final Widget child;
  const TeacherShell({super.key, required this.child});

  @override
  ConsumerState<TeacherShell> createState() => _TeacherShellState();
}

class _TeacherShellState extends ConsumerState<TeacherShell> {
  int _selectedIndex = 0;

  static const _routes = ['/teacher', '/teacher/caderneta'];

  static const _destinations = [
    (icon: Icons.dashboard, label: 'Dashboard'),
    (icon: Icons.book, label: 'Caderneta'),
  ];

  void _onDestinationSelected(int index) {
    setState(() => _selectedIndex = index);
    context.go(_routes[index]);
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 600;
    final auth = ref.read(authProvider);

    if (isWide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _selectedIndex,
              onDestinationSelected: _onDestinationSelected,
              labelType: NavigationRailLabelType.all,
              leading: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Column(
                  children: [
                    const CircleAvatar(
                      radius: 20,
                      child: Icon(Icons.person),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      auth.username ?? 'Educador',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
              trailing: Expanded(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: IconButton(
                      icon: const Icon(Icons.logout),
                      tooltip: 'Sair',
                      onPressed: () =>
                          ref.read(authProvider.notifier).logout(),
                    ),
                  ),
                ),
              ),
              destinations: _destinations
                  .map(
                    (d) => NavigationRailDestination(
                      icon: Icon(d.icon),
                      label: Text(d.label),
                    ),
                  )
                  .toList(),
            ),
            const VerticalDivider(thickness: 1, width: 1),
            Expanded(child: widget.child),
          ],
        ),
      );
    } else {
      return Scaffold(
        body: widget.child,
        bottomNavigationBar: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: _onDestinationSelected,
          destinations: _destinations
              .map(
                (d) => NavigationDestination(
                  icon: Icon(d.icon),
                  label: d.label,
                ),
              )
              .toList(),
        ),
      );
    }
  }
}

// ---------------------------------------------------------------------------

class ParentShell extends ConsumerStatefulWidget {
  final Widget child;
  const ParentShell({super.key, required this.child});

  @override
  ConsumerState<ParentShell> createState() => _ParentShellState();
}

class _ParentShellState extends ConsumerState<ParentShell> {
  int _selectedIndex = 0;

  static const _routes = ['/parent', '/parent/caderneta', '/parent/menu'];

  static const _destinations = [
    (icon: Icons.home, label: 'Início'),
    (icon: Icons.assignment, label: 'Caderneta'),
    (icon: Icons.restaurant_menu, label: 'Ementa'),
  ];

  void _onDestinationSelected(int index) {
    setState(() => _selectedIndex = index);
    context.go(_routes[index]);
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 600;
    final auth = ref.read(authProvider);

    if (isWide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _selectedIndex,
              onDestinationSelected: _onDestinationSelected,
              labelType: NavigationRailLabelType.all,
              leading: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Column(
                  children: [
                    const CircleAvatar(
                      radius: 20,
                      child: Icon(Icons.person),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      auth.username ?? 'Encarregado',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
              trailing: Expanded(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: IconButton(
                      icon: const Icon(Icons.logout),
                      tooltip: 'Sair',
                      onPressed: () =>
                          ref.read(authProvider.notifier).logout(),
                    ),
                  ),
                ),
              ),
              destinations: _destinations
                  .map(
                    (d) => NavigationRailDestination(
                      icon: Icon(d.icon),
                      label: Text(d.label),
                    ),
                  )
                  .toList(),
            ),
            const VerticalDivider(thickness: 1, width: 1),
            Expanded(child: widget.child),
          ],
        ),
      );
    } else {
      return Scaffold(
        body: widget.child,
        bottomNavigationBar: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: _onDestinationSelected,
          destinations: _destinations
              .map(
                (d) => NavigationDestination(
                  icon: Icon(d.icon),
                  label: d.label,
                ),
              )
              .toList(),
        ),
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Router Provider
// ---------------------------------------------------------------------------

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authProvider);

  return GoRouter(
    initialLocation: '/login',
    redirect: (context, state) {
      final isAuthenticated = authState.isAuthenticated;
      final isLoading = authState.isLoading;
      final isLoginPage = state.matchedLocation == '/login';

      // While checking session, stay put
      if (isLoading) return null;

      if (!isAuthenticated && !isLoginPage) return '/login';
      if (isAuthenticated && isLoginPage) {
        return switch (authState.role) {
          UserRole.platformAdmin || UserRole.schoolAdmin => '/admin',
          UserRole.teacher || UserRole.staff => '/teacher',
          UserRole.parent => '/parent',
          null => '/admin',
        };
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (_, __) => const LoginScreen(),
      ),

      // Admin shell
      ShellRoute(
        builder: (context, state, child) => AdminShell(child: child),
        routes: [
          GoRoute(
            path: '/admin',
            builder: (_, __) => const AdminDashboardScreen(),
          ),
          GoRoute(
            path: '/admin/children',
            builder: (_, __) => const ChildrenListScreen(),
          ),
          GoRoute(
            path: '/admin/children/new',
            builder: (_, __) => const ChildFormScreen(),
          ),
          GoRoute(
            path: '/admin/children/:id',
            builder: (_, s) =>
                ChildDetailScreen(id: s.pathParameters['id']!),
          ),
          GoRoute(
            path: '/admin/children/:id/edit',
            builder: (_, s) =>
                ChildFormScreen(childId: s.pathParameters['id']),
          ),
          GoRoute(
            path: '/admin/employees',
            builder: (_, __) => const EmployeesListScreen(),
          ),
          GoRoute(
            path: '/admin/employees/new',
            builder: (_, __) => const EmployeeFormScreen(),
          ),
          GoRoute(
            path: '/admin/employees/:id/edit',
            builder: (_, s) =>
                EmployeeFormScreen(employeeId: s.pathParameters['id']),
          ),
          GoRoute(
            path: '/admin/finance',
            builder: (_, __) => const FinanceDashboardScreen(),
          ),
          GoRoute(
            path: '/admin/finance/invoices',
            builder: (_, __) => const InvoicesScreen(),
          ),
          GoRoute(
            path: '/admin/finance/expenses',
            builder: (_, __) => const ExpensesScreen(),
          ),
          GoRoute(
            path: '/admin/academic/turmas',
            builder: (_, __) => const TurmasScreen(),
          ),
          GoRoute(
            path: '/admin/academic/enrollments',
            builder: (_, __) => const EnrollmentsScreen(),
          ),
          GoRoute(
            path: '/admin/absences',
            builder: (_, __) => const AbsencesScreen(),
          ),
        ],
      ),

      // Teacher shell
      ShellRoute(
        builder: (context, state, child) => TeacherShell(child: child),
        routes: [
          GoRoute(
            path: '/teacher',
            builder: (_, __) => const TeacherDashboardScreen(),
          ),
          GoRoute(
            path: '/teacher/caderneta',
            builder: (_, __) => const CadernetaListScreen(),
          ),
          GoRoute(
            path: '/teacher/caderneta/new',
            builder: (_, __) => const CadernetaFormScreen(),
          ),
          GoRoute(
            path: '/teacher/caderneta/:id/edit',
            builder: (_, s) =>
                CadernetaFormScreen(cadernetaId: s.pathParameters['id']),
          ),
        ],
      ),

      // Parent shell
      ShellRoute(
        builder: (context, state, child) => ParentShell(child: child),
        routes: [
          GoRoute(
            path: '/parent',
            builder: (_, __) => const ParentDashboardScreen(),
          ),
          GoRoute(
            path: '/parent/caderneta',
            builder: (_, __) => const ChildCadernetaScreen(),
          ),
          GoRoute(
            path: '/parent/menu',
            builder: (_, __) => const FoodMenuScreen(),
          ),
        ],
      ),
    ],
  );
});
