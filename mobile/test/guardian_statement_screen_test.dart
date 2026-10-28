import 'package:cellen/core/api/api_client.dart';
import 'package:cellen/core/providers/currency_provider.dart';
import 'package:cellen/features/admin/finance/guardian_statement_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

Map<String, dynamic> _statement() => {
      'guardian_name': 'Maria Silva',
      'total_invoiced': 250000.0,
      'total_settled': 100000.0,
      'current_balance': 150000.0,
      'credit_balance': 0.0,
      'movements': [
        {
          'type': 'invoice',
          'description': 'FT 2026/1 · Propina de Outubro',
          'date': '2026-10-01',
          'debit': 250000.0,
          'credit': 0.0,
          'running_balance': 250000.0,
        },
        {
          'type': 'payment',
          'description': 'Recibo 2026/7 · Transferência',
          'date': '2026-10-10',
          'debit': 0.0,
          'credit': 100000.0,
          'running_balance': 150000.0,
        },
      ],
    };

class _StatementApi extends ApiClient {
  _StatementApi({this.finregActive = true, this.finregFails = false})
      : super(const FlutterSecureStorage());

  final bool finregActive;
  final bool finregFails;
  final List<String> getPaths = [];
  final List<Map<String, dynamic>?> queryFor = [];

  @override
  Future<dynamic> get(String path,
      {Map<String, dynamic>? queryParameters, Duration? receiveTimeout}) async {
    getPaths.add(path);
    queryFor.add(queryParameters);
    if (path == '/guardians') {
      return [
        {'id': 'guardian-1', 'first_name': 'Maria', 'last_name': 'Silva'},
        {'id': 'guardian-2', 'first_name': 'Paulo', 'last_name': 'Neto'},
      ];
    }
    if (path == '/finance/internal-payments/mode') {
      return {
        'mode': finregActive ? 'finreg' : 'internal',
        'finreg_active': finregActive,
      };
    }
    if (path == '/finreg/customers/guardian-1/statement') {
      if (finregFails) throw Exception('FinReg indisponível');
      return _statement();
    }
    if (path == '/finance/reports/statement/guardian-1') {
      return _statement();
    }
    return <dynamic>[];
  }
}

Future<_StatementApi> _pump(
  WidgetTester tester, {
  bool finregActive = true,
  bool finregFails = false,
}) async {
  final api = _StatementApi(
    finregActive: finregActive,
    finregFails: finregFails,
  );
  await tester.pumpWidget(ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(api),
      currencyFormatProvider.overrideWithValue(
        NumberFormat.currency(locale: 'pt_AO', symbol: 'Kz'),
      ),
    ],
    child: const MaterialApp(home: GuardianStatementScreen()),
  ));
  await tester.pumpAndSettle();
  return api;
}

Future<void> _selectMariaAndLoad(WidgetTester tester) async {
  await tester.tap(find.byType(DropdownButtonFormField<String>));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Maria Silva').last);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Ver Extrato'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the statement comes from FinReg when it owns the school',
      (tester) async {
    final api = await _pump(tester);
    await _selectMariaAndLoad(tester);

    expect(api.getPaths, contains('/finreg/customers/guardian-1/statement'));
    final query = api.queryFor[
        api.getPaths.indexOf('/finreg/customers/guardian-1/statement')];
    final year = DateTime.now().year;
    expect(query?['date_from'], '$year-01-01');
    expect(query?['date_to'], isNotNull);

    expect(find.text('Total Facturado'), findsOneWidget);
    expect(find.text('Total Pago'), findsOneWidget);
    expect(find.text('Saldo em Dívida'), findsOneWidget);
    expect(find.text('FT 2026/1 · Propina de Outubro'), findsOneWidget);
    expect(find.text('Recibo 2026/7 · Transferência'), findsOneWidget);
    // No fallback notice: FinReg answered.
    expect(find.textContaining('extrato interno'), findsNothing);
  });

  testWidgets('a FinReg outage falls back to the internal ledger, and says so',
      (tester) async {
    final api = await _pump(tester, finregFails: true);
    await _selectMariaAndLoad(tester);

    expect(api.getPaths, contains('/finance/reports/statement/guardian-1'));
    final query = api.queryFor[
        api.getPaths.indexOf('/finance/reports/statement/guardian-1')];
    expect(query?['from_date'], isNotNull);
    expect(query?['to_date'], isNotNull);
    expect(
      find.text(
          'O FinReg não respondeu; a mostrar o extrato interno do Cellen.'),
      findsOneWidget,
    );
    expect(find.text('FT 2026/1 · Propina de Outubro'), findsOneWidget);
  });

  testWidgets('an internal school reads its own statement directly',
      (tester) async {
    final api = await _pump(tester, finregActive: false);
    await _selectMariaAndLoad(tester);

    expect(api.getPaths,
        isNot(contains('/finreg/customers/guardian-1/statement')));
    expect(api.getPaths, contains('/finance/reports/statement/guardian-1'));
    expect(find.text('Saldo em Dívida'), findsOneWidget);
  });
}
