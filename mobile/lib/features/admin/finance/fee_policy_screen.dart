import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/widgets/app_error_widget.dart';
import 'fee_automation_common.dart';

final _feePolicyProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final data =
      await ref.read(apiClientProvider).get('/billing/fee-policy') as Map;
  return Map<String, dynamic>.from(data);
});

class FeePolicyScreen extends ConsumerWidget {
  const FeePolicyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final policy = ref.watch(_feePolicyProvider);
    final items = ref.watch(feeBillingItemsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Política de Propinas'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(_feePolicyProvider),
          ),
        ],
      ),
      body: policy.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => AppErrorWidget(
          error: error,
          onRetry: () => ref.invalidate(_feePolicyProvider),
        ),
        data: (data) => items.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => AppErrorWidget(
            error: error,
            onRetry: () => ref.invalidate(feeBillingItemsProvider),
          ),
          data: (billingItems) => _PolicyForm(
            key: ValueKey(
              '${(data['policy'] as Map?)?['id']}-'
              '${(data['school_year'] as Map?)?['id']}',
            ),
            data: data,
            billingItems: billingItems,
          ),
        ),
      ),
    );
  }
}

class _PolicyForm extends ConsumerStatefulWidget {
  const _PolicyForm({
    super.key,
    required this.data,
    required this.billingItems,
  });

  final Map<String, dynamic> data;
  final List<Map<String, dynamic>> billingItems;

  @override
  ConsumerState<_PolicyForm> createState() => _PolicyFormState();
}

class _PolicyFormState extends ConsumerState<_PolicyForm> {
  final _enrollmentFee = TextEditingController();
  final _siblingPct = TextEditingController();
  final _minChildren = TextEditingController();
  final _billingDay = TextEditingController();
  final _dueDays = TextEditingController();

  String? _tuitionItemId;
  String _scope = 'additional_children';
  String _proration = 'pro_rata_days';
  bool _autoGenerate = false;
  bool _saving = false;

  Map<String, dynamic> get _policy =>
      Map<String, dynamic>.from(widget.data['policy'] as Map? ?? {});
  Map<String, dynamic> get _year =>
      Map<String, dynamic>.from(widget.data['school_year'] as Map? ?? {});

  @override
  void initState() {
    super.initState();
    final policy = _policy;
    _enrollmentFee.text = policy['default_enrollment_fee'] == null
        ? ''
        : moneyText(policy['default_enrollment_fee']);
    _siblingPct.text = moneyText(policy['sibling_discount_pct']);
    _minChildren.text =
        (policy['sibling_discount_min_children'] ?? 2).toString();
    _billingDay.text = (policy['billing_day'] ?? 1).toString();
    _dueDays.text = (policy['due_days'] ?? 5).toString();
    _tuitionItemId = policy['default_tuition_billing_item_id']?.toString();
    _scope =
        policy['sibling_discount_scope']?.toString() ?? 'additional_children';
    _proration = policy['proration_policy']?.toString() ?? 'pro_rata_days';
    _autoGenerate = policy['auto_generate'] == true;
  }

  @override
  void dispose() {
    _enrollmentFee.dispose();
    _siblingPct.dispose();
    _minChildren.dispose();
    _billingDay.dispose();
    _dueDays.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDefault = _policy['is_default'] == true;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              const Icon(Icons.tune_outlined, size: 32),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ano letivo ${_year['year_label'] ?? '—'}',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isDefault
                          ? 'Ainda usa os valores padrão. Guarde para personalizar.'
                          : 'Valores aplicados a todas as cobranças deste ano letivo.',
                    ),
                  ],
                ),
              ),
              Chip(label: Text(isDefault ? 'Padrão' : 'Personalizada')),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        _Section(
          title: 'Propina e matrícula',
          icon: Icons.school_outlined,
          children: [
            DropdownButtonFormField<String?>(
              value: _tuitionItemId,
              decoration: const InputDecoration(
                labelText: 'Serviço fiscal da propina',
                helperText: 'Usado quando o aluno não tem valor próprio.',
              ),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Sem serviço predefinido'),
                ),
                for (final item in widget.billingItems)
                  DropdownMenuItem<String?>(
                    value: item['id'].toString(),
                    child: Text(
                      '${item['name']} · ${moneyText(item['unit_price'])} Kz'
                      '${item['is_active'] == false ? ' (inactivo)' : ''}',
                    ),
                  ),
              ],
              onChanged: (value) => setState(() => _tuitionItemId = value),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _enrollmentFee,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Matrícula padrão (Kz)',
                helperText: 'Deixe vazio para não aplicar nenhuma matrícula.',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _Section(
          title: 'Desconto de irmãos',
          icon: Icons.family_restroom_outlined,
          children: [
            Row(children: [
              Expanded(
                child: TextFormField(
                  controller: _siblingPct,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration:
                      const InputDecoration(labelText: 'Percentagem (%)'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _minChildren,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Mínimo de filhos',
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _scope,
              decoration: const InputDecoration(labelText: 'Aplicar a'),
              items: const [
                DropdownMenuItem(
                  value: 'additional_children',
                  child: Text('Apenas a partir do 2.º filho'),
                ),
                DropdownMenuItem(
                  value: 'all_children',
                  child: Text('Todos os filhos'),
                ),
              ],
              onChanged: (value) =>
                  setState(() => _scope = value ?? 'additional_children'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _Section(
          title: 'Calendário de cobrança',
          icon: Icons.event_repeat_outlined,
          children: [
            Row(children: [
              Expanded(
                child: TextFormField(
                  controller: _billingDay,
                  keyboardType: TextInputType.number,
                  decoration:
                      const InputDecoration(labelText: 'Dia de cobrança'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _dueDays,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Dias até ao vencimento'),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _proration,
              decoration: const InputDecoration(
                labelText: 'Mês de entrada do aluno',
              ),
              items: const [
                DropdownMenuItem(
                  value: 'pro_rata_days',
                  child: Text('Cobrar proporcional aos dias'),
                ),
                DropdownMenuItem(
                  value: 'full_month',
                  child: Text('Cobrar o mês completo'),
                ),
                DropdownMenuItem(
                  value: 'no_charge',
                  child: Text('Não cobrar no mês de entrada'),
                ),
              ],
              onChanged: (value) =>
                  setState(() => _proration = value ?? 'pro_rata_days'),
            ),
            const SizedBox(height: 4),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Gerar dívidas automaticamente'),
              subtitle: const Text(
                'No dia de cobrança, o sistema prepara as cobranças do mês.',
              ),
              value: _autoGenerate,
              onChanged: (value) => setState(() => _autoGenerate = value),
            ),
          ],
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined),
          label: const Text('Guardar política'),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Future<void> _save() async {
    final pct = parseMoney(_siblingPct.text);
    final minChildren = int.tryParse(_minChildren.text.trim()) ?? 2;
    final billingDay = int.tryParse(_billingDay.text.trim()) ?? 1;
    final dueDays = int.tryParse(_dueDays.text.trim()) ?? 5;
    if (pct < 0 || pct > 100) {
      _snack('A percentagem de desconto deve estar entre 0 e 100.');
      return;
    }
    if (minChildren < 1 || billingDay < 1 || billingDay > 31 || dueDays < 0) {
      _snack('Confirme o mínimo de filhos, o dia e os dias de vencimento.');
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(apiClientProvider).put('/billing/fee-policy', data: {
        'school_year_id': _year['id'],
        'default_tuition_billing_item_id': _tuitionItemId,
        'default_enrollment_fee': _enrollmentFee.text.trim().isEmpty
            ? null
            : parseMoney(_enrollmentFee.text),
        'sibling_discount_pct': pct,
        'sibling_discount_min_children': minChildren,
        'sibling_discount_scope': _scope,
        'due_days': dueDays,
        'billing_day': billingDay,
        'auto_generate': _autoGenerate,
        'proration_policy': _proration,
      });
      if (!mounted) return;
      ref.invalidate(_feePolicyProvider);
      _snack(
          'Política guardada. Os planos serão reconstruídos na próxima geração.');
    } catch (error) {
      if (mounted) _snack('Não foi possível guardar: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ]),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      ),
    );
  }
}
