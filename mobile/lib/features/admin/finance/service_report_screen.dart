import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_client.dart';
import '../../../core/providers/currency_provider.dart';
import '../../../core/widgets/app_error_widget.dart';
import 'fee_automation_common.dart';

final _serviceReportProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, key) async {
  final parts = key.split('|');
  final data = await ref.read(apiClientProvider).get(
    '/billing/reports/services',
    queryParameters: {
      'date_from': parts.first,
      'date_to': parts.last,
    },
  ) as Map;
  return Map<String, dynamic>.from(data);
});

String _isoDate(DateTime date) => '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

/// Sales by service for a period. FinReg-active schools read the fiscal
/// engine's own report, so the director's number and the tax number agree.
class ServiceReportScreen extends ConsumerStatefulWidget {
  const ServiceReportScreen({super.key});

  @override
  ConsumerState<ServiceReportScreen> createState() =>
      _ServiceReportScreenState();
}

class _ServiceReportScreenState extends ConsumerState<ServiceReportScreen> {
  late DateTime _from;
  late DateTime _to;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _from = DateTime(now.year, now.month);
    _to = DateTime(now.year, now.month, now.day);
  }

  String get _key => '${_isoDate(_from)}|${_isoDate(_to)}';

  Future<void> _pickDate({required bool from}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: from ? _from : _to,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() {
      if (from) {
        _from = picked;
        if (_to.isBefore(_from)) _to = _from;
      } else {
        _to = picked;
        if (_from.isAfter(_to)) _from = _to;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final report = ref.watch(_serviceReportProvider(_key));
    final currency = ref.watch(currencyFormatProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Relatório por Serviço'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(_serviceReportProvider(_key)),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(_serviceReportProvider(_key)),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickDate(from: true),
                    icon: const Icon(Icons.calendar_today, size: 16),
                    label: Text(formatIsoDate(_isoDate(_from))),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text('até'),
                ),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickDate(from: false),
                    icon: const Icon(Icons.calendar_today, size: 16),
                    label: Text(formatIsoDate(_isoDate(_to))),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            report.when(
              loading: () => const Center(
                  child: Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: CircularProgressIndicator(),
              )),
              error: (error, _) => AppErrorWidget(
                error: error,
                onRetry: () => ref.invalidate(_serviceReportProvider(_key)),
              ),
              data: (data) => _ReportBody(data: data, currency: currency),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportBody extends StatelessWidget {
  const _ReportBody({required this.data, required this.currency});

  final Map<String, dynamic> data;
  final NumberFormat currency;

  double _money(dynamic value) => (value as num?)?.toDouble() ?? 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final services = ((data['services'] as List?) ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
    final totals =
        Map<String, dynamic>.from((data['totals'] as Map?) ?? const {});
    final period =
        Map<String, dynamic>.from((data['period'] as Map?) ?? const {});
    final maxGross = services.fold<double>(
        0,
        (max, row) => _money(row['gross_total']) > max
            ? _money(row['gross_total'])
            : max);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${formatIsoDate(period['from'] as String?)} – '
          '${formatIsoDate(period['to'] as String?)}',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        currency.format(_money(totals['gross_total'])),
                        style: theme.textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    Chip(
                      label: Text(
                          data['mode'] == 'internal' ? 'Interno' : 'FinReg'),
                    ),
                  ],
                ),
                Text(
                  'Total facturado · ${totals['quantity'] ?? 0} unidade(s)',
                  style: theme.textTheme.bodySmall,
                ),
                const Divider(height: 20),
                Row(
                  children: [
                    _Total(
                        label: 'Base',
                        value: totals['net_total'],
                        currency: currency),
                    _Total(
                        label: 'IVA',
                        value: totals['tax_total'],
                        currency: currency),
                    _Total(
                        label: 'Bruto',
                        value: totals['gross_total'],
                        currency: currency),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (services.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: Text('Sem facturação no período.')),
          ),
        for (final service in services)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          service['service_label']?.toString() ??
                              service['description']?.toString() ??
                              'Serviço',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      Text(
                        currency.format(_money(service['gross_total'])),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  LinearProgressIndicator(
                    value: maxGross <= 0
                        ? 0
                        : (_money(service['gross_total']) / maxGross)
                            .clamp(0.0, 1.0),
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${service['quantity'] ?? 0} un. · '
                    'base ${currency.format(_money(service['net_total']))} · '
                    'IVA ${currency.format(_money(service['tax_total']))}',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _Total extends StatelessWidget {
  const _Total({
    required this.label,
    required this.value,
    required this.currency,
  });

  final String label;
  final dynamic value;
  final NumberFormat currency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          Text(
            currency.format((value as num?)?.toDouble() ?? 0),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
