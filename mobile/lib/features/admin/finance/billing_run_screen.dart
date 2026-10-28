import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/providers/currency_provider.dart';
import '../../../core/widgets/app_error_widget.dart';
import 'fee_automation_common.dart';

final _previewProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, month) async {
  final data = await ref.read(apiClientProvider).post(
    '/billing/runs/preview',
    data: {'billing_month': month},
  ) as Map;
  return Map<String, dynamic>.from(data);
});

final _runsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final data = await ref.read(apiClientProvider).get('/billing/runs') as List;
  return data.map((row) => Map<String, dynamic>.from(row as Map)).toList();
});

final _runDetailProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, runId) async {
  final data =
      await ref.read(apiClientProvider).get('/billing/runs/$runId') as Map;
  return Map<String, dynamic>.from(data);
});

class BillingRunScreen extends ConsumerStatefulWidget {
  const BillingRunScreen({super.key});

  @override
  ConsumerState<BillingRunScreen> createState() => _BillingRunScreenState();
}

class _BillingRunScreenState extends ConsumerState<BillingRunScreen> {
  String _month = billingMonthKey();
  bool _generating = false;
  bool _rebuilding = false;
  Map<String, dynamic>? _lastRun;

  @override
  Widget build(BuildContext context) {
    final preview = ref.watch(_previewProvider(_month));
    final runs = ref.watch(_runsProvider);
    final currency = ref.watch(currencyFormatProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gerar Dívidas'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(_previewProvider(_month));
              ref.invalidate(_runsProvider);
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(_previewProvider(_month));
          ref.invalidate(_runsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _MonthHeader(
              month: _month,
              onPick: _pickMonth,
            ),
            const SizedBox(height: 12),
            preview.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => AppErrorWidget(
                error: error,
                onRetry: () => ref.invalidate(_previewProvider(_month)),
              ),
              data: (data) => _PreviewContent(
                data: data,
                currency: currency,
                generating: _generating,
                rebuilding: _rebuilding,
                lastRun: _lastRun,
                onGenerate: () => _generate(data),
                onRebuild: _rebuild,
                onOpenRun: _showRunDetails,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Execuções recentes',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            runs.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => AppErrorWidget(
                error: error,
                onRetry: () => ref.invalidate(_runsProvider),
              ),
              data: (rows) {
                if (rows.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('Ainda não há execuções nesta escola.'),
                  );
                }
                return Column(
                  children: [
                    for (final run in rows)
                      _RunTile(
                        run: run,
                        currency: currency,
                        onTap: () => _showRunDetails(run['id'].toString()),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Future<void> _pickMonth() async {
    final value = await pickBillingMonth(context, initial: _month);
    if (value != null && value != _month) {
      setState(() {
        _month = value;
        _lastRun = null;
      });
    }
  }

  Future<void> _generate(Map<String, dynamic> preview) async {
    if (_generating) return;
    setState(() => _generating = true);
    try {
      final response = await ref.read(apiClientProvider).post(
        '/billing/runs',
        data: {'billing_month': _month},
      ) as Map;
      final run = Map<String, dynamic>.from(response['run'] as Map);
      setState(() => _lastRun = run);
      ref.invalidate(_previewProvider(_month));
      ref.invalidate(_runsProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          response['created'] == true
              ? 'Cobranças geradas para ${billingMonthLabel(_month)}.'
              : 'Este mês já tinha sido gerado; a execução existente foi mantida.',
        ),
      ));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(apiErrorMessage(error))));
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _rebuild() async {
    if (_rebuilding) return;
    setState(() => _rebuilding = true);
    try {
      final result = await ref.read(apiClientProvider).post(
        '/billing/rebuild-plans',
        data: {'billing_month': _month},
      ) as Map;
      ref.invalidate(_previewProvider(_month));
      ref.invalidate(_runsProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          'Planos actualizados: ${result['confirmed'] ?? 0} confirmados, '
          '${result['queued'] ?? 0} em fila, '
          '${result['unchanged'] ?? 0} sem alterações.',
        ),
      ));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Não foi possível reconstruir os planos: '
                  '${apiErrorMessage(error)}')),
        );
      }
    } finally {
      if (mounted) setState(() => _rebuilding = false);
    }
  }

  Future<void> _showRunDetails(String runId) => showDialog(
        context: context,
        useRootNavigator: false,
        builder: (_) => _RunDetailDialog(runId: runId),
      );
}

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({required this.month, required this.onPick});

  final String month;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.event_note_outlined),
        title: Text(
          billingMonthLabel(month),
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        subtitle: const Text('Mês das cobranças a gerar'),
        trailing: TextButton.icon(
          onPressed: onPick,
          icon: const Icon(Icons.calendar_month_outlined, size: 18),
          label: const Text('Alterar'),
        ),
      ),
    );
  }
}

class _PreviewContent extends StatelessWidget {
  const _PreviewContent({
    required this.data,
    required this.currency,
    required this.generating,
    required this.rebuilding,
    required this.lastRun,
    required this.onGenerate,
    required this.onRebuild,
    required this.onOpenRun,
  });

  final Map<String, dynamic> data;
  final NumberFormat currency;
  final bool generating;
  final bool rebuilding;
  final Map<String, dynamic>? lastRun;
  final VoidCallback onGenerate;
  final VoidCallback onRebuild;
  final ValueChanged<String> onOpenRun;

  @override
  Widget build(BuildContext context) {
    final totals = Map<String, dynamic>.from(
      data['totals'] as Map? ?? const {},
    );
    final blockers = (data['blockers'] as List? ?? const []).cast<Map>();
    final warnings = (data['warnings'] as List? ?? const []).cast<Object>();
    final unbilled = (data['unbilled'] as List? ?? const []).cast<Map>();
    final students = (data['students'] as List? ?? const []).cast<Map>();
    final existing = data['existing_run'] == null
        ? null
        : Map<String, dynamic>.from(data['existing_run'] as Map);
    final mode = data['mode']?.toString() ?? 'internal';
    final blocked = blockers.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          Chip(
            avatar: Icon(
              mode == 'internal'
                  ? Icons.receipt_long_outlined
                  : Icons.cloud_done_outlined,
              size: 16,
            ),
            label: Text(_modeLabel(mode)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Vencimento ${formatIsoDate(data['due_date']?.toString())}',
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ]),
        const SizedBox(height: 8),
        for (final blocker in blockers)
          _AlertCard(
            icon: Icons.error_outline,
            color: Theme.of(context).colorScheme.error,
            title: 'Corrija antes de gerar',
            message: blocker['message']?.toString() ?? '',
          ),
        if (existing != null)
          _AlertCard(
            icon: Icons.info_outline,
            color: Theme.of(context).colorScheme.primary,
            title: 'Já existe uma execução para este mês',
            message: '${_runStatusLabel(existing['status']?.toString())} · '
                '${billingMonthLabel(existing['billing_month']?.toString() ?? '')}. '
                'Gerar novamente mantém a execução existente.',
            action: TextButton(
              onPressed: () => onOpenRun(existing['id'].toString()),
              child: const Text('Ver execução'),
            ),
          ),
        const SizedBox(height: 4),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              _totalRow(context, 'Alunos', '${totals['students'] ?? 0}'),
              _totalRow(
                  context, 'Linhas de cobrança', '${totals['lines'] ?? 0}'),
              const Divider(height: 20),
              _totalRow(
                context,
                'Subtotal',
                currency.format((totals['subtotal'] as num?)?.toDouble() ?? 0),
              ),
              _totalRow(
                context,
                'Descontos',
                '- ${currency.format(
                  (totals['discount_total'] as num?)?.toDouble() ?? 0,
                )}',
              ),
              _totalRow(
                context,
                'IVA',
                currency.format((totals['iva_total'] as num?)?.toDouble() ?? 0),
              ),
              const Divider(height: 20),
              _totalRow(
                context,
                'Total a cobrar',
                currency.format((totals['total'] as num?)?.toDouble() ?? 0),
                bold: true,
              ),
              if ((totals['families_with_discount'] as num? ?? 0) > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '${totals['families_with_discount']} família(s) com desconto de irmãos.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ]),
          ),
        ),
        if (students.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'Detalhe por aluno',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          for (final raw in students)
            _StudentCard(
              student: Map<String, dynamic>.from(raw),
              currency: currency,
            ),
        ],
        for (final warning in warnings)
          _AlertCard(
            icon: Icons.warning_amber_outlined,
            color: Colors.orange,
            title: 'Atenção',
            message: warning.toString(),
          ),
        for (final raw in unbilled)
          _AlertCard(
            icon: Icons.person_off_outlined,
            color: Colors.orange,
            title: '${raw['child_name'] ?? 'Aluno'} não será cobrado',
            message: _unbilledReason(raw['reason']?.toString()),
          ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: blocked || generating ? null : onGenerate,
          icon: generating
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.bolt_outlined),
          label: Text(generating ? 'A gerar…' : 'Gerar dívidas do mês'),
        ),
        if (mode != 'internal') ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: rebuilding ? null : onRebuild,
            icon: rebuilding
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync_outlined),
            label: const Text('Reconstruir planos dos alunos'),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Actualiza os planos no Finreg depois de mudar propinas, '
              'modalidades, transporte ou descontos.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
        if (lastRun != null) ...[
          const SizedBox(height: 16),
          _RunResultCard(run: lastRun!, currency: currency),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => context.push('/admin/finance/debt-control'),
              icon: const Icon(Icons.receipt_long_outlined, size: 18),
              label: const Text('Ver dívidas geradas'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _totalRow(
    BuildContext context,
    String label,
    String value, {
    bool bold = false,
  }) {
    final style = bold
        ? Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(fontWeight: FontWeight.w700)
        : Theme.of(context).textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        Expanded(child: Text(label, style: style)),
        Text(value, style: style),
      ]),
    );
  }
}

class _StudentCard extends StatelessWidget {
  const _StudentCard({required this.student, required this.currency});

  final Map<String, dynamic> student;
  final NumberFormat currency;

  @override
  Widget build(BuildContext context) {
    final lines = (student['lines'] as List? ?? const []).cast<Map>();
    final familySize = (student['family_size'] as num?)?.toInt() ?? 1;
    final siblingIndex = (student['sibling_index'] as num?)?.toInt() ?? 1;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        title: Text(
          student['child_name']?.toString() ?? 'Aluno',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          [
            student['guardian_name']?.toString() ?? 'Sem encarregado',
            if (familySize > 1)
              'Família de $familySize · filho n.º $siblingIndex',
          ].join(' · '),
        ),
        trailing: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              currency.format((student['total'] as num?)?.toDouble() ?? 0),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            if (student['sibling_discount_applied'] == true)
              const Text('desconto irmãos', style: TextStyle(fontSize: 11)),
          ],
        ),
        children: [
          for (final raw in lines)
            _LineRow(line: Map<String, dynamic>.from(raw), currency: currency),
          if ((student['warnings'] as List? ?? const []).isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Text(
                (student['warnings'] as List).join(' · '),
                style: const TextStyle(fontSize: 12, color: Colors.orange),
              ),
            ),
        ],
      ),
    );
  }
}

class _LineRow extends StatelessWidget {
  const _LineRow({required this.line, required this.currency});

  final Map<String, dynamic> line;
  final NumberFormat currency;

  @override
  Widget build(BuildContext context) {
    final discount = (line['discount_amount'] as num?)?.toDouble() ?? 0;
    final factor = (line['proration_factor'] as num?)?.toDouble();
    final taxRate = (line['tax_rate'] as num?)?.toDouble() ?? 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                line['service_label']?.toString() ??
                    line['description']?.toString() ??
                    'Serviço',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(
                [
                  line['description']?.toString() ?? '',
                  if (factor != null && factor < 1)
                    'proporcional ${(factor * 100).round()}%',
                  if (discount > 0)
                    'desconto ${moneyText(line['discount_pct'])}%',
                  if (taxRate > 0) 'IVA ${moneyText(taxRate)}%',
                ].where((part) => part.isNotEmpty).join(' · '),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ]),
          ),
          const SizedBox(width: 8),
          Text(currency.format((line['line_total'] as num?)?.toDouble() ?? 0)),
        ],
      ),
    );
  }
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: color.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(message),
                if (action != null) action!,
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

class _RunResultCard extends StatelessWidget {
  const _RunResultCard({required this.run, required this.currency});

  final Map<String, dynamic> run;
  final NumberFormat currency;

  @override
  Widget build(BuildContext context) {
    final stats = Map<String, dynamic>.from(run['stats'] as Map? ?? const {});
    final instructions = (run['instructions'] as List? ?? const []).cast<Map>();
    final documents = (run['documents'] as List? ?? const []).cast<Map>();
    final failures = (stats['failures'] as List? ?? const []).cast<Map>();
    final total = (stats['totals'] as Map?)?['total'];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(
                'Resultado · ${billingMonthLabel(run['billing_month']?.toString() ?? '')}',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            Chip(label: Text(_runStatusLabel(run['status']?.toString()))),
          ]),
          const SizedBox(height: 6),
          Text(
            '${stats['generated'] ?? 0} geradas · '
            '${stats['queued'] ?? 0} em fila · '
            '${stats['failed'] ?? 0} falhadas'
            '${total == null ? '' : ' · ${currency.format((total as num).toDouble())}'}',
          ),
          for (final raw in failures)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '${raw['child_name'] ?? 'Aluno'}: ${raw['message'] ?? raw['code']}',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          for (final raw in instructions)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                raw['status'] == 'confirmed'
                    ? Icons.check_circle_outline
                    : raw['status'] == 'failed'
                        ? Icons.error_outline
                        : Icons.schedule_outlined,
                size: 20,
              ),
              title: Text(raw['child_name']?.toString() ?? 'Aluno'),
              subtitle: Text(
                raw['error_detail']?.toString() ??
                    _instructionStatus(raw['status']?.toString()),
              ),
            ),
          for (final raw in documents)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.description_outlined, size: 20),
              title: Text(raw['full_document_number']?.toString() ?? 'Factura'),
              subtitle: Text(raw['customer_name']?.toString() ?? ''),
              trailing: Text(currency.format(
                (raw['gross_total'] as num?)?.toDouble() ?? 0,
              )),
            ),
        ]),
      ),
    );
  }
}

class _RunTile extends StatelessWidget {
  const _RunTile({
    required this.run,
    required this.currency,
    required this.onTap,
  });

  final Map<String, dynamic> run;
  final NumberFormat currency;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final stats = Map<String, dynamic>.from(run['stats'] as Map? ?? const {});
    final total = (stats['totals'] as Map?)?['total'];
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: onTap,
        title: Text(
          billingMonthLabel(run['billing_month']?.toString() ?? ''),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${_runStatusLabel(run['status']?.toString())} · '
          '${stats['generated'] ?? 0} geradas · '
          '${stats['failed'] ?? 0} falhadas'
          '${total == null ? '' : ' · ${currency.format((total as num).toDouble())}'}',
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

class _RunDetailDialog extends ConsumerWidget {
  const _RunDetailDialog({required this.runId});

  final String runId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(_runDetailProvider(runId));
    return AlertDialog(
      title: const Text('Execução de cobrança'),
      content: SizedBox(
        width: 560,
        child: detail.when(
          loading: () => const SizedBox(
            height: 180,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => AppErrorWidget(
            error: error,
            onRetry: () => ref.invalidate(_runDetailProvider(runId)),
          ),
          data: (run) => SingleChildScrollView(
            child: _RunResultCard(
              run: run,
              currency: NumberFormat.currency(locale: 'pt_AO', symbol: 'Kz'),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Fechar'),
        ),
      ],
    );
  }
}

String _runStatusLabel(String? status) => switch (status) {
      'preview' => 'Pré-visualização',
      'composing' => 'A preparar',
      'running' => 'Em curso',
      'completed' => 'Concluída',
      'partial_failed' => 'Parcialmente falhada',
      'failed' => 'Falhada',
      _ => status ?? '—',
    };

String _instructionStatus(String? status) => switch (status) {
      'confirmed' => 'Confirmada no Finreg',
      'pending' => 'Em fila para o Finreg',
      'failed' => 'Falhou',
      _ => status ?? '—',
    };

String _modeLabel(String mode) => switch (mode) {
      'fake' => 'Finreg em simulação',
      'shadow' => 'Finreg em sombra (rascunhos)',
      'pilot' => 'Finreg em piloto',
      'live' => 'Finreg em produção fiscal',
      _ => 'Facturação interna',
    };

String _unbilledReason(String? reason) => switch (reason) {
      'missing_guardian' => 'Sem encarregado de facturação ligado.',
      'plan_paused' => 'Plano de cobrança pausado.',
      'plan_withdrawn' => 'Plano de cobrança encerrado.',
      _ => reason ?? 'Sem condições de cobrança.',
    };
