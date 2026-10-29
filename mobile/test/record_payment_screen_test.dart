import 'package:cellen/core/api/api_client.dart';
import 'package:cellen/core/api/api_exception.dart';
import 'package:cellen/core/providers/currency_provider.dart';
import 'package:cellen/features/admin/finance/record_payment_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

Map<String, dynamic> _debtRow() => {
      'source': 'finreg',
      'document_id': 'doc-1',
      'document_number': 'FT 2026/1',
      'due_date': '2026-10-05',
      'student_name': 'Ana Silva',
      'guardian_name': 'Maria Silva',
      'outstanding': 120000.0,
      'status': 'overdue',
    };

class _RecordApi extends ApiClient {
  _RecordApi() : super(const FlutterSecureStorage());

  Map<String, dynamic>? postBody;
  Object? postError;
  int debtsCalls = 0;

  @override
  Future<dynamic> get(String path,
      {Map<String, dynamic>? queryParameters, Duration? receiveTimeout}) async {
    if (path == '/billing/debts') {
      debtsCalls += 1;
      return {
        'mode': 'fake',
        'count': 1,
        'total_outstanding': 120000.0,
        'rows': [_debtRow()],
      };
    }
    return <dynamic>[];
  }

  @override
  Future<dynamic> post(String path,
      {dynamic data, Duration? receiveTimeout}) async {
    if (path == '/finance/payments/record') {
      postBody = Map<String, dynamic>.from(data as Map);
      if (postError != null) throw postError!;
      return {
        'id': 'payment-1',
        'status': 'normal',
        'amount': 120000.0,
        'payment_method': 'cash',
      };
    }
    return <String, dynamic>{};
  }
}

Future<_RecordApi> _pump(WidgetTester tester, {String? documentId}) async {
  final api = _RecordApi();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(api),
      currencyFormatProvider.overrideWithValue(
        NumberFormat.currency(locale: 'pt_AO', symbol: 'Kz'),
      ),
    ],
    child: MaterialApp(home: RecordPaymentScreen(documentId: documentId)),
  ));
  await tester.pumpAndSettle();
  return api;
}

void main() {
  testWidgets('records an in-person payment from the debt list',
      (tester) async {
    final api = await _pump(tester);

    expect(find.text('Ana Silva'), findsOneWidget);
    expect(find.textContaining('FT 2026/1'), findsOneWidget);

    await tester.tap(find.text('Ana Silva'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Em dívida'), findsWidgets);
    await tester.tap(find.text('Registar'));
    await tester.pumpAndSettle();

    expect(api.postBody, isNotNull);
    expect(api.postBody!['document_id'], 'doc-1');
    expect(api.postBody!['amount'], 120000.0);
    expect(api.postBody!['payment_method'], 'cash');
    expect(api.postBody!['idempotency_key'], startsWith('cellen-inperson-'));
    expect(find.text('Pagamento registado com sucesso.'), findsOneWidget);
  });

  testWidgets('opening with a document id goes straight to its payment',
      (tester) async {
    final api = await _pump(tester, documentId: 'doc-1');

    expect(find.textContaining('Em dívida'), findsWidgets);
    await tester.tap(find.text('Registar'));
    await tester.pumpAndSettle();

    expect(api.postBody!['document_id'], 'doc-1');
  });

  testWidgets('a refused payment keeps the dialog open with the reason',
      (tester) async {
    final api = await _pump(tester);
    api.postError = const ApiException(
      statusCode: 422,
      message: 'O valor excede o saldo em dívida.',
    );

    await tester.tap(find.text('Ana Silva'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Registar'));
    await tester.pumpAndSettle();

    expect(find.text('O valor excede o saldo em dívida.'), findsOneWidget);
    // Still on the dialog, so the desk can correct the amount.
    expect(find.text('Registar'), findsOneWidget);
    expect(find.text('Pagamento registado com sucesso.'), findsNothing);
  });
}
