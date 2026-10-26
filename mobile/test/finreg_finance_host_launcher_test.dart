import 'dart:async';

import 'package:cellen/core/api/api_client.dart';
import 'package:cellen/features/admin/finance/finreg_sales_host_screen.dart';
import 'package:cellen/features/admin/finance/internal_payments_screen.dart';
import 'package:cellen/features/admin/guardians/guardians_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher/url_launcher.dart';

/// The manifest Cellen consumes. FinReg owns it in production; this is the
/// shape `FinregManifest.fromJson` reads.
Map<String, dynamic> _manifest() => {
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
          'capability_id': 'cash_sessions',
          'title': 'Cash sessions',
          'description': 'Disabled for schools',
          'route': '/cash-sessions',
          'operational': false,
          'blocked_reasons': ['Disabled by the school profile'],
        },
      ],
    };

const _launchPayload = {
  'url': 'https://finreg.test/#/delegated?code=abc',
  'target_path': '/billing',
  'expires_in': 60,
};

class _FakeApi extends ApiClient {
  _FakeApi({this.mode = 'finreg'}) : super(const FlutterSecureStorage());

  final String mode;
  final List<String> getPaths = [];
  final List<String> postPaths = [];
  Object? postError;
  Completer<dynamic>? pendingLaunch;

  @override
  Future<dynamic> get(String path,
      {Map<String, dynamic>? queryParameters}) async {
    getPaths.add(path);
    if (path == '/finance/internal-payments/mode') return {'mode': mode};
    if (path == '/finreg/capabilities') return _manifest();
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
    return <dynamic>[];
  }

  @override
  Future<dynamic> post(String path, {dynamic data}) async {
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

Future<_FakeApi> _pumpHost(
  WidgetTester tester, {
  String mode = 'finreg',
  String initialCapabilityId = 'billing',
}) async {
  final api = _FakeApi(mode: mode);
  await tester.pumpWidget(ProviderScope(
    overrides: [apiClientProvider.overrideWithValue(api)],
    child: MaterialApp(
      locale: const Locale('pt'),
      supportedLocales: const [Locale('pt'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(
        body: FinregSalesHostScreen(initialCapabilityId: initialCapabilityId),
      ),
    ),
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

  testWidgets('a school without FinReg keeps the native payments controller',
      (tester) async {
    await _pumpHost(tester, mode: 'internal');

    expect(find.byType(InternalPaymentsScreen), findsOneWidget);
    expect(find.text('Abrir no FinReg'), findsNothing);
  });

  testWidgets('only operational workspaces get a launcher tab',
      (tester) async {
    final api = await _pumpHost(tester);

    expect(api.getPaths, contains('/finreg/capabilities'));
    expect(find.widgetWithText(Tab, 'Vendas e facturação'), findsOneWidget);
    expect(find.widgetWithText(Tab, 'Pessoas e entidades'), findsOneWidget);
    // The manifest still lists cash sessions, but blocked at the profile.
    expect(find.widgetWithText(Tab, 'Sessões de caixa'), findsNothing);
    expect(find.text('Abrir no FinReg'), findsOneWidget);
  });

  testWidgets('a tap mints one code and opens FinReg in an external tab',
      (tester) async {
    final api = await _pumpHost(tester);

    await tester.tap(find.text('Abrir no FinReg'));
    await tester.pumpAndSettle();

    expect(api.postPaths, ['/finreg/workspace-launch/billing']);
    expect(launches, hasLength(1));
    expect(launches.single.url.toString(),
        'https://finreg.test/#/delegated?code=abc');
    expect(launches.single.mode, LaunchMode.externalApplication);
    expect(launches.single.window, '_blank');
  });

  testWidgets('a double tap still mints a single code', (tester) async {
    final api = await _pumpHost(tester);
    final pending = Completer<dynamic>();
    api.pendingLaunch = pending;

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

  testWidgets('billing keeps school operations and parties keeps guardians',
      (tester) async {
    await _pumpHost(tester);

    // Billing opens on the authoritative FinReg pane; the school operations
    // grid stays one tab away.
    expect(find.text('Operações escolares'), findsOneWidget);
    await tester.tap(find.text('Operações escolares'));
    await tester.pumpAndSettle();
    expect(find.text('Operações financeiras da escola'), findsOneWidget);

    await tester.tap(find.text('Pessoas e entidades'));
    await tester.pumpAndSettle();
    expect(find.text('Encarregados e responsáveis'), findsOneWidget);
    expect(find.byType(GuardiansListScreen), findsOneWidget);
  });
}
