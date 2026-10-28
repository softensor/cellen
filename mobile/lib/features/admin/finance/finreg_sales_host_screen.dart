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
import 'finance_home_screen.dart';
import 'internal_payments_screen.dart';
import 'school_finance_hubs.dart';

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

/// Cellen's door into FinReg's own application, and the school's own finance
/// area beneath it.
///
/// FinReg used to be compiled into this app and mounted as a tab. That copy
/// could only ever be as current as the last Cellen release, and it made one
/// product's router fight the other's for the address bar. FinReg now opens
/// in its own tab from one entry card; the tabs below it are Cellen's own
/// records and never depend on FinReg being reachable.
///
/// One entry card, not a mirrored menu: duplicating FinReg's workspace list
/// here produced two navigation systems for the same entities. Contextual
/// routes still choose which workspace the card opens.
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
  Future<Map<String, dynamic>>? _readiness;

  /// One mint at a time, so a double tap cannot burn two launch codes.
  bool _opening = false;
  String? _launchError;

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
      _readiness = null;
      _launchError = null;
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

  /// The workspace the card opens. A contextual route (receipts, statement,
  /// SAF-T…) asks for its own capability; anything else opens billing. An
  /// ERP workspace only appears when FinReg entitled and composed the add-on.
  FinregWorkspace? _targetWorkspace(FinregManifest manifest) {
    final workspaces = manifest.operationalWorkspaces;
    if (workspaces.isEmpty) return null;
    for (final workspace in workspaces) {
      if (workspace.capabilityId == widget.initialCapabilityId) {
        return workspace;
      }
    }
    for (final workspace in workspaces) {
      if (workspace.capabilityId == 'billing') return workspace;
    }
    return workspaces.first;
  }

  Future<void> _open(FinregWorkspace workspace) async {
    if (_opening) return;
    final portuguese = Localizations.localeOf(context).languageCode == 'pt';
    setState(() {
      _opening = true;
      _launchError = null;
    });
    try {
      final launch = await _createWorkspaceLaunch(workspace.capabilityId);
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
      if (mounted) setState(() => _opening = false);
    }
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
            final manifest = capabilitySnapshot.data;
            if (manifest != null) {
              // Readiness is the schools' own data; it is asked for once the
              // manifest exists and can be retried from the card.
              _readiness ??= _compositionReadiness('parties');
            }
            final target = manifest == null ? null : _targetWorkspace(manifest);
            return Column(
              children: [
                _FinregEntryCard(
                  manifest: manifest,
                  loading: capabilitySnapshot.connectionState !=
                      ConnectionState.done,
                  failed: capabilitySnapshot.hasError,
                  readiness: _readiness,
                  opening: _opening,
                  launchError: _launchError,
                  onOpen: target == null ? null : () => _open(target),
                  onRetry: _refresh,
                  onRetryReadiness: () => setState(() => _readiness = null),
                  onManageAccess: ref
                          .watch(authProvider)
                          .roles
                          .contains(UserRole.schoolAdmin)
                      ? () async {
                          await showSchoolAccessPolicyDialog(
                            context,
                            ref.read(apiClientProvider),
                          );
                          _refresh();
                        }
                      : null,
                ),
                const Divider(height: 1),
                const Expanded(child: _NativeSchoolFinanceTabs()),
              ],
            );
          },
        );
      },
    );
  }
}

/// The single way into FinReg, with its commercial state and its one action.
///
/// Collapsed by default: the school's day-to-day finance lives in the
/// operations below, and FinReg is a destination, not a daily stop. The
/// header keeps the connection state visible; the plan details, readiness
/// and the mint-on-tap button only render when someone opens it.
class _FinregEntryCard extends StatefulWidget {
  const _FinregEntryCard({
    required this.manifest,
    required this.loading,
    required this.failed,
    required this.readiness,
    required this.opening,
    required this.launchError,
    required this.onOpen,
    required this.onRetry,
    required this.onRetryReadiness,
    this.onManageAccess,
  });

  final FinregManifest? manifest;
  final bool loading;
  final bool failed;
  final Future<Map<String, dynamic>>? readiness;
  final bool opening;
  final String? launchError;
  final VoidCallback? onOpen;
  final VoidCallback onRetry;
  final VoidCallback onRetryReadiness;
  final VoidCallback? onManageAccess;

  @override
  State<_FinregEntryCard> createState() => _FinregEntryCardState();
}

class _FinregEntryCardState extends State<_FinregEntryCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final languageCode = Localizations.localeOf(context).languageCode;
    final portuguese = languageCode == 'pt';
    final manifest = widget.manifest;
    final verticalMismatch = manifest != null && manifest.vertical != 'school';
    final erp = manifest?.erpEntitled ?? false;

    final (Color dotColor, String summary) = widget.failed
        ? (
            theme.colorScheme.error,
            portuguese
                ? 'Indisponível — as operações da escola continuam'
                : 'Unavailable — school operations keep working',
          )
        : widget.loading
            ? (
                theme.colorScheme.onSurfaceVariant,
                portuguese
                    ? 'A validar a ligação…'
                    : 'Checking the connection…',
              )
            : verticalMismatch
                ? (
                    theme.colorScheme.error,
                    portuguese
                        ? 'Perfil financeiro não escolar'
                        : 'Non-school financial profile',
                  )
                : manifest == null
                    ? (
                        theme.colorScheme.onSurfaceVariant,
                        portuguese ? 'Desligado' : 'Disconnected',
                      )
                    : (
                        Colors.green,
                        portuguese
                            ? (erp
                                ? 'Ligado · plano completo (ERP ativo)'
                                : 'Ligado · plano base de facturação')
                            : (erp
                                ? 'Connected · full plan (ERP active)'
                                : 'Connected · billing base plan'),
                      );

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            button: true,
            expanded: _expanded,
            label: portuguese
                ? 'FinReg, facturação e conformidade. $summary'
                : 'FinReg, billing and compliance. $summary',
            child: InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: theme.colorScheme.primaryContainer,
                      child: Icon(Icons.receipt_long_outlined,
                          size: 20, color: theme.colorScheme.primary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            portuguese
                                ? 'FinReg — facturação e conformidade'
                                : 'FinReg — billing and compliance',
                            style: theme.textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: dotColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  summary,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (widget.onManageAccess != null)
                      IconButton(
                        onPressed: widget.onManageAccess,
                        tooltip: portuguese
                            ? 'Acesso local aos módulos'
                            : 'Local module access',
                        icon: const Icon(Icons.admin_panel_settings_outlined,
                            size: 20),
                      ),
                    Tooltip(
                      message: _expanded
                          ? (portuguese ? 'Recolher' : 'Collapse')
                          : (portuguese ? 'Expandir' : 'Expand'),
                      child: Icon(
                        _expanded ? Icons.expand_less : Icons.expand_more,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Divider(height: 8),
                  if (manifest != null &&
                      !widget.failed &&
                      !widget.loading) ...[
                    const SizedBox(height: 8),
                    Text(
                      erp
                          ? (portuguese
                              ? 'Plano completo: facturação e ERP ativo '
                                  '(contabilidade, tesouraria, compras e RH).'
                              : 'Full plan: billing and ERP active '
                                  '(accounting, treasury, purchasing and payroll).')
                          : (portuguese
                              ? 'Plano base: facturação e conformidade. '
                                  'Contabilidade, tesouraria, compras e RH '
                                  'são um complemento opcional.'
                              : 'Base plan: billing and compliance. '
                                  'Accounting, treasury, purchasing and payroll '
                                  'are an optional add-on.'),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                  if (widget.failed) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(Icons.cloud_off, color: theme.colorScheme.error),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            portuguese
                                ? 'O FinReg está indisponível. As operações da '
                                    'escola abaixo continuam a funcionar.'
                                : 'FinReg is unavailable. The school operations '
                                    'below keep working.',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: widget.onRetry,
                          icon: const Icon(Icons.refresh),
                          label:
                              Text(portuguese ? 'Tentar novamente' : 'Retry'),
                        ),
                      ],
                    ),
                  ] else if (widget.loading) ...[
                    const SizedBox(height: 12),
                    const LinearProgressIndicator(),
                    const SizedBox(height: 8),
                    Text(
                      portuguese
                          ? 'A validar a ligação ao FinReg…'
                          : 'Checking the FinReg connection…',
                      style: theme.textTheme.bodySmall,
                    ),
                  ] else if (verticalMismatch) ...[
                    const SizedBox(height: 12),
                    Text(
                      portuguese
                          ? 'O perfil financeiro desta organização não é escolar.'
                          : 'This organisation’s financial profile is not a school.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.error),
                    ),
                  ] else if (manifest != null) ...[
                    if (widget.readiness != null)
                      _CompositionReadiness(
                        capabilityId: 'parties',
                        readiness: widget.readiness!,
                        languageCode: languageCode,
                        onRetry: widget.onRetryReadiness,
                      ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: widget.opening || widget.onOpen == null
                          ? null
                          : widget.onOpen,
                      icon: widget.opening
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.open_in_new),
                      label: Text(widget.opening
                          ? (portuguese
                              ? 'A abrir o FinReg…'
                              : 'Opening FinReg…')
                          : (portuguese
                              ? 'Abrir no FinReg'
                              : 'Open in FinReg')),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      portuguese
                          ? 'O FinReg abre num separador próprio, com uma sessão de '
                              'uso único. As operações escolares ficam aqui no Cellen.'
                          : 'FinReg opens in its own tab with a single-use session. '
                              'School operations stay here in Cellen.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    if (widget.onOpen == null) ...[
                      const SizedBox(height: 8),
                      Text(
                        portuguese
                            ? 'Não existem módulos financeiros disponíveis para '
                                'este perfil.'
                            : 'No financial modules are available for this profile.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                    if (widget.launchError != null) ...[
                      const SizedBox(height: 8),
                      Text(widget.launchError!,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.colorScheme.error)),
                    ],
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Cellen's own school-finance areas. Manifest-independent by design: an
/// unreachable or misconfigured FinReg must never take these away.
///
/// The tabs follow the school year, not the database: the month's state and
/// totals first (Painel), then everything about debts (generate, chase,
/// fine, agree, remind, credit), then where money comes in and where it is
/// kept (Pagamentos), and last the jargon (Configuração) — so a director who
/// never opens the settings still has every daily action one tab away.
class _NativeSchoolFinanceTabs extends StatelessWidget {
  const _NativeSchoolFinanceTabs();

  @override
  Widget build(BuildContext context) {
    final portuguese = Localizations.localeOf(context).languageCode == 'pt';
    return DefaultTabController(
      length: 6,
      child: Column(
        children: [
          Material(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            child: TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                Tab(text: portuguese ? 'Painel' : 'Overview'),
                Tab(
                    text: portuguese
                        ? 'Dívidas e cobrança'
                        : 'Debts & collection'),
                Tab(text: portuguese ? 'Pagamentos' : 'Payments'),
                Tab(text: portuguese ? 'Configuração' : 'Settings'),
                Tab(text: portuguese ? 'Encarregados' : 'Guardians'),
                Tab(text: portuguese ? 'Funcionários' : 'Employees'),
              ],
            ),
          ),
          const Expanded(
            child: TabBarView(
              children: [
                FinanceHomeScreen(),
                DebtsHub(),
                PaymentsHub(),
                FinanceConfigHub(),
                GuardiansListScreen(),
                EmployeesListScreen(),
              ],
            ),
          ),
        ],
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
                          title: Text(_workspaceLabel(
                              capability, portuguese ? 'pt' : 'en')),
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
