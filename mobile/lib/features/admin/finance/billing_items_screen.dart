import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_client.dart';
import '../../../core/providers/currency_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_error_widget.dart';

// ─── Providers ───────────────────────────────────────────────────────────────

final _billingItemsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final api = ref.read(apiClientProvider);
  final data = await api.get('/finance/billing-items') as List;
  return data.cast<Map<String, dynamic>>();
});

final _schoolYearsProvider2 = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final api = ref.read(apiClientProvider);
  final data = await api.get('/schools/school-years') as List;
  return data.cast<Map<String, dynamic>>();
});

// ─── Screen ──────────────────────────────────────────────────────────────────

class BillingItemsScreen extends ConsumerWidget {
  const BillingItemsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(_billingItemsProvider);
    final currency = ref.watch(currencyFormatProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Itens Faturáveis'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(_billingItemsProvider),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateDialog(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Novo Item'),
      ),
      body: itemsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AppErrorWidget(error: e, onRetry: () => ref.invalidate(_billingItemsProvider)),
        data: (items) {
          if (items.isEmpty) {
            return const Center(child: Text('Nenhum item faturável', style: TextStyle(color: AppTheme.textSecondary)));
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(_billingItemsProvider),
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
              itemCount: items.length,
              itemBuilder: (_, i) => _BillingItemCard(
                item: items[i],
                currency: currency,
                onChanged: () => ref.invalidate(_billingItemsProvider),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showCreateDialog(BuildContext context, WidgetRef ref) {
    showDialog(useRootNavigator: false, 
      context: context,
      builder: (_) => _BillingItemDialog(
        onSaved: () => ref.invalidate(_billingItemsProvider),
      ),
    );
  }
}

// ─── Item Card ───────────────────────────────────────────────────────────────

class _BillingItemCard extends ConsumerWidget {
  final Map<String, dynamic> item;
  final NumberFormat currency;
  final VoidCallback onChanged;

  const _BillingItemCard({required this.item, required this.currency, required this.onChanged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isActive = item['is_active'] as bool? ?? true;
    final catColor = _categoryColor(item['category'] as String? ?? 'other');

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: catColor.withOpacity(0.3)),
      ),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: catColor.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
          child: Icon(_categoryIcon(item['category'] as String? ?? 'other'), color: catColor, size: 20),
        ),
        title: Text(item['name'] as String? ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(
          '${item['code'] ?? ''} · IVA ${item['iva_rate'] ?? 0}%${!isActive ? ' · Inactivo' : ''}',
          style: TextStyle(fontSize: 12, color: isActive ? AppTheme.textSecondary : AppTheme.danger),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              currency.format((item['unit_price'] as num?)?.toDouble() ?? 0),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, size: 18),
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit_outlined, size: 18), SizedBox(width: 8), Text('Editar')])),
                const PopupMenuItem(value: 'prices', child: Row(children: [Icon(Icons.price_change_outlined, size: 18), SizedBox(width: 8), Text('Preços por Ano')])),
                const PopupMenuItem(value: 'toggle', child: Row(children: [Icon(Icons.toggle_on_outlined, size: 18), SizedBox(width: 8), Text('Activar/Desactivar')])),
              ],
              onSelected: (action) {
                if (action == 'edit') {
                  showDialog(useRootNavigator: false, context: context, builder: (_) => _BillingItemDialog(item: item, onSaved: onChanged));
                } else if (action == 'prices') {
                  showDialog(useRootNavigator: false, context: context, builder: (_) => _PriceTableDialog(item: item, ref: ref));
                } else if (action == 'toggle') {
                  _toggle(context, ref);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggle(BuildContext context, WidgetRef ref) async {
    try {
      final api = ref.read(apiClientProvider);
      await api.patch('/finance/billing-items/${item['id']}', data: {'is_active': !(item['is_active'] as bool? ?? true)});
      onChanged();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e'), backgroundColor: AppTheme.danger));
      }
    }
  }

  Color _categoryColor(String cat) => switch (cat) {
    'tuition' => Colors.blue,
    'meals' => Colors.orange,
    'transport' => Colors.teal,
    'materials' => Colors.purple,
    'activities' => Colors.green,
    _ => Colors.grey,
  };

  IconData _categoryIcon(String cat) => switch (cat) {
    'tuition' => Icons.school_outlined,
    'meals' => Icons.restaurant_outlined,
    'transport' => Icons.directions_bus_outlined,
    'materials' => Icons.book_outlined,
    'activities' => Icons.sports_outlined,
    _ => Icons.receipt_outlined,
  };
}

// ─── Create/Edit Dialog ──────────────────────────────────────────────────────

class _BillingItemDialog extends ConsumerStatefulWidget {
  final Map<String, dynamic>? item;
  final VoidCallback onSaved;
  const _BillingItemDialog({this.item, required this.onSaved});

  @override
  ConsumerState<_BillingItemDialog> createState() => _BillingItemDialogState();
}

class _BillingItemDialogState extends ConsumerState<_BillingItemDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _codeCtrl;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _ivaCtrl;
  late final TextEditingController _exemptionCtrl;
  late final TextEditingController _descCtrl;
  String _category = 'other';
  bool _isLoading = false;
  String? _error;
  bool _codeManuallyEdited = false;

  bool get _isEdit => widget.item != null;

  static String _generateCode(String name) {
    const accents = {
      'á': 'a', 'à': 'a', 'ã': 'a', 'â': 'a', 'ä': 'a',
      'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
      'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
      'ó': 'o', 'ò': 'o', 'õ': 'o', 'ô': 'o', 'ö': 'o',
      'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
      'ç': 'c', 'ñ': 'n',
    };
    var s = name.toLowerCase();
    for (final e in accents.entries) s = s.replaceAll(e.key, e.value);
    final clean = s.replaceAll(RegExp(r'[^a-z0-9\s]'), '');
    final words = clean.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    String code;
    if (words.isEmpty) return '';
    if (words.length == 1) {
      code = words[0].substring(0, words[0].length.clamp(0, 8));
    } else {
      code = words.map((w) => w.substring(0, w.length.clamp(0, 3))).join();
      if (code.length > 8) code = code.substring(0, 8);
    }
    return code.toUpperCase();
  }

  void _syncCode() {
    if (_isEdit || _codeManuallyEdited) return;
    final generated = _generateCode(_nameCtrl.text);
    if (_codeCtrl.text != generated) {
      _codeCtrl.value = TextEditingValue(text: generated, selection: TextSelection.collapsed(offset: generated.length));
    }
  }

  static const _categories = {
    'tuition': 'Mensalidade',
    'meals': 'Refeições',
    'transport': 'Transporte',
    'materials': 'Materiais',
    'activities': 'Actividades',
    'other': 'Outro',
  };

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _codeCtrl = TextEditingController(text: item?['code'] as String? ?? '');
    _nameCtrl = TextEditingController(text: item?['name'] as String? ?? '');
    if (!_isEdit) _nameCtrl.addListener(_syncCode);
    _priceCtrl = TextEditingController(text: (item?['unit_price'] as num?)?.toStringAsFixed(2) ?? '');
    _ivaCtrl = TextEditingController(text: (item?['iva_rate'] as num?)?.toStringAsFixed(2) ?? '0');
    _exemptionCtrl = TextEditingController(text: item?['iva_exemption_reason'] as String? ?? '');
    _descCtrl = TextEditingController(text: item?['description'] as String? ?? '');
    _category = item?['category'] as String? ?? 'other';
  }

  @override
  void dispose() {
    if (!_isEdit) _nameCtrl.removeListener(_syncCode);
    _codeCtrl.dispose(); _nameCtrl.dispose(); _priceCtrl.dispose();
    _ivaCtrl.dispose(); _exemptionCtrl.dispose(); _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _isLoading = true; _error = null; });
    try {
      final api = ref.read(apiClientProvider);
      final body = {
        if (!_isEdit) 'code': _codeCtrl.text.trim(),
        'name': _nameCtrl.text.trim(),
        'unit_price': double.tryParse(_priceCtrl.text) ?? 0.0,
        'iva_rate': double.tryParse(_ivaCtrl.text) ?? 0.0,
        'category': _category,
        if (_exemptionCtrl.text.trim().isNotEmpty) 'iva_exemption_reason': _exemptionCtrl.text.trim(),
        if (_descCtrl.text.trim().isNotEmpty) 'description': _descCtrl.text.trim(),
      };
      if (_isEdit) {
        await api.patch('/finance/billing-items/${widget.item!['id']}', data: body);
      } else {
        await api.post('/finance/billing-items', data: body);
      }
      widget.onSaved();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEdit ? 'Editar Item' : 'Novo Item Faturável'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!_isEdit) ...[
                  TextFormField(
                    controller: _codeCtrl,
                    decoration: const InputDecoration(labelText: 'Código *', helperText: 'Auto-gerado · Imutável após criação'),
                    textCapitalization: TextCapitalization.characters,
                    onChanged: (v) {
                      final generated = _generateCode(_nameCtrl.text);
                      _codeManuallyEdited = v.isNotEmpty && v != generated;
                    },
                    validator: (v) => v == null || v.trim().isEmpty ? 'Obrigatório' : null,
                  ),
                  const SizedBox(height: 12),
                ],
                TextFormField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(labelText: 'Nome *'),
                  validator: (v) => v == null || v.trim().isEmpty ? 'Obrigatório' : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _category,
                  decoration: const InputDecoration(labelText: 'Categoria'),
                  items: _categories.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                  onChanged: (v) => setState(() => _category = v ?? 'other'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _priceCtrl,
                  decoration: const InputDecoration(labelText: 'Preço Padrão *', prefixIcon: Icon(Icons.monetization_on_outlined)),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  validator: (v) => v == null || v.trim().isEmpty ? 'Obrigatório' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _ivaCtrl,
                  decoration: const InputDecoration(labelText: 'Taxa IVA (%)', prefixIcon: Icon(Icons.percent)),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _exemptionCtrl,
                  decoration: const InputDecoration(labelText: 'Código Isenção IVA', helperText: 'Ex: M10'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descCtrl,
                  decoration: const InputDecoration(labelText: 'Descrição'),
                  maxLines: 2,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: AppTheme.danger, fontSize: 12)),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _isLoading ? null : () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: _isLoading ? null : _save,
          child: _isLoading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text(_isEdit ? 'Guardar' : 'Criar'),
        ),
      ],
    );
  }
}

// ─── Price Table Dialog ───────────────────────────────────────────────────────

class _PriceTableDialog extends ConsumerStatefulWidget {
  final Map<String, dynamic> item;
  final WidgetRef ref;
  const _PriceTableDialog({required this.item, required this.ref});

  @override
  ConsumerState<_PriceTableDialog> createState() => _PriceTableDialogState();
}

class _PriceTableDialogState extends ConsumerState<_PriceTableDialog> {
  List<Map<String, dynamic>> _prices = [];
  List<Map<String, dynamic>> _years = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final api = ref.read(apiClientProvider);
      final results = await Future.wait([
        api.get('/finance/billing-items/${widget.item['id']}/prices') as Future,
        api.get('/schools/school-years') as Future,
      ]);
      setState(() {
        _prices = (results[0] as List).cast<Map<String, dynamic>>();
        _years = (results[1] as List).cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _setPrice(Map<String, dynamic> year) async {
    final ctrl = TextEditingController();
    final confirmed = await showDialog<bool>(useRootNavigator: false, 
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Preço para ${year['name']}'),
        content: TextFormField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Preço *', prefixIcon: Icon(Icons.monetization_on_outlined)),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Guardar')),
        ],
      ),
    );
    if (confirmed != true || ctrl.text.isEmpty) return;
    try {
      final api = ref.read(apiClientProvider);
      await api.post('/finance/billing-items/prices', data: {
        'billing_item_id': widget.item['id'],
        'school_year_id': year['id'],
        'unit_price': double.tryParse(ctrl.text) ?? 0.0,
      });
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e'), backgroundColor: AppTheme.danger));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Preços — ${widget.item['name']}'),
      content: SizedBox(
        width: 360,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Text(_error!, style: const TextStyle(color: AppTheme.danger))
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: _years.map((year) {
                      final existing = _prices.where((p) => p['school_year_id'] == year['id']).firstOrNull;
                      return ListTile(
                        dense: true,
                        title: Text(year['name'] as String? ?? ''),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (existing != null)
                              Text(
                                NumberFormat.simpleCurrency(name: 'AOA').format((existing['unit_price'] as num?)?.toDouble() ?? 0),
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                            IconButton(
                              icon: Icon(existing != null ? Icons.edit_outlined : Icons.add, size: 18),
                              onPressed: () => _setPrice(year),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fechar')),
      ],
    );
  }
}
