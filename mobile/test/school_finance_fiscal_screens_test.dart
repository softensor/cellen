import 'package:cellen/core/api/api_client.dart';
import 'package:cellen/features/admin/finance/fiscal/fiscal_documents_screen.dart';
import 'package:cellen/features/admin/finance/internal_payments_screen.dart';
import 'package:cellen/features/admin/finance/school_finance_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// Answers the few calls the finance shell and the fiscal screens make.
class _FakeApi extends ApiClient {
  _FakeApi({this.mode = 'finreg'}) : super(const FlutterSecureStorage());

  final String mode;
  final List<String> getPaths = [];
  final List<(String, dynamic)> posts = [];

  static final _document = <String, dynamic>{
    'id': 'doc-1',
    'finreg_document_id': 'fin-1',
    'kind': 'invoice',
    'full_document_number': 'FT 2026/17',
    'document_status': 'finalized',
    'agt_status': 'rejected',
    'agt_message': 'NIF inválido',
    'state': 'rejected',
    'gross_total': 114000.0,
    'net_total': 100000.0,
    'tax_total': 14000.0,
    'document_date': '2026-11-02',
    'customer_name': 'Maria Encarregada',
    'pupil_name': 'Joana Aluna',
    'lines': [
      {'description': 'Propina Novembro', 'quantity': 1, 'line_total': 114000}
    ],
    'related': <dynamic>[],
  };

  @override
  Future<dynamic> get(String path,
      {Map<String, dynamic>? queryParameters, Duration? receiveTimeout}) async {
    getPaths.add(path);
    switch (path) {
      case '/finance/internal-payments/mode':
        return {'mode': mode};
      case '/schools/info':
        return {
          'id': 'school-1',
          'name': 'Escola',
          'slug': 'escola',
          'currency': 'AOA',
          'is_active': true,
        };
      case '/finreg/admin/documents':
        return {
          'total': 1,
          'summary': {'rejected': 1, 'processing': 0, 'submitted': 0},
          'items': [_document],
        };
      case '/finreg/admin/documents/doc-1':
        return _document;
      case '/finreg/admin/attention':
        return {'rejected_documents': 0, 'pending_documents': 0, 'failed_operations': 0};
      case '/billing/dashboard':
        return {
          'mode': 'finreg',
          'period': {'from': '2026-11-01', 'to': '2026-11-27'},
          'debts': {'by_bucket': <String, dynamic>{}, 'by_service': <dynamic>[]},
          'sales': <String, dynamic>{},
          'collections': <String, dynamic>{},
        };
    }
    return <dynamic>[];
  }

  @override
  Future<dynamic> post(String path, {dynamic data, Duration? receiveTimeout}) async {
    posts.add((path, data));
    return {
      'status': 'confirmed',
      'credit_note': {'full_document_number': 'NC 2026/3'},
    };
  }
}

Future<_FakeApi> _pump(WidgetTester tester, Widget child, {String mode = 'finreg'}) async {
  final api = _FakeApi(mode: mode);
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
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
      home: Scaffold(body: child),
    ),
  ));
  await tester.pumpAndSettle();
  return api;
}

void main() {
  testWidgets('the finance shell is Cellen only and has a fiscal documents tab',
      (tester) async {
    final api = await _pump(tester, const SchoolFinanceScreen());

    expect(find.text('Documentos fiscais'), findsOneWidget);
    expect(find.textContaining('FinReg'), findsNothing);
    expect(find.text('Abrir no FinReg'), findsNothing);
    expect(api.getPaths, isNot(contains('/finreg/capabilities')));
    expect(api.posts, isEmpty);
  });

  testWidgets('a school without certified invoicing keeps the internal controller',
      (tester) async {
    await _pump(tester, const SchoolFinanceScreen(), mode: 'internal');
    expect(find.byType(InternalPaymentsScreen), findsOneWidget);
  });

  testWidgets('invoices list FinReg values and flag AGT rejections', (tester) async {
    await _pump(tester, const FiscalDocumentsScreen());

    expect(find.text('FT 2026/17'), findsOneWidget);
    expect(find.text('Rejeitada pela AGT'), findsOneWidget);
    expect(find.text('1 documento foi rejeitado pela AGT.'), findsOneWidget);
    expect(find.text('Emitir fatura'), findsOneWidget);
  });

  testWidgets('a correction sends one request id and the reason', (tester) async {
    final api = await _pump(tester, const FiscalDocumentsScreen());

    await tester.tap(find.text('FT 2026/17'));
    await tester.pumpAndSettle();
    expect(find.text('Motivo da AGT: NIF inválido'), findsOneWidget);

    final annul = find.text('Anular (nota de crédito)');
    await tester.ensureVisible(annul);
    await tester.tap(annul);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Valor errado');
    await tester.tap(find.widgetWithText(FilledButton, 'Anular'));
    await tester.pumpAndSettle();

    final correction = api.posts.single;
    expect(correction.$1, '/finreg/admin/documents/doc-1/corrections');
    final body = correction.$2 as Map;
    expect(body['reason'], 'Valor errado');
    expect(
      RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')
          .hasMatch(body['request_id'] as String),
      isTrue,
    );
  });
}
