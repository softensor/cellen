import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_client.dart';
import '../../../core/providers/currency_provider.dart';
import '../../../core/widgets/app_error_widget.dart';
import 'fee_automation_common.dart';

final _deliveriesProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, status) async {
  final data = await ref.read(apiClientProvider).get(
    '/billing/dunning/deliveries',
    queryParameters: {if (status.isNotEmpty) 'status_filter': status},
  ) as List;
  return data.map((row) => Map<String, dynamic>.from(row as Map)).toList();
});

const _deliveryStatusLabels = <String, String>{
  'sent': 'Enviado',
  'failed': 'Falhou',
  'skipped': 'Saltado',
};

/// The collection ladder the school configured in the fee policy. The daily
/// Luanda-midnight job sends the latest due rung; this screen previews what
/// would go out today and shows exactly what was delivered on each channel.
class DunningScreen extends ConsumerStatefulWidget {
  const DunningScreen({super.key});

  @override
  ConsumerState<DunningScreen> createState() => _DunningScreenState();
}

class _DunningScreenState extends ConsumerState<DunningScreen> {
  String _status = '';
  bool _loadingPreview = false;
  bool _sending = false;
  Map<String, dynamic>? _preview;
  String? _previewError;

  @override
  void initState() {
    super.initState();
    _loadPreview();
  }

  Future<void> _loadPreview() async {
    setState(() {
      _loadingPreview = true;
      _previewError = null;
    });
    try {
      final data = await ref.read(apiClientProvider).post(
        '/billing/dunning/run',
        data: {'dry_run': true},
      ) as Map;
      if (!mounted) return;
      setState(() => _preview = Map<String, dynamic>.from(data));
    } catch (error) {
      if (!mounted) return;
      setState(() => _previewError = error.toString());
    } finally {
      if (mounted) setState(() => _loadingPreview = false);
    }
  }

  Future<void> _sendNow() async {
    final planned = (_preview?['planned'] as List?) ?? const [];
    if (planned.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enviar lembretes agora?'),
        content: Text(
          'Serão enviados ${planned.length} lembrete(s), um por dívida, '
          'no nível mais recente da política. O envio diário automático '
          'não volta a enviar os mesmos.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Enviar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _sending = true);
    try {
      final result = await ref.read(apiClientProvider).post(
        '/billing/dunning/run',
        data: {'dry_run': false},
      ) as Map;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Enviados ${result['sent'] ?? 0}, falharam '
            '${result['failed'] ?? 0}, saltados ${result['skipped'] ?? 0}.',
          ),
        ),
      );
      ref.invalidate(_deliveriesProvider(_status));
      await _loadPreview();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Envio falhou: $error')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final deliveries = ref.watch(_deliveriesProvider(_status));
    final currency = ref.watch(currencyFormatProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lembretes de Cobrança'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _loadPreview();
              ref.invalidate(_deliveriesProvider(_status));
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _loadPreview();
          ref.invalidate(_deliveriesProvider(_status));
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.schedule),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'O envio corre todos os dias à meia-noite de Luanda.',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_loadingPreview)
                      const LinearProgressIndicator()
                    else if (_previewError != null)
                      Text(
                        'Pré-visualização indisponível: $_previewError',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error),
                      )
                    else if (_preview != null)
                      _PreviewSummary(
                        preview: _preview!,
                        currency: currency,
                        sending: _sending,
                        onSend: _sendNow,
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Entregas registadas',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final entry in const {
                    '': 'Todas',
                    'sent': 'Enviadas',
                    'failed': 'Falhadas',
                    'skipped': 'Saltadas',
                  }.entries)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(entry.value),
                        selected: _status == entry.key,
                        onSelected: (_) => setState(() => _status = entry.key),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            deliveries.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => AppErrorWidget(
                error: error,
                onRetry: () => ref.invalidate(_deliveriesProvider(_status)),
              ),
              data: (rows) {
                if (rows.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(child: Text('Ainda não há entregas.')),
                  );
                }
                return Column(
                  children: [for (final row in rows) _DeliveryCard(row: row)],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewSummary extends StatelessWidget {
  const _PreviewSummary({
    required this.preview,
    required this.currency,
    required this.sending,
    required this.onSend,
  });

  final Map<String, dynamic> preview;
  final NumberFormat currency;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = preview['enabled'] == true;
    final reason = preview['reason']?.toString();
    final planned = ((preview['planned'] as List?) ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
    if (!enabled) {
      return Text(
        switch (reason) {
          'disabled' =>
            'Os lembretes estão desligados na política de propinas.',
          'no_schedule' =>
            'A política não tem níveis de lembrete configurados.',
          'no_school_year' => 'A escola ainda não tem ano lectivo definido.',
          _ => 'Sem lembretes a enviar hoje.',
        },
        style: theme.textTheme.bodySmall,
      );
    }
    if (planned.isEmpty) {
      return Text(
        'Nada a enviar hoje: nenhuma dívida atingiu um novo nível.',
        style: theme.textTheme.bodySmall,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${planned.length} lembrete(s) sairiam hoje',
          style:
              theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        for (final row in planned.take(20))
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${row['student_name'] ?? row['guardian_name'] ?? 'Aluno'}'
                        ' · nível ${row['level']} (${row['offset_days']} dias)',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        '${row['document_number'] ?? ''} · '
                        '${(row['channels'] as List?)?.join(', ') ?? ''}'
                        '${(row['superseded_levels'] as List?)?.isNotEmpty == true ? ' · níveis anteriores saltados' : ''}',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Text(
                  currency
                      .format((row['outstanding'] as num?)?.toDouble() ?? 0),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        if (planned.length > 20)
          Text('… e mais ${planned.length - 20}.',
              style: theme.textTheme.bodySmall),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: sending ? null : onSend,
            icon: const Icon(Icons.send, size: 18),
            label: Text(sending ? 'A enviar…' : 'Enviar agora'),
          ),
        ),
      ],
    );
  }
}

class _DeliveryCard extends StatelessWidget {
  const _DeliveryCard({required this.row});

  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = row['status']?.toString() ?? '';
    final sentAt = row['sent_at']?.toString();
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          switch (status) {
            'sent' => Icons.mark_email_read_outlined,
            'failed' => Icons.error_outline,
            _ => Icons.remove_circle_outline,
          },
          color: status == 'sent'
              ? Colors.green
              : status == 'failed'
                  ? theme.colorScheme.error
                  : theme.colorScheme.onSurfaceVariant,
        ),
        title: Text(
          '${row['document_number'] ?? 'Documento'} · nível ${row['level']}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${row['channel'] ?? ''} · ${_deliveryStatusLabels[status] ?? status}'
          '${row['error'] != null ? ' (${row['error']})' : ''}'
          '${sentAt != null ? ' · ${formatIsoDate(sentAt)}' : ''}',
        ),
      ),
    );
  }
}
