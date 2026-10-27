import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/api/api_client.dart';
import '../../../core/providers/currency_provider.dart';
import '../../../core/widgets/app_error_widget.dart';
import 'fee_automation_common.dart';

final _connectionProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final data =
      await ref.read(apiClientProvider).get('/billing/principia-pay') as Map;
  return Map<String, dynamic>.from(data);
});

final _referencesProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, status) async {
  final data = await ref.read(apiClientProvider).get(
    '/billing/principia-pay/references',
    queryParameters: {if (status.isNotEmpty) 'status_filter': status},
  ) as List;
  return data.map((row) => Map<String, dynamic>.from(row as Map)).toList();
});

const _statusLabels = <String, String>{
  'creating': 'Em criação',
  'active': 'Activa',
  'paid': 'Paga',
  'cancelled': 'Cancelada',
  'expired': 'Expirada',
};

/// principia-pay reference payments. The rail carries no fiscal identity:
/// each reference points at an open debt and its settlement returns to the
/// engine that owns the school (FinReg when the school is FinReg-active).
class PrincipiaPayScreen extends ConsumerStatefulWidget {
  const PrincipiaPayScreen({super.key});

  @override
  ConsumerState<PrincipiaPayScreen> createState() => _PrincipiaPayScreenState();
}

class _PrincipiaPayScreenState extends ConsumerState<PrincipiaPayScreen> {
  String _status = '';
  bool _registering = false;

  Future<void> _register() async {
    setState(() => _registering = true);
    try {
      await ref.read(apiClientProvider).post('/billing/principia-pay/register');
      ref.invalidate(_connectionProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Escola registada na principia-pay.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Registo falhou: $error')),
      );
    } finally {
      if (mounted) setState(() => _registering = false);
    }
  }

  Future<void> _refreshReference(Map<String, dynamic> reference) async {
    try {
      await ref.read(apiClientProvider).post(
            '/billing/principia-pay/references/${reference['id']}/refresh',
          );
      ref.invalidate(_referencesProvider(_status));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Referência consultada no rail.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Consulta falhou: $error')),
      );
    }
  }

  Future<void> _copy(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copiado.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final connection = ref.watch(_connectionProvider);
    final references = ref.watch(_referencesProvider(_status));
    final currency = ref.watch(currencyFormatProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pagamentos por Referência'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(_connectionProvider);
              ref.invalidate(_referencesProvider(_status));
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(_connectionProvider);
          ref.invalidate(_referencesProvider(_status));
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            connection.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => AppErrorWidget(
                error: error,
                onRetry: () => ref.invalidate(_connectionProvider),
              ),
              data: (status) => _ConnectionCard(
                status: status,
                registering: _registering,
                onRegister: _register,
              ),
            ),
            const SizedBox(height: 16),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final entry in const {
                    '': 'Todas',
                    'active': 'Activas',
                    'paid': 'Pagas',
                    'cancelled': 'Canceladas',
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
            references.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => AppErrorWidget(
                error: error,
                onRetry: () => ref.invalidate(_referencesProvider(_status)),
              ),
              data: (rows) {
                if (rows.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                      child: Text('Ainda não há referências nesta escola.'),
                    ),
                  );
                }
                return Column(
                  children: [
                    for (final row in rows)
                      _ReferenceCard(
                        reference: row,
                        currency: currency,
                        onRefresh: () => _refreshReference(row),
                        onCopy: _copy,
                      ),
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

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({
    required this.status,
    required this.registering,
    required this.onRegister,
  });

  final Map<String, dynamic> status;
  final bool registering;
  final VoidCallback onRegister;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final registered = status['registered'] == true;
    final configured = status['configured'] == true;
    final lastError = status['last_error']?.toString();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  registered ? Icons.check_circle : Icons.link_off,
                  color: registered
                      ? Colors.green
                      : theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    registered
                        ? 'Escola ligada à principia-pay'
                        : 'Escola ainda não registada',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              registered
                  ? 'As referências emitidas aqui são pagáveis em qualquer '
                      'canal Multicaixa/Appy Pay e conciliadas automaticamente.'
                  : 'Registe a escola para emitir referências de pagamento '
                      'aos encarregados.',
              style: theme.textTheme.bodySmall,
            ),
            if (!configured) ...[
              const SizedBox(height: 8),
              Text(
                'A ligação ao processador ainda não está configurada no '
                'servidor desta escola.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error),
              ),
            ],
            if (lastError != null && lastError.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Último erro: $lastError',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Chip(
                  label: Text('Fornecedor: ${status['provider'] ?? '—'}'),
                  visualDensity: VisualDensity.compact,
                ),
                const Spacer(),
                if (!registered)
                  FilledButton.icon(
                    onPressed: registering || !configured ? null : onRegister,
                    icon: const Icon(Icons.add_link, size: 18),
                    label:
                        Text(registering ? 'A registar…' : 'Registar escola'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ReferenceCard extends StatelessWidget {
  const _ReferenceCard({
    required this.reference,
    required this.currency,
    required this.onRefresh,
    required this.onCopy,
  });

  final Map<String, dynamic> reference;
  final NumberFormat currency;
  final VoidCallback onRefresh;
  final Future<void> Function(String value) onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = reference['status']?.toString() ?? 'creating';
    final amount = (reference['amount'] as num?)?.toDouble() ??
        (reference['paid_amount'] as num?)?.toDouble() ??
        0;
    final entity = reference['entity']?.toString() ?? '';
    final number = reference['reference']?.toString() ?? '';
    final checkout = reference['checkout_url']?.toString();
    final documentNumber =
        reference['finreg_document_number']?.toString() ?? '';
    final paidAt = reference['paid_at']?.toString();
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    documentNumber.isEmpty
                        ? 'Referência ${reference['id']}'
                        : 'Documento $documentNumber',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Chip(
                  label: Text(_statusLabels[status] ?? status),
                  visualDensity: VisualDensity.compact,
                  backgroundColor: status == 'paid'
                      ? Colors.green.withValues(alpha: 0.12)
                      : status == 'cancelled'
                          ? theme.colorScheme.errorContainer
                          : null,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              currency.format(amount),
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            if (entity.isNotEmpty || number.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Entidade $entity · Ref $number',
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 13),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Copiar referência',
                    icon: const Icon(Icons.copy, size: 18),
                    onPressed: () => onCopy(number),
                  ),
                ],
              ),
            ],
            if (paidAt != null && paidAt.isNotEmpty)
              Text(
                'Pago em ${formatIsoDate(paidAt)}',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: Colors.green.shade700),
              ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              children: [
                if (status == 'creating' || status == 'active')
                  TextButton.icon(
                    onPressed: onRefresh,
                    icon: const Icon(Icons.sync, size: 18),
                    label: const Text('Consultar estado'),
                  ),
                if (checkout != null && checkout.isNotEmpty)
                  TextButton.icon(
                    onPressed: () async {
                      final uri = Uri.tryParse(checkout);
                      if (uri == null) return;
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri,
                            mode: LaunchMode.externalApplication);
                      }
                    },
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: const Text('Abrir pagamento'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
