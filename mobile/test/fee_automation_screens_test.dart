import 'package:cellen/core/api/api_client.dart';
import 'package:cellen/core/providers/currency_provider.dart';
import 'package:cellen/features/admin/finance/billing_run_screen.dart';
import 'package:cellen/features/admin/finance/fee_policy_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

Map<String, dynamic> _line() => {
      'service': 'tuition',
      'service_label': 'Propina',
      'source_id': null,
      'billing_item_id': 'item-1',
      'description': 'Propina de Outubro',
      'quantity': 1.0,
      'base_unit_price': 100000.0,
      'unit_price': 100000.0,
      'discount_pct': 5.0,
      'discount_amount': 5000.0,
      'tax_rate': 0.0,
      'tax_option_code': 'IVA_ISE',
      'exemption_reason': 'M10',
      'proration_factor': null,
      'line_net': 95000.0,
      'iva_amount': 0.0,
      'line_total': 95000.0,
    };

Map<String, dynamic> _preview({bool blocked = false}) => {
      'billing_month': '2026-10',
      'mode': 'fake',
      'school_year': {
        'id': 'year-1',
        'year_label': '2026/2027',
        'start_date': '2026-09-01',
        'end_date': '2027-07-31',
      },
      'policy': {
        'billing_day': 1,
        'due_days': 5,
        'sibling_discount_pct': 5.0,
        'proration_policy': 'pro_rata_days',
      },
      'run_date': '2026-10-01',
      'due_date': '2026-10-06',
      'totals': {
        'students': 1,
        'lines': 1,
        'subtotal': 100000.0,
        'discount_total': 5000.0,
        'net_total': 95000.0,
        'iva_total': 0.0,
        'total': 95000.0,
        'families_with_discount': 1,
      },
      'students': [
        {
          'child_id': 'child-1',
          'child_name': 'Ana Silva',
          'guardian_id': 'guardian-1',
          'guardian_name': 'Maria Silva',
          'guardian_nif': '123456789',
          'enrollment_id': 'enrollment-1',
          'plan_external_id': 'plan-1',
          'billing_day': 1,
          'sibling_index': 2,
          'family_size': 2,
          'sibling_discount_applied': true,
          'lines': [_line()],
          'subtotal': 100000.0,
          'discount_total': 5000.0,
          'net_total': 95000.0,
          'iva_total': 0.0,
          'total': 95000.0,
          'warnings': <String>[],
        }
      ],
      'unbilled': <Map<String, dynamic>>[],
      'warnings': <String>[],
      'blockers': blocked
          ? [
              {
                'code': 'no_billable_students',
                'message': 'Nenhum aluno ativo com valores a cobrar neste mês.',
              }
            ]
          : <Map<String, dynamic>>[],
      'existing_run': null,
    };

Map<String, dynamic> _run() => {
      'id': 'run-1',
      'school_year_id': 'year-1',
      'billing_month': '2026-10',
      'status': 'completed',
      'mode': 'fake',
      'stats': {
        'generated': 1,
        'queued': 0,
        'failed': 0,
        'totals': {'total': 95000.0},
        'failures': <Map<String, dynamic>>[],
      },
      'created_at': null,
      'completed_at': null,
      'instructions': [
        {
          'instruction_id': 'instruction-1',
          'child_id': 'child-1',
          'child_name': 'Ana Silva',
          'plan_external_id': 'plan-1',
          'status': 'confirmed',
          'error_code': null,
          'error_detail': null,
          'finreg_document_id': 'document-1',
          'attempts': 1,
        }
      ],
      'documents': <Map<String, dynamic>>[],
    };

class _FakeApi extends ApiClient {
  _FakeApi() : super(const FlutterSecureStorage());

  bool blocked = false;
  Object? previewError;
  final List<Map<String, dynamic>> putBodies = [];
  int previewCalls = 0;
  int generateCalls = 0;

  @override
  Future<dynamic> get(String path,
      {Map<String, dynamic>? queryParameters, Duration? receiveTimeout}) async {
    if (path == '/billing/runs') return <Map<String, dynamic>>[];
    if (path == '/billing/fee-policy') {
      return {
        'school_year': {
          'id': 'year-1',
          'year_label': '2026/2027',
          'start_date': '2026-09-01',
          'end_date': '2027-07-31',
          'is_active': true,
        },
        'policy': {
          'default_tuition_billing_item_id': null,
          'default_enrollment_fee': null,
          'sibling_discount_pct': 5.0,
          'sibling_discount_min_children': 2,
          'sibling_discount_scope': 'additional_children',
          'due_days': 5,
          'billing_day': 1,
          'auto_generate': false,
          'proration_policy': 'pro_rata_days',
          'is_default': true,
        },
        'default_tuition_item': null,
      };
    }
    if (path == '/finance/billing-items') return <Map<String, dynamic>>[];
    return <dynamic>[];
  }

  @override
  Future<dynamic> post(String path,
      {dynamic data, Duration? receiveTimeout}) async {
    if (path == '/billing/runs/preview') {
      previewCalls += 1;
      if (previewError != null) throw previewError!;
      return _preview(blocked: blocked);
    }
    if (path == '/billing/runs') {
      generateCalls += 1;
      return {'created': true, 'run': _run()};
    }
    return <String, dynamic>{};
  }

  @override
  Future<dynamic> put(String path, {dynamic data}) async {
    putBodies.add(Map<String, dynamic>.from(data as Map));
    return <String, dynamic>{};
  }
}

Future<_FakeApi> _pump(
  WidgetTester tester,
  Widget screen, {
  _FakeApi? api,
}) async {
  final fake = api ?? _FakeApi();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(fake),
      currencyFormatProvider.overrideWithValue(
        NumberFormat.currency(locale: 'pt_AO', symbol: 'Kz'),
      ),
    ],
    child: MaterialApp(home: screen),
  ));
  await tester.pumpAndSettle();
  return fake;
}

void main() {
  testWidgets('billing run previews the director numbers and generates',
      (tester) async {
    final api = await _pump(tester, const BillingRunScreen());

    expect(find.text('Gerar Dívidas'), findsOneWidget);
    expect(find.text('Ana Silva'), findsOneWidget);
    expect(find.text('Total a cobrar'), findsOneWidget);
    expect(find.text('Gerar dívidas do mês'), findsOneWidget);
    expect(api.previewCalls, 1);

    final generate = find.text('Gerar dívidas do mês');
    await tester.ensureVisible(generate);
    await tester.pumpAndSettle();
    await tester.tap(generate);
    await tester.pumpAndSettle();

    expect(api.generateCalls, 1);
    expect(find.textContaining('Cobranças geradas'), findsOneWidget);
    expect(find.textContaining('Resultado · Outubro 2026'), findsOneWidget);
  });

  testWidgets('billing run refuses to generate while a blocker remains',
      (tester) async {
    final api = _FakeApi()..blocked = true;
    await _pump(tester, const BillingRunScreen(), api: api);

    expect(find.text('Corrija antes de gerar'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Gerar dívidas do mês'),
    );
    expect(button.onPressed, isNull);
    expect(api.generateCalls, 0);
  });

  testWidgets('fee policy loads defaults and saves the school values',
      (tester) async {
    final api = await _pump(tester, const FeePolicyScreen());

    expect(find.text('Política de Propinas'), findsOneWidget);
    expect(find.text('Desconto de irmãos'), findsOneWidget);
    expect(find.text('Ainda usa os valores padrão. Guarde para personalizar.'),
        findsOneWidget);

    final save = find.text('Guardar política');
    await tester.scrollUntilVisible(
      save,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(api.putBodies, hasLength(1));
    final body = api.putBodies.single;
    expect(body['school_year_id'], 'year-1');
    expect(body['sibling_discount_pct'], 5.0);
    expect(body['sibling_discount_scope'], 'additional_children');
    expect(find.textContaining('Política guardada'), findsOneWidget);
  });
}
