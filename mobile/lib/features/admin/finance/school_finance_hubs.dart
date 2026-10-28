import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';

/// The school-finance hubs: one section per workflow step, cards ordered the
/// way a school year runs (generate, then chase, then collect).
///
/// These are static card grids on purpose. They must keep working when the
/// fiscal engine is unreachable, so nothing here talks to the API.
class DebtsHub extends StatelessWidget {
  const DebtsHub({super.key});

  @override
  Widget build(BuildContext context) {
    final portuguese = Localizations.localeOf(context).languageCode == 'pt';
    final items = <_HubItem>[
      (
        icon: Icons.bolt_outlined,
        color: Colors.orange,
        pt: 'Gerar dívidas do mês',
        en: 'Generate this month charges',
        descriptionPt: 'Calcula propinas, modalidades, transporte e descontos.',
        descriptionEn:
            'Calculates tuition, activities, transport and discounts.',
        route: '/admin/finance/billing-run',
      ),
      (
        icon: Icons.warning_amber_outlined,
        color: Colors.red,
        pt: 'Controlo de dívidas',
        en: 'Debt control',
        descriptionPt: 'Quem deve, quanto e desde quando.',
        descriptionEn: 'Who owes what, and since when.',
        route: '/admin/finance/debt-control',
      ),
      (
        icon: Icons.gavel_outlined,
        color: Colors.deepOrange,
        pt: 'Multas por atraso',
        en: 'Late fees',
        descriptionPt:
            'Percentagens por atraso, calculadas e emitidas em massa.',
        descriptionEn: 'Overdue percentages, calculated and issued in bulk.',
        route: '/admin/finance/late-fees',
      ),
      (
        icon: Icons.calendar_month_outlined,
        color: Colors.teal,
        pt: 'Acordos de pagamento',
        en: 'Payment arrangements',
        descriptionPt: 'Planos de prestações para famílias com dívidas.',
        descriptionEn: 'Instalment plans for families with debts.',
        route: '/admin/finance/payment-plans',
      ),
      (
        icon: Icons.notifications_active_outlined,
        color: Colors.indigo,
        pt: 'Lembretes de cobrança',
        en: 'Collection reminders',
        descriptionPt: 'Avisos aos encarregados com valores em atraso.',
        descriptionEn: 'Notices to guardians with overdue amounts.',
        route: '/admin/finance/reminders',
      ),
      (
        icon: Icons.account_balance_wallet_outlined,
        color: Colors.green,
        pt: 'Créditos dos encarregados',
        en: 'Guardian credits',
        descriptionPt: 'Saldos a favor das famílias.',
        descriptionEn: 'Balances in the families’ favour.',
        route: '/admin/finance/credits',
      ),
    ];
    return _HubList(
      intro: portuguese
          ? 'Gerar, controlar e cobrar — tudo sobre dívidas num só lugar.'
          : 'Generate, control and collect — everything about debts in one place.',
      sections: [(title: null, items: items)],
    );
  }
}

class PaymentsHub extends StatelessWidget {
  const PaymentsHub({super.key});

  @override
  Widget build(BuildContext context) {
    final portuguese = Localizations.localeOf(context).languageCode == 'pt';
    final receive = <_HubItem>[
      (
        icon: Icons.qr_code_2_outlined,
        color: Colors.indigo,
        pt: 'Pagamentos por referência',
        en: 'Reference payments',
        descriptionPt:
            'Referências emitidas e o estado da ligação à principia-pay.',
        descriptionEn:
            'Issued references and the state of the principia-pay link.',
        route: '/admin/finance/principia-pay',
      ),
      (
        icon: Icons.point_of_sale_outlined,
        color: Colors.blue,
        pt: 'Referências Multicaixa',
        en: 'Multicaixa references',
        descriptionPt: 'Referências de Multicaixa registadas manualmente.',
        descriptionEn: 'Manually recorded Multicaixa references.',
        route: '/admin/finance/payment-references',
      ),
      (
        icon: Icons.receipt_long_outlined,
        color: Colors.purple,
        pt: 'Comprovativos de pagamento',
        en: 'Payment proofs',
        descriptionPt: 'Comprovativos enviados pelos encarregados.',
        descriptionEn: 'Proofs uploaded by guardians.',
        route: '/admin/finance/payment-proofs',
      ),
    ];
    final treasury = <_HubItem>[
      (
        icon: Icons.savings_outlined,
        color: Colors.green,
        pt: 'Fecho de caixa',
        en: 'Cash close',
        descriptionPt: 'Abertura, movimentos e fecho do caixa.',
        descriptionEn: 'Opening, movements and closing of the till.',
        route: '/admin/finance/cash-sessions',
      ),
      (
        icon: Icons.shopping_cart_outlined,
        color: Colors.brown,
        pt: 'Despesas',
        en: 'Expenses',
        descriptionPt: 'Despesas da escola por categoria.',
        descriptionEn: 'School expenses by category.',
        route: '/admin/finance/expenses',
      ),
      (
        icon: Icons.description_outlined,
        color: Colors.blueGrey,
        pt: 'Extrato de contas',
        en: 'Account statements',
        descriptionPt:
            'Movimentos de cada encarregado: facturas, pagamentos e saldo.',
        descriptionEn:
            'Each guardian’s movements: invoices, payments and balance.',
        route: '/admin/finance/statements',
      ),
    ];
    return _HubList(
      sections: [
        (title: portuguese ? 'Receber' : 'To receive', items: receive),
        (title: portuguese ? 'Tesouraria' : 'Treasury', items: treasury),
      ],
    );
  }
}

class FinanceConfigHub extends StatelessWidget {
  const FinanceConfigHub({super.key});

  @override
  Widget build(BuildContext context) {
    final portuguese = Localizations.localeOf(context).languageCode == 'pt';
    final values = <_HubItem>[
      (
        icon: Icons.tune_outlined,
        color: Colors.indigo,
        pt: 'Política de propinas',
        en: 'Fee policy',
        descriptionPt: 'Regras de propinas, descontos, multas e lembretes.',
        descriptionEn: 'Tuition rules, discounts, late fees and reminders.',
        route: '/admin/finance/fee-policy',
      ),
      (
        icon: Icons.sell_outlined,
        color: Colors.orange,
        pt: 'Serviços e mensalidades',
        en: 'Services and fees',
        descriptionPt: 'Catálogo de serviços, preços e IVA.',
        descriptionEn: 'Service catalogue, prices and VAT.',
        route: '/admin/finance/billing-items',
      ),
    ];
    final extras = <_HubItem>[
      (
        icon: Icons.sports_soccer_outlined,
        color: Colors.green,
        pt: 'Modalidades',
        en: 'Extracurricular activities',
        descriptionPt: 'Actividades extracurriculares e respectivos valores.',
        descriptionEn: 'Extracurricular activities and their fees.',
        route: '/admin/finance/modalities',
      ),
      (
        icon: Icons.directions_bus_outlined,
        color: Colors.amber.shade800,
        pt: 'Transporte escolar',
        en: 'School transport',
        descriptionPt: 'Rotas, paragens e valores do transporte.',
        descriptionEn: 'Routes, stops and transport fees.',
        route: '/admin/finance/transport',
      ),
      (
        icon: Icons.school_outlined,
        color: Colors.teal,
        pt: 'Planos dos alunos',
        en: 'Student plans',
        descriptionPt: 'Plano de cobrança de cada aluno.',
        descriptionEn: 'Each student’s billing plan.',
        route: '/admin/finance/contracts',
      ),
    ];
    final analysis = <_HubItem>[
      (
        icon: Icons.bar_chart_outlined,
        color: Colors.blue,
        pt: 'Relatório por serviço',
        en: 'Service report',
        descriptionPt: 'Quanto cada serviço facturou no período.',
        descriptionEn: 'How much each service billed in the period.',
        route: '/admin/finance/service-report',
      ),
    ];
    return _HubList(
      sections: [
        (title: portuguese ? 'Valores' : 'Amounts', items: values),
        (
          title: portuguese ? 'Extras dos alunos' : 'Student extras',
          items: extras
        ),
        (title: portuguese ? 'Análise' : 'Analysis', items: analysis),
      ],
    );
  }
}

typedef _HubItem = ({
  IconData icon,
  Color color,
  String pt,
  String en,
  String descriptionPt,
  String descriptionEn,
  String route,
});

typedef _HubSection = ({String? title, List<_HubItem> items});

class _HubList extends StatelessWidget {
  const _HubList({required this.sections, this.intro});

  final List<_HubSection> sections;
  final String? intro;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (intro != null) ...[
          Text(
            intro!,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 16),
        ],
        for (final section in sections) ...[
          if (section.title != null) ...[
            Text(
              section.title!,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
          ],
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 340,
              mainAxisExtent: 150,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: section.items.length,
            itemBuilder: (context, index) {
              final item = section.items[index];
              return _HubCard(item: item);
            },
          ),
          const SizedBox(height: 20),
        ],
      ],
    );
  }
}

class _HubCard extends StatelessWidget {
  const _HubCard({required this.item});

  final _HubItem item;

  @override
  Widget build(BuildContext context) {
    final portuguese = Localizations.localeOf(context).languageCode == 'pt';
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: item.color.withAlpha(60), width: 1.5),
      ),
      child: InkWell(
        onTap: () => context.push(item.route),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: item.color.withAlpha(25),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(item.icon, color: item.color, size: 24),
              ),
              const SizedBox(height: 10),
              Text(
                portuguese ? item.pt : item.en,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              // The card has a fixed height so every tile in a row matches;
              // the description takes whatever room the title leaves and
              // ellipsizes instead of pushing the column past its bounds.
              Expanded(
                child: Text(
                  portuguese ? item.descriptionPt : item.descriptionEn,
                  style: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 12),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
