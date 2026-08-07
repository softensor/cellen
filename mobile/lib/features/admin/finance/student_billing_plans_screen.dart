import 'package:cellen/core/api/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

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
      onAdd: () => _showCreate(context, ref),
    );
    if (embedded) return body;
    return Scaffold(
      appBar: AppBar(title: const Text('Planos de Cobrança')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreate(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Novo Plano'),
      ),
      body: body,
    );
  }

  Future<void> _showCreate(BuildContext context, WidgetRef ref) async {
    final created = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (_) => const _CreateBillingPlanDialog(),
    );
    if (created == true) ref.invalidate(_billingPlansProvider);
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
      error: (error, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off_outlined, size: 48),
            const SizedBox(height: 12),
            Text('Não foi possível carregar os planos: $error',
                textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(
                onPressed: () => ref.invalidate(_billingPlansProvider),
                child: const Text('Tentar novamente')),
          ]),
        ),
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
                'Um plano liga o aluno, o responsável e vários serviços. A recorrência e as facturas são geridas pelo Finreg.',
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add),
                label: const Text('Criar primeiro plano')),
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
    final total = lines.fold<double>(0, (sum, raw) {
      final line = Map<String, dynamic>.from(raw);
      final quantity = (line['quantity'] as num?)?.toDouble() ?? 0;
      final price = (line['unit_price'] as num?)?.toDouble() ?? 0;
      final discount = (line['discount_pct'] as num?)?.toDouble() ?? 0;
      return sum + quantity * price * (1 - discount / 100);
    });
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
            return Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(children: [
                Expanded(
                    child: Text(line['description']?.toString() ?? 'Serviço')),
                Text(NumberFormat.currency(locale: 'pt_AO', symbol: 'Kz')
                    .format((line['unit_price'] as num?) ?? 0)),
              ]),
            );
          }),
          const SizedBox(height: 6),
          Row(children: [
            Text(
                '${_frequency(plan['frequency']?.toString())} · próxima ${plan['next_run_date'] ?? '—'}'),
            const Spacer(),
            Text(
                NumberFormat.currency(locale: 'pt_AO', symbol: 'Kz')
                    .format(total),
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ]),
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
      if (context.mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro: $error')));
    }
  }
}

class _CreateBillingPlanDialog extends ConsumerStatefulWidget {
  const _CreateBillingPlanDialog();
  @override
  ConsumerState<_CreateBillingPlanDialog> createState() =>
      _CreateBillingPlanDialogState();
}

class _CreateBillingPlanDialogState
    extends ConsumerState<_CreateBillingPlanDialog> {
  String? pupilId;
  String? guardianId;
  final selectedItems = <String>{};
  String frequency = 'monthly';
  DateTime nextRun = DateTime.now();
  bool saving = false;
  String? error;

  Future<List<dynamic>> _load(String path) async =>
      await ref.read(apiClientProvider).get(path) as List;

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Novo Plano de Cobrança'),
        content: SizedBox(
          width: 560,
          child: FutureBuilder<List<List<dynamic>>>(
            future: Future.wait([
              _load('/children'),
              _load('/guardians'),
              _load('/finance/billing-items')
            ]),
            builder: (context, snapshot) {
              if (!snapshot.hasData)
                return const SizedBox(
                    height: 180,
                    child: Center(child: CircularProgressIndicator()));
              final pupils = snapshot.data![0];
              final guardians = snapshot.data![1];
              final items = snapshot.data![2]
                  .where((raw) => (raw as Map)['is_active'] != false)
                  .toList();
              return StatefulBuilder(
                  builder: (context, setLocal) => SingleChildScrollView(
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                        DropdownButtonFormField<String>(
                          value: pupilId,
                          decoration:
                              const InputDecoration(labelText: 'Aluno *'),
                          items: pupils.map((raw) {
                            final v = raw as Map;
                            return DropdownMenuItem(
                                value: v['id'].toString(),
                                child: Text(
                                    '${v['first_name']} ${v['last_name']}'));
                          }).toList(),
                          onChanged: (value) => setLocal(() => pupilId = value),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          value: guardianId,
                          decoration: const InputDecoration(
                              labelText: 'Responsável pelo pagamento *'),
                          items: guardians.map((raw) {
                            final v = raw as Map;
                            return DropdownMenuItem(
                                value: v['id'].toString(),
                                child: Text(
                                    '${v['first_name']} ${v['last_name']}'));
                          }).toList(),
                          onChanged: (value) =>
                              setLocal(() => guardianId = value),
                        ),
                        const SizedBox(height: 16),
                        const Align(
                            alignment: Alignment.centerLeft,
                            child: Text('Serviços incluídos *',
                                style: TextStyle(fontWeight: FontWeight.w600))),
                        ...items.map((raw) {
                          final v = raw as Map;
                          final id = v['id'].toString();
                          return CheckboxListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            value: selectedItems.contains(id),
                            title: Text(v['name'].toString()),
                            subtitle: Text(
                                '${v['unit_price']} Kz · IVA ${v['iva_rate']}%'),
                            onChanged: (checked) => setLocal(() =>
                                checked == true
                                    ? selectedItems.add(id)
                                    : selectedItems.remove(id)),
                          );
                        }),
                        DropdownButtonFormField<String>(
                          value: frequency,
                          decoration:
                              const InputDecoration(labelText: 'Periodicidade'),
                          items: const [
                            DropdownMenuItem(
                                value: 'monthly', child: Text('Mensal')),
                            DropdownMenuItem(
                                value: 'quarterly', child: Text('Trimestral')),
                            DropdownMenuItem(
                                value: 'annual', child: Text('Anual'))
                          ],
                          onChanged: (value) =>
                              setLocal(() => frequency = value ?? 'monthly'),
                        ),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Primeira cobrança'),
                          subtitle:
                              Text(DateFormat('dd/MM/yyyy').format(nextRun)),
                          trailing: const Icon(Icons.calendar_today_outlined),
                          onTap: () async {
                            final value = await showDatePicker(
                                context: context,
                                firstDate: DateTime.now(),
                                lastDate: DateTime.now()
                                    .add(const Duration(days: 730)),
                                initialDate: nextRun);
                            if (value != null) setLocal(() => nextRun = value);
                          },
                        ),
                        if (error != null)
                          Text(error!,
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.error)),
                      ])));
            },
          ),
        ),
        actions: [
          TextButton(
              onPressed: saving ? null : () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: saving ? null : _save,
              child: saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Criar plano')),
        ],
      );

  Future<void> _save() async {
    if (pupilId == null || guardianId == null || selectedItems.isEmpty) {
      setState(() =>
          error = 'Seleccione o aluno, o responsável e pelo menos um serviço.');
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    final externalId = DateTime.now()
        .microsecondsSinceEpoch
        .toRadixString(16)
        .padLeft(32, '0');
    final uuid =
        '${externalId.substring(0, 8)}-${externalId.substring(8, 12)}-${externalId.substring(12, 16)}-${externalId.substring(16, 20)}-${externalId.substring(20, 32)}';
    try {
      await ref
          .read(apiClientProvider)
          .put('/finreg/billing-plans/$uuid', data: {
        'external_id': uuid,
        'guardian_id': guardianId,
        'pupil_id': pupilId,
        'frequency': frequency,
        'interval_count': 1,
        'due_days': 10,
        'next_run_date': DateFormat('yyyy-MM-dd').format(nextRun),
        'lines': selectedItems
            .map((id) =>
                {'billing_item_id': id, 'quantity': 1, 'discount_pct': 0})
            .toList(),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (value) {
      setState(() {
        saving = false;
        error = value.toString();
      });
    }
  }
}
