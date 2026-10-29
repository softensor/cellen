import 'package:cellen/core/api/api_client.dart';
import 'package:cellen/features/parent/dashboard/parent_dashboard_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

/// The owner's report: a month was billed in FinReg and the parent home said
/// there was nothing to pay. The home must merge the local and FinReg
/// documents and show the family's open month.
class _DashboardApi extends ApiClient {
  _DashboardApi({this.documents = const []})
      : super(const FlutterSecureStorage());

  final List<Map<String, dynamic>> documents;

  @override
  Future<dynamic> get(String path,
      {Map<String, dynamic>? queryParameters, Duration? receiveTimeout}) async {
    switch (path) {
      case '/finance/parent/payment-mode':
        return {'mode': 'finreg', 'finreg_active': true};
      case '/finance/parent/invoices':
        return <dynamic>[];
      case '/finreg/parent/documents':
        return documents;
      default:
        return <dynamic>[];
    }
  }
}

Map<String, dynamic> _document({
  required String status,
  double balance = 120000.0,
}) =>
    {
      'id': 'instruction-1',
      'finreg': true,
      'document_id': 'finreg-doc-1',
      'child_id': 'child-1',
      'child_name': 'Ana Silva',
      'full_document_number': 'FT 2026/1',
      'reference_month': '2026-10-01',
      'gross_total': balance,
      'status': status,
      'due_date': '2026-10-05',
      'amount_paid': 0.0,
      'balance': balance,
      'payment_proofs': <Map<String, dynamic>>[],
    };

Future<dynamic> _overview(List<Map<String, dynamic>> documents) async {
  final container = ProviderContainer(overrides: [
    apiClientProvider.overrideWithValue(_DashboardApi(documents: documents)),
  ]);
  addTearDown(container.dispose);
  final subscription =
      container.listen(parentOutstandingInvoicesProvider, (_, __) {});
  addTearDown(subscription.close);
  return container.read(parentOutstandingInvoicesProvider.future);
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('pt_PT', null);
  });

  test('a billed month appears on the parent home with its balance', () async {
    final overview = await _overview([_document(status: 'overdue')]);

    expect(overview.isFinreg, isTrue);
    expect(overview.items, hasLength(1));
    final item = overview.items.single;
    expect(item.description, contains('Ana Silva'));
    expect(item.description.toLowerCase(), contains('outubro 2026'));
    expect(item.amount, 120000.0);
    expect(item.status, 'overdue');
  });

  test('a document still processing is shown nowhere as payable', () async {
    final overview = await _overview([_document(status: 'processing')]);
    expect(overview.items, isEmpty);
  });

  test('a paid document is history, not a payable item', () async {
    final overview = await _overview([_document(status: 'paid', balance: 0.0)]);
    expect(overview.items, isEmpty);
  });
}
