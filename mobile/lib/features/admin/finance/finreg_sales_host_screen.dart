import 'dart:typed_data';

import 'package:cellen/core/api/api_client.dart';
import 'package:finreg_app/embedded_modules.dart';
import 'package:finreg_client_sdk/finreg_client_sdk.dart';
import 'package:finreg_sales_ui/finreg_sales_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import 'billing_items_screen.dart';
import 'credit_balances_screen.dart';
import 'parent_payment_review_screen.dart';
import 'payment_plans_screen.dart';
import 'payment_references_screen.dart';
import 'reminders_screen.dart';
import 'student_billing_plans_screen.dart';

class FinregSalesHostScreen extends ConsumerStatefulWidget {
  const FinregSalesHostScreen({super.key});

  @override
  ConsumerState<FinregSalesHostScreen> createState() =>
      _FinregSalesHostScreenState();
}

class _FinregSalesHostScreenState extends ConsumerState<FinregSalesHostScreen> {
  late Future<dynamic> _connection;
  late _CellenFinregAdapter _adapter;
  late Future<FinregCapabilities> _capabilities;

  @override
  void initState() {
    super.initState();
    _adapter = _CellenFinregAdapter(ref.read(apiClientProvider));
    _connection = ref.read(apiClientProvider).get('/finreg/connection');
    _capabilities = _adapter.capabilities();
  }

  void _refresh() {
    setState(() {
      _connection = ref.read(apiClientProvider).get('/finreg/connection');
      _capabilities = _adapter.capabilities();
    });
  }

  Future<FinregEmbeddedSession> _createEmbeddedSession(
      String capabilityId) async {
    final payload = Map<String, dynamic>.from(await ref
        .read(apiClientProvider)
        .post('/finreg/embedded-session/$capabilityId') as Map);
    final tokens = Map<String, dynamic>.from(payload['tokens'] as Map);
    final user = Map<String, dynamic>.from(payload['user'] as Map);
    return FinregEmbeddedSession(
      apiBaseUrl: payload['api_base_url'].toString(),
      accessToken: tokens['access_token'].toString(),
      refreshToken: tokens['refresh_token'].toString(),
      userId: user['id'].toString(),
      email: user['email'].toString(),
      fullName: user['full_name'].toString(),
      role: user['role'].toString(),
      companyId: user['company_id'].toString(),
      companyName: user['company_name']?.toString(),
      permissions: Set<String>.from(user['permissions'] as List? ?? const []),
      enabledModules:
          Set<String>.from(user['enabled_modules'] as List? ?? const []),
      effectiveCapabilities:
          Set<String>.from(user['effective_capabilities'] as List? ?? const []),
      verticalProfile:
          user['vertical_profile']?.toString() ?? 'generic_service',
      moduleManifestFingerprint:
          user['module_manifest_fingerprint']?.toString(),
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<dynamic>(
        future: _connection,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                    'Não foi possível abrir o Finreg: ${snapshot.error}',
                    textAlign: TextAlign.center),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final value = Map<String, dynamic>.from(snapshot.data as Map);
          if (!{'fake', 'shadow', 'pilot', 'live'}.contains(value['mode'])) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'A faturação Finreg ainda não está configurada para esta escola. '
                  'Contacte o administrador da plataforma.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return FutureBuilder<FinregCapabilities>(
            future: _capabilities,
            builder: (context, capabilitySnapshot) {
              if (capabilitySnapshot.hasError) {
                return Center(
                    child: Text(
                        'Não foi possível validar o perfil Finreg: ${capabilitySnapshot.error}'));
              }
              if (!capabilitySnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final capabilities = capabilitySnapshot.data!;
              if (capabilities.vertical != 'school') {
                return const Center(
                    child: Text(
                        'O perfil financeiro desta organização não é escolar.'));
              }
              final workspaces = capabilities.workspaces
                  .where((item) =>
                      item.operational &&
                      finregEmbeddedModules.containsKey(item.capabilityId))
                  .toList(growable: false);
              final schoolModule = FinregSchoolBillingModule(
                  repository: _adapter,
                  host: _adapter,
                  configuredCapabilities: capabilities.configuredCapabilities,
                  effectiveCapabilities: capabilities.effectiveCapabilities,
                  blockedCapabilities: capabilities.blockedCapabilities,
                  hostSurfaces: capabilities.hostSurfaces,
                  onRefreshCapabilities: _refresh,
                  surfaceBuilders: {
                    'school_student_plans': (_) =>
                        const StudentBillingPlansScreen(),
                    'school_services': (_) => const BillingItemsScreen(),
                    'school_payment_proofs': (_) =>
                        const ParentPaymentReviewScreen(),
                    'school_payment_arrangements': (_) =>
                        const PaymentPlansScreen(),
                    'school_payment_references': (_) =>
                        const PaymentReferencesScreen(),
                    'school_guardian_credits': (_) =>
                        const CreditBalancesScreen(),
                    'school_reminders': (_) => const RemindersScreen(),
                  },
                  onOfficialDocument: (name, bytes) =>
                      Printing.sharePdf(bytes: bytes, filename: name));
              if (workspaces.isEmpty || value['mode'] == 'fake') {
                return schoolModule;
              }
              return _EmbeddedFinregMenu(
                key: ValueKey(workspaces
                    .map((workspace) => workspace.capabilityId)
                    .join('|')),
                workspaces: workspaces,
                initialCapabilityId: 'billing',
                sessionForCapability: _createEmbeddedSession,
                capabilityOverrides: {'billing': schoolModule},
              );
            },
          );
        },
      );
}

class _EmbeddedFinregMenu extends StatefulWidget {
  const _EmbeddedFinregMenu({
    super.key,
    required this.workspaces,
    required this.sessionForCapability,
    required this.capabilityOverrides,
    this.initialCapabilityId,
  });

  final List<FinregWorkspace> workspaces;
  final Future<FinregEmbeddedSession> Function(String capabilityId)
      sessionForCapability;
  final Map<String, Widget> capabilityOverrides;
  final String? initialCapabilityId;

  @override
  State<_EmbeddedFinregMenu> createState() => _EmbeddedFinregMenuState();
}

class _EmbeddedFinregMenuState extends State<_EmbeddedFinregMenu>
    with SingleTickerProviderStateMixin {
  late final TabController _controller;
  late int _selected;
  final Map<String, Future<FinregEmbeddedSession>> _sessions = {};
  final Set<String> _visitedCapabilityIds = {};

  @override
  void initState() {
    super.initState();
    final initialIndex = widget.workspaces.indexWhere(
        (workspace) => workspace.capabilityId == widget.initialCapabilityId);
    _selected = initialIndex < 0 ? 0 : initialIndex;
    _visitedCapabilityIds.add(widget.workspaces[_selected].capabilityId);
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
        _visitedCapabilityIds.add(
          widget.workspaces[_controller.index].capabilityId,
        );
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

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          child: TabBar(
            controller: _controller,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              for (final workspace in widget.workspaces)
                Tab(
                  icon: Icon(
                    finregEmbeddedModules[workspace.capabilityId]!.icon,
                  ),
                  text: workspace.title,
                ),
            ],
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _selected,
            children: [
              for (final workspace in widget.workspaces)
                if (_visitedCapabilityIds.contains(workspace.capabilityId))
                  widget.capabilityOverrides[workspace.capabilityId] ??
                      _buildAuthoritativeModule(workspace)
                else
                  const SizedBox.shrink(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAuthoritativeModule(FinregWorkspace workspace) {
    final capabilityId = workspace.capabilityId;
    final session = _sessions.putIfAbsent(
      capabilityId,
      () => widget.sessionForCapability(capabilityId),
    );
    return FutureBuilder<FinregEmbeddedSession>(
      future: session,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Não foi possível abrir este módulo.'),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () =>
                      setState(() => _sessions.remove(capabilityId)),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Tentar novamente'),
                ),
              ],
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return FinregEmbeddedModuleHost(
          key: ObjectKey(snapshot.data),
          capabilityId: capabilityId,
          session: snapshot.data!,
          onSessionExpired: () {
            if (!mounted) return;
            setState(() => _sessions.remove(capabilityId));
          },
        );
      },
    );
  }
}

class _CellenFinregAdapter implements FinregSalesRepository, FinregHostAdapter {
  _CellenFinregAdapter(this.api);
  final ApiClient api;
  InvoicePreview? lastPreview;

  @override
  Future<FinregCapabilities> capabilities() async {
    final value =
        Map<String, dynamic>.from(await api.get('/finreg/capabilities') as Map);
    return FinregCapabilities(
        companyId: value['company_id']?.toString(),
        apiVersion: value['api_version'] as String,
        schemaVersion: value['schema_version'] as String,
        vertical: value['vertical'] as String,
        terminology:
            Map<String, String>.from(value['terminology'] as Map? ?? {}),
        enabledModules:
            Set<String>.from(value['enabled_modules'] as List? ?? []),
        configuredCapabilities:
            Set<String>.from(value['configured_capabilities'] as List? ?? []),
        effectiveCapabilities:
            Set<String>.from(value['effective_capabilities'] as List? ?? []),
        blockedCapabilities: (value['blocked_capabilities'] as Map? ?? const {})
            .map((key, value) => MapEntry(
                key.toString(), Set<String>.from(value as List? ?? const []))),
        hostSurfaces: (value['host_surfaces'] as List? ?? const []).map((raw) {
          final surface = Map<String, dynamic>.from(raw as Map);
          return FinregHostSurface(
              id: surface['id'].toString(),
              capabilityId: surface['capability_id'].toString(),
              presentation: surface['presentation'].toString(),
              labels: Map<String, String>.from(surface['labels'] as Map),
              icon: surface['icon'].toString(),
              order: surface['order'] as int,
              operational: surface['operational'] as bool,
              blockedReasons: List<String>.from(
                  surface['blocked_reasons'] as List? ?? const []));
        }).toList(growable: false),
        workspaces: (value['workspaces'] as List? ?? const []).map((raw) {
          final workspace = Map<String, dynamic>.from(raw as Map);
          return FinregWorkspace(
              capabilityId: workspace['capability_id'].toString(),
              title: workspace['title'].toString(),
              description: workspace['description'].toString(),
              route: workspace['route'].toString(),
              operational: workspace['operational'] as bool,
              blockedReasons: List<String>.from(
                  workspace['blocked_reasons'] as List? ?? const []));
        }).toList(growable: false),
        manifestFingerprint: value['manifest_fingerprint']?.toString(),
        countryPack: value['country_pack']?.toString(),
        agtChannel: value['agt_channel']?.toString() ?? 'disabled',
        nonFiscal: value['non_fiscal'] as bool? ?? false);
  }

  @override
  Future<SchoolFinanceContext> currentSchool() async {
    final now = DateTime.now();
    return SchoolFinanceContext(
        schoolExternalId: 'current',
        billingPeriod: '${now.year}-${now.month.toString().padLeft(2, '0')}');
  }

  @override
  Future<List<ExternalReference>> searchGuardians(String query) async {
    final rows = await api.get(
      '/finreg/guardians',
      queryParameters: query.trim().isEmpty ? null : {'search': query.trim()},
    ) as List;
    return rows.map((raw) {
      final v = Map<String, dynamic>.from(raw as Map);
      return ExternalReference(
          id: v['id'].toString(), displayName: v['display_name'].toString());
    }).toList();
  }

  @override
  Future<List<ExternalReference>> searchPupils(String query) async {
    final rows = await api.get('/children') as List;
    return rows
        .map((raw) {
          final v = Map<String, dynamic>.from(raw as Map);
          return ExternalReference(
              id: v['id'].toString(),
              displayName: '${v['first_name']} ${v['last_name']}');
        })
        .where((x) => x.displayName.toLowerCase().contains(query.toLowerCase()))
        .toList();
  }

  @override
  Future<List<ExternalReference>> pupilsForGuardian(String guardianId) async {
    final rows = await api.get('/finreg/guardians/$guardianId/pupils') as List;
    return rows.map((raw) {
      final value = Map<String, dynamic>.from(raw as Map);
      return ExternalReference(
        id: value['id'].toString(),
        displayName: value['display_name'].toString(),
      );
    }).toList(growable: false);
  }

  @override
  Future<List<FinregProduct>> searchProducts(String query) async {
    final rows = await api.get('/finance/billing-items') as List;
    return rows
        .map((raw) {
          final v = Map<String, dynamic>.from(raw as Map);
          return FinregProduct(
              id: v['id'].toString(),
              code: v['code'].toString(),
              name: v['name'].toString(),
              unitPrice: v['unit_price'] as num,
              taxRate: v['iva_rate'] as num);
        })
        .where((x) =>
            '${x.code} ${x.name}'.toLowerCase().contains(query.toLowerCase()))
        .toList();
  }

  Map<String, dynamic> _payload(InvoiceDraft draft) => {
        'request_id': draft.externalReference,
        'guardian_id': draft.customerId,
        'pupil_id': draft.context.pupilExternalId,
        'academic_year_id': draft.context.academicYearExternalId,
        'academic_year_label': draft.context.academicYearLabel,
        'billing_period': draft.context.billingPeriod,
        'lines': draft.lines
            .map((x) => {
                  'billing_item_id': x.productId,
                  'quantity': x.quantity,
                  'unit_price': x.unitPrice,
                  'discount_pct': 0
                })
            .toList(),
      };

  @override
  Future<InvoicePreview> previewInvoice(InvoiceDraft draft) async {
    final v = Map<String, dynamic>.from(
        await api.post('/finreg/sales/preview', data: _payload(draft)) as Map);
    return lastPreview = InvoicePreview(
        netTotal: v['net_total'] as num,
        taxTotal: v['tax_total'] as num,
        grossTotal: v['gross_total'] as num);
  }

  @override
  Future<FiscalDocument> issueInvoice(InvoiceDraft draft,
      {required String idempotencyKey}) async {
    final v = Map<String, dynamic>.from(
        await api.post('/finreg/sales/issue', data: _payload(draft)) as Map);
    return FiscalDocument(
        id: (v['finreg_document_id'] ?? v['id']).toString(),
        status: v['status'].toString(),
        externalReference: draft.externalReference,
        grossTotal: lastPreview?.grossTotal ?? 0);
  }

  @override
  Future<void> recordMapping(
      String entityType, String externalId, String finregId) async {}
  @override
  Future<Uint8List> downloadOfficialDocument(String documentId) =>
      api.getBytes('/finreg/documents/$documentId/pdf');
  @override
  Future<PaymentResult> registerPayment(RegisterPayment command,
      {required String idempotencyKey}) async {
    final value =
        Map<String, dynamic>.from(await api.post('/finreg/payments', data: {
      'document_id': command.documentId,
      'amount': command.amount,
      'method': command.method,
      'external_reference': command.externalReference,
    }) as Map);
    return PaymentResult(
        id: value['id'].toString(),
        status: value['status'].toString(),
        receiptId: value['receipt_id']?.toString(),
        receiptExternalReference: command.externalReference);
  }

  @override
  Future<List<FinregInstruction>> listInstructions() async {
    final rows = await api.get('/finreg/instructions') as List;
    return rows.map((raw) {
      final value = Map<String, dynamic>.from(raw as Map);
      return FinregInstruction(
          externalReference: value['id'].toString(),
          status: value['status'].toString(),
          createdAt: DateTime.parse(value['created_at'].toString()),
          documentId: value['finreg_document_id']?.toString(),
          errorCode: value['error_code']?.toString(),
          errorDetail: value['error_detail']?.toString());
    }).toList();
  }

  @override
  Future<JsonMap> documentDetail(String externalReference) async =>
      Map<String, Object?>.from(
          await api.get('/finreg/documents/$externalReference') as Map);

  @override
  Future<JsonMap> correctDocument(CorrectDocument command,
          {required String idempotencyKey}) async =>
      Map<String, Object?>.from(await api.post(
          '/finreg/documents/${command.documentExternalReference}/corrections',
          data: {
            'external_reference': command.correctionExternalReference,
            'reason': command.reason
          }) as Map);

  @override
  Future<Uint8List> downloadReceipt(String paymentExternalReference) =>
      api.getBytes('/finreg/receipts/$paymentExternalReference/pdf');

  String _date(DateTime value) => value.toIso8601String().split('T').first;

  @override
  Future<JsonMap> customerStatement(String customerExternalId,
          {required DateTime from, required DateTime to}) async =>
      Map<String, Object?>.from(await api.get(
              '/finreg/customers/$customerExternalId/statement',
              queryParameters: {'date_from': _date(from), 'date_to': _date(to)})
          as Map);

  @override
  Future<JsonMap> salesSummary(
          {required DateTime from, required DateTime to}) async =>
      Map<String, Object?>.from(await api.get('/finreg/reports/sales-summary',
              queryParameters: {'date_from': _date(from), 'date_to': _date(to)})
          as Map);

  @override
  Future<JsonMap> delinquentReport({DateTime? asOf}) async =>
      Map<String, Object?>.from(await api.get('/finreg/reports/delinquent',
              queryParameters: asOf == null ? null : {'as_of': _date(asOf)})
          as Map);

  @override
  Future<Uint8List> downloadSaftSales(
          {required DateTime from, required DateTime to}) =>
      api.getBytes('/finreg/reports/saft-sales'
          '?date_from=${_date(from)}&date_to=${_date(to)}');
}
