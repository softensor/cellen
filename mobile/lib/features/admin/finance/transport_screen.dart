import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_client.dart';
import '../../../core/providers/currency_provider.dart';
import '../../../core/widgets/app_error_widget.dart';
import 'fee_automation_common.dart';

final _transportRoutesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final data = await ref
      .read(apiClientProvider)
      .get('/billing/transport/routes') as List;
  return data.map((row) => Map<String, dynamic>.from(row as Map)).toList();
});

class TransportScreen extends ConsumerWidget {
  const TransportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routes = ref.watch(_transportRoutesProvider);
    final currency = ref.watch(currencyFormatProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transporte Escolar'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(_transportRoutesProvider),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Nova rota'),
      ),
      body: routes.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => AppErrorWidget(
          error: error,
          onRetry: () => ref.invalidate(_transportRoutesProvider),
        ),
        data: (rows) {
          if (rows.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(28),
                child: Text(
                  'Nenhuma rota de transporte. Crie as rotas para associar '
                  'alunos e cobrar o valor mensal automaticamente.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(_transportRoutesProvider),
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
              itemCount: rows.length,
              itemBuilder: (_, index) => _RouteCard(
                route: rows[index],
                currency: currency,
                onChanged: () => ref.invalidate(_transportRoutesProvider),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _openEditor(BuildContext context, WidgetRef ref) async {
    final changed = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (_) => const _RouteDialog(),
    );
    if (changed == true) ref.invalidate(_transportRoutesProvider);
  }
}

class _RouteCard extends ConsumerWidget {
  const _RouteCard({
    required this.route,
    required this.currency,
    required this.onChanged,
  });

  final Map<String, dynamic> route;
  final NumberFormat currency;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = route['is_active'] != false;
    final item = Map<String, dynamic>.from(
      route['billing_item'] as Map? ?? const {},
    );
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text(
                  route['name']?.toString() ?? 'Rota',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Chip(label: Text(active ? 'Activa' : 'Inactiva')),
            ]),
            if ((route['description']?.toString() ?? '').isNotEmpty)
              Text(route['description'].toString()),
            const SizedBox(height: 8),
            Wrap(spacing: 16, runSpacing: 6, children: [
              Text('Mensal: ${currency.format(
                (route['monthly_price'] as num?)?.toDouble() ?? 0,
              )}'),
              Text('Alunos: ${route['assigned_count'] ?? 0}'),
            ]),
            if ((item['name']?.toString() ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Serviço fiscal: ${item['name']}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 4),
            Row(children: [
              TextButton.icon(
                onPressed: () => _assign(context, ref),
                icon: const Icon(Icons.person_add_alt_outlined, size: 18),
                label: const Text('Atribuir aluno'),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Editar',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => _edit(context, ref),
              ),
              IconButton(
                tooltip: active ? 'Desactivar' : 'Reactivar',
                icon: Icon(
                  active
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
                onPressed: () => _toggle(context, ref, active),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final changed = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (_) => _RouteDialog(route: route),
    );
    if (changed == true) onChanged();
  }

  Future<void> _toggle(
    BuildContext context,
    WidgetRef ref,
    bool active,
  ) async {
    try {
      await ref.read(apiClientProvider).patch(
        '/billing/transport/routes/${route['id']}',
        data: {'is_active': !active},
      );
      onChanged();
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro: $error')));
      }
    }
  }

  Future<void> _assign(BuildContext context, WidgetRef ref) async {
    final message = await showDialog<String>(
      context: context,
      useRootNavigator: false,
      builder: (_) => _AssignDialog(
        routeId: route['id'].toString(),
        routeName: route['name']?.toString() ?? 'Rota',
      ),
    );
    if (message != null) {
      onChanged();
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    }
  }
}

class _RouteDialog extends ConsumerStatefulWidget {
  const _RouteDialog({this.route});

  final Map<String, dynamic>? route;

  @override
  ConsumerState<_RouteDialog> createState() => _RouteDialogState();
}

class _RouteDialogState extends ConsumerState<_RouteDialog> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _monthlyPrice;
  String? _billingItemId;
  bool _active = true;
  bool _saving = false;
  String? _error;

  bool get _editing => widget.route != null;

  @override
  void initState() {
    super.initState();
    final route = widget.route ?? const <String, dynamic>{};
    _name = TextEditingController(text: route['name']?.toString() ?? '');
    _description =
        TextEditingController(text: route['description']?.toString() ?? '');
    _monthlyPrice = TextEditingController(
      text: moneyText(route['monthly_price'] ?? 0),
    );
    _billingItemId = route['billing_item_id']?.toString();
    _active = route['is_active'] != false;
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _monthlyPrice.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(feeBillingItemsProvider);
    return AlertDialog(
      title: Text(_editing ? 'Editar rota' : 'Nova rota'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Nome *'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _description,
              decoration: const InputDecoration(labelText: 'Descrição'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _monthlyPrice,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Valor mensal (Kz)'),
            ),
            const SizedBox(height: 10),
            items.when(
              loading: () => const LinearProgressIndicator(),
              error: (_, __) =>
                  const Text('Não foi possível carregar os serviços.'),
              data: (rows) => DropdownButtonFormField<String?>(
                value: _billingItemId,
                decoration: const InputDecoration(
                  labelText: 'Serviço fiscal',
                  helperText:
                      'Necessário para emitir a cobrança do transporte.',
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Sem serviço fiscal'),
                  ),
                  for (final item in rows)
                    DropdownMenuItem<String?>(
                      value: item['id'].toString(),
                      child: Text(item['name'].toString()),
                    ),
                ],
                onChanged: (value) => setState(() => _billingItemId = value),
              ),
            ),
            const SizedBox(height: 4),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Activa'),
              value: _active,
              onChanged: (value) => setState(() => _active = value),
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ]),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_editing ? 'Guardar' : 'Criar'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Indique o nome da rota.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final body = {
      'name': _name.text.trim(),
      'description':
          _description.text.trim().isEmpty ? null : _description.text.trim(),
      'monthly_price': parseMoney(_monthlyPrice.text),
      'billing_item_id': _billingItemId,
      'is_active': _active,
    };
    try {
      final api = ref.read(apiClientProvider);
      if (_editing) {
        await api.patch(
          '/billing/transport/routes/${widget.route!['id']}',
          data: body,
        );
      } else {
        await api.post('/billing/transport/routes', data: body);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      setState(() {
        _saving = false;
        _error = error.toString();
      });
    }
  }
}

class _AssignDialog extends ConsumerStatefulWidget {
  const _AssignDialog({required this.routeId, required this.routeName});

  final String routeId;
  final String routeName;

  @override
  ConsumerState<_AssignDialog> createState() => _AssignDialogState();
}

class _AssignDialogState extends ConsumerState<_AssignDialog> {
  String? _childId;
  DateTime _startDate = DateTime.now();
  bool _saving = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final students = ref.watch(feeStudentsProvider);
    return AlertDialog(
      title: Text('Atribuir ${widget.routeName}'),
      content: SizedBox(
        width: 460,
        child: students.when(
          loading: () => const SizedBox(
            height: 120,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => Text('Erro ao carregar alunos: $error'),
          data: (rows) => SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String>(
                value: _childId,
                decoration: const InputDecoration(labelText: 'Aluno *'),
                items: [
                  for (final row in rows)
                    DropdownMenuItem(
                      value: row['id'].toString(),
                      child: Text(
                        '${row['first_name'] ?? ''} ${row['last_name'] ?? ''}'
                            .trim(),
                      ),
                    ),
                ],
                onChanged: (value) => setState(() => _childId = value),
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Início'),
                subtitle: Text(
                  '${_startDate.day.toString().padLeft(2, '0')}/'
                  '${_startDate.month.toString().padLeft(2, '0')}/'
                  '${_startDate.year}',
                ),
                trailing: const Icon(Icons.calendar_today_outlined),
                onTap: () async {
                  final value = await showDatePicker(
                    context: context,
                    initialDate: _startDate,
                    firstDate: DateTime(2000),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (value != null) setState(() => _startDate = value);
                },
              ),
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Se o aluno já tiver transporte, a rota anterior termina na '
                  'véspera desta data.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ]),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'A atribuir…' : 'Atribuir'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (_childId == null) {
      setState(() => _error = 'Seleccione o aluno.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(apiClientProvider).post(
        '/billing/transport/routes/${widget.routeId}/assign',
        data: {
          'child_id': _childId,
          'start_date':
              '${_startDate.year}-${_startDate.month.toString().padLeft(2, '0')}'
                  '-${_startDate.day.toString().padLeft(2, '0')}',
        },
      );
      if (mounted) Navigator.pop(context, 'Transporte atribuído ao aluno.');
    } catch (error) {
      setState(() {
        _saving = false;
        _error = error.toString();
      });
    }
  }
}
