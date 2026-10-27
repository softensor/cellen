import 'package:cellen/core/api/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/widgets/app_error_widget.dart';
import 'fee_automation_common.dart';

final _billingPlansProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final rows =
      await ref.read(apiClientProvider).get('/finreg/billing-plans') as List;
  return rows.map((row) => Map<String, dynamic>.from(row as Map)).toList();
});

class StudentBillingPlansScreen extends ConsumerWidget {
  const StudentBillingPlansScreen({super.key, this.embedded = false});
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final body = _StudentBillingPlansBody(
      onAdd: () => _showProfileEditor(context, ref),
    );
    if (embedded) return body;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Planos de Cobrança'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(_billingPlansProvider),
          ),
          IconButton(
            tooltip: 'Reconstruir planos',
            icon: const Icon(Icons.sync_outlined),
            onPressed: () => _rebuildPlans(context, ref),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showProfileEditor(context, ref),
        icon: const Icon(Icons.person_search_outlined),
        label: const Text('Ficha do aluno'),
      ),
      body: body,
    );
  }

  Future<void> _showProfileEditor(BuildContext context, WidgetRef ref) async {
    final changed = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (_) => const _StudentFinanceDialog(),
    );
    if (changed == true) ref.invalidate(_billingPlansProvider);
  }

  Future<void> _rebuildPlans(BuildContext context, WidgetRef ref) async {
    try {
      final result = await ref.read(apiClientProvider).post(
        '/billing/rebuild-plans',
        data: const <String, dynamic>{},
      ) as Map;
      ref.invalidate(_billingPlansProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            'Planos actualizados: ${result['confirmed'] ?? 0} confirmados, '
            '${result['queued'] ?? 0} em fila, '
            '${result['unchanged'] ?? 0} sem alterações.',
          ),
        ));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro ao reconstruir: $error')));
      }
    }
  }
}

class _StudentBillingPlansBody extends ConsumerWidget {
  const _StudentBillingPlansBody({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plans = ref.watch(_billingPlansProvider);
    return plans.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => AppErrorWidget(
        error: error,
        onRetry: () => ref.invalidate(_billingPlansProvider),
      ),
      data: (rows) {
        if (rows.isEmpty) {
          return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.event_repeat_outlined, size: 56),
            const SizedBox(height: 12),
            const Text('Nenhum plano de cobrança'),
            const SizedBox(height: 6),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 28),
              child: Text(
                'A ficha financeira do aluno define a propina, o encarregado e o estado do plano. '
                'Os planos são enviados ao Finreg e as facturas emitidas por ele.',
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.person_search_outlined),
                label: const Text('Abrir ficha financeira')),
          ]));
        }
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(_billingPlansProvider),
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
            itemCount: rows.length,
            itemBuilder: (_, index) => _BillingPlanCard(plan: rows[index]),
          ),
        );
      },
    );
  }
}

class _BillingPlanCard extends ConsumerWidget {
  const _BillingPlanCard({required this.plan});
  final Map<String, dynamic> plan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contextData =
        Map<String, dynamic>.from(plan['school_context'] as Map? ?? {});
    final lines = (plan['lines'] as List? ?? const []).cast<Map>();
    final active = plan['is_active'] == true;
    var gross = 0.0;
    var total = 0.0;
    for (final raw in lines) {
      final line = Map<String, dynamic>.from(raw);
      final quantity = (line['quantity'] as num?)?.toDouble() ?? 0;
      final price = (line['unit_price'] as num?)?.toDouble() ?? 0;
      final discount = (line['discount_pct'] as num?)?.toDouble() ?? 0;
      gross += quantity * price;
      total += quantity * price * (1 - discount / 100);
    }
    final discountTotal = gross - total;
    final currency = NumberFormat.currency(locale: 'pt_AO', symbol: 'Kz');
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
                child: Text(contextData['pupil_name']?.toString() ?? 'Aluno',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700))),
            Chip(label: Text(active ? 'Activo' : 'Pausado')),
          ]),
          if (contextData['academic_year_label'] != null)
            Text('Ano lectivo ${contextData['academic_year_label']}',
                style: Theme.of(context).textTheme.bodySmall),
          const Divider(height: 24),
          ...lines.map((raw) {
            final line = Map<String, dynamic>.from(raw);
            final discount = (line['discount_pct'] as num?)?.toDouble() ?? 0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(children: [
                Expanded(
                    child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(line['description']?.toString() ?? 'Serviço'),
                    if (discount > 0)
                      Text(
                        'Desconto ${moneyText(discount)}%',
                        style: const TextStyle(fontSize: 11),
                      ),
                  ],
                )),
                Text(currency.format((line['unit_price'] as num?) ?? 0)),
              ]),
            );
          }),
          const SizedBox(height: 6),
          if (discountTotal > 0)
            Row(children: [
              const Expanded(child: Text('Desconto aplicado')),
              Text('- ${currency.format(discountTotal)}',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ]),
          Row(children: [
            Text(
                '${_frequency(plan['frequency']?.toString())} · próxima ${formatIsoDate(plan['next_run_date']?.toString())}'),
            const Spacer(),
            Text(currency.format(total),
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 4),
          Text(
            'Plano ${plan['external_id'] ?? '—'}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () =>
                  _changeState(context, ref, active ? 'pause' : 'resume'),
              icon: Icon(active
                  ? Icons.pause_circle_outline
                  : Icons.play_circle_outline),
              label: Text(active ? 'Pausar' : 'Retomar'),
            ),
          ),
        ]),
      ),
    );
  }

  static String _frequency(String? value) => switch (value) {
        'weekly' => 'Semanal',
        'monthly' => 'Mensal',
        'quarterly' => 'Trimestral',
        'annual' => 'Anual',
        _ => value ?? '—'
      };

  Future<void> _changeState(
      BuildContext context, WidgetRef ref, String action) async {
    final reason =
        action == 'pause' ? 'Pausado pelo administrador da escola' : null;
    try {
      await ref.read(apiClientProvider).post(
          '/finreg/billing-plans/${plan['external_id']}/$action',
          data: {'reason': reason});
      ref.invalidate(_billingPlansProvider);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro: $error')));
      }
    }
  }
}

class _StudentFinanceData {
  const _StudentFinanceData({required this.profile, required this.guardians});

  final Map<String, dynamic> profile;
  final List<Map<String, dynamic>> guardians;
}

class _StudentFinanceDialog extends ConsumerStatefulWidget {
  const _StudentFinanceDialog();

  @override
  ConsumerState<_StudentFinanceDialog> createState() =>
      _StudentFinanceDialogState();
}

class _StudentFinanceDialogState extends ConsumerState<_StudentFinanceDialog> {
  String? _pupilId;
  Future<_StudentFinanceData>? _loading;

  Future<_StudentFinanceData> _load(String childId) async {
    final api = ref.read(apiClientProvider);
    final results = await Future.wait([
      api.get('/billing/students/$childId/profile'),
      api.get('/children/$childId/guardians'),
    ]);
    return _StudentFinanceData(
      profile: Map<String, dynamic>.from(results[0] as Map),
      guardians: (results[1] as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final students = ref.watch(feeStudentsProvider);
    return AlertDialog(
      title: const Text('Ficha financeira do aluno'),
      content: SizedBox(
        width: 560,
        child: students.when(
          loading: () => const SizedBox(
            height: 160,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => Text('Erro ao carregar alunos: $error'),
          data: (rows) => SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String>(
                value: _pupilId,
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
                onChanged: (value) => setState(() {
                  _pupilId = value;
                  _loading = value == null ? null : _load(value);
                }),
              ),
              const SizedBox(height: 8),
              if (_loading == null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'Seleccione o aluno para editar a propina, o encarregado de '
                    'facturação e o estado do plano.',
                    textAlign: TextAlign.center,
                  ),
                )
              else
                FutureBuilder<_StudentFinanceData>(
                  future: _loading,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    if (snapshot.hasError) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child:
                            Text('Erro ao carregar a ficha: ${snapshot.error}'),
                      );
                    }
                    final data = snapshot.data!;
                    return Column(children: [
                      _ProfileFields(
                        data: data,
                        onSaved: () => Navigator.pop(context, true),
                      ),
                      const Padding(
                        padding: EdgeInsets.only(top: 10),
                        child: Text(
                          'Depois de guardar, use Reconstruir planos para '
                          'enviar a alteração ao Finreg.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ]);
                  },
                ),
            ]),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Fechar'),
        ),
      ],
    );
  }
}

class _ProfileFields extends ConsumerStatefulWidget {
  const _ProfileFields({required this.data, required this.onSaved});

  final _StudentFinanceData data;
  final VoidCallback onSaved;

  @override
  ConsumerState<_ProfileFields> createState() => _ProfileFieldsState();
}

class _ProfileFieldsState extends ConsumerState<_ProfileFields> {
  late final TextEditingController _tuitionOverride;
  late final TextEditingController _billingDay;
  String? _guardianId;
  String _status = 'active';
  bool _saving = false;
  String? _error;

  Map<String, dynamic> get _profile =>
      Map<String, dynamic>.from(widget.data.profile['profile'] as Map? ?? {});
  Map<String, dynamic> get _year => Map<String, dynamic>.from(
      widget.data.profile['school_year'] as Map? ?? {});

  @override
  void initState() {
    super.initState();
    final profile = _profile;
    _tuitionOverride = TextEditingController(
      text: profile['tuition_override'] == null
          ? ''
          : (profile['tuition_override'] as num).toString(),
    );
    _billingDay = TextEditingController(
      text: (profile['billing_day'] ?? 1).toString(),
    );
    _guardianId = profile['billing_guardian_id']?.toString();
    _status = profile['status']?.toString() ?? 'active';
  }

  @override
  void dispose() {
    _tuitionOverride.dispose();
    _billingDay.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        Expanded(
          child: Text(
            'Ano letivo ${_year['year_label'] ?? '—'} · propina actual '
            '${moneyText(_profile['effective_tuition_price'])} Kz',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ]),
      const SizedBox(height: 10),
      TextField(
        controller: _tuitionOverride,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(
          labelText: 'Propina mensal própria (Kz)',
          helperText: 'Deixe vazio para usar o valor padrão da escola.',
        ),
      ),
      const SizedBox(height: 10),
      DropdownButtonFormField<String?>(
        value: _guardianId,
        decoration:
            const InputDecoration(labelText: 'Encarregado de facturação'),
        items: [
          const DropdownMenuItem<String?>(
            value: null,
            child: Text('Automático (primeiro encarregado)'),
          ),
          for (final guardian in widget.data.guardians)
            DropdownMenuItem<String?>(
              value: guardian['id'].toString(),
              child: Text(
                '${guardian['first_name'] ?? ''} ${guardian['last_name'] ?? ''}'
                    .trim(),
              ),
            ),
        ],
        onChanged: (value) => setState(() => _guardianId = value),
      ),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(
          child: TextField(
            controller: _billingDay,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Dia de cobrança'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: DropdownButtonFormField<String>(
            value: _status,
            decoration: const InputDecoration(labelText: 'Estado do plano'),
            items: const [
              DropdownMenuItem(value: 'active', child: Text('Activo')),
              DropdownMenuItem(value: 'paused', child: Text('Pausado')),
              DropdownMenuItem(value: 'withdrawn', child: Text('Encerrado')),
            ],
            onChanged: (value) => setState(() => _status = value ?? 'active'),
          ),
        ),
      ]),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      const SizedBox(height: 10),
      FilledButton.icon(
        onPressed: _saving ? null : _save,
        icon: _saving
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.save_outlined),
        label: const Text('Guardar ficha'),
      ),
    ]);
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final profile = _profile;
      await ref.read(apiClientProvider).put(
        '/billing/students/${profile['child_id']}/profile',
        data: {
          'school_year_id': _year['id'],
          'billing_guardian_id': _guardianId,
          'tuition_override': _tuitionOverride.text.trim().isEmpty
              ? null
              : parseMoney(_tuitionOverride.text),
          'billing_day': int.tryParse(_billingDay.text.trim()),
          'status': _status,
        },
      );
      widget.onSaved();
    } catch (error) {
      setState(() {
        _saving = false;
        _error = error.toString();
      });
    }
  }
}
