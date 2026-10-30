import 'package:cellen/core/api/api_client.dart';
import 'package:cellen/core/providers/currency_provider.dart';
import 'package:cellen/features/admin/finance/debt_control_screen.dart';
import 'package:cellen/features/admin/finance/dunning_screen.dart';
import 'package:cellen/features/admin/finance/fee_policy_screen.dart';
import 'package:cellen/features/admin/finance/finance_home_screen.dart';
import 'package:cellen/features/admin/finance/principia_pay_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

Map<String, dynamic> _debtRow() => {
      'source': 'finreg',
      'document_id': 'doc-1',
      'document_external_id': 'ext-1',
      'document_number': 'FT 2026/1',
      'document_type': 'FT',
      'due_date': '2026-10-05',
      'student_id': 'child-1',
      'student_name': 'Ana Silva',
      'guardian_id': 'guardian-1',
      'guardian_name': 'Maria Silva',
      'currency_code': 'AOA',
      'gross_total': 120000.0,
      'credited_total': 0.0,
      'paid_total': 0.0,
      'outstanding': 120000.0,
      'days_overdue': 22,
      'bucket': '21-30',
      'status': 'overdue',
      'lines': [
        {
          'service': 'item-1',
          'service_label': 'Propina',
          'description': 'Propina de Outubro',
          'quantity': 1.0,
          'gross_amount': 120000.0,
        }
      ],
      'services': [
        {
          'service': 'item-1',
          'service_label': 'Propina',
          'outstanding_amount': 120000.0,
        }
      ],
    };

Map<String, dynamic> _debts() => {
      'mode': 'fake',
      'as_of': '2026-10-27',
      'count': 1,
      'overdue_only': false,
      'total_outstanding': 120000.0,
      'total_overdue': 120000.0,
      'by_bucket': {'21-30': 120000.0, 'current': 0.0},
      'by_service': [
        {
          'service': 'item-1',
          'service_label': 'Propina',
          'outstanding': 120000.0,
          'documents': 1,
        }
      ],
      'by_student': [
        {
          'student_id': 'child-1',
          'student_name': 'Ana Silva',
          'outstanding': 120000.0,
          'overdue': 120000.0,
          'documents': 1,
        }
      ],
      'rows': [_debtRow()],
    };

Map<String, dynamic> _dashboard() => {
      'mode': 'fake',
      'as_of': '2026-10-27',
      'period': {'from': '2026-10-01', 'to': '2026-10-27'},
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
        'count': 3,
        'total_outstanding': 440000.0,
        'total_overdue': 125000.0,
        'by_bucket': {'current': 315000.0, '21-30': 125000.0},
        'by_service': [
          {
            'service': 'item-1',
            'service_label': 'Propina',
            'outstanding': 440000.0,
            'documents': 3,
          }
        ],
      },
      'sales': {'invoice_count': 12, 'total_gross': 980000.0},
      'collections': {'payment_count': 8, 'total_collected': 540000.0},
    };

Map<String, dynamic> _reference() => {
      'id': 'ref-1',
      'school_id': 'school-1',
      'billing_guardian_id': 'guardian-1',
      'entity': '12345',
      'reference': '987654321',
      'amount': 120000.0,
      'status': 'active',
      'provider': 'principia_pay',
      'checkout_url': 'https://pay.example/ref-1',
      'finreg_document_number': 'FT 2026/1',
      'paid_at': null,
      'created_at': '2026-10-27T08:00:00Z',
    };

Map<String, dynamic> _policy() => {
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
        'late_fee_enabled': true,
        'late_fee_billing_item_id': 'item-1',
        'late_fee_base': 'outstanding',
        'late_fee_bands': [
          {
            'id': 'band-1',
            'label': '10% até ao fim do mês',
            'anchor': 'due_month',
            'start_day': 10,
            'end_day': null,
            'percent': 10.0,
            'min_amount': null,
            'max_amount': null,
          },
          {
            'id': 'band-2',
            'label': '15% no mês seguinte',
            'anchor': 'next_month',
            'start_day': 10,
            'end_day': null,
            'percent': 15.0,
            'min_amount': null,
            'max_amount': null,
          },
        ],
        'dunning_enabled': true,
        'dunning_schedule': [
          {
            'level': 1,
            'offset_days': 5,
            'channels': ['in_app'],
            'message': null,
          },
          {
            'level': 2,
            'offset_days': 30,
            'channels': ['in_app', 'email'],
            'message': null,
          },
        ],
        'dunning_message_template': 'Olá {guardian_name}',
      },
      'default_tuition_item': null,
    };

class _OpsApi extends ApiClient {
  _OpsApi() : super(const FlutterSecureStorage());

  Map<String, dynamic>? lastReferenceBody;
  Map<String, dynamic>? probeResult;
  Map<String, dynamic>? dashboardOverride;
  Map<String, dynamic>? debtsOverride;
  final List<Map<String, dynamic>> dunningBodies = [];
  final List<Map<String, dynamic>> putBodies = [];
  int refreshCalls = 0;

  @override
  Future<dynamic> get(String path,
      {Map<String, dynamic>? queryParameters, Duration? receiveTimeout}) async {
    switch (path) {
      case '/billing/debts':
        return debtsOverride ?? _debts();
      case '/billing/dashboard':
        return dashboardOverride ?? _dashboard();
      case '/billing/principia-pay':
        return {
          'configured': true,
          'registered': true,
          'status': 'active',
          'client_id': 'client-1',
          'last_error': null,
          'provider': 'appy_pay',
        };
      case '/billing/principia-pay/references':
        return [_reference()];
      case '/billing/principia-pay/check':
        return probeResult ??
            {
              'status': 'active',
              'reachable': true,
              'checked_at': '2026-10-28T09:15:00Z',
              'latency_ms': 42,
            };
      case '/billing/dunning/deliveries':
        return [
          {
            'id': 'delivery-1',
            'source_kind': 'finreg_document',
            'source_id': 'doc-1',
            'document_number': 'FT 2026/1',
            'guardian_id': 'guardian-1',
            'student_id': 'child-1',
            'level': 2,
            'offset_days': 30,
            'channel': 'in_app',
            'status': 'sent',
            'error': null,
            'message_snapshot': 'Olá Maria',
            'sent_at': '2026-10-27T00:00:00Z',
            'created_at': '2026-10-27T00:00:00Z',
          }
        ];
      case '/billing/fee-policy':
        return _policy();
      case '/finance/billing-items':
        return [
          {'id': 'item-1', 'name': 'Multa por atraso', 'is_active': true}
        ];
      default:
        return <dynamic>[];
    }
  }

  @override
  Future<dynamic> post(String path,
      {dynamic data, Duration? receiveTimeout}) async {
    if (path == '/billing/principia-pay/references') {
      lastReferenceBody = Map<String, dynamic>.from(data as Map);
      return _reference();
    }
    if (path.endsWith('/refresh')) {
      refreshCalls += 1;
      return _reference();
    }
    if (path == '/billing/dunning/run') {
      dunningBodies.add(Map<String, dynamic>.from(data as Map));
      if (data['dry_run'] == true) {
        return {
          'as_of': '2026-10-27',
          'enabled': true,
          'reason': null,
          'steps': 2,
          'planned': [
            {
              'document_id': 'doc-1',
              'document_number': 'FT 2026/1',
              'student_name': 'Ana Silva',
              'guardian_name': 'Maria Silva',
              'outstanding': 120000.0,
              'due_date': '2026-10-05',
              'level': 2,
              'offset_days': 30,
              'channels': ['in_app'],
              'message': 'Olá Maria',
              'superseded_levels': [1],
            }
          ],
          'sent': 0,
          'failed': 0,
          'skipped': 0,
        };
      }
      return {
        'as_of': '2026-10-27',
        'enabled': true,
        'reason': null,
        'steps': 2,
        'planned': <Map<String, dynamic>>[],
        'sent': 1,
        'failed': 0,
        'skipped': 0,
      };
    }
    return <String, dynamic>{};
  }

  @override
  Future<dynamic> put(String path, {dynamic data}) async {
    putBodies.add(Map<String, dynamic>.from(data as Map));
    return <String, dynamic>{};
  }
}

Future<_OpsApi> _pump(
  WidgetTester tester,
  Widget screen, {
  _OpsApi? api,
}) async {
  final fake = api ?? _OpsApi();
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
  testWidgets('debt control groups by student and opens a reference',
      (tester) async {
    final api = await _pump(tester, const DebtControlScreen());

    expect(find.text('Controlo de Dívidas'), findsOneWidget);
    expect(find.text('Total em dívida'), findsOneWidget);
    expect(find.text('Ana Silva'), findsOneWidget);

    await tester.tap(find.text('Ana Silva'));
    await tester.pumpAndSettle();
    expect(find.text('Gerar referência'), findsOneWidget);

    await tester.tap(find.text('Gerar referência'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gerar'));
    await tester.pumpAndSettle();

    expect(api.lastReferenceBody?['document_id'], 'doc-1');
    expect(api.lastReferenceBody?['amount'], 120000.0);
    expect(find.text('Referência do encarregado'), findsOneWidget);
    expect(find.text('987654321'), findsOneWidget);
    // The admin hands the reference over; only the family opens the payment.
    expect(find.text('Copiar mensagem'), findsOneWidget);
    expect(find.text('https://pay.example/ref-1'), findsNothing);
  });

  testWidgets(
      'a debt the dispatcher already referenced shows it, not a new one',
      (tester) async {
    final api = _OpsApi()
      ..debtsOverride = {
        ..._debts(),
        'rows': [
          {..._debtRow(), 'payment_reference': _reference()},
        ],
      };
    await _pump(tester, const DebtControlScreen(), api: api);

    await tester.tap(find.text('Ana Silva'));
    await tester.pumpAndSettle();
    expect(find.text('Referência enviada ao encarregado'), findsOneWidget);
    expect(find.text('Gerar referência'), findsNothing);

    await tester.tap(find.text('Ver referência'));
    await tester.pumpAndSettle();

    expect(api.lastReferenceBody, isNull);
    expect(find.text('Referência do encarregado'), findsOneWidget);
    expect(find.text('987654321'), findsOneWidget);
  });

  testWidgets('principia-pay shows the connection and refreshes a reference',
      (tester) async {
    final api = await _pump(tester, const PrincipiaPayScreen());

    expect(find.text('Escola ligada à principia-pay'), findsOneWidget);
    expect(find.textContaining('FT 2026/1'), findsOneWidget);
    expect(find.text('Activa'), findsOneWidget);

    expect(find.text('Copiar mensagem para o encarregado'), findsOneWidget);
    expect(find.text('Abrir pagamento'), findsNothing);

    await tester.tap(find.text('Consultar estado'));
    await tester.pumpAndSettle();
    expect(api.refreshCalls, 1);
  });

  testWidgets('a refused probe revokes the green tick on principia-pay',
      (tester) async {
    final api = _OpsApi()
      ..probeResult = {
        'status': 'error',
        'reachable': false,
        'checked_at': '2026-10-28T09:15:00Z',
        'latency_ms': 12,
        'probe_error': 'Chave rejeitada pelo rail.',
      };
    await _pump(tester, const PrincipiaPayScreen(), api: api);

    expect(find.text('Escola ligada à principia-pay'), findsOneWidget);

    await tester.tap(find.text('Testar ligação'));
    await tester.pumpAndSettle();

    expect(find.text('Sem ligação à principia-pay'), findsOneWidget);
    expect(
      find.textContaining('Falha: Chave rejeitada pelo rail.'),
      findsOneWidget,
    );
  });

  testWidgets('a healthy probe confirms the rail and its latency',
      (tester) async {
    await _pump(tester, const PrincipiaPayScreen());

    await tester.tap(find.text('Testar ligação'));
    await tester.pumpAndSettle();

    expect(find.text('Escola ligada à principia-pay'), findsOneWidget);
    expect(find.textContaining('Ligação confirmada'), findsOneWidget);
    expect(find.textContaining('42 ms'), findsOneWidget);
  });

  testWidgets('finance home shows the cross-engine KPIs', (tester) async {
    await _pump(tester, const FinanceHomeScreen());

    expect(find.text('Painel Financeiro'), findsOneWidget);
    expect(find.text('Outubro 2026 · dívidas por gerar'), findsOneWidget);
    expect(find.text('vence a 05/11/2026'), findsOneWidget);
    expect(find.text('Em dívida'), findsOneWidget);
    expect(find.text('Em atraso'), findsOneWidget);
    expect(find.text('Cobrado no período'), findsOneWidget);
    expect(find.text('Ações rápidas'), findsOneWidget);
    expect(find.text('Gerar dívidas do mês'), findsOneWidget);
  });

  testWidgets('finance home reports a generated month and its failures',
      (tester) async {
    final api = _OpsApi()
      ..dashboardOverride = {
        ..._dashboard(),
        'month': {
          'billing_month': '2026-10',
          'generated': true,
          'status': 'partial_failed',
          'students': 22,
          'failed': 2,
          'total': 5610000.0,
          'due_date': '2026-11-10',
          'auto_generate': true,
        },
      };
    await _pump(tester, const FinanceHomeScreen(), api: api);

    expect(find.text('Outubro 2026 · dívidas geradas'), findsOneWidget);
    expect(find.textContaining('22 alunos'), findsOneWidget);
    expect(find.text('2 falhadas — ver execução'), findsOneWidget);
    expect(find.text('geração automática ligada'), findsOneWidget);
    expect(find.text('Ver dívidas'), findsOneWidget);
    expect(find.text('Ver execução'), findsOneWidget);
  });

  testWidgets('finance home follows the month to the families and the payments',
      (tester) async {
    final api = _OpsApi()
      ..dashboardOverride = {
        ..._dashboard(),
        'month': {
          'billing_month': '2026-10',
          'generated': true,
          'status': 'completed',
          'students': 42,
          'failed': 0,
          'total': 5610000.0,
          'due_date': '2026-11-10',
          'auto_generate': false,
          'references': {
            'enabled': true,
            'documents': 42,
            'sent': 40,
            'waiting': 0,
            'failed': 2,
            'skipped': 0,
            'paid': 12,
          },
        },
      };
    await _pump(tester, const FinanceHomeScreen(), api: api);

    expect(find.text('Referências enviadas: 40 de 42'), findsOneWidget);
    expect(find.text('Pagas por referência: 12 de 40'), findsOneWidget);
    expect(
        find.text('2 por enviar — o sistema volta a tentar'), findsOneWidget);
  });

  testWidgets('finance home asks to connect the rail when families get none',
      (tester) async {
    final api = _OpsApi()
      ..dashboardOverride = {
        ..._dashboard(),
        'month': {
          'billing_month': '2026-10',
          'generated': true,
          'status': 'completed',
          'students': 42,
          'failed': 0,
          'total': 5610000.0,
          'due_date': '2026-11-10',
          'auto_generate': false,
          'references': {
            'enabled': false,
            'documents': 42,
            'sent': 0,
            'waiting': 42,
            'failed': 0,
            'skipped': 0,
            'paid': 0,
          },
        },
      };
    await _pump(tester, const FinanceHomeScreen(), api: api);

    expect(find.textContaining('ainda não recebem referência automática'),
        findsOneWidget);
    expect(find.textContaining('Referências enviadas'), findsNothing);
  });

  testWidgets('dunning previews today and sends only the latest rung',
      (tester) async {
    final api = await _pump(tester, const DunningScreen());

    expect(find.text('1 lembrete(s) sairiam hoje'), findsOneWidget);
    expect(find.textContaining('níveis anteriores saltados'), findsOneWidget);
    expect(api.dunningBodies.single['dry_run'], true);

    await tester.tap(find.text('Enviar agora'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enviar'));
    await tester.pumpAndSettle();

    expect(api.dunningBodies.any((body) => body['dry_run'] == false), isTrue);
    expect(find.textContaining('Enviados 1'), findsOneWidget);
  });

  testWidgets('fee policy preserves late-fee bands and the dunning ladder',
      (tester) async {
    final api = await _pump(tester, const FeePolicyScreen());

    final scrollable = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(find.text('Multas por atraso'), 300,
        scrollable: scrollable);
    expect(find.text('10% até ao fim do mês'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Lembretes de cobrança'), 300,
        scrollable: scrollable);
    await tester.scrollUntilVisible(find.text('Nível 2'), 300,
        scrollable: scrollable);
    expect(find.text('Nível 2'), findsOneWidget);

    final save = find.text('Guardar política');
    await tester.scrollUntilVisible(
      save,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(save);
    await tester.pumpAndSettle();

    final body = api.putBodies.single;
    expect(body['late_fee_enabled'], true);
    expect(body['late_fee_billing_item_id'], 'item-1');
    expect((body['late_fee_bands'] as List), hasLength(2));
    expect((body['late_fee_bands'] as List).first['percent'], 10.0);
    expect(body['dunning_enabled'], true);
    expect((body['dunning_schedule'] as List), hasLength(2));
    expect((body['dunning_schedule'] as List).last['offset_days'], 30);
  });
}
