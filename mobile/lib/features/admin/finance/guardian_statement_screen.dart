import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/providers/currency_provider.dart';
import '../../../core/theme/app_theme.dart';

/// One guardian's account statement — every invoice, payment and the running
/// balance — from whichever engine owns the school.
///
/// In FinReg mode the statement is FinReg's; otherwise Cellen's own ledger
/// answers. Both return the same shape, so the screen renders one way.
class GuardianStatementScreen extends ConsumerStatefulWidget {
  const GuardianStatementScreen({super.key});

  @override
  ConsumerState<GuardianStatementScreen> createState() =>
      _GuardianStatementScreenState();
}

class _GuardianStatementScreenState
    extends ConsumerState<GuardianStatementScreen> {
  List<Map<String, dynamic>> _guardians = [];
  String? _selectedGuardianId;
  String? _selectedGuardianName;
  Map<String, dynamic>? _statement;
  bool _loadingGuardians = true;
  bool _loadingStatement = false;
  String? _fallbackNotice;
  String? _error;
  DateTime _dateFrom = DateTime(DateTime.now().year, 1, 1);
  DateTime _dateTo = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadGuardians();
  }

  String _iso(DateTime value) => '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  Future<void> _loadGuardians() async {
    try {
      final data = await ref.read(apiClientProvider).get('/guardians') as List;
      setState(() {
        _guardians =
            data.map((row) => Map<String, dynamic>.from(row as Map)).toList();
        _loadingGuardians = false;
      });
    } catch (error) {
      setState(() {
        _error = apiErrorMessage(error);
        _loadingGuardians = false;
      });
    }
  }

  Future<void> _loadStatement() async {
    final guardianId = _selectedGuardianId;
    if (guardianId == null) return;
    setState(() {
      _loadingStatement = true;
      _error = null;
      _fallbackNotice = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      final modeValue = await api.get('/finance/internal-payments/mode') as Map;
      final finregActive =
          Map<String, dynamic>.from(modeValue)['finreg_active'] == true;
      Map<String, dynamic>? statement;
      if (finregActive) {
        try {
          statement = Map<String, dynamic>.from(await api.get(
            '/finreg/customers/$guardianId/statement',
            queryParameters: {
              'date_from': _iso(_dateFrom),
              'date_to': _iso(_dateTo),
            },
          ) as Map);
        } catch (_) {
          statement = null;
        }
        if (statement == null) {
          _fallbackNotice =
              'O FinReg não respondeu; a mostrar o extrato interno do Cellen.';
        }
      }
      statement ??= Map<String, dynamic>.from(await api.get(
        '/finance/reports/statement/$guardianId',
        queryParameters: {
          'from_date': _iso(_dateFrom),
          'to_date': _iso(_dateTo),
        },
      ) as Map);
      if (!mounted) return;
      setState(() {
        _statement = statement;
        _loadingStatement = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = apiErrorMessage(error);
        _loadingStatement = false;
      });
    }
  }

  Future<void> _pickDate({required bool from}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: from ? _dateFrom : _dateTo,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked == null) return;
    setState(() {
      if (from) {
        _dateFrom = picked;
      } else {
        _dateTo = picked;
      }
      _statement = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final currency = ref.watch(currencyFormatProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Extrato de Contas')),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: Theme.of(context)
                .colorScheme
                .surfaceContainerHighest
                .withOpacity(0.5),
            child: Column(
              children: [
                _loadingGuardians
                    ? const LinearProgressIndicator()
                    : DropdownButtonFormField<String>(
                        value: _selectedGuardianId,
                        decoration: const InputDecoration(
                          labelText: 'Encarregado',
                          prefixIcon: Icon(Icons.person_outline),
                          filled: true,
                        ),
                        isExpanded: true,
                        items: _guardians
                            .map((guardian) => DropdownMenuItem(
                                  value: guardian['id']?.toString(),
                                  child: Text(
                                    '${guardian['first_name'] ?? ''} ${guardian['last_name'] ?? ''}'
                                        .trim(),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ))
                            .toList(),
                        onChanged: (value) {
                          final guardian = _guardians
                              .where((g) => g['id']?.toString() == value)
                              .firstOrNull;
                          setState(() {
                            _selectedGuardianId = value;
                            _selectedGuardianName =
                                '${guardian?['first_name'] ?? ''} ${guardian?['last_name'] ?? ''}'
                                    .trim();
                            _statement = null;
                            _fallbackNotice = null;
                          });
                        },
                      ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _datePicker(
                          'De', _dateFrom, () => _pickDate(from: true)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _datePicker(
                          'Até', _dateTo, () => _pickDate(from: false)),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _selectedGuardianId != null && !_loadingStatement
                        ? _loadStatement
                        : null,
                    icon: _loadingStatement
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.search),
                    label: const Text('Ver Extrato'),
                  ),
                ),
              ],
            ),
          ),
          if (_fallbackNotice != null)
            Container(
              width: double.infinity,
              color: Theme.of(context).colorScheme.errorContainer,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(_fallbackNotice!,
                  style: Theme.of(context).textTheme.bodySmall),
            ),
          Expanded(
            child: _statement == null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.receipt_long_outlined,
                            size: 56, color: AppTheme.textSecondary),
                        const SizedBox(height: 12),
                        Text(
                          _error ??
                              'Seleccione um encarregado e clique em "Ver Extrato"',
                          style: TextStyle(
                              color: _error != null
                                  ? AppTheme.danger
                                  : AppTheme.textSecondary),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  )
                : _StatementView(
                    statement: _statement!,
                    guardianName: _selectedGuardianName ?? '',
                    currency: currency,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _datePicker(String label, DateTime value, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
        child: Text(DateFormat('dd/MM/yyyy').format(value),
            style: const TextStyle(fontSize: 13)),
      ),
    );
  }
}

class _StatementView extends StatelessWidget {
  final Map<String, dynamic> statement;
  final String guardianName;
  final NumberFormat currency;

  const _StatementView({
    required this.statement,
    required this.guardianName,
    required this.currency,
  });

  double _toDouble(dynamic value) => value == null
      ? 0
      : (value is num ? value.toDouble() : double.tryParse('$value') ?? 0);

  @override
  Widget build(BuildContext context) {
    final totalInvoiced = _toDouble(statement['total_invoiced']);
    final totalSettled = _toDouble(statement['total_settled']);
    final balance = _toDouble(statement['current_balance']);
    final creditBalance = _toDouble(statement['credit_balance']);
    final movements = (statement['movements'] as List? ?? [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Theme.of(context)
                .colorScheme
                .surfaceContainerHighest
                .withOpacity(0.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(guardianName,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 10),
              _headerRow('Total Facturado', currency.format(totalInvoiced),
                  Colors.blue),
              _headerRow('Total Pago', currency.format(totalSettled),
                  AppTheme.success),
              _headerRow('Saldo em Dívida', currency.format(balance),
                  balance > 0 ? AppTheme.danger : AppTheme.success),
              if (creditBalance > 0)
                _headerRow('Saldo de Crédito', currency.format(creditBalance),
                    AppTheme.primary),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text('Movimentos',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700, color: AppTheme.textSecondary)),
        const SizedBox(height: 8),
        if (movements.isEmpty)
          const Text('Sem movimentos no período escolhido.',
              style: TextStyle(color: AppTheme.textSecondary))
        else
          ...movements.map((movement) =>
              _MovementRow(movement: movement, currency: currency)),
      ],
    );
  }

  Widget _headerRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style:
                  const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
          Text(value,
              style: TextStyle(
                  fontWeight: FontWeight.bold, color: color, fontSize: 13)),
        ],
      ),
    );
  }
}

class _MovementRow extends StatelessWidget {
  final Map<String, dynamic> movement;
  final NumberFormat currency;

  const _MovementRow({required this.movement, required this.currency});

  double _toDouble(dynamic value) => value == null
      ? 0
      : (value is num ? value.toDouble() : double.tryParse('$value') ?? 0);

  @override
  Widget build(BuildContext context) {
    final type = movement['type'] as String? ?? '';
    final description = movement['description'] as String? ?? type;
    final date = movement['date'] as String? ?? '';
    final debit = _toDouble(movement['debit']);
    final credit = _toDouble(movement['credit']);
    final runningBalance = movement['running_balance'] != null
        ? _toDouble(movement['running_balance'])
        : null;
    final isDebit = debit > 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border(
            left: BorderSide(
                width: 3, color: isDebit ? AppTheme.danger : AppTheme.success)),
        color: (isDebit ? AppTheme.danger : AppTheme.success).withOpacity(0.03),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(description,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13)),
                Text(date,
                    style: const TextStyle(
                        fontSize: 11, color: AppTheme.textSecondary)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                isDebit
                    ? '+${currency.format(debit)}'
                    : '-${currency.format(credit)}',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: isDebit ? AppTheme.danger : AppTheme.success),
              ),
              if (runningBalance != null)
                Text('Saldo: ${currency.format(runningBalance)}',
                    style: const TextStyle(
                        fontSize: 10, color: AppTheme.textSecondary)),
            ],
          ),
        ],
      ),
    );
  }
}
