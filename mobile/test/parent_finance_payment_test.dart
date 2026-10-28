import 'package:cellen/core/api/api_client.dart';
import 'package:cellen/core/providers/currency_provider.dart';
import 'package:cellen/features/parent/finance/parent_invoices_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

Map<String, dynamic> _finregDocument() => {
      'id': 'instruction-1',
      'finreg': true,
      'document_id': 'finreg-doc-1',
      'child_id': 'child-1',
      'child_name': 'Ana Silva',
      'document_type': 'invoice',
      'full_document_number': 'FT 2026/1',
      'reference_month': '2026-10-01',
      'gross_total': 120000.0,
      'status': 'issued',
      'due_date': '2026-10-05',
      'amount_paid': 0.0,
      'balance': 120000.0,
      'payment_proofs': <Map<String, dynamic>>[],
    };

class _ParentApi extends ApiClient {
  _ParentApi() : super(const FlutterSecureStorage());

  Map<String, dynamic>? lastReferenceBody;

  @override
  Future<dynamic> get(String path,
      {Map<String, dynamic>? queryParameters, Duration? receiveTimeout}) async {
    switch (path) {
      case '/finance/parent/invoices':
        return <dynamic>[];
      case '/finreg/parent/documents':
        return [_finregDocument()];
      case '/guardians/me':
        return {'nif': '123456789'};
      case '/finance/parent/credits':
        return {'balance': 0, 'entries': <Map<String, dynamic>>[]};
      case '/finance/parent/payment-references':
        return <dynamic>[];
      default:
        return <dynamic>[];
    }
  }

  @override
  Future<dynamic> post(String path,
      {dynamic data, Duration? receiveTimeout}) async {
    if (path == '/finance/parent/payment-references/principia-pay') {
      lastReferenceBody = Map<String, dynamic>.from(data as Map);
      return {
        'id': 'ref-1',
        'school_id': 'school-1',
        'billing_guardian_id': 'guardian-1',
        'entity': '12345',
        'reference': '987654321',
        'amount': 120000.0,
        'status': 'active',
        'provider': 'principia_pay',
        'checkout_url': 'https://pay.example/ref-1',
        'paid_at': null,
        'created_at': '2026-10-27T08:00:00Z',
      };
    }
    return <String, dynamic>{};
  }
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('pt_PT', null);
  });

  testWidgets('a parent opens a reference for their FinReg document',
      (tester) async {
    final api = _ParentApi();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(api),
        currencyFormatProvider.overrideWithValue(
          NumberFormat.currency(locale: 'pt_AO', symbol: 'Kz'),
        ),
      ],
      child: const MaterialApp(home: ParentInvoicesScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Ana Silva'), findsOneWidget);
    final pay = find.text('Pagar com referência');
    expect(pay, findsOneWidget);

    await tester.ensureVisible(pay);
    await tester.tap(pay);
    await tester.pumpAndSettle();

    expect(api.lastReferenceBody?['document_id'], 'finreg-doc-1');
    expect(find.text('Referência de pagamento'), findsOneWidget);
    expect(find.text('987654321'), findsOneWidget);
  });
}
