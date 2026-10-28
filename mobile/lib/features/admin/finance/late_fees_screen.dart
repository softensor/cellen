import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/providers/currency_provider.dart';
import '../../../core/widgets/app_error_widget.dart';
import 'fee_automation_common.dart';

final _assessPreviewProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final data = await ref.read(apiClientProvider).post(
    '/billing/late-fees/assess',
    data: {'dry_run': true},
  ) as Map;
  return Map<String, dynamic>.from(data);
});

final _assessmentsProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final data =
      await ref.read(apiClientProvider).get('/billing/late-fees') as Map;
  return Map<String, dynamic>.from(data);
});

/// Multas por atraso: the bands the school defined in the fee policy,
/// what they would charge today, and one action to issue them.
///
/// The preview is the same endpoint the assessment itself uses, in dry-run
/// form, so what the director reads is exactly what will be issued.
class LateFeesScreen extends ConsumerStatefulWidget {
  const LateFeesScreen({super.key});

  @override
  ConsumerState<LateFeesScreen> createState() => _LateFeesScreenState();
}

class _LateFeesScreenState extends ConsumerState<LateFeesScreen> {
  bool _generating = false;

  Future<void> _generate() async {
    if (_generating) return;
    setState(() => _generating = true);
    try {
      final result = await ref.read(apiClientProvider).post(
        '/billing/late-fees/assess',
        data: {'dry_run': false},
      ) as Map;
      final created = (result['created'] as List?)?.length ?? 0;
      final skipped = (result['skipped'] as List?)?.length ?? 0;
      ref.invalidate(_assessPreviewProvider);
      ref.invalidate(_assessmentsProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Emitidas $created, saltadas $skipped.'),
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

  void _openFeePolicy() => context.push('/admin/finance/fee-policy');

  @override
  Widget build(BuildContext context) {
    final preview = ref.watch(_assessPreviewProvider);
    final assessments = ref.watch(_assessmentsProvider);
    final currency = ref.watch(currencyFormatProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Multas por Atraso'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(_assessPreviewProvider);
              ref.invalidate(_assessmentsProvider);
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(_assessPreviewProvider);
          ref.invalidate(_assessmentsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            preview.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => AppErrorWidget(
                error: error,
                onRetry: () => ref.invalidate(_assessPreviewProvider),
              ),
              data: (data) => _PreviewContent(
                data: data,
                currency: currency,
                generating: _generating,
                onGenerate: _generate,
                onOpenFeePolicy: _openFeePolicy,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Multas emitidas',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            assessments.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => AppErrorWidget(
                error: error,
                onRetry: () => ref.invalidate(_assessmentsProvider),
              ),
              data: (data) {
                final rows = ((data['rows'] as List?) ?? const [])
                    .whereType<Map>()
                    .map((row) => Map<String, dynamic>.from(row))
                    .toList();
                if (rows.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('Sem multas emitidas.'),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${data['count'] ?? rows.length} multa(s) · '
                      '${currency.format((data['total'] as num?)?.toDouble() ?? 0)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 8),
                    for (final row in rows)
                      _AssessmentTile(row: row, currency: currency),
                  ],
                );
              },
            ),
          ],
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
    required this.onGenerate,
    required this.onOpenFeePolicy,
  });

  final Map<String, dynamic> data;
  final NumberFormat currency;
  final bool generating;
  final VoidCallback onGenerate;
  final VoidCallback onOpenFeePolicy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (data['enabled'] != true) {
      return _Notice(
        icon: Icons.tune_outlined,
        message: 'Multas desativadas.',
        detail: 'Ative as multas na política de propinas para as usar.',
        actionLabel: 'Abrir política de propinas',
        onAction: onOpenFeePolicy,
      );
    }
    final bands = ((data['bands'] as List?) ?? const [])
        .whereType<Map>()
        .map((band) => Map<String, dynamic>.from(band))
        .toList();
    if (bands.isEmpty) {
      return _Notice(
        icon: Icons.tune_outlined,
        message: 'Sem escalões de multa definidos na política.',
        detail: 'Defina os escalões na política de propinas.',
        actionLabel: 'Abrir política de propinas',
        onAction: onOpenFeePolicy,
      );
    }
    final created = ((data['created'] as List?) ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
    final skipped = (data['skipped'] as List?)?.length ?? 0;
    final totalFee =
        ((data['totals'] as Map?)?['fee_total'] as num?)?.toDouble() ?? 0;
    final shadow = data['mode'] == 'shadow';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Escalões da política',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final band in bands)
                      Chip(
                        label: Text(
                            '${band['label'] ?? 'Escalão'} · ${(band['percent'] as num?)?.toStringAsFixed(0) ?? 0}%'),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (shadow)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text(
              'Modo de ensaio: as multas são calculadas mas não emitidas.',
              style: TextStyle(fontStyle: FontStyle.italic),
            ),
          ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.gavel_outlined,
                        color: theme.colorScheme.primary, size: 22),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        created.isEmpty
                            ? 'Nenhuma multa a emitir hoje.'
                            : '${created.length} multa(s) a emitir · '
                                '${currency.format(totalFee)}',
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                if (skipped > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    '$skipped documento(s) sem aumento de multa.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
                if (created.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  for (final row in created)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  row['document_number']?.toString() ??
                                      'Documento',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13),
                                ),
                                Text(
                                  '${row['student_name'] ?? ''} · '
                                  '${((row['band'] as Map?)?['label']) ?? ''}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                      color:
                                          theme.colorScheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            currency.format(
                                (row['fee_amount'] as num?)?.toDouble() ?? 0),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 8),
                  if (!shadow)
                    FilledButton.icon(
                      onPressed: generating ? null : onGenerate,
                      icon: generating
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.play_arrow),
                      label: const Text('Gerar multas do mês'),
                    ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.message,
    required this.detail,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String message;
  final String detail;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(message,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(detail,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.chevron_right),
              label: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class _AssessmentTile extends StatelessWidget {
  const _AssessmentTile({required this.row, required this.currency});

  final Map<String, dynamic> row;
  final NumberFormat currency;

  @override
  Widget build(BuildContext context) {
    final status = row['status']?.toString() ?? '';
    final (label, color) = switch (status) {
      'issued' => ('Emitida', Colors.green),
      'pending' => ('Em fila', Colors.orange),
      'failed' => ('Falhou', Colors.red),
      _ => (status, Colors.grey),
    };
    return Card(
      child: ListTile(
        leading: const Icon(Icons.gavel_outlined),
        title: Text(row['document_number']?.toString() ?? 'Documento'),
        subtitle: Text(
          '${(row['band_percent'] as num?)?.toStringAsFixed(0) ?? 0}% · '
          '${formatIsoDate(row['assessed_on']?.toString())}',
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              currency.format((row['fee_amount'] as num?)?.toDouble() ?? 0),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            Text(label, style: TextStyle(fontSize: 11, color: color)),
          ],
        ),
      ),
    );
  }
}
