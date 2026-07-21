import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/auth/auth_state.dart';
import '../../core/models/school.dart';
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
import '../../features/admin/academic/schedules_screen.dart';
import '../../features/admin/academic/enrollments_screen.dart';
import '../../features/admin/absences/absences_screen.dart';
import '../../features/admin/people/people_hub_screen.dart';
import '../../features/admin/academic/academic_hub_screen.dart';
import '../../features/admin/health_hub/health_hub_screen.dart';
import '../../features/admin/comms/comms_hub_screen.dart';
import '../../features/admin/activities/activities_hub_screen.dart';
import '../../features/parent/children_hub/parent_children_hub.dart';
import '../../features/parent/school_hub/parent_school_hub.dart';
import '../../features/parent/authorizations_hub/parent_auth_hub.dart';
import '../../features/platform/dashboard/platform_dashboard_screen.dart';
import '../../features/platform/schools/schools_screen.dart';
import '../../features/platform/website/website_dashboard_screen.dart';
import '../../features/platform/website/website_page_editor_screen.dart';
import '../../features/platform/website/website_section_editor_screen.dart';
import '../../features/platform/website/website_settings_screen.dart';
import '../../features/platform/website/website_media_screen.dart';
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
import '../../features/admin/finance/billing_items_screen.dart';
import '../../features/admin/finance/credit_balances_screen.dart';
import '../../features/admin/finance/payment_plans_screen.dart';
import '../../features/admin/finance/reminders_screen.dart';
import '../../features/admin/finance/statement_screen.dart';
import '../../features/admin/finance/audit_log_screen.dart';
import '../../features/admin/finance/payment_references_screen.dart';
import '../../features/announcements/announcements_screen.dart';
import '../../features/documents/documents_screen.dart';
import '../../features/appointments/appointments_screen.dart';
import '../../features/evaluations/evaluations_screen.dart';
import '../../features/health/health_events_screen.dart';
import '../../features/health/immunizations_screen.dart';
import '../../features/admin/guardians/guardians_list_screen.dart';
import '../../features/admin/guardians/guardian_form_screen.dart';
import '../../features/admin/school_settings_screen.dart';
import '../../features/admin/school_profile_screen.dart';
import '../../features/admin/food/admin_food_screen.dart';
import '../../features/admin/food/food_hub_screen.dart';
import '../../features/trip_authorizations/trip_authorizations_screen.dart';
import '../../features/pickup/pickup_authorizations_screen.dart';
import '../../features/pickup/meal_orders_screen.dart';
import '../../features/admin/finance/cash_sessions_screen.dart';
import '../../features/teacher/attendance/attendance_history_screen.dart';
import '../../features/parent/food/parent_food_hub.dart';
import '../../features/admin/reports/med_report_screen.dart';
import '../../features/admin/academic/subjects_screen.dart';
import '../../features/admin/academic/turma_subjects_screen.dart';
import '../../features/admin/academic/report_cards_screen.dart';
import '../../features/admin/academic/timetable_screen.dart';
import '../../features/teacher/grades/grades_screen.dart';
import '../../features/parent/grades/parent_grades_screen.dart';
import '../../core/api/api_client.dart';
import '../../core/providers/currency_provider.dart';
import '../../features/notifications/notifications_screen.dart';

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
// Multi-role users get the union of their applicable lists (deduped by path).
// ---------------------------------------------------------------------------

// Platform Admin
const _platformItems = [
  SidebarItem(path: '/platform',         label: 'Dashboard', icon: Icons.dashboard_outlined, selectedIcon: Icons.dashboard),
  SidebarItem(path: '/platform/schools', label: 'Escolas',   icon: Icons.school_outlined,    selectedIcon: Icons.school),
  SidebarItem(path: '/platform/website', label: 'Website',   icon: Icons.language_outlined,  selectedIcon: Icons.language),
];

// School Admin — full access
const _adminItems = [
  SidebarItem(path: '/admin',                 label: 'Dashboard',    icon: Icons.dashboard_outlined,              selectedIcon: Icons.dashboard),
  SidebarItem(path: '/admin/people',          label: 'Pessoas',      icon: Icons.people_outline,                  selectedIcon: Icons.people),
  SidebarItem(path: '/admin/academic',        label: 'Académico',    icon: Icons.school_outlined,                 selectedIcon: Icons.school),
  SidebarItem(path: '/admin/finance',         label: 'Financeiro',   icon: Icons.account_balance_wallet_outlined, selectedIcon: Icons.account_balance_wallet),
  SidebarItem(path: '/admin/health-hub',      label: 'Saúde',        icon: Icons.health_and_safety_outlined,      selectedIcon: Icons.health_and_safety),
  SidebarItem(path: '/admin/comms',           label: 'Comunicação',  icon: Icons.forum_outlined,                  selectedIcon: Icons.forum),
  SidebarItem(path: '/admin/activities',      label: 'Actividades',  icon: Icons.category_outlined,               selectedIcon: Icons.category),
  SidebarItem(path: '/admin/food-hub',        label: 'Alimentação',  icon: Icons.restaurant_outlined,             selectedIcon: Icons.restaurant),
  SidebarItem(path: '/admin/reports/med',     label: 'Relatórios',   icon: Icons.bar_chart_outlined,              selectedIcon: Icons.bar_chart),
  SidebarItem(path: '/notifications',         label: 'Notificações', icon: Icons.notifications_outlined,          selectedIcon: Icons.notifications),
  SidebarItem(path: '/admin/school-settings', label: 'Configurações',icon: Icons.settings_outlined,               selectedIcon: Icons.settings),
];

// Coordinator — academic management, no finance, no school settings
const _coordinatorItems = [
  SidebarItem(path: '/admin',             label: 'Dashboard',    icon: Icons.dashboard_outlined,         selectedIcon: Icons.dashboard),
  SidebarItem(path: '/admin/people',      label: 'Pessoas',      icon: Icons.people_outline,             selectedIcon: Icons.people),
  SidebarItem(path: '/admin/academic',    label: 'Académico',    icon: Icons.school_outlined,            selectedIcon: Icons.school),
  SidebarItem(path: '/admin/health-hub',  label: 'Saúde',        icon: Icons.health_and_safety_outlined, selectedIcon: Icons.health_and_safety),
  SidebarItem(path: '/admin/comms',       label: 'Comunicação',  icon: Icons.forum_outlined,             selectedIcon: Icons.forum),
  SidebarItem(path: '/admin/activities',  label: 'Actividades',  icon: Icons.category_outlined,          selectedIcon: Icons.category),
  SidebarItem(path: '/admin/food-hub',    label: 'Alimentação',  icon: Icons.restaurant_outlined,        selectedIcon: Icons.restaurant),
  SidebarItem(path: '/admin/reports/med', label: 'Relatórios',   icon: Icons.bar_chart_outlined,         selectedIcon: Icons.bar_chart),
  SidebarItem(path: '/notifications',     label: 'Notificações', icon: Icons.notifications_outlined,     selectedIcon: Icons.notifications),
];

// Finance Officer — finance only
const _financeItems = [
  SidebarItem(path: '/admin/finance', label: 'Financeiro',   icon: Icons.account_balance_wallet_outlined, selectedIcon: Icons.account_balance_wallet),
  SidebarItem(path: '/notifications', label: 'Notificações', icon: Icons.notifications_outlined,          selectedIcon: Icons.notifications),
];

// Secretary — enrollment lookup, comms, read-only admin
const _secretaryItems = [
  SidebarItem(path: '/admin/people',   label: 'Pessoas',      icon: Icons.people_outline,         selectedIcon: Icons.people),
  SidebarItem(path: '/admin/academic', label: 'Académico',    icon: Icons.school_outlined,         selectedIcon: Icons.school),
  SidebarItem(path: '/admin/absences', label: 'Ausências',    icon: Icons.event_busy_outlined,     selectedIcon: Icons.event_busy),
  SidebarItem(path: '/announcements',  label: 'Comunicados',  icon: Icons.campaign_outlined,       selectedIcon: Icons.campaign),
  SidebarItem(path: '/messages',       label: 'Mensagens',    icon: Icons.chat_bubble_outline,     selectedIcon: Icons.chat_bubble),
  SidebarItem(path: '/notifications',  label: 'Notificações', icon: Icons.notifications_outlined,  selectedIcon: Icons.notifications),
];

// Teacher — classroom operations
const _teacherItems = [
  SidebarItem(path: '/teacher',               label: 'Dashboard',     icon: Icons.dashboard_outlined,                 selectedIcon: Icons.dashboard),
  SidebarItem(path: '/teacher/attendance',    label: 'Presenças',     icon: Icons.fact_check_outlined,                selectedIcon: Icons.fact_check),
  SidebarItem(path: '/teacher/caderneta',     label: 'Caderneta',     icon: Icons.menu_book_outlined,                 selectedIcon: Icons.menu_book),
  SidebarItem(path: '/teacher/grades',        label: 'Notas',         icon: Icons.grade_outlined,                     selectedIcon: Icons.grade),
  SidebarItem(path: '/timetable',             label: 'Horário',       icon: Icons.table_chart_outlined,               selectedIcon: Icons.table_chart),
  SidebarItem(path: '/health',                label: 'Saúde',         icon: Icons.health_and_safety_outlined,         selectedIcon: Icons.health_and_safety),
  SidebarItem(path: '/health/immunizations',  label: 'Vacinas',       icon: Icons.vaccines_outlined,                  selectedIcon: Icons.vaccines),
  SidebarItem(path: '/incidents',             label: 'Ocorrências',   icon: Icons.report_outlined,                    selectedIcon: Icons.report),
  SidebarItem(path: '/evaluations',           label: 'Avaliações',    icon: Icons.school_outlined,                    selectedIcon: Icons.school),
  SidebarItem(path: '/announcements',         label: 'Comunicados',   icon: Icons.campaign_outlined,                  selectedIcon: Icons.campaign),
  SidebarItem(path: '/messages',              label: 'Mensagens',     icon: Icons.chat_bubble_outline,                selectedIcon: Icons.chat_bubble),
  SidebarItem(path: '/photos',                label: 'Galeria',       icon: Icons.photo_library_outlined,             selectedIcon: Icons.photo_library),
  SidebarItem(path: '/events',                label: 'Calendário',    icon: Icons.calendar_month_outlined,            selectedIcon: Icons.calendar_month),
  SidebarItem(path: '/trip-authorizations',   label: 'Autorizações',  icon: Icons.assignment_outlined,                selectedIcon: Icons.assignment),
  SidebarItem(path: '/pickup-authorizations', label: 'Levantamentos', icon: Icons.transfer_within_a_station_outlined, selectedIcon: Icons.transfer_within_a_station),
  SidebarItem(path: '/meal-orders',           label: 'Refeições',     icon: Icons.restaurant_menu_outlined,           selectedIcon: Icons.restaurant_menu),
  SidebarItem(path: '/appointments',          label: 'Marcações',     icon: Icons.event_available_outlined,           selectedIcon: Icons.event_available),
  SidebarItem(path: '/documents',             label: 'Documentos',    icon: Icons.folder_outlined,                    selectedIcon: Icons.folder),
  SidebarItem(path: '/notifications',         label: 'Notificações',  icon: Icons.notifications_outlined,             selectedIcon: Icons.notifications),
];

// Nurse — health + immunizations only
const _nurseItems = [
  SidebarItem(path: '/health',               label: 'Saúde',        icon: Icons.health_and_safety_outlined, selectedIcon: Icons.health_and_safety),
  SidebarItem(path: '/health/immunizations', label: 'Vacinas',      icon: Icons.vaccines_outlined,          selectedIcon: Icons.vaccines),
  SidebarItem(path: '/messages',             label: 'Mensagens',    icon: Icons.chat_bubble_outline,        selectedIcon: Icons.chat_bubble),
  SidebarItem(path: '/notifications',        label: 'Notificações', icon: Icons.notifications_outlined,     selectedIcon: Icons.notifications),
];

// Parent
const _parentItems = [
  SidebarItem(path: '/parent',                label: 'Início',         icon: Icons.home_outlined,                   selectedIcon: Icons.home),
  SidebarItem(path: '/parent/children',       label: 'Os Meus Filhos', icon: Icons.people_outline,                  selectedIcon: Icons.people),
  SidebarItem(path: '/parent/caderneta',      label: 'Caderneta',      icon: Icons.menu_book_outlined,              selectedIcon: Icons.menu_book),
  SidebarItem(path: '/parent/invoices',       label: 'Finanças',       icon: Icons.account_balance_wallet_outlined, selectedIcon: Icons.account_balance_wallet),
  SidebarItem(path: '/health',                label: 'Saúde',          icon: Icons.health_and_safety_outlined,      selectedIcon: Icons.health_and_safety),
  SidebarItem(path: '/parent/school',         label: 'Escola',         icon: Icons.school_outlined,                 selectedIcon: Icons.school),
  SidebarItem(path: '/parent/food',           label: 'Alimentação',    icon: Icons.restaurant_outlined,             selectedIcon: Icons.restaurant),
  SidebarItem(path: '/messages',              label: 'Mensagens',      icon: Icons.chat_bubble_outline,             selectedIcon: Icons.chat_bubble),
  SidebarItem(path: '/appointments',          label: 'Marcações',      icon: Icons.event_available_outlined,        selectedIcon: Icons.event_available),
  SidebarItem(path: '/parent/authorizations', label: 'Autorizações',   icon: Icons.assignment_outlined,             selectedIcon: Icons.assignment),
  SidebarItem(path: '/notifications',         label: 'Notificações',   icon: Icons.notifications_outlined,          selectedIcon: Icons.notifications),
];

// Student — minimal portal (secondary only)
const _studentItems = [
  SidebarItem(path: '/parent/grades', label: 'Boletim',      icon: Icons.grade_outlined,            selectedIcon: Icons.grade),
  SidebarItem(path: '/documents',     label: 'Documentos',   icon: Icons.folder_outlined,            selectedIcon: Icons.folder),
  SidebarItem(path: '/events',        label: 'Calendário',   icon: Icons.calendar_month_outlined,    selectedIcon: Icons.calendar_month),
  SidebarItem(path: '/notifications', label: 'Notificações', icon: Icons.notifications_outlined,     selectedIcon: Icons.notifications),
];

// ---------------------------------------------------------------------------
// Multi-role sidebar builder — merges applicable lists, dedupes by path
// ---------------------------------------------------------------------------

// Priority order determines whose items appear first when roles are merged
const _roleItemOrder = [
  (UserRole.platformAdmin,  _platformItems),
  (UserRole.schoolAdmin,    _adminItems),
  (UserRole.coordinator,    _coordinatorItems),
  (UserRole.financeOfficer, _financeItems),
  (UserRole.secretary,      _secretaryItems),
  (UserRole.teacher,        _teacherItems),
  (UserRole.nurse,          _nurseItems),
  (UserRole.parent,         _parentItems),
  (UserRole.student,        _studentItems),
];

/// Feature flag required per sidebar path. Paths not listed are always shown.
const _pathFeatureMap = {
  '/teacher/caderneta':     'caderneta',
  '/teacher/grades':        'grades',
  '/timetable':             'timetable_k12',
  '/evaluations':           'evaluations',
  '/parent/caderneta':      'caderneta',
  '/health/immunizations':  'immunizations',
  '/meal-orders':           'meal_orders',
  '/pickup-authorizations': 'pickup_auth',
  '/trip-authorizations':   'trip_auth',
  '/admin/reports/med':     'med_report',
};

List<SidebarItem> _buildSidebarItems(Set<UserRole> roles, [School? school]) {
  final seen = <String>{};
  final result = <SidebarItem>[];
  for (final (role, items) in _roleItemOrder) {
    if (roles.contains(role)) {
      for (final item in items) {
        final feature = _pathFeatureMap[item.path];
        if (feature != null && !(school?.hasFeature(feature) ?? true)) continue;
        if (seen.add(item.path)) result.add(item);
      }
    }
  }
  return result;
}

// ---------------------------------------------------------------------------
// Title helper
// ---------------------------------------------------------------------------

String _titleForPath(String path, List<SidebarItem> items) {
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
// Role home routes (used by redirect logic)
// ---------------------------------------------------------------------------

String _roleHome(Set<UserRole> roles) => _buildHomeFromRoles(roles);

String _buildHomeFromRoles(Set<UserRole> roles) {
  // Uses same priority order as AuthState.homeRoute
  if (roles.contains(UserRole.platformAdmin))  return '/platform';
  if (roles.contains(UserRole.schoolAdmin))    return '/admin';
  if (roles.contains(UserRole.coordinator))    return '/admin';
  if (roles.contains(UserRole.financeOfficer)) return '/admin/finance';
  if (roles.contains(UserRole.secretary))      return '/admin/people';
  if (roles.contains(UserRole.teacher))        return '/teacher';
  if (roles.contains(UserRole.nurse))          return '/health';
  if (roles.contains(UserRole.parent))         return '/parent';
  if (roles.contains(UserRole.student))        return '/parent/grades';
  return '/login';
}

// ---------------------------------------------------------------------------
// Unified Shell — single widget, selects nav items by role
// ---------------------------------------------------------------------------

class _UnifiedShell extends ConsumerWidget {
  final Widget child;
  const _UnifiedShell({required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final currentPath = GoRouterState.of(context).uri.path;
    final school = ref.watch(schoolInfoProvider).valueOrNull;

    final unread = ref.watch(unreadNotifCountProvider).valueOrNull ?? 0;

    final baseItems = _buildSidebarItems(auth.roles, school);

    // Inject notification badge count into the Notificações item
    final items = unread > 0
        ? baseItems.map((item) => item.path == '/notifications'
            ? SidebarItem(
                path: item.path,
                label: item.label,
                icon: item.icon,
                selectedIcon: item.selectedIcon,
                badge: unread,
              )
            : item).toList()
        : baseItems;

    return SidebarLayout(
      child: child,
      items: items,
      currentPath: currentPath,
      title: _titleForPath(currentPath, items),
      schoolName: !auth.hasRole(UserRole.platformAdmin) ? school?.name : null,
      schoolLogoUrl: !auth.hasRole(UserRole.platformAdmin) ? school?.logoUrl : null,
      onSchoolTap: auth.isAdmin ? () => context.go('/admin/school-profile') : null,
      actions: [
        IconButton(
          icon: const Icon(Icons.lock_outline),
          tooltip: 'Alterar palavra-passe',
          onPressed: () => showDialog(useRootNavigator: false, 
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
      final path = state.matchedLocation;
      final isLoginPage = path == '/login';

      if (isLoading) return null;

      // Not authenticated → login
      if (!isAuthenticated && !isLoginPage) return '/login';

      // Authenticated on login page → home
      if (isAuthenticated && isLoginPage) return _roleHome(authState.roles);

      // ── Role-based route guards ──────────────────────────────────────────
      final roles = authState.roles;
      const adminAreaRoles = {
        UserRole.schoolAdmin, UserRole.coordinator,
        UserRole.financeOfficer, UserRole.secretary,
      };

      // Platform routes: only platform admin
      if (path.startsWith('/platform') && !roles.contains(UserRole.platformAdmin)) {
        return _roleHome(roles);
      }

      // Admin area: admin-tier roles only
      if (path.startsWith('/admin') && !roles.any(adminAreaRoles.contains)) {
        return _roleHome(roles);
      }

      // Finance routes: must have finance access
      if (path.startsWith('/admin/finance') &&
          !roles.any({UserRole.schoolAdmin, UserRole.financeOfficer}.contains)) {
        return _roleHome(roles);
      }

      // School settings: school admin only
      if (path.startsWith('/admin/school-settings') && !roles.contains(UserRole.schoolAdmin)) {
        return _roleHome(roles);
      }

      // Teacher area: not for parent or student
      if (path.startsWith('/teacher') &&
          roles.any({UserRole.parent, UserRole.student}.contains) &&
          !roles.any({UserRole.teacher, UserRole.coordinator, UserRole.schoolAdmin}.contains)) {
        return _roleHome(roles);
      }

      // Parent-only routes
      if (path.startsWith('/parent') && !roles.contains(UserRole.parent) &&
          !roles.any(adminAreaRoles.contains) && !roles.contains(UserRole.platformAdmin)) {
        return _roleHome(roles);
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (_, __) => const LoginScreen(),
      ),

      // ── Single unified shell — all authenticated routes ──────────────────
      ShellRoute(
        builder: (context, state, child) => _UnifiedShell(child: child),
        routes: [

          // ── Platform admin ───────────────────────────────────────────────
          GoRoute(path: '/platform',         builder: (_, __) => const PlatformDashboardScreen()),
          GoRoute(path: '/platform/schools', builder: (_, __) => const SchoolsScreen()),

          // ── Platform: Website CMS ────────────────────────────────────────────
          GoRoute(path: '/platform/website', builder: (_, __) => const WebsiteDashboardScreen()),
          GoRoute(path: '/platform/website/pages/:pageId', builder: (_, s) => WebsitePageEditorScreen(pageId: s.pathParameters['pageId']!)),
          GoRoute(path: '/platform/website/pages/:pageId/sections/:sectionId', builder: (_, s) => WebsiteSectionEditorScreen(
            pageId: s.pathParameters['pageId']!,
            sectionId: s.pathParameters['sectionId']!,
          )),
          GoRoute(path: '/platform/website/settings', builder: (_, __) => const WebsiteSettingsScreen()),
          GoRoute(path: '/platform/website/media', builder: (_, __) => const WebsiteMediaScreen()),

          // ── School admin ─────────────────────────────────────────────────
          GoRoute(path: '/admin',                      builder: (_, __) => const AdminDashboardScreen()),
          GoRoute(path: '/admin/people',               builder: (_, __) => const PeopleHubScreen()),
          GoRoute(path: '/admin/academic',             builder: (_, __) => const AcademicHubScreen()),
          GoRoute(path: '/admin/health-hub',           builder: (_, __) => const HealthHubScreen()),
          GoRoute(path: '/admin/comms',                builder: (_, __) => const CommsHubScreen()),
          GoRoute(path: '/admin/activities',           builder: (_, __) => const ActivitiesHubScreen()),
          GoRoute(path: '/admin/children',             builder: (_, __) => const ChildrenListScreen()),
          GoRoute(path: '/admin/children/new',         builder: (_, __) => const ChildFormScreen()),
          GoRoute(path: '/admin/children/:id',         builder: (_, s)  => ChildDetailScreen(id: s.pathParameters['id']!)),
          GoRoute(path: '/admin/children/:id/edit',    builder: (_, s)  => ChildFormScreen(childId: s.pathParameters['id'])),
          GoRoute(path: '/admin/guardians',            builder: (_, __) => const GuardiansListScreen()),
          GoRoute(path: '/admin/guardians/new',        builder: (_, __) => const GuardianFormScreen()),
          GoRoute(path: '/admin/guardians/:id/edit',   builder: (_, s)  => GuardianFormScreen(guardianId: s.pathParameters['id'])),
          GoRoute(path: '/admin/employees',            builder: (_, __) => const EmployeesListScreen()),
          GoRoute(path: '/admin/employees/new',        builder: (_, __) => const EmployeeFormScreen()),
          GoRoute(path: '/admin/employees/:id/edit',   builder: (_, s)  => EmployeeFormScreen(employeeId: s.pathParameters['id'])),
          GoRoute(path: '/admin/absences',             builder: (_, __) => const AbsencesScreen()),
          GoRoute(path: '/admin/academic/turmas',      builder: (_, __) => const TurmasScreen()),
          GoRoute(path: '/admin/academic/schedules',   builder: (_, __) => const SchedulesScreen()),
          GoRoute(path: '/admin/academic/enrollments', builder: (_, __) => const EnrollmentsScreen()),
          GoRoute(path: '/admin/school-settings',      builder: (_, __) => const SchoolSettingsScreen()),
          GoRoute(path: '/admin/school-profile',       builder: (_, __) => const SchoolProfileScreen()),
          GoRoute(path: '/admin/food-hub',             builder: (_, __) => const FoodHubScreen()),
          GoRoute(path: '/admin/food',                 builder: (_, __) => const AdminFoodScreen()),
          GoRoute(path: '/admin/finance',              builder: (_, __) => const FinanceDashboardScreen()),
          GoRoute(path: '/admin/finance/invoices',     builder: (_, __) => const InvoicesScreen()),
          GoRoute(path: '/admin/finance/expenses',     builder: (_, __) => const ExpensesScreen()),
          GoRoute(path: '/admin/finance/contracts',    builder: (_, __) => const ContractsScreen()),
          GoRoute(path: '/admin/finance/receipts',     builder: (_, __) => const ReceiptsScreen()),
          GoRoute(path: '/admin/finance/credit-notes',       builder: (_, __) => const CreditNotesScreen()),
          GoRoute(path: '/admin/finance/saft',               builder: (_, __) => const SaftScreen()),
          GoRoute(path: '/admin/finance/delinquent',         builder: (_, __) => const DelinquentScreen()),
          GoRoute(path: '/admin/finance/billing-items',      builder: (_, __) => const BillingItemsScreen()),
          GoRoute(path: '/admin/finance/credits',            builder: (_, __) => const CreditBalancesScreen()),
          GoRoute(path: '/admin/finance/payment-plans',      builder: (_, __) => const PaymentPlansScreen()),
          GoRoute(path: '/admin/finance/reminders',          builder: (_, __) => const RemindersScreen()),
          GoRoute(path: '/admin/finance/statement',          builder: (_, __) => const StatementScreen()),
          GoRoute(path: '/admin/finance/audit-log',          builder: (_, __) => const AuditLogScreen()),
          GoRoute(path: '/admin/finance/payment-references', builder: (_, __) => const PaymentReferencesScreen()),
          GoRoute(path: '/admin/finance/cash-sessions',    builder: (_, __) => const CashSessionsScreen()),
          GoRoute(path: '/admin/reports/med',             builder: (_, __) => const MedReportScreen()),
          GoRoute(path: '/admin/academic/subjects',       builder: (_, __) => const SubjectsScreen()),
          GoRoute(path: '/admin/academic/turma-subjects', builder: (_, __) => const TurmaSubjectsScreen()),
          GoRoute(path: '/admin/academic/report-cards',   builder: (_, __) => const ReportCardsScreen()),
          GoRoute(path: '/admin/academic/timetable',      builder: (_, __) => const TimetableScreen()),

          // ── Teacher / Staff ──────────────────────────────────────────────
          GoRoute(path: '/teacher',                    builder: (_, __) => const TeacherDashboardScreen()),
          GoRoute(path: '/teacher/attendance',         builder: (_, __) => const AttendanceScreen()),
          GoRoute(path: '/teacher/attendance/history', builder: (_, __) => const AttendanceHistoryScreen()),
          GoRoute(path: '/teacher/grades',             builder: (_, __) => const GradesScreen()),
          GoRoute(path: '/teacher/caderneta',          builder: (_, __) => const CadernetaListScreen()),
          GoRoute(path: '/teacher/caderneta/new',      builder: (_, __) => const CadernetaFormScreen()),
          GoRoute(path: '/teacher/caderneta/:id/edit', builder: (_, s)  => CadernetaFormScreen(cadernetaId: s.pathParameters['id'])),

          // ── Parent ───────────────────────────────────────────────────────
          GoRoute(path: '/parent',                     builder: (_, __) => const ParentDashboardScreen()),
          GoRoute(path: '/parent/children',            builder: (_, __) => const ParentChildrenHubScreen()),
          GoRoute(path: '/parent/school',              builder: (_, __) => const ParentSchoolHubScreen()),
          GoRoute(path: '/parent/authorizations',      builder: (_, __) => const ParentAuthHubScreen()),
          GoRoute(path: '/parent/caderneta',           builder: (_, __) => const ChildCadernetaScreen()),
          GoRoute(path: '/parent/invoices',            builder: (_, __) => const ParentInvoicesScreen()),
          GoRoute(path: '/parent/food',                builder: (_, __) => const ParentFoodHubScreen()),
          GoRoute(path: '/parent/menu',                builder: (_, __) => const FoodMenuScreen()),
          GoRoute(path: '/parent/attendance',            builder: (_, __) => const AttendanceHistoryScreen()),
          GoRoute(path: '/parent/grades',              builder: (_, __) => const ParentGradesScreen()),

          // ── Timetable (shared: admin via hub + teacher read-only) ───────
          GoRoute(path: '/timetable', builder: (_, __) => const TimetableScreen()),

          // ── Shared routes (registered ONCE — shell picks correct nav) ────
          GoRoute(path: '/announcements',              builder: (_, __) => const AnnouncementsScreen()),
          GoRoute(path: '/messages',                   builder: (_, __) => const MessagesScreen()),
          GoRoute(path: '/messages/thread/:threadId',  builder: (_, s)  => ThreadScreen(
            threadId: s.pathParameters['threadId']!,
            subject: s.uri.queryParameters['subject'],
          )),
          GoRoute(path: '/photos',                     builder: (_, __) => const PhotosScreen()),
          GoRoute(path: '/documents',                  builder: (_, __) => const DocumentsScreen()),
          GoRoute(path: '/events',                     builder: (_, __) => const EventsScreen()),
          GoRoute(path: '/appointments',               builder: (_, __) => const AppointmentsScreen()),
          GoRoute(path: '/notifications',              builder: (_, __) => const NotificationsScreen()),
          GoRoute(path: '/health',                     builder: (_, __) => const HealthEventsScreen()),
          GoRoute(path: '/health/immunizations',       builder: (_, __) => const ImmunizationsScreen()),
          GoRoute(path: '/evaluations',                builder: (_, __) => const EvaluationsScreen()),
          GoRoute(path: '/incidents',                  builder: (_, __) => const IncidentsScreen()),
          GoRoute(path: '/trip-authorizations',        builder: (_, __) => const TripAuthorizationsScreen()),
          GoRoute(path: '/pickup-authorizations',      builder: (_, __) => const PickupAuthorizationsScreen()),
          GoRoute(path: '/meal-orders',                builder: (_, __) => const MealOrdersScreen()),
        ],
      ),
    ],
  );
});
