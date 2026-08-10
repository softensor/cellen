import 'package:cellen/core/api/api_client.dart';
import 'package:flutter/material.dart';

class FinregAccountingOverviewScreen extends StatefulWidget {
  const FinregAccountingOverviewScreen({super.key, required this.api});

  final ApiClient api;

  @override
  State<FinregAccountingOverviewScreen> createState() =>
      _FinregAccountingOverviewScreenState();
}

class _FinregAccountingOverviewScreenState
    extends State<FinregAccountingOverviewScreen> {
  late Future<Map<String, dynamic>> _value;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _value = widget.api
        .get('/finreg/accounting/overview')
        .then((value) => Map<String, dynamic>.from(value as Map));
  }

  void _refresh() => setState(_load);

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
        future: _value,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _ModuleError(message: snapshot.error.toString(), retry: _refresh);
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final value = snapshot.data!;
          final entries = List<Map<String, dynamic>>.from(
              (value['latest_entries'] as List? ?? const [])
                  .map((item) => Map<String, dynamic>.from(item as Map)));
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              _ModuleHeader(
                title: 'Contabilidade Finreg',
                subtitle:
                    'Lançamentos automáticos da faturação escolar e controlo do razão.',
                icon: Icons.account_balance_outlined,
                refresh: _refresh,
              ),
              const SizedBox(height: 16),
              Wrap(spacing: 12, runSpacing: 12, children: [
                _Metric(label: 'Contas ativas', value: '${value['active_accounts'] ?? 0}'),
                _Metric(label: 'Lançamentos', value: '${value['journal_entries'] ?? 0}'),
                _Metric(label: 'Débitos', value: '${value['total_debit'] ?? '0'} AOA'),
                _Metric(label: 'Créditos', value: '${value['total_credit'] ?? '0'} AOA'),
                _Metric(
                    label: 'Razão',
                    value: value['balanced'] == true ? 'Equilibrado' : 'Requer atenção'),
              ]),
              const SizedBox(height: 24),
              Text('Últimos lançamentos',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (entries.isEmpty)
                const Card(
                    child: ListTile(
                        title: Text('Ainda não existem lançamentos contabilísticos.')))
              else
                ...entries.map((entry) => Card(
                      child: ListTile(
                        leading: const Icon(Icons.menu_book_outlined),
                        title: Text(
                            '${entry['journal_code']} · ${entry['entry_number']}'),
                        subtitle: Text(
                            '${entry['entry_date']} · ${entry['description'] ?? 'Sem descrição'}'),
                        trailing: Text(entry['status'] == 'posted'
                            ? 'Lançado'
                            : 'Estornado'),
                      ),
                    )),
            ],
          );
        },
      );
}

class FinregCashSessionsScreen extends StatefulWidget {
  const FinregCashSessionsScreen({super.key, required this.api});

  final ApiClient api;

  @override
  State<FinregCashSessionsScreen> createState() =>
      _FinregCashSessionsScreenState();
}

class _FinregCashSessionsScreenState extends State<FinregCashSessionsScreen> {
  late Future<Map<String, dynamic>> _value;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _value = widget.api
        .get('/finreg/cash-sessions')
        .then((value) => Map<String, dynamic>.from(value as Map));
  }

  void _refresh() => setState(_load);

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
        future: _value,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _ModuleError(message: snapshot.error.toString(), retry: _refresh);
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final value = snapshot.data!;
          final sessions = List<Map<String, dynamic>>.from(
              (value['sessions'] as List? ?? const [])
                  .map((item) => Map<String, dynamic>.from(item as Map)));
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              _ModuleHeader(
                title: 'Sessões de caixa Finreg',
                subtitle:
                    'Acompanhamento de abertura, fecho e diferenças de caixa.',
                icon: Icons.point_of_sale_outlined,
                refresh: _refresh,
              ),
              const SizedBox(height: 16),
              Wrap(spacing: 12, runSpacing: 12, children: [
                _Metric(label: 'Caixas abertos', value: '${value['open_count'] ?? 0}'),
                _Metric(
                    label: 'Revisões pendentes',
                    value: '${value['review_count'] ?? 0}'),
              ]),
              const SizedBox(height: 24),
              if (sessions.isEmpty)
                const Card(
                    child: ListTile(
                        title: Text('Ainda não existem sessões de caixa.'),
                        subtitle: Text(
                            'A capacidade está ativa e esta área mostrará as sessões criadas no Finreg.')))
              else
                ...sessions.map((session) => Card(
                      child: ListTile(
                        leading: Icon(session['status'] == 'open'
                            ? Icons.lock_open_outlined
                            : Icons.lock_outline),
                        title: Text(session['status'] == 'open'
                            ? 'Caixa aberto'
                            : 'Caixa fechado'),
                        subtitle: Text(
                            'Abertura: ${session['opened_at']}\nDiferença: ${session['difference'] ?? '—'} AOA'),
                        isThreeLine: true,
                        trailing: session['needs_review'] == true &&
                                session['reviewed'] != true
                            ? const Chip(label: Text('Rever'))
                            : null,
                      ),
                    )),
            ],
          );
        },
      );
}

class _ModuleHeader extends StatelessWidget {
  const _ModuleHeader(
      {required this.title,
      required this.subtitle,
      required this.icon,
      required this.refresh});
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback refresh;

  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, size: 32, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          Text(subtitle),
        ])),
        IconButton(
            tooltip: 'Atualizar',
            onPressed: refresh,
            icon: const Icon(Icons.refresh)),
      ]);
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 190,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 6),
              Text(value, style: Theme.of(context).textTheme.titleMedium),
            ]),
          ),
        ),
      );
}

class _ModuleError extends StatelessWidget {
  const _ModuleError({required this.message, required this.retry});
  final String message;
  final VoidCallback retry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline, size: 36),
            const SizedBox(height: 12),
            Text('Não foi possível carregar o módulo.\n$message',
                textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: retry, child: const Text('Tentar novamente')),
          ]),
        ),
      );
}
