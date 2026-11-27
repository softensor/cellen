import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/api/api_client.dart';
import '../../../../core/api/api_exception.dart';
import '../../../../core/models/account_statement.dart';
import '../../../../core/providers/currency_provider.dart';
import '../../../../core/theme/app_theme.dart';
import 'fiscal_common.dart';

/// A guardian's fiscal account statement, as FinReg keeps it.
class FiscalStatementScreen extends ConsumerStatefulWidget {
  const FiscalStatementScreen({super.key});

  @override
  ConsumerState<FiscalStatementScreen> createState() => _FiscalStatementScreenState();
}

class _FiscalStatementScreenState extends ConsumerState<FiscalStatementScreen> {
  final _format = DateFormat('yyyy-MM-dd');
  List<Map<String, dynamic>> _guardians = [];
  Map<String, dynamic>? _guardian;
  late DateTimeRange _range;
  AccountStatement? _statement;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _range = DateTimeRange(start: DateTime(now.year, 1, 1), end: now);
  }

  Future<List<Map<String, dynamic>>> _search(String term) async {
    try {
      final data = await ref.read(apiClientProvider).get('/finreg/guardians',
          queryParameters: {if (term.isNotEmpty) 'search': term}) as List;
      _guardians = data.cast<Map<String, dynamic>>();
    } catch (_) {
      _guardians = [];
    }
    return _guardians;
  }

  Future<void> _load() async {
    final guardian = _guardian;
    if (guardian == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ref.read(apiClientProvider).get(
        '/finreg/customers/${guardian['id']}/statement',
        queryParameters: {
          'date_from': _format.format(_range.start),
          'date_to': _format.format(_range.end),
        },
      ) as Map<String, dynamic>;
      setState(() {
        _statement = AccountStatement.fromJson(data);
        _loading = false;
      });
    } catch (error) {
      setState(() {
        _statement = null;
        _loading = false;
        _error = apiErrorMessage(error);
      });
    }
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _range,
    );
    if (picked == null) return;
    setState(() => _range = picked);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final currency = ref.watch(currencyFormatProvider);
    final statement = _statement;
    return Scaffold(
      appBar: AppBar(title: const Text('Extrato do encarregado')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Autocomplete<Map<String, dynamic>>(
          displayStringForOption: (option) => option['display_name'] as String? ?? '',
          optionsBuilder: (value) => _search(value.text.trim()),
          onSelected: (guardian) {
            setState(() => _guardian = guardian);
            _load();
          },
          fieldViewBuilder: (context, controller, focus, onSubmit) => TextField(
            controller: controller,
            focusNode: focus,
            decoration: const InputDecoration(
              labelText: 'Encarregado',
              prefixIcon: Icon(Icons.person_search_outlined),
              border: OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _pickRange,
          icon: const Icon(Icons.date_range),
          label: Text('${fiscalDate(_format.format(_range.start))} – ${fiscalDate(_format.format(_range.end))}'),
        ),
        const SizedBox(height: 16),
        if (_loading) const Center(child: CircularProgressIndicator()),
        if (_error != null) Text(_error!, style: const TextStyle(color: AppTheme.danger)),
        if (_guardian == null && !_loading)
          const FiscalEmptyState(
            icon: Icons.account_balance_wallet_outlined,
            message: 'Escolha um encarregado para ver o extrato.',
          ),
        if (statement != null && !_loading) ...[
          Wrap(spacing: 8, runSpacing: 8, children: [
            _Figure('Faturado', statement.totalInvoiced, currency, AppTheme.textPrimary),
            _Figure('Pago', statement.totalSettled, currency, AppTheme.success),
            _Figure('Saldo', statement.currentBalance, currency,
                statement.currentBalance > 0 ? AppTheme.danger : AppTheme.success),
          ]),
          const SizedBox(height: 16),
          if (statement.movements.isEmpty)
            const Text('Sem movimentos neste período.',
                style: TextStyle(color: AppTheme.textSecondary)),
          for (final movement in statement.movements)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(movement.documentNumber.isEmpty
                  ? movement.description
                  : '${movement.documentNumber} · ${movement.description}'),
              subtitle: Text(fiscalDate(movement.date)),
              trailing: Text(
                movement.debit > 0
                    ? currency.format(movement.debit)
                    : '− ${currency.format(movement.credit)}',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: movement.debit > 0 ? AppTheme.textPrimary : AppTheme.success,
                ),
              ),
            ),
        ],
      ]),
    );
  }
}

class _Figure extends StatelessWidget {
  final String label;
  final double value;
  final NumberFormat currency;
  final Color color;
  const _Figure(this.label, this.value, this.currency, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 160,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(color: AppTheme.textSecondary)),
        const SizedBox(height: 4),
        Text(currency.format(value),
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: color)),
      ]),
    );
  }
}
