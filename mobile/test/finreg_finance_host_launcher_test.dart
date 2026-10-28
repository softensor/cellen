import 'dart:async';

import 'package:cellen/core/api/api_client.dart';
import 'package:cellen/features/admin/finance/finance_home_screen.dart';
import 'package:cellen/features/admin/finance/finreg_sales_host_screen.dart';
import 'package:cellen/features/admin/finance/internal_payments_screen.dart';
import 'package:cellen/features/admin/guardians/guardians_list_screen.dart';
import 'package:cellen/features/admin/employees/employees_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

/// The manifest Cellen consumes. FinReg owns it in production; this is the
/// shape `FinregManifest.fromJson` reads.
Map<String, dynamic> _manifest({Map<String, dynamic>? extra}) => {
      'company_id': 'company-1',
      'api_version': 'v1',
      'schema_version': 'school/v1',
      'vertical': 'school',
      'agt_channel': 'disabled',
      'non_fiscal': true,
      'manifest_fingerprint': 'fingerprint-1',
      'country_pack': 'AO',
      'workspaces': [
        {
          'capability_id': 'billing',
          'title': 'Sales and billing',
          'description': 'Invoices and credit notes',
          'route': '/billing',
          'operational': true,
          'blocked_reasons': <String>[],
        },
        {
          'capability_id': 'parties',
          'title': 'Parties',
          'description': 'Customers and suppliers',
          'route': '/parties',
          'operational': true,
          'blocked_reasons': <String>[],
        },
        {
          'capability_id': 'payments',
          'title': 'Payments and receipts',
          'description': 'Receipts',
          'route': '/payments',
          'operational': true,
          'blocked_reasons': <String>[],
        },
        {
          'capability_id': 'cash_sessions',
          'title': 'Cash sessions',
          'description': 'Disabled for schools',
          'route': '/cash-sessions',
          'operational': false,
          'blocked_reasons': ['Disabled by the school profile'],
        },
      ],
      ...?extra,
    };

const _launchPayload = {
  'url': 'https://finreg.test/#/delegated?code=abc',
  'target_path': '/billing',
  'expires_in': 60,
};

class _FakeApi extends ApiClient {
  _FakeApi({
    this.mode = 'finreg',
    this.manifest,
    this.failManifest = false,
  }) : super(const FlutterSecureStorage());

  final String mode;
  final Map<String, dynamic>? manifest;
  bool failManifest;
  final List<String> getPaths = [];
  final List<String> postPaths = [];
  Object? postError;
  Completer<dynamic>? pendingLaunch;

  @override
  Future<dynamic> get(String path,
      {Map<String, dynamic>? queryParameters, Duration? receiveTimeout}) async {
    getPaths.add(path);
    if (path == '/finance/internal-payments/mode') return {'mode': mode};
    if (path == '/finreg/capabilities') {
      if (failManifest) throw Exception('FinReg indisponível');
      return manifest ?? _manifest();
    }
    if (path == '/schools/info') {
      return {
        'id': 'school-1',
        'name': 'Escola',
        'slug': 'escola',
        'currency': 'AOA',
        'is_active': true,
      };
    }
    if (path.startsWith('/finreg/composition-readiness/')) {
      return {'source_total': 0, 'ready_total': 0, 'mapped_total': 0};
    }
    if (path == '/billing/dashboard') {
      return {
        'mode': mode == 'internal' ? 'internal' : 'fake',
        'as_of': '2026-10-28',
        'period': {'from': '2026-10-01', 'to': '2026-10-28'},
        'month': {
          'billing_month': '2026-10',
          'generated': false,
          'status': null,
          'students': null,
          'failed': null,
          'total': null,
          'due_date': '2026-11-05',
          'auto_generate': false,
        },
        'debts': {
          'count': 0,
          'total_outstanding': 0.0,
          'total_overdue': 0.0,
          'by_bucket': <String, dynamic>{},
          'by_service': <dynamic>[],
        },
        'sales': {'invoice_count': 0, 'total_gross': 0.0},
        'collections': {'payment_count': 0, 'total_collected': 0.0},
      };
    }
    return <dynamic>[];
  }

  @override
  Future<dynamic> post(String path,
      {dynamic data, Duration? receiveTimeout}) async {
    postPaths.add(path);
    if (pendingLaunch != null) return pendingLaunch!.future;
    if (postError != null) throw postError!;
    return _launchPayload;
  }
}

class _Launched {
  const _Launched(this.url, this.mode, this.window);

  final Uri url;
  final LaunchMode mode;
  final String? window;
}

/// The FinReg card is collapsed by default; its details and the mint-on-tap
/// button only exist once the person opens it.
Future<void> _expandFinregCard(WidgetTester tester) async {
  await tester.tap(find.text('FinReg — facturação e conformidade'));
  await tester.pumpAndSettle();
}

/// Six tabs are wider than a test surface, so the outer tab can be scrolled
/// out of reach; bring it into view before tapping it.
Future<void> _tapTab(WidgetTester tester, String label) async {
  final target = find.text(label);
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<_FakeApi> _pumpHost(
  WidgetTester tester, {
  String mode = 'finreg',
  String initialCapabilityId = 'billing',
  Map<String, dynamic>? manifest,
  bool failManifest = false,
  bool withRouter = false,
}) async {
  final api = _FakeApi(
    mode: mode,
    manifest: manifest,
    failManifest: failManifest,
  );
  const delegates = [
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ];
  final Widget app;
  if (withRouter) {
    app = MaterialApp.router(
      locale: const Locale('pt'),
      supportedLocales: const [Locale('pt'), Locale('en')],
      localizationsDelegates: delegates,
      routerConfig: GoRouter(
        initialLocation: '/admin/finance',
        routes: [
          GoRoute(
            path: '/admin/finance',
            builder: (_, __) => Scaffold(
              body: FinregSalesHostScreen(
                initialCapabilityId: initialCapabilityId,
              ),
            ),
          ),
          // Every other route in this test resolves to an empty page; the
          // assertions care that navigation happened, not where it landed.
          GoRoute(
            path: '/admin/finance/home',
            builder: (_, __) => const FinanceHomeScreen(),
          ),
        ],
      ),
    );
  } else {
    app = MaterialApp(
      locale: const Locale('pt'),
      supportedLocales: const [Locale('pt'), Locale('en')],
      localizationsDelegates: delegates,
      home: Scaffold(
        body: FinregSalesHostScreen(initialCapabilityId: initialCapabilityId),
      ),
    );
  }
  await tester.pumpWidget(ProviderScope(
    overrides: [apiClientProvider.overrideWithValue(api)],
    child: app,
  ));
  await tester.pumpAndSettle();
  return api;
}

void main() {
  final launches = <_Launched>[];

  setUp(() {
    launches.clear();
    finregUrlLauncher = (
      Uri url, {
      LaunchMode mode = LaunchMode.platformDefault,
      String? webOnlyWindowName,
    }) async {
      launches.add(_Launched(url, mode, webOnlyWindowName));
      return true;
    };
  });

  tearDown(() {
    finregUrlLauncher = launchUrl;
  });

  testWidgets(
      'a school without FinReg keeps the native payments controller and '
      'reaches the finance area', (tester) async {
    await _pumpHost(tester, mode: 'internal', withRouter: true);

    expect(find.byType(InternalPaymentsScreen), findsOneWidget);
    expect(find.text('Abrir no FinReg'), findsNothing);

    await tester.tap(find.byTooltip('Área financeira'));
    await tester.pumpAndSettle();
    expect(find.byType(FinanceHomeScreen), findsOneWidget);
    expect(find.text('Painel Financeiro'), findsOneWidget);
  });

  testWidgets('FinReg has one entry card, not a mirrored workspace menu',
      (tester) async {
    final api = await _pumpHost(tester);

    expect(api.getPaths, contains('/finreg/capabilities'));
    // The card starts collapsed: status only, details on demand.
    expect(find.text('FinReg — facturação e conformidade'), findsOneWidget);
    expect(find.textContaining('Ligado · plano base'), findsOneWidget);
    expect(find.text('Abrir no FinReg'), findsNothing);
    await _expandFinregCard(tester);
    expect(find.text('Abrir no FinReg'), findsOneWidget);
    // FinReg's own workspace list is not reproduced as host tabs.
    expect(find.widgetWithText(Tab, 'Vendas e facturação'), findsNothing);
    expect(find.widgetWithText(Tab, 'Pessoas e entidades'), findsNothing);
    expect(find.widgetWithText(Tab, 'Sessões de caixa'), findsNothing);
    // The school's own areas are the tabs, ordered by the school year:
    // month state, debts, money in and out, settings, the two directories.
    expect(find.widgetWithText(Tab, 'Painel'), findsOneWidget);
    expect(find.widgetWithText(Tab, 'Dívidas e cobrança'), findsOneWidget);
    expect(find.widgetWithText(Tab, 'Pagamentos'), findsOneWidget);
    expect(find.widgetWithText(Tab, 'Configuração'), findsOneWidget);
    expect(find.widgetWithText(Tab, 'Encarregados'), findsOneWidget);
    expect(find.widgetWithText(Tab, 'Funcionários'), findsOneWidget);
    expect(find.widgetWithText(Tab, 'Operações da escola'), findsNothing);
  });

  testWidgets('a tap mints one code and opens FinReg in an external tab',
      (tester) async {
    final api = await _pumpHost(tester);
    await _expandFinregCard(tester);

    await tester.tap(find.text('Abrir no FinReg'));
    await tester.pumpAndSettle();

    expect(api.postPaths, ['/finreg/workspace-launch/billing']);
    expect(launches, hasLength(1));
    expect(launches.single.url.toString(),
        'https://finreg.test/#/delegated?code=abc');
    expect(launches.single.mode, LaunchMode.externalApplication);
    expect(launches.single.window, '_blank');
  });

  testWidgets('a contextual route opens its own FinReg capability',
      (tester) async {
    final api = await _pumpHost(tester, initialCapabilityId: 'payments');
    await _expandFinregCard(tester);

    await tester.tap(find.text('Abrir no FinReg'));
    await tester.pumpAndSettle();

    expect(api.postPaths, ['/finreg/workspace-launch/payments']);
    expect(launches, hasLength(1));
  });

  testWidgets('a double tap still mints a single code', (tester) async {
    final api = await _pumpHost(tester);
    final pending = Completer<dynamic>();
    api.pendingLaunch = pending;
    await _expandFinregCard(tester);

    await tester.tap(find.text('Abrir no FinReg'));
    await tester.tap(find.text('Abrir no FinReg'));
    await tester.pump();

    expect(api.postPaths, hasLength(1));

    pending.complete(_launchPayload);
    await tester.pumpAndSettle();
    expect(launches, hasLength(1));
  });

  testWidgets('a failed launch shows the error and a retry mints again',
      (tester) async {
    final api = await _pumpHost(tester);
    api.postError = Exception('FinReg indisponível');
    await _expandFinregCard(tester);

    await tester.tap(find.text('Abrir no FinReg'));
    await tester.pumpAndSettle();

    expect(find.textContaining('FinReg indisponível'), findsOneWidget);
    expect(launches, isEmpty);

    api.postError = null;
    await tester.tap(find.text('Abrir no FinReg'));
    await tester.pumpAndSettle();

    expect(api.postPaths, hasLength(2));
    expect(launches, hasLength(1));
  });

  testWidgets('a FinReg outage leaves every native school area usable',
      (tester) async {
    final api = await _pumpHost(tester, failManifest: true);

    expect(find.textContaining('Indisponível'), findsOneWidget);
    expect(find.text('Abrir no FinReg'), findsNothing);
    // The native areas stay, led by the month card.
    expect(find.text('Outubro 2026 · dívidas por gerar'), findsOneWidget);

    await _tapTab(tester, 'Encarregados');
    expect(find.byType(GuardiansListScreen), findsOneWidget);

    await _tapTab(tester, 'Funcionários');
    expect(find.byType(EmployeesListScreen), findsOneWidget);

    api.failManifest = false;
    await _expandFinregCard(tester);
    await tester.tap(find.text('Tentar novamente'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Indisponível'), findsNothing);
    expect(find.textContaining('Ligado · plano base'), findsOneWidget);
    expect(find.text('Abrir no FinReg'), findsOneWidget);
  });

  testWidgets('the plan line follows FinReg, not a local toggle',
      (tester) async {
    await _pumpHost(tester);
    expect(find.textContaining('plano base'), findsOneWidget);
    expect(find.textContaining('plano completo'), findsNothing);
  });

  testWidgets('an entitled ERP add-on is stated on the card', (tester) async {
    await _pumpHost(
      tester,
      manifest: _manifest(extra: {
        'erp_entitled': true,
        'erp_capabilities': ['accounting', 'purchasing', 'payroll', 'treasury'],
        'navigable_capabilities': [
          'parties',
          'catalog',
          'billing',
          'receivables',
          'payments',
          'recurring_billing',
          'reporting',
          'integrations',
          'accounting',
          'treasury',
          'payroll',
          'purchasing',
        ],
      }),
    );

    expect(find.textContaining('plano completo'), findsOneWidget);
    expect(find.textContaining('plano base'), findsNothing);
  });

  testWidgets('an older FinReg plan payload still states the plan',
      (tester) async {
    await _pumpHost(
      tester,
      manifest: _manifest(extra: {
        'finreg_plan': {
          'plan': 'erp',
          'erp_enabled': true,
          'erp_capabilities': [
            'accounting',
            'purchasing',
            'payroll',
            'treasury'
          ],
        },
      }),
    );

    expect(find.textContaining('plano completo'), findsOneWidget);
  });

  testWidgets('the debts tab keeps every debt workflow in one hub',
      (tester) async {
    await _pumpHost(tester);

    await _tapTab(tester, 'Dívidas e cobrança');
    expect(find.text('Gerar dívidas do mês'), findsOneWidget);
    expect(find.text('Controlo de dívidas'), findsOneWidget);
    expect(find.text('Multas por atraso'), findsOneWidget);
    expect(find.text('Acordos de pagamento'), findsOneWidget);
    expect(find.text('Lembretes de cobrança'), findsOneWidget);
    expect(find.text('Créditos dos encarregados'), findsOneWidget);

    await _tapTab(tester, 'Pagamentos');
    expect(find.text('Pagamentos por referência'), findsOneWidget);
    expect(find.text('Referências Multicaixa'), findsOneWidget);
    expect(find.text('Comprovativos de pagamento'), findsOneWidget);
    expect(find.text('Fecho de caixa'), findsOneWidget);
    expect(find.text('Despesas'), findsOneWidget);
    expect(find.text('Extrato de contas'), findsOneWidget);

    await _tapTab(tester, 'Configuração');
    expect(find.text('Política de propinas'), findsOneWidget);
    expect(find.text('Serviços e mensalidades'), findsOneWidget);
    expect(find.text('Relatório por serviço'), findsOneWidget);

    await _tapTab(tester, 'Encarregados');
    expect(find.byType(GuardiansListScreen), findsOneWidget);

    await _tapTab(tester, 'Funcionários');
    expect(find.byType(EmployeesListScreen), findsOneWidget);
  });
}
