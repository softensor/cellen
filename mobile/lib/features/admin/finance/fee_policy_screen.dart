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
  final _dunningTemplate = TextEditingController();

  String? _tuitionItemId;
  String _scope = 'additional_children';
  String _proration = 'pro_rata_days';
  bool _autoGenerate = false;
  bool _saving = false;
  bool _lateFeeEnabled = false;
  String? _lateFeeItemId;
  String _lateFeeBase = 'outstanding';
  List<Map<String, dynamic>> _bands = [];
  bool _dunningEnabled = false;
  List<Map<String, dynamic>> _schedule = [];

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
    _lateFeeEnabled = policy['late_fee_enabled'] == true;
    _lateFeeItemId = policy['late_fee_billing_item_id']?.toString();
    _lateFeeBase = policy['late_fee_base']?.toString() ?? 'outstanding';
    _bands = _mapList(policy['late_fee_bands']);
    _dunningEnabled = policy['dunning_enabled'] == true;
    _schedule = _mapList(policy['dunning_schedule']);
    _dunningTemplate.text =
        policy['dunning_message_template']?.toString() ?? '';
  }

  List<Map<String, dynamic>> _mapList(dynamic value) {
    if (value is! List) return [];
    return value
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  @override
  void dispose() {
    _enrollmentFee.dispose();
    _siblingPct.dispose();
    _minChildren.dispose();
    _billingDay.dispose();
    _dueDays.dispose();
    _dunningTemplate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDefault = _policy['is_default'] == true;
    final lateItemKnown = widget.billingItems
        .any((item) => item['id'].toString() == _lateFeeItemId);
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
        const SizedBox(height: 12),
        _Section(
          title: 'Multas por atraso',
          icon: Icons.gavel_outlined,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Cobrar multa por atraso'),
              subtitle: const Text(
                'As multas são calculadas nesta escola e emitidas como nota '
                'de débito fiscal.',
              ),
              value: _lateFeeEnabled,
              onChanged: (value) => setState(() => _lateFeeEnabled = value),
            ),
            if (_lateFeeEnabled) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<String?>(
                value: lateItemKnown ? _lateFeeItemId : null,
                decoration: const InputDecoration(
                  labelText: 'Serviço fiscal da multa',
                  helperText:
                      'Obrigatório: todas as multas são emitidas por este serviço.',
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Escolher serviço'),
                  ),
                  for (final item in widget.billingItems)
                    DropdownMenuItem<String?>(
                      value: item['id'].toString(),
                      child: Text(
                        '${item['name']}'
                        '${item['is_active'] == false ? ' (inactivo)' : ''}',
                      ),
                    ),
                ],
                onChanged: (value) => setState(() => _lateFeeItemId = value),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _lateFeeBase,
                decoration: const InputDecoration(
                  labelText: 'Calcular a multa sobre',
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'outstanding',
                    child: Text('O saldo ainda em dívida'),
                  ),
                  DropdownMenuItem(
                    value: 'document_total',
                    child: Text('O valor total do documento'),
                  ),
                ],
                onChanged: (value) =>
                    setState(() => _lateFeeBase = value ?? 'outstanding'),
              ),
              const SizedBox(height: 12),
              for (final band in _bands)
                _BandCard(
                  key: ValueKey('band-${band['id']}'),
                  band: band,
                  onChanged: (value) => _replaceBand(value),
                  onRemove: () => setState(() =>
                      _bands.removeWhere((row) => row['id'] == band['id'])),
                ),
              OutlinedButton.icon(
                onPressed: _addBand,
                icon: const Icon(Icons.add),
                label: const Text('Adicionar faixa'),
              ),
              const SizedBox(height: 8),
              Text(
                'Exemplo da direção: 10% do dia 10 até ao fim do mês do '
                'vencimento; 15% a partir do dia 10 do mês seguinte. A multa '
                'é sempre aplicada por acréscimo — nunca duas vezes.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        _Section(
          title: 'Lembretes de cobrança',
          icon: Icons.notifications_active_outlined,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Enviar lembretes automáticos'),
              subtitle: const Text(
                'Cada nível é enviado uma única vez, após o número de dias '
                'configurado.',
              ),
              value: _dunningEnabled,
              onChanged: (value) => setState(() => _dunningEnabled = value),
            ),
            if (_dunningEnabled) ...[
              const SizedBox(height: 8),
              for (final step in _schedule)
                _StepCard(
                  key: ValueKey('step-${step['level']}'),
                  step: step,
                  onChanged: (value) => _replaceStep(value),
                  onRemove: () => setState(() => _schedule
                      .removeWhere((row) => row['level'] == step['level'])),
                ),
              OutlinedButton.icon(
                onPressed: _addStep,
                icon: const Icon(Icons.add),
                label: const Text('Adicionar nível'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _dunningTemplate,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Mensagem (opcional)',
                  helperText: 'Marcadores: {guardian_name}, {student_name}, '
                      '{document_number}, {amount}, {due_date}, {days_overdue}.',
                ),
              ),
            ],
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

  void _addBand() {
    final index = _bands.length + 1;
    setState(() {
      _bands.add({
        'id': 'band-${DateTime.now().microsecondsSinceEpoch}',
        'label': 'Faixa $index',
        'anchor': 'due_month',
        'start_day': index == 1 ? 10 : 10,
        'end_day': null,
        'percent': index == 1 ? 10.0 : 15.0,
        'min_amount': null,
        'max_amount': null,
      });
    });
  }

  void _replaceBand(Map<String, dynamic> value) {
    setState(() {
      final index = _bands.indexWhere((row) => row['id'] == value['id']);
      if (index >= 0) _bands[index] = value;
    });
  }

  void _addStep() {
    final levels = _schedule.map((row) => row['level'] as int? ?? 0).toList();
    final level =
        levels.isEmpty ? 1 : levels.reduce((a, b) => a > b ? a : b) + 1;
    setState(() {
      _schedule.add({
        'level': level,
        'offset_days': level == 1 ? 5 : 30,
        'channels': const ['in_app'],
        'message': null,
      });
    });
  }

  void _replaceStep(Map<String, dynamic> value) {
    setState(() {
      final index =
          _schedule.indexWhere((row) => row['level'] == value['level']);
      if (index >= 0) _schedule[index] = value;
    });
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
    if (_lateFeeEnabled) {
      if (_lateFeeItemId == null) {
        _snack('Escolha o serviço fiscal usado para emitir a multa.');
        return;
      }
      if (_bands.isEmpty) {
        _snack('Active as multas e defina pelo menos uma faixa.');
        return;
      }
      for (final band in _bands) {
        final start = band['start_day'] as int? ?? 0;
        final end = band['end_day'] as int?;
        final bandPct = (band['percent'] as num?)?.toDouble() ?? 0;
        if (start < 1 ||
            start > 31 ||
            (end != null && (end < start || end > 31)) ||
            bandPct <= 0 ||
            bandPct > 100) {
          _snack('Confirme os dias e a percentagem de cada faixa de multa.');
          return;
        }
      }
    }
    if (_dunningEnabled) {
      if (_schedule.isEmpty) {
        _snack('Active os lembretes e defina pelo menos um nível.');
        return;
      }
      for (final step in _schedule) {
        final channels = (step['channels'] as List?) ?? const [];
        if (channels.isEmpty) {
          _snack('Cada nível de lembrete precisa de pelo menos um canal.');
          return;
        }
      }
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
        'late_fee_enabled': _lateFeeEnabled,
        'late_fee_billing_item_id': _lateFeeItemId,
        'late_fee_base': _lateFeeBase,
        'late_fee_bands': _lateFeeEnabled ? _bands : const [],
        'dunning_enabled': _dunningEnabled,
        'dunning_schedule': _dunningEnabled ? _schedule : const [],
        'dunning_message_template': _dunningTemplate.text.trim().isEmpty
            ? null
            : _dunningTemplate.text.trim(),
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

class _BandCard extends StatefulWidget {
  const _BandCard({
    super.key,
    required this.band,
    required this.onChanged,
    required this.onRemove,
  });

  final Map<String, dynamic> band;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final VoidCallback onRemove;

  @override
  State<_BandCard> createState() => _BandCardState();
}

class _BandCardState extends State<_BandCard> {
  late final TextEditingController _label;
  late final TextEditingController _start;
  late final TextEditingController _end;
  late final TextEditingController _percent;
  late final TextEditingController _min;
  late final TextEditingController _max;
  late String _anchor;

  @override
  void initState() {
    super.initState();
    final band = widget.band;
    _label = TextEditingController(text: band['label']?.toString() ?? '');
    _start = TextEditingController(text: '${band['start_day'] ?? 10}');
    _end = TextEditingController(
        text: band['end_day'] == null ? '' : '${band['end_day']}');
    _percent = TextEditingController(text: moneyText(band['percent']));
    _min = TextEditingController(
        text: band['min_amount'] == null ? '' : moneyText(band['min_amount']));
    _max = TextEditingController(
        text: band['max_amount'] == null ? '' : moneyText(band['max_amount']));
    _anchor = band['anchor']?.toString() ?? 'due_month';
  }

  @override
  void dispose() {
    for (final controller in [_label, _start, _end, _percent, _min, _max]) {
      controller.dispose();
    }
    super.dispose();
  }

  int? _int(TextEditingController controller) =>
      int.tryParse(controller.text.trim());

  void _emit() {
    widget.onChanged({
      'id': widget.band['id'],
      'label': _label.text.trim().isEmpty ? null : _label.text.trim(),
      'anchor': _anchor,
      'start_day': _int(_start) ?? 0,
      'end_day': _end.text.trim().isEmpty ? null : _int(_end),
      'percent': parseMoney(_percent.text),
      'min_amount': _min.text.trim().isEmpty ? null : parseMoney(_min.text),
      'max_amount': _max.text.trim().isEmpty ? null : parseMoney(_max.text),
    });
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: TextFormField(
                  controller: _label,
                  decoration: const InputDecoration(labelText: 'Nome da faixa'),
                  onChanged: (_) => _emit(),
                ),
              ),
              IconButton(
                tooltip: 'Remover faixa',
                onPressed: widget.onRemove,
                icon: const Icon(Icons.delete_outline),
              ),
            ]),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _anchor,
              decoration: const InputDecoration(labelText: 'Mês da faixa'),
              items: const [
                DropdownMenuItem(
                  value: 'due_month',
                  child: Text('Mês do vencimento'),
                ),
                DropdownMenuItem(
                  value: 'next_month',
                  child: Text('Mês seguinte'),
                ),
              ],
              onChanged: (value) {
                setState(() => _anchor = value ?? 'due_month');
                _emit();
              },
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextFormField(
                  controller: _start,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Dia inicial'),
                  onChanged: (_) => _emit(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _end,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Dia final',
                    helperText: 'Vazio = fim do mês',
                  ),
                  onChanged: (_) => _emit(),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextFormField(
                  controller: _percent,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration:
                      const InputDecoration(labelText: 'Percentagem (%)'),
                  onChanged: (_) => _emit(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _min,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Mínimo (Kz)'),
                  onChanged: (_) => _emit(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _max,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Máximo (Kz)'),
                  onChanged: (_) => _emit(),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

const _dunningChannelLabels = <String, String>{
  'in_app': 'Aplicação',
  'email': 'Email',
  'sms': 'SMS',
  'whatsapp': 'WhatsApp',
};

class _StepCard extends StatefulWidget {
  const _StepCard({
    super.key,
    required this.step,
    required this.onChanged,
    required this.onRemove,
  });

  final Map<String, dynamic> step;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final VoidCallback onRemove;

  @override
  State<_StepCard> createState() => _StepCardState();
}

class _StepCardState extends State<_StepCard> {
  late final TextEditingController _offset;
  late final TextEditingController _message;
  late Set<String> _channels;

  @override
  void initState() {
    super.initState();
    final step = widget.step;
    _offset = TextEditingController(text: '${step['offset_days'] ?? 5}');
    _message = TextEditingController(text: step['message']?.toString() ?? '');
    _channels = {
      for (final channel in (step['channels'] as List?) ?? const [])
        channel.toString(),
    };
    if (_channels.isEmpty) _channels = {'in_app'};
  }

  @override
  void dispose() {
    _offset.dispose();
    _message.dispose();
    super.dispose();
  }

  void _emit() {
    widget.onChanged({
      'level': widget.step['level'],
      'offset_days': int.tryParse(_offset.text.trim()) ?? 0,
      'channels': _channels.toList()..sort(),
      'message': _message.text.trim().isEmpty ? null : _message.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text(
                  'Nível ${widget.step['level']}',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                tooltip: 'Remover nível',
                onPressed: widget.onRemove,
                icon: const Icon(Icons.delete_outline),
              ),
            ]),
            TextFormField(
              controller: _offset,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Dias após o vencimento',
              ),
              onChanged: (_) => _emit(),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final entry in _dunningChannelLabels.entries)
                  FilterChip(
                    label: Text(entry.value),
                    selected: _channels.contains(entry.key),
                    onSelected: (selected) {
                      setState(() {
                        selected
                            ? _channels.add(entry.key)
                            : _channels.remove(entry.key);
                      });
                      _emit();
                    },
                  ),
              ],
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _message,
              decoration: const InputDecoration(
                labelText: 'Mensagem deste nível (opcional)',
              ),
              onChanged: (_) => _emit(),
            ),
          ],
        ),
      ),
    );
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
