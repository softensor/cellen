import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/auth/auth_state.dart';
import '../../core/widgets/sidebar_layout.dart';
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
import '../../features/parent/finance/parent_invoices_screen.dart';
import '../../features/parent/menu/food_menu_screen.dart';
import '../../features/messages/messages_screen.dart';
import '../../features/messages/thread_screen.dart';
import '../../features/photos/photos_screen.dart';
import '../../features/incidents/incidents_screen.dart';
import '../../features/events/events_screen.dart';
import '../../features/notifications/notifications_screen.dart';
import '../../features/finance/contracts_screen.dart';
import '../../features/finance/receipts_screen.dart';
import '../../features/finance/credit_notes_screen.dart';
import '../../features/finance/saft_screen.dart';
import '../../features/finance/delinquent_screen.dart';
import '../../features/announcements/announcements_screen.dart';
import '../../features/documents/documents_screen.dart';
import '../../features/appointments/appointments_screen.dart';
import '../../features/evaluations/evaluations_screen.dart';
import '../../features/health/health_events_screen.dart';
import '../../features/health/immunizations_screen.dart';
import '../../features/admin/guardians/guardians_list_screen.dart';
import '../../features/admin/guardians/guardian_form_screen.dart';
import '../../features/admin/school_settings_screen.dart';
import '../../features/trip_authorizations/trip_authorizations_screen.dart';
import '../../features/pickup/pickup_authorizations_screen.dart';
import '../../features/pickup/meal_orders_screen.dart';
import '../../core/api/api_client.dart';

// ---------------------------------------------------------------------------
// Change Password Dialog
// ---------------------------------------------------------------------------

class _ChangePasswordDialog extends ConsumerStatefulWidget {
  const _ChangePasswordDialog();

  @override
  ConsumerState<_ChangePasswordDialog> createState() =>
      _ChangePasswordDialogState();
}

class _ChangePasswordDialogState
    extends ConsumerState<_ChangePasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _currentCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      await api.post('/auth/change-password', data: {
        'current_password': _currentCtrl.text,
        'new_password': _newCtrl.text,
      });
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Palavra-passe alterada com sucesso')),
        );
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Alterar Palavra-passe'),
      content: SizedBox(
        width: 360,
        child: Form(
          key: _formKey,
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
                  child: Text(_error!,
                      style: TextStyle(
                          color: Theme.of(context)
                              .colorScheme
                              .onErrorContainer)),
                ),
                const SizedBox(height: 12),
              ],
              TextFormField(
                controller: _currentCtrl,
                decoration: const InputDecoration(
                    labelText: 'Palavra-passe actual'),
                obscureText: true,
                validator: (v) =>
                    v == null || v.isEmpty ? 'Obrigatório' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _newCtrl,
                decoration: const InputDecoration(
                    labelText: 'Nova palavra-passe'),
                obscureText: true,
                validator: (v) => v == null || v.length < 6
                    ? 'Mínimo 6 caracteres'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _confirmCtrl,
                decoration: const InputDecoration(
                    labelText: 'Confirmar nova palavra-passe'),
                obscureText: true,
                validator: (v) =>
                    v != _newCtrl.text ? 'As palavras-passe não coincidem' : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _loading ? null : _submit,
          child: _loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Alterar'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Nav item definitions per role
// ---------------------------------------------------------------------------

const _adminItems = [
  SidebarItem(path: '/admin', label: 'Dashboard', icon: Icons.dashboard_outlined, selectedIcon: Icons.dashboard),
  SidebarItem(path: '/admin/children', label: 'Crianças', icon: Icons.child_care_outlined, selectedIcon: Icons.child_care),
  SidebarItem(path: '/admin/guardians', label: 'Encarregados', icon: Icons.people_outline, selectedIcon: Icons.people),
  SidebarItem(path: '/teacher/attendance', label: 'Presenças', icon: Icons.fact_check_outlined, selectedIcon: Icons.fact_check),
  SidebarItem(path: '/admin/finance', label: 'Financeiro', icon: Icons.account_balance_wallet_outlined, selectedIcon: Icons.account_balance_wallet),
  SidebarItem(path: '/messages', label: 'Mensagens', icon: Icons.chat_bubble_outline, selectedIcon: Icons.chat_bubble),
  SidebarItem(path: '/admin/employees', label: 'Funcionários', icon: Icons.badge_outlined, selectedIcon: Icons.badge),
  SidebarItem(path: '/admin/absences', label: 'Faltas', icon: Icons.event_busy_outlined, selectedIcon: Icons.event_busy),
  SidebarItem(path: '/admin/academic/turmas', label: 'Turmas', icon: Icons.class_outlined, selectedIcon: Icons.class_),
  SidebarItem(path: '/admin/academic/enrollments', label: 'Matrículas', icon: Icons.how_to_reg_outlined, selectedIcon: Icons.how_to_reg),
  SidebarItem(path: '/admin/school-settings', label: 'Configurações', icon: Icons.settings_outlined, selectedIcon: Icons.settings),
  SidebarItem(path: '/events', label: 'Calendário', icon: Icons.calendar_month_outlined, selectedIcon: Icons.calendar_month),
  SidebarItem(path: '/photos', label: 'Galeria', icon: Icons.photo_library_outlined, selectedIcon: Icons.photo_library),
  SidebarItem(path: '/incidents', label: 'Ocorrências', icon: Icons.report_outlined, selectedIcon: Icons.report),
  SidebarItem(path: '/announcements', label: 'Comunicados', icon: Icons.campaign_outlined, selectedIcon: Icons.campaign),
  SidebarItem(path: '/documents', label: 'Documentos', icon: Icons.folder_outlined, selectedIcon: Icons.folder),
  SidebarItem(path: '/evaluations', label: 'Avaliações', icon: Icons.school_outlined, selectedIcon: Icons.school),
  SidebarItem(path: '/health', label: 'Saúde', icon: Icons.health_and_safety_outlined, selectedIcon: Icons.health_and_safety),
  SidebarItem(path: '/admin/health/immunizations', label: 'Vacinas', icon: Icons.vaccines_outlined, selectedIcon: Icons.vaccines),
  SidebarItem(path: '/appointments', label: 'Marcações', icon: Icons.calendar_month_outlined, selectedIcon: Icons.calendar_month),
  SidebarItem(path: '/trip-authorizations', label: 'Autorizações', icon: Icons.assignment_outlined, selectedIcon: Icons.assignment),
  SidebarItem(path: '/pickup-authorizations', label: 'Levantamentos', icon: Icons.transfer_within_a_station_outlined, selectedIcon: Icons.transfer_within_a_station),
  SidebarItem(path: '/meal-orders', label: 'Refeições', icon: Icons.restaurant_menu_outlined, selectedIcon: Icons.restaurant_menu),
  SidebarItem(path: '/notifications', label: 'Notificações', icon: Icons.notifications_outlined, selectedIcon: Icons.notifications),
];

const _teacherItems = [
  SidebarItem(path: '/teacher', label: 'Dashboard', icon: Icons.dashboard_outlined, selectedIcon: Icons.dashboard),
  SidebarItem(path: '/teacher/attendance', label: 'Presenças', icon: Icons.fact_check_outlined, selectedIcon: Icons.fact_check),
  SidebarItem(path: '/teacher/caderneta', label: 'Caderneta', icon: Icons.menu_book_outlined, selectedIcon: Icons.menu_book),
  SidebarItem(path: '/announcements', label: 'Comunicados', icon: Icons.campaign_outlined, selectedIcon: Icons.campaign),
  SidebarItem(path: '/evaluations', label: 'Avaliações', icon: Icons.school_outlined, selectedIcon: Icons.school),
  SidebarItem(path: '/health', label: 'Saúde', icon: Icons.health_and_safety_outlined, selectedIcon: Icons.health_and_safety),
  SidebarItem(path: '/teacher/health/immunizations', label: 'Vacinas', icon: Icons.vaccines_outlined, selectedIcon: Icons.vaccines),
  SidebarItem(path: '/appointments', label: 'Marcações', icon: Icons.calendar_month_outlined, selectedIcon: Icons.calendar_month),
  SidebarItem(path: '/trip-authorizations', label: 'Autorizações', icon: Icons.assignment_outlined, selectedIcon: Icons.assignment),
  SidebarItem(path: '/pickup-authorizations', label: 'Levantamentos', icon: Icons.transfer_within_a_station_outlined, selectedIcon: Icons.transfer_within_a_station),
  SidebarItem(path: '/meal-orders', label: 'Refeições', icon: Icons.restaurant_menu_outlined, selectedIcon: Icons.restaurant_menu),
  SidebarItem(path: '/messages', label: 'Mensagens', icon: Icons.chat_bubble_outline, selectedIcon: Icons.chat_bubble),
  SidebarItem(path: '/notifications', label: 'Notificações', icon: Icons.notifications_outlined, selectedIcon: Icons.notifications),
];

const _parentItems = [
  SidebarItem(path: '/parent', label: 'Início', icon: Icons.home_outlined, selectedIcon: Icons.home),
  SidebarItem(path: '/messages', label: 'Mensagens', icon: Icons.chat_bubble_outline, selectedIcon: Icons.chat_bubble),
  SidebarItem(path: '/photos', label: 'Galeria', icon: Icons.photo_library_outlined, selectedIcon: Icons.photo_library),
  SidebarItem(path: '/parent/caderneta', label: 'Caderneta', icon: Icons.menu_book_outlined, selectedIcon: Icons.menu_book),
  SidebarItem(path: '/parent/menu', label: 'Ementa', icon: Icons.restaurant_outlined, selectedIcon: Icons.restaurant),
  SidebarItem(path: '/announcements', label: 'Comunicados', icon: Icons.campaign_outlined, selectedIcon: Icons.campaign),
  SidebarItem(path: '/documents', label: 'Documentos', icon: Icons.folder_outlined, selectedIcon: Icons.folder),
  SidebarItem(path: '/appointments', label: 'Marcações', icon: Icons.calendar_month_outlined, selectedIcon: Icons.calendar_month),
  SidebarItem(path: '/health', label: 'Saúde', icon: Icons.health_and_safety_outlined, selectedIcon: Icons.health_and_safety),
  SidebarItem(path: '/evaluations', label: 'Avaliações', icon: Icons.school_outlined, selectedIcon: Icons.school),
  SidebarItem(path: '/trip-authorizations', label: 'Autorizações', icon: Icons.assignment_outlined, selectedIcon: Icons.assignment),
  SidebarItem(path: '/pickup-authorizations', label: 'Levantamentos', icon: Icons.transfer_within_a_station_outlined, selectedIcon: Icons.transfer_within_a_station),
  SidebarItem(path: '/meal-orders', label: 'Pré-Refeições', icon: Icons.restaurant_menu_outlined, selectedIcon: Icons.restaurant_menu),
  SidebarItem(path: '/parent/invoices', label: 'Faturas', icon: Icons.receipt_long_outlined, selectedIcon: Icons.receipt_long),
];

const _platformItems = [
  SidebarItem(path: '/platform', label: 'Dashboard', icon: Icons.dashboard_outlined, selectedIcon: Icons.dashboard),
  SidebarItem(path: '/platform/schools', label: 'Escolas', icon: Icons.school_outlined, selectedIcon: Icons.school),
];

// ---------------------------------------------------------------------------
// Title helper
// ---------------------------------------------------------------------------

String _titleForPath(String path, List<SidebarItem> items) {
  // Find the most specific matching item
  SidebarItem? best;
  for (final item in items) {
    if (path.startsWith(item.path)) {
      if (best == null || item.path.length > best.path.length) {
        best = item;
      }
    }
  }
  return best?.label ?? 'Cellen';
}

// ---------------------------------------------------------------------------
// Shell Widgets
// ---------------------------------------------------------------------------

class PlatformShell extends ConsumerWidget {
  final Widget child;
  const PlatformShell({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentPath = GoRouterState.of(context).uri.path;
    return SidebarLayout(
      child: child,
      items: _platformItems,
      currentPath: currentPath,
      title: _titleForPath(currentPath, _platformItems),
      actions: [
        IconButton(
          icon: const Icon(Icons.lock_outline),
          tooltip: 'Alterar palavra-passe',
          onPressed: () => showDialog(
            context: context,
            builder: (_) => const _ChangePasswordDialog(),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.logout),
          tooltip: 'Sair',
          onPressed: () => ref.read(authProvider.notifier).logout(),
        ),
      ],
    );
  }
}

class AdminShell extends ConsumerWidget {
  final Widget child;
  const AdminShell({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentPath = GoRouterState.of(context).uri.path;
    return SidebarLayout(
      child: child,
      items: _adminItems,
      currentPath: currentPath,
      title: _titleForPath(currentPath, _adminItems),
      actions: [
        IconButton(
          icon: const Icon(Icons.lock_outline),
          tooltip: 'Alterar palavra-passe',
          onPressed: () => showDialog(
            context: context,
            builder: (_) => const _ChangePasswordDialog(),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.logout),
          tooltip: 'Sair',
          onPressed: () => ref.read(authProvider.notifier).logout(),
        ),
      ],
    );
  }
}

class TeacherShell extends ConsumerWidget {
  final Widget child;
  const TeacherShell({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentPath = GoRouterState.of(context).uri.path;
    return SidebarLayout(
      child: child,
      items: _teacherItems,
      currentPath: currentPath,
      title: _titleForPath(currentPath, _teacherItems),
      actions: [
        IconButton(
          icon: const Icon(Icons.lock_outline),
          tooltip: 'Alterar palavra-passe',
          onPressed: () => showDialog(
            context: context,
            builder: (_) => const _ChangePasswordDialog(),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.logout),
          tooltip: 'Sair',
          onPressed: () => ref.read(authProvider.notifier).logout(),
        ),
      ],
    );
  }
}

class ParentShell extends ConsumerWidget {
  final Widget child;
  const ParentShell({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentPath = GoRouterState.of(context).uri.path;
    return SidebarLayout(
      child: child,
      items: _parentItems,
      currentPath: currentPath,
      title: _titleForPath(currentPath, _parentItems),
      actions: [
        IconButton(
          icon: const Icon(Icons.lock_outline),
          tooltip: 'Alterar palavra-passe',
          onPressed: () => showDialog(
            context: context,
            builder: (_) => const _ChangePasswordDialog(),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.logout),
          tooltip: 'Sair',
          onPressed: () => ref.read(authProvider.notifier).logout(),
        ),
      ],
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
            path: '/admin/guardians',
            builder: (_, __) => const GuardiansListScreen(),
          ),
          GoRoute(
            path: '/admin/guardians/new',
            builder: (_, __) => const GuardianFormScreen(),
          ),
          GoRoute(
            path: '/admin/guardians/:id/edit',
            builder: (_, s) =>
                GuardianFormScreen(guardianId: s.pathParameters['id']),
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
            path: '/admin/school-settings',
            builder: (_, __) => const SchoolSettingsScreen(),
          ),
          GoRoute(
            path: '/admin/finance/contracts',
            builder: (_, __) => const ContractsScreen(),
          ),
          GoRoute(
            path: '/admin/finance/receipts',
            builder: (_, __) => const ReceiptsScreen(),
          ),
          GoRoute(
            path: '/admin/finance/credit-notes',
            builder: (_, __) => const CreditNotesScreen(),
          ),
          GoRoute(
            path: '/admin/finance/saft',
            builder: (_, __) => const SaftScreen(),
          ),
          GoRoute(
            path: '/admin/finance/delinquent',
            builder: (_, __) => const DelinquentScreen(),
          ),
          GoRoute(
            path: '/teacher/attendance',
            builder: (_, __) => const AttendanceScreen(),
          ),
          GoRoute(
            path: '/announcements',
            builder: (_, __) => const AnnouncementsScreen(),
          ),
          GoRoute(
            path: '/documents',
            builder: (_, __) => const DocumentsScreen(),
          ),
          GoRoute(
            path: '/appointments',
            builder: (_, __) => const AppointmentsScreen(),
          ),
          GoRoute(
            path: '/trip-authorizations',
            builder: (_, __) => const TripAuthorizationsScreen(),
          ),
          GoRoute(
            path: '/pickup-authorizations',
            builder: (_, __) => const PickupAuthorizationsScreen(),
          ),
          GoRoute(
            path: '/meal-orders',
            builder: (_, __) => const MealOrdersScreen(),
          ),
          GoRoute(
            path: '/evaluations',
            builder: (_, __) => const EvaluationsScreen(),
          ),
          GoRoute(
            path: '/health',
            builder: (_, __) => const HealthEventsScreen(),
          ),
          GoRoute(
            path: '/admin/health/immunizations',
            builder: (_, __) => const ImmunizationsScreen(),
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
            path: '/announcements',
            builder: (_, __) => const AnnouncementsScreen(),
          ),
          GoRoute(
            path: '/evaluations',
            builder: (_, __) => const EvaluationsScreen(),
          ),
          GoRoute(
            path: '/health',
            builder: (_, __) => const HealthEventsScreen(),
          ),
          GoRoute(
            path: '/teacher/health/immunizations',
            builder: (_, __) => const ImmunizationsScreen(),
          ),
          GoRoute(
            path: '/appointments',
            builder: (_, __) => const AppointmentsScreen(),
          ),
          GoRoute(
            path: '/trip-authorizations',
            builder: (_, __) => const TripAuthorizationsScreen(),
          ),
          GoRoute(
            path: '/pickup-authorizations',
            builder: (_, __) => const PickupAuthorizationsScreen(),
          ),
          GoRoute(
            path: '/meal-orders',
            builder: (_, __) => const MealOrdersScreen(),
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
            path: '/parent/invoices',
            builder: (_, __) => const ParentInvoicesScreen(),
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
          GoRoute(
            path: '/announcements',
            builder: (_, __) => const AnnouncementsScreen(),
          ),
          GoRoute(
            path: '/documents',
            builder: (_, __) => const DocumentsScreen(),
          ),
          GoRoute(
            path: '/evaluations',
            builder: (_, __) => const EvaluationsScreen(),
          ),
          GoRoute(
            path: '/appointments',
            builder: (_, __) => const AppointmentsScreen(),
          ),
          GoRoute(
            path: '/health',
            builder: (_, __) => const HealthEventsScreen(),
          ),
          GoRoute(
            path: '/trip-authorizations',
            builder: (_, __) => const TripAuthorizationsScreen(),
          ),
          GoRoute(
            path: '/pickup-authorizations',
            builder: (_, __) => const PickupAuthorizationsScreen(),
          ),
          GoRoute(
            path: '/meal-orders',
            builder: (_, __) => const MealOrdersScreen(),
          ),
        ],
      ),
    ],
  );
});
