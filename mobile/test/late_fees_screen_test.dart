import 'package:cellen/core/api/api_client.dart';
import 'package:cellen/core/providers/currency_provider.dart';
import 'package:cellen/features/admin/finance/late_fees_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

Map<String, dynamic> _preview({
  bool enabled = true,
  List<Map<String, dynamic>>? bands,
  List<Map<String, dynamic>>? created,
}) =>
    {
      'mode': 'live',
      'as_of': '2026-10-28',
      'enabled': enabled,
      'reason': enabled ? null : 'late_fee_disabled',
      'base': 'outstanding',
      'preview_only': false,
      'bands': bands ??
          [
            {
              'id': 'band-1',
              'label': '10% até ao fim do mês',
              'anchor': 'due_month',
              'start_day': 10,
              'end_day': null,
              'percent': 10.0,
              'min_amount': null,
              'max_amount': null,
            }
          ],
      'created': created ??
          [
            {
              'document_id': 'doc-1',
              'document_number': 'FT 2026/1',
              'student_name': 'Ana Silva',
              'band': {'label': '10% até ao fim do mês', 'percent': 10.0},
              'incremental_percent': 10.0,
              'fee_amount': 2500.0,
              'base_amount': 25000.0,
              'outstanding_before': 25000.0,
            }
          ],
      'skipped': <Map<String, dynamic>>[],
      'totals': {'count': 1, 'fee_total': 2500.0},
    };

class _LateFeesApi extends ApiClient {
  _LateFeesApi({this.enabled = true, this.hasBands = true})
      : super(const FlutterSecureStorage());

  final bool enabled;
  final bool hasBands;
  final List<bool> dryRuns = [];

  @override
  Future<dynamic> get(String path,
      {Map<String, dynamic>? queryParameters, Duration? receiveTimeout}) async {
    if (path == '/billing/late-fees') {
      return {
        'count': 1,
        'total': 2500.0,
        'rows': [
          {
            'id': 'assessment-1',
            'source_kind': 'finreg_document',
            'source_id': 'doc-1',
            'document_number': 'FT 2026/1',
            'student_id': 'child-1',
            'guardian_id': 'guardian-1',
            'band_id': 'band-1',
            'band_percent': 10.0,
            'incremental_percent': 10.0,
            'base_amount': 25000.0,
            'fee_amount': 2500.0,
            'status': 'issued',
            'assessed_on': '2026-10-28',
          }
        ],
      };
    }
    return <dynamic>[];
  }

  @override
  Future<dynamic> post(String path,
      {dynamic data, Duration? receiveTimeout}) async {
    if (path == '/billing/late-fees/assess') {
      final dryRun = (data as Map)['dry_run'] == true;
      dryRuns.add(dryRun);
      if (dryRun) {
        return _preview(
          enabled: enabled,
          bands: hasBands ? null : <Map<String, dynamic>>[],
        );
      }
      return {
        'created': (_preview()['created'] as List),
        'skipped': <Map<String, dynamic>>[],
      };
    }
    return <String, dynamic>{};
  }
}

Future<_LateFeesApi> _pump(
  WidgetTester tester, {
  bool enabled = true,
  bool hasBands = true,
}) async {
  final api = _LateFeesApi(enabled: enabled, hasBands: hasBands);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(api),
      currencyFormatProvider.overrideWithValue(
        NumberFormat.currency(locale: 'pt_AO', symbol: 'Kz'),
      ),
    ],
    child: const MaterialApp(home: LateFeesScreen()),
  ));
  await tester.pumpAndSettle();
  return api;
}

void main() {
  testWidgets('late fees preview what they would charge, then issue it',
      (tester) async {
    final api = await _pump(tester);

    expect(find.text('Multas por Atraso'), findsOneWidget);
    expect(find.textContaining('10% até ao fim do mês'), findsWidgets);
    expect(find.textContaining('multa(s) a emitir'), findsOneWidget);
    expect(api.dryRuns, [true]);
    // The history of issued fees is under the preview.
    expect(find.text('Multas emitidas'), findsOneWidget);
    expect(find.text('Emitida'), findsOneWidget);

    await tester.tap(find.text('Gerar multas do mês'));
    await tester.pumpAndSettle();

    // One real assessment, then the screen re-reads the preview and history.
    expect(api.dryRuns.where((dryRun) => !dryRun), hasLength(1));
    expect(api.dryRuns.indexOf(false), 1);
    expect(find.text('Emitidas 1, saltadas 0.'), findsOneWidget);
  });

  testWidgets('a disabled policy explains itself and offers the way to enable',
      (tester) async {
    await _pump(tester, enabled: false);

    expect(find.text('Multas desativadas.'), findsOneWidget);
    expect(find.text('Abrir política de propinas'), findsOneWidget);
    expect(find.text('Gerar multas do mês'), findsNothing);
  });

  testWidgets('no bands sends the director to the policy, not to a dead end',
      (tester) async {
    await _pump(tester, hasBands: false);

    expect(find.text('Sem escalões de multa definidos na política.'),
        findsOneWidget);
    expect(find.text('Abrir política de propinas'), findsOneWidget);
    expect(find.text('Gerar multas do mês'), findsNothing);
  });
}
