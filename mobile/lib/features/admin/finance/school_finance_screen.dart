import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../employees/employees_list_screen.dart';
import '../guardians/guardians_list_screen.dart';
import 'finance_home_screen.dart';
import 'internal_payments_screen.dart';
import 'school_finance_hubs.dart';

/// The school's whole finance area, entirely inside Cellen.
///
/// Certified invoicing runs in the background: invoices, receipts, credit
/// notes and SAF-T are issued by the fiscal engine server to server, and
/// every screen here is Cellen's own. Nothing opens another product, and
/// nothing here depends on the fiscal engine being reachable to render.
///
/// The tabs follow the school year, not the database: the month's state and
/// totals first (Painel), then everything about debts, then where money comes
/// in (Pagamentos), the certified documents themselves, and last the jargon
/// (Configuração).
class SchoolFinanceScreen extends ConsumerStatefulWidget {
  const SchoolFinanceScreen({super.key});

  @override
  ConsumerState<SchoolFinanceScreen> createState() => _SchoolFinanceScreenState();
}

class _SchoolFinanceScreenState extends ConsumerState<SchoolFinanceScreen> {
  late Future<dynamic> _paymentMode;

  @override
  void initState() {
    super.initState();
    _paymentMode = ref.read(apiClientProvider).get('/finance/internal-payments/mode');
  }

  void _retry() => setState(() {
        _paymentMode =
            ref.read(apiClientProvider).get('/finance/internal-payments/mode');
      });

  @override
  Widget build(BuildContext context) {
    final portuguese = Localizations.localeOf(context).languageCode == 'pt';
    return FutureBuilder<dynamic>(
      future: _paymentMode,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(
                    portuguese
                        ? 'Não foi possível abrir a gestão de pagamentos.'
                        : 'Payment management could not be opened.',
                    textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _retry,
                  icon: const Icon(Icons.refresh),
                  label: Text(portuguese ? 'Tentar novamente' : 'Retry'),
                ),
              ]),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final value = Map<String, dynamic>.from(snapshot.data as Map);
        if (value['mode'] != 'finreg') {
          return const InternalPaymentsScreen();
        }
        return const _SchoolFinanceTabs();
      },
    );
  }
}

class _SchoolFinanceTabs extends StatelessWidget {
  const _SchoolFinanceTabs();

  @override
  Widget build(BuildContext context) {
    final portuguese = Localizations.localeOf(context).languageCode == 'pt';
    return DefaultTabController(
      length: 7,
      child: Column(
        children: [
          Material(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            child: TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                Tab(text: portuguese ? 'Painel' : 'Overview'),
                Tab(text: portuguese ? 'Dívidas e cobrança' : 'Debts & collection'),
                Tab(text: portuguese ? 'Pagamentos' : 'Payments'),
                Tab(text: portuguese ? 'Documentos fiscais' : 'Fiscal documents'),
                Tab(text: portuguese ? 'Configuração' : 'Settings'),
                Tab(text: portuguese ? 'Encarregados' : 'Guardians'),
                Tab(text: portuguese ? 'Funcionários' : 'Employees'),
              ],
            ),
          ),
          const Expanded(
            child: TabBarView(
              children: [
                FinanceHomeScreen(),
                DebtsHub(),
                PaymentsHub(),
                FiscalDocumentsHub(),
                FinanceConfigHub(),
                GuardiansListScreen(),
                EmployeesListScreen(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
