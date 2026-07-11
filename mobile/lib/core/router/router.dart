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
import '../../features/platform/dashboard/platform_dashboard_screen.dart';
import '../../features/platform/schools/schools_screen.dart';
import '../../features/teacher/dashboard/teacher_dashboard_screen.dart';
import '../../features/teacher/caderneta/caderneta_list_screen.dart';
import '../../features/teacher/caderneta/caderneta_form_screen.dart';
import '../../features/teacher/attendance/attendance_screen.dart';
import '../../features/parent/dashboard/parent_dashboard_screen.dart';
import '../../features/parent/caderneta/child_caderneta_screen.dart';
import '../../features/parent/menu/food_menu_screen.dart';
import '../../features/messages/messages_screen.dart';
import '../../features/messages/thread_screen.dart';
import '../../features/photos/photos_screen.dart';
import '../../features/incidents/incidents_screen.dart';
import '../../features/events/events_screen.dart';
import '../../features/notifications/notifications_screen.dart';

// ---------------------------------------------------------------------------
// Shell Widgets
// ---------------------------------------------------------------------------

class PlatformShell extends ConsumerStatefulWidget {
  final Widget child;
  const PlatformShell({super.key, required this.child});

  @override
  ConsumerState<PlatformShell> createState() => _PlatformShellState();
}

class _PlatformShellState extends ConsumerState<PlatformShell> {
  int _selectedIndex = 0;

  static const _routes = ['/platform', '/platform/schools'];

  static const _destinations = [
    (icon: Icons.dashboard, label: 'Dashboard'),
    (icon: Icons.school, label: 'Escolas'),
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
                      child: Icon(Icons.admin_panel_settings),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      auth.username ?? 'Platform',
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
                  .map((d) => NavigationRailDestination(
                        icon: Icon(d.icon),
                        label: Text(d.label),
                      ))
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
              .map((d) => NavigationDestination(
                    icon: Icon(d.icon),
                    label: d.label,
                  ))
              .toList(),
        ),
      );
    }
  }
}

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
    '/teacher/attendance',
    '/messages',
    '/admin/children',
    '/admin/employees',
    '/admin/finance',
    '/admin/academic/turmas',
    '/admin/absences',
  ];

  static const _destinations = [
    (icon: Icons.dashboard, label: 'Dashboard'),
    (icon: Icons.how_to_reg, label: 'Presenças'),
    (icon: Icons.chat_bubble_outline, label: 'Mensagens'),
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

    // Bottom nav shows only the first 3 items; rest accessible via nav rail
    const bottomNavCount = 3;
    const bottomNavDestinations = [
      (icon: Icons.dashboard, label: 'Dashboard'),
      (icon: Icons.how_to_reg, label: 'Presenças'),
      (icon: Icons.chat_bubble_outline, label: 'Mensagens'),
    ];

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
      // Mobile: show 3 items + "Mais" drawer
      final mobileIndex = _selectedIndex < bottomNavCount ? _selectedIndex : 0;
      return Scaffold(
        body: widget.child,
        bottomNavigationBar: NavigationBar(
          selectedIndex: mobileIndex,
          onDestinationSelected: (index) {
            if (index < bottomNavCount) {
              _onDestinationSelected(index);
            }
          },
          destinations: [
            ...bottomNavDestinations.map(
              (d) => NavigationDestination(
                icon: Icon(d.icon),
                label: d.label,
              ),
            ),
            const NavigationDestination(
              icon: Icon(Icons.more_horiz),
              label: 'Mais',
            ),
          ],
        ),
        drawer: Drawer(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              DrawerHeader(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const CircleAvatar(
                      radius: 24,
                      child: Icon(Icons.person),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      auth.username ?? 'Administrador',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onPrimaryContainer,
                          ),
                    ),
                  ],
                ),
              ),
              _DrawerItem(
                icon: Icons.photo_library,
                label: 'Galeria de Fotos',
                onTap: () {
                  Navigator.pop(context);
                  context.push('/photos');
                },
              ),
              _DrawerItem(
                icon: Icons.warning_amber,
                label: 'Ocorrências',
                onTap: () {
                  Navigator.pop(context);
                  context.push('/incidents');
                },
              ),
              _DrawerItem(
                icon: Icons.event,
                label: 'Calendário',
                onTap: () {
                  Navigator.pop(context);
                  context.push('/events');
                },
              ),
              _DrawerItem(
                icon: Icons.notifications,
                label: 'Notificações',
                onTap: () {
                  Navigator.pop(context);
                  context.push('/notifications');
                },
              ),
              const Divider(),
              _DrawerItem(
                icon: Icons.child_care,
                label: 'Crianças',
                onTap: () {
                  Navigator.pop(context);
                  context.go('/admin/children');
                },
              ),
              _DrawerItem(
                icon: Icons.people,
                label: 'Funcionários',
                onTap: () {
                  Navigator.pop(context);
                  context.go('/admin/employees');
                },
              ),
              _DrawerItem(
                icon: Icons.account_balance_wallet,
                label: 'Financeiro',
                onTap: () {
                  Navigator.pop(context);
                  context.go('/admin/finance');
                },
              ),
              _DrawerItem(
                icon: Icons.school,
                label: 'Turmas',
                onTap: () {
                  Navigator.pop(context);
                  context.go('/admin/academic/turmas');
                },
              ),
              _DrawerItem(
                icon: Icons.event_busy,
                label: 'Ausências',
                onTap: () {
                  Navigator.pop(context);
                  context.go('/admin/absences');
                },
              ),
              const Divider(),
              _DrawerItem(
                icon: Icons.logout,
                label: 'Sair',
                onTap: () {
                  Navigator.pop(context);
                  ref.read(authProvider.notifier).logout();
                },
              ),
            ],
          ),
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

  static const _routes = [
    '/teacher',
    '/teacher/attendance',
    '/teacher/caderneta',
    '/messages',
  ];

  static const _destinations = [
    (icon: Icons.dashboard, label: 'Dashboard'),
    (icon: Icons.how_to_reg, label: 'Presenças'),
    (icon: Icons.book, label: 'Caderneta'),
    (icon: Icons.chat_bubble_outline, label: 'Mensagens'),
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

  static const _routes = [
    '/parent',
    '/messages',
    '/photos',
    '/parent/caderneta',
    '/parent/menu',
  ];

  static const _destinations = [
    (icon: Icons.home, label: 'Início'),
    (icon: Icons.chat_bubble_outline, label: 'Mensagens'),
    (icon: Icons.photo_library, label: 'Galeria'),
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
// Helper drawer item widget
// ---------------------------------------------------------------------------

class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _DrawerItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      onTap: onTap,
      dense: true,
    );
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
          UserRole.platformAdmin => '/platform',
          UserRole.schoolAdmin => '/admin',
          UserRole.teacher || UserRole.staff => '/teacher',
          UserRole.parent => '/parent',
          null => '/login',
        };
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (_, __) => const LoginScreen(),
      ),

      // Platform admin shell
      ShellRoute(
        builder: (context, state, child) => PlatformShell(child: child),
        routes: [
          GoRoute(
            path: '/platform',
            builder: (_, __) => const PlatformDashboardScreen(),
          ),
          GoRoute(
            path: '/platform/schools',
            builder: (_, __) => const SchoolsScreen(),
          ),
        ],
      ),

      // School admin shell
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
          GoRoute(
            path: '/teacher/attendance',
            builder: (_, __) => const AttendanceScreen(),
          ),
          GoRoute(
            path: '/messages',
            builder: (_, __) => const MessagesScreen(),
          ),
          GoRoute(
            path: '/messages/thread/:threadId',
            builder: (_, s) => ThreadScreen(
              threadId: s.pathParameters['threadId']!,
              subject: s.uri.queryParameters['subject'],
            ),
          ),
          GoRoute(
            path: '/photos',
            builder: (_, __) => const PhotosScreen(),
          ),
          GoRoute(
            path: '/incidents',
            builder: (_, __) => const IncidentsScreen(),
          ),
          GoRoute(
            path: '/events',
            builder: (_, __) => const EventsScreen(),
          ),
          GoRoute(
            path: '/notifications',
            builder: (_, __) => const NotificationsScreen(),
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
          GoRoute(
            path: '/teacher/attendance',
            builder: (_, __) => const AttendanceScreen(),
          ),
          GoRoute(
            path: '/messages',
            builder: (_, __) => const MessagesScreen(),
          ),
          GoRoute(
            path: '/messages/thread/:threadId',
            builder: (_, s) => ThreadScreen(
              threadId: s.pathParameters['threadId']!,
              subject: s.uri.queryParameters['subject'],
            ),
          ),
          GoRoute(
            path: '/photos',
            builder: (_, __) => const PhotosScreen(),
          ),
          GoRoute(
            path: '/incidents',
            builder: (_, __) => const IncidentsScreen(),
          ),
          GoRoute(
            path: '/events',
            builder: (_, __) => const EventsScreen(),
          ),
          GoRoute(
            path: '/notifications',
            builder: (_, __) => const NotificationsScreen(),
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
          GoRoute(
            path: '/messages',
            builder: (_, __) => const MessagesScreen(),
          ),
          GoRoute(
            path: '/messages/thread/:threadId',
            builder: (_, s) => ThreadScreen(
              threadId: s.pathParameters['threadId']!,
              subject: s.uri.queryParameters['subject'],
            ),
          ),
          GoRoute(
            path: '/photos',
            builder: (_, __) => const PhotosScreen(),
          ),
          GoRoute(
            path: '/notifications',
            builder: (_, __) => const NotificationsScreen(),
          ),
          GoRoute(
            path: '/events',
            builder: (_, __) => const EventsScreen(),
          ),
        ],
      ),
    ],
  );
});
