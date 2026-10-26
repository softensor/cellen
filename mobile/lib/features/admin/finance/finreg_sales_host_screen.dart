import 'package:cellen/core/api/api_client.dart';
import 'package:cellen/core/models/finreg_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/auth/auth_state.dart';
import '../../../core/models/custom_role.dart';
import '../../../core/models/role_definitions.dart';
import '../../../core/providers/currency_provider.dart';
import '../employees/employees_list_screen.dart';
import '../guardians/guardians_list_screen.dart';
import 'internal_payments_screen.dart';

/// Open a delegated launch address.
///
/// A deliberately public seam, as in Mwenenzo: `url_launcher` answers through
/// a platform channel that `flutter test` does not serve, so a widget test
/// driving the real button would fail on a missing plugin instead of on the
/// launch flow. Tests replace this; production never does.
Future<bool> Function(
  Uri url, {
  LaunchMode mode,
  String? webOnlyWindowName,
}) finregUrlLauncher = launchUrl;

/// How one capability is painted here. FinReg's manifest decides which
/// capabilities exist and whether they are operational; this registry only
/// supplies an icon and a label in the host's languages. A capability the
/// host has never heard of still appears, under the manifest's own title.
class _WorkspaceLook {
  const _WorkspaceLook(this.icon, this.labels);

  final IconData icon;
  final Map<String, String> labels;

  String label(String languageCode, String fallback) {
    final normalized = languageCode.toLowerCase().split(RegExp('[-_]')).first;
    return labels[normalized] ?? labels['pt'] ?? fallback;
  }
}

const _workspaceLooks = <String, _WorkspaceLook>{
  'parties': _WorkspaceLook(
      Icons.people_outline, {'pt': 'Pessoas e entidades', 'en': 'Parties'}),
  'catalog': _WorkspaceLook(
      Icons.category_outlined, {'pt': 'Catálogo', 'en': 'Catalog'}),
  'billing': _WorkspaceLook(Icons.receipt_long_outlined,
      {'pt': 'Vendas e facturação', 'en': 'Sales and billing'}),
  'receivables': _WorkspaceLook(Icons.request_quote_outlined,
      {'pt': 'Contas a receber', 'en': 'Receivables'}),
  'payments': _WorkspaceLook(Icons.payments_outlined,
      {'pt': 'Pagamentos e recibos', 'en': 'Payments and receipts'}),
  'recurring_billing': _WorkspaceLook(Icons.autorenew_outlined,
      {'pt': 'Cobrança recorrente', 'en': 'Recurring billing'}),
  'accounting': _WorkspaceLook(Icons.account_balance_outlined,
      {'pt': 'Contabilidade', 'en': 'Accounting'}),
  'reporting': _WorkspaceLook(
      Icons.analytics_outlined, {'pt': 'Relatórios', 'en': 'Reporting'}),
  'purchasing': _WorkspaceLook(
      Icons.shopping_cart_outlined, {'pt': 'Compras', 'en': 'Purchasing'}),
  'treasury': _WorkspaceLook(Icons.account_balance_wallet_outlined,
      {'pt': 'Tesouraria', 'en': 'Treasury'}),
  'integrations': _WorkspaceLook(
      Icons.hub_outlined, {'pt': 'Integrações', 'en': 'Integrations'}),
  'cash_sessions': _WorkspaceLook(Icons.point_of_sale_outlined,
      {'pt': 'Sessões de caixa', 'en': 'Cash sessions'}),
};

String _workspaceLabel(String capabilityId, String languageCode) {
  final look = _workspaceLooks[capabilityId];
  return look?.label(languageCode, capabilityId) ?? capabilityId;
}

Future<FinregManifest> _loadFinregManifest(ApiClient api) async {
  final value =
      Map<String, dynamic>.from(await api.get('/finreg/capabilities') as Map);
  return FinregManifest.fromJson(value);
}

/// Cellen's door into FinReg's own application.
///
/// FinReg used to be compiled into this app and mounted as a tab. That copy
/// could only ever be as current as the last Cellen release, and it made one
/// product's router fight the other's for the address bar. The workspace now
/// opens in FinReg itself: this screen lists what the school's manifest
/// offers, and each tap mints a single-use launch code and hands the address
/// to the browser. There is no token, no embedded router and no second copy
/// of FinReg's UI here.
class FinregSalesHostScreen extends ConsumerStatefulWidget {
  const FinregSalesHostScreen({
    super.key,
    this.initialCapabilityId = 'billing',
  });

  final String initialCapabilityId;

  @override
  ConsumerState<FinregSalesHostScreen> createState() =>
      _FinregSalesHostScreenState();
}

class _FinregSalesHostScreenState extends ConsumerState<FinregSalesHostScreen> {
  late Future<dynamic> _paymentMode;
  Future<FinregManifest>? _manifest;

  @override
  void initState() {
    super.initState();
    _paymentMode =
        ref.read(apiClientProvider).get('/finance/internal-payments/mode');
  }

  void _refresh() {
    setState(() {
      _paymentMode =
          ref.read(apiClientProvider).get('/finance/internal-payments/mode');
      _manifest = null;
    });
  }

  /// Mint a single-use launch code for one workspace. Minted at the tap,
  /// never with the screen: the code lives under a minute, so one fetched
  /// with the manifest would be dead by the time anyone pressed the button.
  Future<FinregWorkspaceLaunch> _createWorkspaceLaunch(
      String capabilityId) async {
    final payload = Map<String, dynamic>.from(await ref
        .read(apiClientProvider)
        .post('/finreg/workspace-launch/$capabilityId') as Map);
    return FinregWorkspaceLaunch.fromJson(payload);
  }

  Future<Map<String, dynamic>> _compositionReadiness(
      String capabilityId) async {
    final payload = await ref
        .read(apiClientProvider)
        .get('/finreg/composition-readiness/$capabilityId');
    return Map<String, dynamic>.from(payload as Map);
  }

  @override
  Widget build(BuildContext context) {
    final portuguese = Localizations.localeOf(context).languageCode == 'pt';
    return FutureBuilder<dynamic>(
      future: _paymentMode,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(
                    portuguese
                        ? 'Não foi possível abrir a gestão de pagamentos.'
                        : 'Payment management could not be opened.',
                    textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _refresh,
                  icon: const Icon(Icons.refresh),
                  label: Text(portuguese ? 'Tentar novamente' : 'Retry'),
                ),
              ]),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final value = Map<String, dynamic>.from(snapshot.data as Map);
        if (value['mode'] != 'finreg') {
          return const InternalPaymentsScreen();
        }
        _manifest ??= _loadFinregManifest(ref.read(apiClientProvider));
        return FutureBuilder<FinregManifest>(
          future: _manifest!,
          builder: (context, capabilitySnapshot) {
            if (capabilitySnapshot.hasError) {
              return Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(portuguese
                    ? 'Não foi possível validar o perfil Finreg.'
                    : 'The Finreg profile could not be validated.'),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _refresh,
                  icon: const Icon(Icons.refresh),
                  label: Text(portuguese ? 'Tentar novamente' : 'Retry'),
                ),
              ]));
            }
            if (!capabilitySnapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final manifest = capabilitySnapshot.data!;
            if (manifest.vertical != 'school') {
              return const Center(
                  child: Text(
                      'O perfil financeiro desta organização não é escolar.'));
            }
            final workspaces = manifest.operationalWorkspaces;
            if (workspaces.isEmpty) {
              return Center(
                child: Text(portuguese
                    ? 'Não existem módulos financeiros disponíveis para este perfil.'
                    : 'No financial modules are available for this profile.'),
              );
            }
            return _FinregWorkspaceMenu(
              key: ValueKey(workspaces
                  .map((workspace) => workspace.capabilityId)
                  .join('|')),
              workspaces: workspaces,
              initialCapabilityId: widget.initialCapabilityId,
              launchForCapability: _createWorkspaceLaunch,
              contextualCapabilities: const {
                'billing': _SchoolContextDefinition(
                  labels: {
                    'pt': 'Finreg — vendas e faturação',
                    'en': 'Finreg — sales and billing',
                  },
                  authoritativeLabels: {
                    'pt': 'Operações escolares',
                    'en': 'School operations',
                  },
                  authoritativeFirst: true,
                  showReadiness: false,
                  child: _SchoolBillingOperations(),
                ),
                'parties': _SchoolContextDefinition(
                  labels: {
                    'pt': 'Encarregados e responsáveis',
                    'en': 'Guardians and responsible payers',
                  },
                  authoritativeLabels: {
                    'pt': 'Registos fiscais',
                    'en': 'Fiscal records',
                  },
                  child: GuardiansListScreen(),
                ),
                'payroll': _SchoolContextDefinition(
                  labels: {
                    'pt': 'Professores e funcionários',
                    'en': 'Teachers and employees',
                  },
                  authoritativeLabels: {
                    'pt': 'Contratos e salários',
                    'en': 'Contracts and payroll',
                  },
                  authoritativeFirst: true,
                  child: EmployeesListScreen(),
                ),
              },
              readinessForCapability: _compositionReadiness,
              onManageAccess:
                  ref.watch(authProvider).roles.contains(UserRole.schoolAdmin)
                      ? () async {
                          await showSchoolAccessPolicyDialog(
                            context,
                            ref.read(apiClientProvider),
                          );
                          _refresh();
                        }
                      : null,
            );
          },
        );
      },
    );
  }
}

class _FinregWorkspaceMenu extends StatefulWidget {
  const _FinregWorkspaceMenu({
    super.key,
    required this.workspaces,
    required this.launchForCapability,
    required this.contextualCapabilities,
    required this.readinessForCapability,
    this.onManageAccess,
    this.initialCapabilityId,
  });

  final List<FinregWorkspace> workspaces;
  final Future<FinregWorkspaceLaunch> Function(String capabilityId)
      launchForCapability;
  final Map<String, _SchoolContextDefinition> contextualCapabilities;
  final Future<Map<String, dynamic>> Function(String capabilityId)
      readinessForCapability;
  final VoidCallback? onManageAccess;
  final String? initialCapabilityId;

  @override
  State<_FinregWorkspaceMenu> createState() => _FinregWorkspaceMenuState();
}

class _FinregWorkspaceMenuState extends State<_FinregWorkspaceMenu>
    with SingleTickerProviderStateMixin {
  late final TabController _controller;
  late int _selected;
  final Map<String, Future<Map<String, dynamic>>> _readiness = {};

  /// Capability currently being minted/opened; one at a time, so a double
  /// tap cannot burn two launch codes.
  String? _opening;
  String? _launchError;

  @override
  void initState() {
    super.initState();
    final initialIndex = widget.workspaces.indexWhere(
        (workspace) => workspace.capabilityId == widget.initialCapabilityId);
    _selected = initialIndex < 0 ? 0 : initialIndex;
    _controller = TabController(
      length: widget.workspaces.length,
      initialIndex: _selected,
      vsync: this,
    )..addListener(_selectTab);
  }

  void _selectTab() {
    if (!_controller.indexIsChanging && _selected != _controller.index) {
      setState(() {
        _selected = _controller.index;
        _launchError = null;
      });
    }
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_selectTab)
      ..dispose();
    super.dispose();
  }

  Future<void> _open(FinregWorkspace workspace) async {
    if (_opening != null) return;
    final portuguese = Localizations.localeOf(context).languageCode == 'pt';
    setState(() {
      _opening = workspace.capabilityId;
      _launchError = null;
    });
    try {
      final launch = await widget.launchForCapability(workspace.capabilityId);
      final uri = Uri.tryParse(launch.url);
      if (uri == null || !uri.hasScheme) {
        throw Exception(portuguese
            ? 'O FinReg não devolveu o endereço do módulo'
            : 'FinReg did not return the workspace address');
      }
      final opened = await finregUrlLauncher(
        uri,
        mode: LaunchMode.externalApplication,
        webOnlyWindowName: '_blank',
      );
      if (!opened) {
        throw Exception(portuguese
            ? 'O navegador não permitiu abrir o FinReg'
            : 'The browser did not open FinReg');
      }
    } catch (error) {
      if (mounted) {
        setState(() =>
            _launchError = error.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _opening = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final localeCode = Localizations.localeOf(context).languageCode;
    final index =
        _selected < widget.workspaces.length ? _selected : widget.workspaces.length - 1;
    final selected = widget.workspaces[index];
    return Column(
      children: [
        Material(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          child: Row(
            children: [
              Expanded(
                child: TabBar(
                  controller: _controller,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  tabs: [
                    for (final workspace in widget.workspaces)
                      Tab(
                        icon: Icon(_workspaceLooks[workspace.capabilityId]
                                ?.icon ??
                            Icons.apps_outlined),
                        text: _workspaceLabel(
                            workspace.capabilityId, localeCode),
                      ),
                  ],
                ),
              ),
              if (widget.onManageAccess != null)
                IconButton(
                  onPressed: widget.onManageAccess,
                  tooltip: localeCode == 'pt'
                      ? 'Acesso local aos módulos'
                      : 'Local module access',
                  icon: const Icon(Icons.admin_panel_settings_outlined),
                ),
            ],
          ),
        ),
        Expanded(child: _buildWorkspace(selected)),
      ],
    );
  }

  Widget _buildWorkspace(FinregWorkspace workspace) {
    final definition =
        widget.contextualCapabilities[workspace.capabilityId];
    final pane = _WorkspaceLaunchPanel(
      workspace: workspace,
      label: _workspaceLabel(workspace.capabilityId,
          Localizations.localeOf(context).languageCode),
      icon: _workspaceLooks[workspace.capabilityId]?.icon ?? Icons.apps_outlined,
      opening: _opening == workspace.capabilityId,
      locked: _opening != null && _opening != workspace.capabilityId,
      error: _launchError,
      onOpen: () => _open(workspace),
    );
    if (definition == null) return pane;
    return _SchoolContextualModule(
      // One tab controller per capability: without the key Flutter reuses the
      // previous workspace's controller, so a sub-tab chosen in billing would
      // carry over and open parties on its FinReg pane instead of guardians.
      key: ValueKey(workspace.capabilityId),
      capabilityId: workspace.capabilityId,
      definition: definition,
      authoritative: pane,
      readiness: definition.showReadiness
          ? _readiness.putIfAbsent(
              workspace.capabilityId,
              () => widget.readinessForCapability(workspace.capabilityId),
            )
          : null,
      onRetryReadiness: () =>
          setState(() => _readiness.remove(workspace.capabilityId)),
    );
  }
}

/// The one action this screen exists for, stated with its consequences.
class _WorkspaceLaunchPanel extends StatelessWidget {
  const _WorkspaceLaunchPanel({
    required this.workspace,
    required this.label,
    required this.icon,
    required this.opening,
    required this.locked,
    required this.error,
    required this.onOpen,
  });

  final FinregWorkspace workspace;
  final String label;
  final IconData icon;
  final bool opening;
  final bool locked;
  final String? error;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final portuguese = Localizations.localeOf(context).languageCode == 'pt';
    final blocked = workspace.blockedReasons;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            CircleAvatar(
              radius: 32,
              backgroundColor:
                  theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
              child: Icon(icon, size: 32, color: theme.colorScheme.primary),
            ),
            const SizedBox(height: 16),
            Text(label,
                textAlign: TextAlign.center, style: theme.textTheme.titleLarge),
            if (workspace.description.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(workspace.description,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
            if (blocked.isNotEmpty) ...[
              const SizedBox(height: 16),
              for (final reason in blocked)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('• $reason',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.error)),
                ),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed:
                  opening || locked || blocked.isNotEmpty ? null : onOpen,
              icon: opening
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.open_in_new),
              label: Text(opening
                  ? (portuguese ? 'A abrir o FinReg…' : 'Opening FinReg…')
                  : (portuguese ? 'Abrir no FinReg' : 'Open in FinReg')),
            ),
            const SizedBox(height: 12),
            Text(
              portuguese
                  ? 'O FinReg abre num separador próprio, com uma sessão de '
                      'uso único. Volte aqui para abrir outro módulo.'
                  : 'FinReg opens in its own tab with a single-use session. '
                      'Come back here to open another module.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            if (error != null) ...[
              const SizedBox(height: 16),
              Text(error!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.error)),
            ],
          ]),
        ),
      ),
    );
  }
}

Future<void> showSchoolAccessPolicyDialog(
  BuildContext context,
  ApiClient api,
) =>
    showDialog<void>(
      context: context,
      useRootNavigator: false,
      builder: (_) => _FinregAccessPolicyDialog(api: api),
    );

class _FinregAccessPolicyDialog extends StatefulWidget {
  const _FinregAccessPolicyDialog({required this.api});

  final ApiClient api;

  @override
  State<_FinregAccessPolicyDialog> createState() =>
      _FinregAccessPolicyDialogState();
}

class _FinregAccessPolicyDialogState extends State<_FinregAccessPolicyDialog> {
  late final Future<void> _load = _loadPolicy();
  final Map<String, Set<String>> _roleCapabilities = {};
  final Map<String, Set<String>> _roleWorkspaces = {};
  final Map<String, Map<String, bool>> _roleFeatures = {};
  final Map<String, bool> _schoolFeatures = {};
  final Map<String, bool> _roleAvailable = {};
  List<RoleDef> _roles = kConfigRoles;
  List<String> _available = const [];
  List<String> _featureKeys = const [];
  bool _saving = false;

  Future<void> _loadPolicy() async {
    final payload = Map<String, dynamic>.from(
        await widget.api.get('/finreg/local-access-policy') as Map);
    final customRoles = (payload['custom_roles'] as List? ?? const [])
        .map((entry) =>
            CustomRole.fromJson(Map<String, dynamic>.from(entry as Map)))
        .map((role) => role.definition)
        .toList();
    _roles = [...kConfigRoles, ...customRoles];
    _available = List<String>.from(payload['available_capabilities'] as List);
    final roles =
        Map<String, dynamic>.from(payload['role_capabilities'] as Map);
    for (final entry in roles.entries) {
      _roleCapabilities[entry.key] = Set<String>.from(entry.value as List);
    }
    final workspaces = Map<String, dynamic>.from(
        payload['role_workspaces'] as Map? ?? const {});
    for (final entry in workspaces.entries) {
      _roleWorkspaces[entry.key] = Set<String>.from(entry.value as List);
    }
    _featureKeys =
        List<String>.from(payload['feature_keys'] as List? ?? const []);
    _schoolFeatures.addAll(
        Map<String, bool>.from(payload['school_features'] as Map? ?? const {}));
    _roleAvailable.addAll(
        Map<String, bool>.from(payload['role_available'] as Map? ?? const {}));
    final features =
        Map<String, dynamic>.from(payload['role_features'] as Map? ?? const {});
    for (final entry in features.entries) {
      _roleFeatures[entry.key] = Map<String, bool>.from(entry.value as Map);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.api.put('/finreg/local-access-policy', data: {
        'role_capabilities': _roleCapabilities.map(
          (role, capabilities) => MapEntry(role, capabilities.toList()..sort()),
        ),
        'role_features': _roleFeatures,
      });
      // Refresh navigation immediately after policy changes.
      if (mounted) {
        // The dialog is hosted by a Consumer screen, so its nearest container
        // can invalidate the shared school policy provider.
        ProviderScope.containerOf(context).invalidate(schoolInfoProvider);
      }
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final portuguese = Localizations.localeOf(context).languageCode == 'pt';
    return AlertDialog(
      title: Text(portuguese ? 'Acessos e funções' : 'Access and roles'),
      content: SizedBox(
        width: 720,
        height: 520,
        child: FutureBuilder<void>(
          future: _load,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(child: Text(snapshot.error.toString()));
            }
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            return ListView(
              children: [
                Text(portuguese
                    ? 'Estas permissões apenas restringem o acesso dentro da escola. Não podem ativar módulos ou alterar a composição definida pelo proprietário Finreg. Administradores da escola mantêm acesso completo.'
                    : 'These permissions only restrict access inside the school. They cannot activate modules or change the composition granted by the Finreg owner. School administrators retain full access.'),
                const SizedBox(height: 16),
                for (final definition in _roles)
                  ExpansionTile(
                    enabled: _roleAvailable[definition.key] ?? true,
                    leading: Icon(definition.icon, color: definition.color),
                    title: Text(definition.label),
                    subtitle: Text((_roleAvailable[definition.key] ?? true)
                        ? definition.description
                        : (portuguese
                            ? 'Função desativada para esta escola'
                            : 'Role disabled for this school')),
                    children: [
                      ListTile(
                        dense: true,
                        title: Text(
                            portuguese ? 'Áreas do Cellen' : 'Cellen areas'),
                        subtitle: Text(portuguese
                            ? 'Controla a navegação. As ações continuam protegidas pelo tipo de função.'
                            : 'Controls navigation. Actions remain protected by the role type.'),
                      ),
                      for (final feature in _featureKeys)
                        CheckboxListTile(
                          dense: true,
                          value: _roleFeatures[definition.key]?[feature] ??
                              definition.defaultFeatures.contains(feature),
                          title: Text(_humanize(feature)),
                          onChanged: _schoolFeatures[feature] == false
                              ? null
                              : (selected) => setState(() {
                                    _roleFeatures.putIfAbsent(
                                            definition.key, () => {})[feature] =
                                        selected == true;
                                  }),
                        ),
                      const Divider(),
                      ListTile(
                        dense: true,
                        title: Text(portuguese
                            ? 'Módulos financeiros Finreg'
                            : 'Finreg financial modules'),
                        subtitle: Text(
                          (_roleWorkspaces[definition.key]?.isNotEmpty ?? false)
                              ? (portuguese
                                  ? 'Apenas módulos autorizados para esta função pelo Finreg.'
                                  : 'Only modules authorized for this role by Finreg.')
                              : (portuguese
                                  ? 'Esta função não possui um perfil operacional Finreg. O portal contextual permanece no Cellen.'
                                  : 'This role has no operational Finreg profile. Contextual portal access remains in Cellen.'),
                        ),
                      ),
                      for (final capability in _available)
                        CheckboxListTile(
                          dense: true,
                          value: _roleCapabilities[definition.key]
                                  ?.contains(capability) ??
                              false,
                          title: Text(
                              _workspaceLabel(capability, portuguese ? 'pt' : 'en')),
                          onChanged: _roleWorkspaces[definition.key]
                                      ?.contains(capability) !=
                                  true
                              ? null
                              : (selected) => setState(() {
                                    final values =
                                        _roleCapabilities.putIfAbsent(
                                            definition.key, () => <String>{});
                                    selected == true
                                        ? values.add(capability)
                                        : values.remove(capability);
                                  }),
                        ),
                    ],
                  ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: Text(portuguese ? 'Cancelar' : 'Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(portuguese ? 'Guardar' : 'Save'),
        ),
      ],
    );
  }

  String _humanize(String value) => value
      .split('_')
      .map((part) =>
          part.isEmpty ? part : '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}

class _SchoolBillingOperations extends StatelessWidget {
  const _SchoolBillingOperations();

  @override
  Widget build(BuildContext context) {
    final portuguese = Localizations.localeOf(context).languageCode == 'pt';
    final operations = <({IconData icon, String pt, String en, String route})>[
      (
        icon: Icons.school_outlined,
        pt: 'Planos dos alunos',
        en: 'Student plans',
        route: '/admin/finance/contracts'
      ),
      (
        icon: Icons.sell_outlined,
        pt: 'Serviços e mensalidades',
        en: 'Services and fees',
        route: '/admin/finance/billing-items'
      ),
      (
        icon: Icons.receipt_long_outlined,
        pt: 'Comprovativos de pagamento',
        en: 'Payment proofs',
        route: '/admin/finance/payment-proofs'
      ),
      (
        icon: Icons.calendar_month_outlined,
        pt: 'Acordos de pagamento',
        en: 'Payment arrangements',
        route: '/admin/finance/payment-plans'
      ),
      (
        icon: Icons.numbers_outlined,
        pt: 'Referências de pagamento',
        en: 'Payment references',
        route: '/admin/finance/payment-references'
      ),
      (
        icon: Icons.account_balance_wallet_outlined,
        pt: 'Créditos dos encarregados',
        en: 'Guardian credits',
        route: '/admin/finance/credits'
      ),
      (
        icon: Icons.notifications_active_outlined,
        pt: 'Lembretes de cobrança',
        en: 'Collection reminders',
        route: '/admin/finance/reminders'
      ),
    ];
    return LayoutBuilder(builder: (context, constraints) {
      final columns = constraints.maxWidth >= 1000
          ? 3
          : constraints.maxWidth >= 620
              ? 2
              : 1;
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            portuguese
                ? 'Operações financeiras da escola'
                : 'School financial operations',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 6),
          Text(portuguese
              ? 'Use estas áreas para os dados escolares. A faturação fiscal, pagamentos e relatórios permanecem no Finreg.'
              : 'Use these areas for school data. Fiscal billing, payments and reports remain in Finreg.'),
          const SizedBox(height: 20),
          GridView.count(
            crossAxisCount: columns,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: columns == 1 ? 4.3 : 2.6,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            children: [
              for (final operation in operations)
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => context.push(operation.route),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(children: [
                        Icon(operation.icon, size: 30),
                        const SizedBox(width: 14),
                        Expanded(
                            child:
                                Text(portuguese ? operation.pt : operation.en)),
                        const Icon(Icons.chevron_right),
                      ]),
                    ),
                  ),
                ),
            ],
          ),
        ],
      );
    });
  }
}

class _SchoolContextDefinition {
  const _SchoolContextDefinition({
    required this.labels,
    required this.authoritativeLabels,
    required this.child,
    this.authoritativeFirst = false,
    this.showReadiness = true,
  });

  final Map<String, String> labels;
  final Map<String, String> authoritativeLabels;
  final Widget child;
  final bool authoritativeFirst;
  final bool showReadiness;

  String label(String languageCode) =>
      labels[languageCode] ?? labels['pt'] ?? labels.values.first;

  String authoritativeLabel(String languageCode) =>
      authoritativeLabels[languageCode] ??
      authoritativeLabels['pt'] ??
      authoritativeLabels.values.first;
}

class _SchoolContextualModule extends StatelessWidget {
  const _SchoolContextualModule({
    super.key,
    required this.capabilityId,
    required this.definition,
    required this.authoritative,
    required this.readiness,
    required this.onRetryReadiness,
  });

  final String capabilityId;
  final _SchoolContextDefinition definition;
  final Widget authoritative;
  final Future<Map<String, dynamic>>? readiness;
  final VoidCallback onRetryReadiness;

  @override
  Widget build(BuildContext context) {
    final languageCode = Localizations.localeOf(context).languageCode;
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          if (readiness != null)
            _CompositionReadiness(
              capabilityId: capabilityId,
              readiness: readiness!,
              languageCode: languageCode,
              onRetry: onRetryReadiness,
            ),
          Material(
            color: Theme.of(context).colorScheme.surfaceContainerLowest,
            child: Align(
              alignment: Alignment.centerLeft,
              child: TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  if (definition.authoritativeFirst) ...[
                    Tab(text: definition.label(languageCode)),
                    Tab(text: definition.authoritativeLabel(languageCode)),
                  ] else ...[
                    Tab(text: definition.label(languageCode)),
                    Tab(text: definition.authoritativeLabel(languageCode)),
                  ],
                ],
              ),
            ),
          ),
          Expanded(
            child: TabBarView(
              children: definition.authoritativeFirst
                  ? [authoritative, definition.child]
                  : [definition.child, authoritative],
            ),
          ),
        ],
      ),
    );
  }
}

class _CompositionReadiness extends StatelessWidget {
  const _CompositionReadiness({
    required this.capabilityId,
    required this.readiness,
    required this.languageCode,
    required this.onRetry,
  });

  final String capabilityId;
  final Future<Map<String, dynamic>> readiness;
  final String languageCode;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
        future: readiness,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            final portuguese = languageCode == 'pt';
            return ListTile(
              leading: const Icon(Icons.error_outline),
              title: Text(portuguese
                  ? 'Não foi possível validar a preparação dos dados.'
                  : 'Data readiness could not be checked.'),
              trailing: IconButton(
                tooltip: portuguese ? 'Tentar novamente' : 'Retry',
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
              ),
            );
          }
          if (!snapshot.hasData) return const LinearProgressIndicator();
          final value = snapshot.data!;
          final source = value['source_total'] as int? ?? 0;
          final ready = value['ready_total'] as int? ?? 0;
          final mapped = value['mapped_total'] as int?;
          final portuguese = languageCode == 'pt';
          final message = capabilityId == 'parties'
              ? (portuguese
                  ? '$source encarregados no Cellen; ${mapped ?? 0} já possuem registo fiscal. Os restantes são associados automaticamente na primeira operação financeira.'
                  : '$source guardians in Cellen; ${mapped ?? 0} already have a fiscal record. Remaining guardians are linked automatically on first financial use.')
              : (portuguese
                  ? '$ready de $source funcionários têm data de admissão e salário prontos para revisão no processamento salarial.'
                  : '$ready of $source employees have a hire date and salary ready for payroll review.');
          final complete = ready == source;
          return Material(
            color: complete
                ? Theme.of(context).colorScheme.primaryContainer
                : Theme.of(context).colorScheme.errorContainer,
            child: ListTile(
              dense: true,
              leading: Icon(complete ? Icons.link : Icons.warning_amber),
              title: Text(message),
            ),
          );
        },
      );
}
