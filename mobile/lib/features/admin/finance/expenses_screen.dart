import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_client.dart';

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------
class Expense {
  final String id;
  final String description;
  final double amount;
  final DateTime expenseDate;
  final String category;
  final String? notes;

  const Expense({
    required this.id,
    required this.description,
    required this.amount,
    required this.expenseDate,
    required this.category,
    this.notes,
  });

  String get categoryLabel {
    switch (category) {
      case 'salary':
        return 'Salários';
      case 'utilities':
        return 'Serviços';
      case 'supplies':
        return 'Material';
      case 'food':
        return 'Alimentação';
      case 'maintenance':
        return 'Manutenção';
      default:
        return category;
    }
  }

  factory Expense.fromJson(Map<String, dynamic> json) {
    return Expense(
      id: json['id']?.toString() ?? '',
      description: json['description'] as String? ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      expenseDate: json['expense_date'] != null
          ? DateTime.tryParse(json['expense_date'] as String) ?? DateTime.now()
          : DateTime.now(),
      category: json['category'] as String? ?? 'other',
      notes: json['notes'] as String?,
    );
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------
final expensesProvider =
    FutureProvider.autoDispose<List<Expense>>((ref) async {
  final api = ref.read(apiClientProvider);
  final data = await api.get('/expenses', queryParameters: {'ordering': '-expense_date'}) as List;
  return data
      .map((e) => Expense.fromJson(e as Map<String, dynamic>))
      .toList();
});

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------
class ExpensesScreen extends ConsumerWidget {
  const ExpensesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expensesAsync = ref.watch(expensesProvider);
    final currency = NumberFormat.currency(locale: 'pt_PT', symbol: '€');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Despesas'),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddExpenseDialog(context, ref),
        tooltip: 'Adicionar Despesa',
        child: const Icon(Icons.add),
      ),
      body: expensesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 8),
              Text(e.toString(), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => ref.invalidate(expensesProvider),
                icon: const Icon(Icons.refresh),
                label: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
        data: (expenses) {
          if (expenses.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.receipt_long,
                      size: 64,
                      color:
                          Theme.of(context).colorScheme.outlineVariant),
                  const SizedBox(height: 16),
                  Text(
                    'Nenhuma despesa registada',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            );
          }

          // Group expenses by date
          final grouped = <String, List<Expense>>{};
          for (final e in expenses) {
            final key = DateFormat('dd/MM/yyyy').format(e.expenseDate);
            grouped.putIfAbsent(key, () => []).add(e);
          }

          final sortedKeys = grouped.keys.toList()
            ..sort((a, b) {
              final df = DateFormat('dd/MM/yyyy');
              return df.parse(b).compareTo(df.parse(a));
            });

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(expensesProvider),
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 88),
              itemCount: sortedKeys.length,
              itemBuilder: (context, i) {
                final dateKey = sortedKeys[i];
                final dayExpenses = grouped[dateKey]!;
                final dayTotal = dayExpenses.fold<double>(
                    0.0, (sum, e) => sum + e.amount);

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding:
                          const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            dateKey,
                            style: Theme.of(context)
                                .textTheme
                                .labelLarge
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primary,
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          Text(
                            currency.format(dayTotal),
                            style: TextStyle(
                                color: Colors.red,
                                fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                    ...dayExpenses.map(
                      (exp) => Card(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 2),
                        child: ListTile(
                          leading: _CategoryIcon(
                              category: exp.category),
                          title: Text(exp.description),
                          subtitle: Text(exp.categoryLabel),
                          trailing: Text(
                            currency.format(exp.amount),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.red,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }

  void _showAddExpenseDialog(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AddExpenseSheet(
        onAdded: () {
          ref.invalidate(expensesProvider);
          Navigator.pop(context);
        },
      ),
    );
  }
}

class _CategoryIcon extends StatelessWidget {
  final String category;
  const _CategoryIcon({required this.category});

  @override
  Widget build(BuildContext context) {
    IconData icon;
    Color color;
    switch (category) {
      case 'salary':
        icon = Icons.people;
        color = Colors.blue;
        break;
      case 'utilities':
        icon = Icons.bolt;
        color = Colors.orange;
        break;
      case 'food':
        icon = Icons.restaurant;
        color = Colors.green;
        break;
      case 'supplies':
        icon = Icons.inventory;
        color = Colors.purple;
        break;
      case 'maintenance':
        icon = Icons.build;
        color = Colors.brown;
        break;
      default:
        icon = Icons.receipt;
        color = Colors.grey;
    }
    return CircleAvatar(
      radius: 18,
      backgroundColor: color.withOpacity(0.15),
      child: Icon(icon, color: color, size: 18),
    );
  }
}

// ---------------------------------------------------------------------------
// Add Expense sheet
// ---------------------------------------------------------------------------
class _AddExpenseSheet extends ConsumerStatefulWidget {
  final VoidCallback onAdded;
  const _AddExpenseSheet({required this.onAdded});

  @override
  ConsumerState<_AddExpenseSheet> createState() =>
      _AddExpenseSheetState();
}

class _AddExpenseSheetState extends ConsumerState<_AddExpenseSheet> {
  final _formKey = GlobalKey<FormState>();
  final _descCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  String _category = 'other';
  DateTime _date = DateTime.now();
  bool _isLoading = false;
  String? _error;

  static const _categories = [
    ('salary', 'Salários'),
    ('utilities', 'Serviços'),
    ('food', 'Alimentação'),
    ('supplies', 'Material'),
    ('maintenance', 'Manutenção'),
    ('other', 'Outro'),
  ];

  @override
  void dispose() {
    _descCtrl.dispose();
    _amountCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      await api.post('/expenses', data: {
        'description': _descCtrl.text.trim(),
        'amount': double.tryParse(_amountCtrl.text) ?? 0.0,
        'expense_date':
            '${_date.year.toString().padLeft(4, '0')}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}',
        'category': _category,
        if (_notesCtrl.text.trim().isNotEmpty) 'notes': _notesCtrl.text.trim(),
      });
      widget.onAdded();
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Nova Despesa',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),

            TextFormField(
              controller: _descCtrl,
              decoration: const InputDecoration(
                labelText: 'Descrição *',
                prefixIcon: Icon(Icons.notes),
              ),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Campo obrigatório' : null,
            ),
            const SizedBox(height: 12),

            TextFormField(
              controller: _amountCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Valor (€) *',
                prefixIcon: Icon(Icons.euro),
              ),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Campo obrigatório' : null,
            ),
            const SizedBox(height: 12),

            DropdownButtonFormField<String>(
              value: _category,
              decoration: const InputDecoration(
                labelText: 'Categoria',
                prefixIcon: Icon(Icons.category),
              ),
              items: _categories
                  .map((c) => DropdownMenuItem(
                        value: c.$1,
                        child: Text(c.$2),
                      ))
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _category = v);
              },
            ),
            const SizedBox(height: 12),

            TextFormField(
              controller: _notesCtrl,
              decoration: const InputDecoration(
                labelText: 'Notas (opcional)',
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error)),
            ],

            const SizedBox(height: 16),
            FilledButton(
              onPressed: _isLoading ? null : _submit,
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Registar Despesa'),
            ),
          ],
        ),
      ),
    );
  }
}
