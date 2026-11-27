import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/api/api_client.dart';
import '../../../../core/api/api_exception.dart';
import '../../../../core/providers/currency_provider.dart';
import '../../../../core/theme/app_theme.dart';
import 'fiscal_common.dart';

/// A one-off invoice for one guardian and pupil.
///
/// The confirm step shows only FinReg's own totals (`/finreg/sales/preview`);
/// the app never adds up tax. Issuing reuses the same request id, so a
/// second press after a timeout is the same invoice, not another.
class FiscalIssueInvoiceScreen extends ConsumerStatefulWidget {
  const FiscalIssueInvoiceScreen({super.key});

  @override
  ConsumerState<FiscalIssueInvoiceScreen> createState() =>
      _FiscalIssueInvoiceScreenState();
}

class _Line {
  Map<String, dynamic>? item;
  final quantity = TextEditingController(text: '1');
  final price = TextEditingController();

  void dispose() {
    quantity.dispose();
    price.dispose();
  }
}

class _FiscalIssueInvoiceScreenState
    extends ConsumerState<FiscalIssueInvoiceScreen> {
  final String _requestId = newRequestId();
  final List<_Line> _lines = [_Line()];
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _guardians = [];
  List<Map<String, dynamic>> _pupils = [];
  Map<String, dynamic>? _guardian;
  Map<String, dynamic>? _pupil;
  String _period = DateFormat('yyyy-MM').format(DateTime.now());
  Map<String, dynamic>? _preview;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadItems();
    _searchGuardians('');
  }

  @override
  void dispose() {
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  Future<void> _loadItems() async {
    try {
      final data = await ref.read(apiClientProvider).get('/finance/billing-items') as List;
      setState(() {
        _items = data
            .cast<Map<String, dynamic>>()
            .where((item) =>
                item['is_active'] != false &&
                (item['finreg_tax_option_code'] as String?)?.isNotEmpty == true)
            .toList();
      });
    } catch (error) {
      setState(() => _error = apiErrorMessage(error));
    }
  }

  Future<void> _searchGuardians(String term) async {
    try {
      final data = await ref.read(apiClientProvider).get('/finreg/guardians',
          queryParameters: {if (term.isNotEmpty) 'search': term}) as List;
      setState(() => _guardians = data.cast<Map<String, dynamic>>());
    } catch (error) {
      setState(() => _error = apiErrorMessage(error));
    }
  }

  Future<void> _selectGuardian(Map<String, dynamic>? guardian) async {
    setState(() {
      _guardian = guardian;
      _pupil = null;
      _pupils = [];
      _preview = null;
    });
    if (guardian == null) return;
    try {
      final data = await ref
          .read(apiClientProvider)
          .get('/finreg/guardians/${guardian['id']}/pupils') as List;
      setState(() {
        _pupils = data.cast<Map<String, dynamic>>();
        if (_pupils.length == 1) _pupil = _pupils.first;
      });
    } catch (error) {
      setState(() => _error = apiErrorMessage(error));
    }
  }

  Map<String, dynamic>? _draft() {
    if (_guardian == null || _pupil == null) return null;
    final lines = <Map<String, dynamic>>[];
    for (final line in _lines) {
      final quantity = double.tryParse(line.quantity.text.replaceAll(',', '.'));
      final price = double.tryParse(line.price.text.replaceAll(',', '.'));
      if (line.item == null || quantity == null || quantity <= 0 || price == null || price < 0) {
        return null;
      }
      lines.add({
        'billing_item_id': line.item!['id'],
        'quantity': quantity,
        'unit_price': price,
      });
    }
    return {
      'request_id': _requestId,
      'guardian_id': _guardian!['id'],
      'pupil_id': _pupil!['id'],
      'billing_period': _period,
      'lines': lines,
    };
  }

  Future<void> _previewTotals() async {
    final draft = _draft();
    if (draft == null) {
      setState(() => _error = 'Preencha o encarregado, o aluno e todas as linhas.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await ref.read(apiClientProvider).post('/finreg/sales/preview', data: draft)
          as Map<String, dynamic>;
      setState(() {
        _preview = data;
        _busy = false;
      });
    } catch (error) {
      setState(() {
        _busy = false;
        _error = apiErrorMessage(error);
      });
    }
  }

  Future<void> _issue() async {
    final draft = _draft();
    if (draft == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await ref.read(apiClientProvider).post('/finreg/sales/issue', data: draft)
          as Map<String, dynamic>;
      if (!mounted) return;
      final confirmed = result['status'] == 'confirmed';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(confirmed
            ? 'Fatura emitida.'
            : 'Fatura enviada; a confirmação fiscal chega em instantes.'),
      ));
      Navigator.of(context).pop(true);
    } catch (error) {
      setState(() {
        _busy = false;
        _error = apiErrorMessage(error);
      });
    }
  }

  void _changed() {
    if (_preview != null) setState(() => _preview = null);
  }

  @override
  Widget build(BuildContext context) {
    final currency = ref.watch(currencyFormatProvider);
    final months = List.generate(12, (index) {
      final now = DateTime.now();
      final month = DateTime(now.year, now.month - 6 + index);
      return DateFormat('yyyy-MM').format(month);
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Emitir fatura')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
        children: [
          Autocomplete<Map<String, dynamic>>(
            displayStringForOption: (option) => option['display_name'] as String? ?? '',
            optionsBuilder: (value) async {
              await _searchGuardians(value.text.trim());
              return _guardians;
            },
            onSelected: _selectGuardian,
            fieldViewBuilder: (context, controller, focus, onSubmit) => TextField(
              controller: controller,
              focusNode: focus,
              decoration: const InputDecoration(
                labelText: 'Encarregado (pagador)',
                prefixIcon: Icon(Icons.person_search_outlined),
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<Map<String, dynamic>>(
            value: _pupil,
            decoration: const InputDecoration(labelText: 'Aluno', border: OutlineInputBorder()),
            items: [
              for (final pupil in _pupils)
                DropdownMenuItem(value: pupil, child: Text(pupil['display_name'] as String? ?? '')),
            ],
            onChanged: _guardian == null
                ? null
                : (value) {
                    setState(() => _pupil = value);
                    _changed();
                  },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _period,
            decoration: const InputDecoration(labelText: 'Período', border: OutlineInputBorder()),
            items: [
              for (final month in months) DropdownMenuItem(value: month, child: Text(month)),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() => _period = value);
              _changed();
            },
          ),
          const SizedBox(height: 20),
          const Text('Linhas', style: TextStyle(fontWeight: FontWeight.w700)),
          if (_items.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Nenhum serviço com tratamento fiscal configurado. Configure-o em Serviços.',
                style: TextStyle(color: AppTheme.warning),
              ),
            ),
          for (var index = 0; index < _lines.length; index++) _lineEditor(index),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () {
                setState(() => _lines.add(_Line()));
                _changed();
              },
              icon: const Icon(Icons.add),
              label: const Text('Adicionar linha'),
            ),
          ),
          if (_preview != null) ...[
            const Divider(height: 32),
            const Text('Totais calculados pelo sistema fiscal',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            _total('Sem imposto', _preview!['net_total'], currency),
            _total('Imposto', _preview!['tax_total'], currency),
            _total('Total', _preview!['gross_total'], currency, bold: true),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!, style: const TextStyle(color: AppTheme.danger)),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: _busy ? null : (_preview == null ? _previewTotals : _issue),
            child: _busy
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(_preview == null ? 'Ver totais' : 'Emitir fatura'),
          ),
        ),
      ),
    );
  }

  Widget _lineEditor(int index) {
    final line = _lines[index];
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          flex: 5,
          child: DropdownButtonFormField<Map<String, dynamic>>(
            value: line.item,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Serviço', border: OutlineInputBorder(), isDense: true),
            items: [
              for (final item in _items)
                DropdownMenuItem(value: item, child: Text(item['name'] as String? ?? '', overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (value) {
              setState(() {
                line.item = value;
                final price = (value?['unit_price'] as num?)?.toDouble();
                if (price != null) line.price.text = price.toStringAsFixed(2);
              });
              _changed();
            },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: TextField(
            controller: line.quantity,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => _changed(),
            decoration: const InputDecoration(labelText: 'Qtd.', border: OutlineInputBorder(), isDense: true),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 3,
          child: TextField(
            controller: line.price,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => _changed(),
            decoration: const InputDecoration(labelText: 'Preço', border: OutlineInputBorder(), isDense: true),
          ),
        ),
        if (_lines.length > 1)
          IconButton(
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: () {
              setState(() => _lines.removeAt(index).dispose());
              _changed();
            },
          ),
      ]),
    );
  }

  Widget _total(String label, Object? value, NumberFormat currency, {bool bold = false}) {
    final style = TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w500);
    final number = value is num ? value.toDouble() : double.tryParse('$value');
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(children: [
        Expanded(child: Text(label, style: style)),
        Text(number == null ? '—' : currency.format(number), style: style),
      ]),
    );
  }
}
