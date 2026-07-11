import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_client.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/auth/auth_state.dart';
import '../../core/models/child.dart';
import '../../core/theme/app_theme.dart';

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------
class ChildEvaluation {
  final String id;
  final String childId;
  final String? childName;
  final String evaluationPeriod;
  final String evaluationDate;
  final int? cognitive;
  final int? motor;
  final int? language;
  final int? socialEmotional;
  final int? creativity;
  final int? autonomy;
  final String? overallRating;
  final String? observations;

  const ChildEvaluation({
    required this.id,
    required this.childId,
    this.childName,
    required this.evaluationPeriod,
    required this.evaluationDate,
    this.cognitive,
    this.motor,
    this.language,
    this.socialEmotional,
    this.creativity,
    this.autonomy,
    this.overallRating,
    this.observations,
  });

  factory ChildEvaluation.fromJson(Map<String, dynamic> json) {
    return ChildEvaluation(
      id: json['id']?.toString() ?? '',
      childId: json['child_id']?.toString() ?? '',
      childName: json['child_name'] as String?,
      evaluationPeriod: json['evaluation_period'] as String? ?? '',
      evaluationDate: json['evaluation_date'] as String? ?? '',
      cognitive: (json['cognitive'] as num?)?.toInt(),
      motor: (json['motor'] as num?)?.toInt(),
      language: (json['language'] as num?)?.toInt(),
      socialEmotional: (json['social_emotional'] as num?)?.toInt(),
      creativity: (json['creativity'] as num?)?.toInt(),
      autonomy: (json['autonomy'] as num?)?.toInt(),
      overallRating: json['overall_rating'] as String?,
      observations: json['observations'] as String?,
    );
  }
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------
final evaluationsProvider =
    FutureProvider.autoDispose<List<ChildEvaluation>>((ref) async {
  final api = ref.read(apiClientProvider);
  final auth = ref.read(authProvider);
  final data = auth.isParent
      ? await api.get('/evaluations') as List
      : await api.get('/evaluations') as List;
  return data
      .map((e) => ChildEvaluation.fromJson(e as Map<String, dynamic>))
      .toList();
});

final childrenForEvaluationProvider =
    FutureProvider.autoDispose<List<Child>>((ref) async {
  final api = ref.read(apiClientProvider);
  final auth = ref.read(authProvider);
  final endpoint = auth.isParent ? '/children/my' : '/children';
  final data = await api.get(endpoint) as List;
  return data.map((e) => Child.fromJson(e as Map<String, dynamic>)).toList();
});

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------
class EvaluationsScreen extends ConsumerStatefulWidget {
  const EvaluationsScreen({super.key});

  @override
  ConsumerState<EvaluationsScreen> createState() => _EvaluationsScreenState();
}

class _EvaluationsScreenState extends ConsumerState<EvaluationsScreen> {
  String? _periodFilter;

  static const _periods = ['1T', '2T', '3T', 'anual'];
  static const _periodLabels = {
    '1T': '1º Trimestre',
    '2T': '2º Trimestre',
    '3T': '3º Trimestre',
    'anual': 'Anual',
  };

  @override
  Widget build(BuildContext context) {
    final evaluationsAsync = ref.watch(evaluationsProvider);
    final auth = ref.watch(authProvider);
    final canCreate = auth.isAdmin || auth.isTeacher;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Avaliações'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(evaluationsProvider),
          ),
        ],
      ),
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              onPressed: () => _showCreateDialog(context),
              icon: const Icon(Icons.add),
              label: const Text('Nova Avaliação'),
            )
          : null,
      body: Column(
        children: [
          // Period filter
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: const Text('Todos'),
                      selected: _periodFilter == null,
                      showCheckmark: false,
                      selectedColor: AppTheme.primaryLight,
                      onSelected: (_) =>
                          setState(() => _periodFilter = null),
                    ),
                  ),
                  ..._periods.map((p) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: Text(_periodLabels[p] ?? p),
                          selected: _periodFilter == p,
                          showCheckmark: false,
                          selectedColor: AppTheme.primaryLight,
                          onSelected: (_) =>
                              setState(() => _periodFilter = p),
                        ),
                      )),
                ],
              ),
            ),
          ),

          Expanded(
            child: evaluationsAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline,
                        size: 48, color: AppTheme.danger),
                    const SizedBox(height: 8),
                    Text(e.toString(), textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () => ref.invalidate(evaluationsProvider),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Tentar novamente'),
                    ),
                  ],
                ),
              ),
              data: (evaluations) {
                final filtered = _periodFilter == null
                    ? evaluations
                    : evaluations
                        .where(
                            (e) => e.evaluationPeriod == _periodFilter)
                        .toList();

                if (filtered.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.school_outlined,
                            size: 64, color: Colors.grey.shade400),
                        const SizedBox(height: 16),
                        const Text('Nenhuma avaliação encontrada',
                            style: TextStyle(
                                color: AppTheme.textSecondary)),
                      ],
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async =>
                      ref.invalidate(evaluationsProvider),
                  child: ListView.builder(
                    padding:
                        const EdgeInsets.fromLTRB(12, 4, 12, 100),
                    itemCount: filtered.length,
                    itemBuilder: (context, i) =>
                        _EvaluationCard(evaluation: filtered[i]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showCreateDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => _CreateEvaluationDialog(
        onCreated: () => ref.invalidate(evaluationsProvider),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Evaluation card
// ---------------------------------------------------------------------------
class _EvaluationCard extends StatefulWidget {
  final ChildEvaluation evaluation;
  const _EvaluationCard({required this.evaluation});

  @override
  State<_EvaluationCard> createState() => _EvaluationCardState();
}

class _EvaluationCardState extends State<_EvaluationCard> {
  bool _expanded = false;

  String _periodLabel(String p) => switch (p) {
        '1T' => '1º Trimestre',
        '2T' => '2º Trimestre',
        '3T' => '3º Trimestre',
        'anual' => 'Anual',
        _ => p,
      };

  Color _ratingColor(String? r) => switch (r) {
        'Excelente' => AppTheme.success,
        'Bom' => AppTheme.primary,
        'Satisfatório' => AppTheme.warning,
        'Precisa Melhorar' => AppTheme.danger,
        _ => Colors.grey,
      };

  @override
  Widget build(BuildContext context) {
    final e = widget.evaluation;
    final theme = Theme.of(context);

    final dimensions = <String, int?>{
      'Cognitivo': e.cognitive,
      'Motor': e.motor,
      'Linguagem': e.language,
      'Social/Emocional': e.socialEmotional,
      'Criatividade': e.creativity,
      'Autonomia': e.autonomy,
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      e.childName ?? 'Criança',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE0F2FE),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _periodLabel(e.evaluationPeriod),
                      style: const TextStyle(
                          color: Color(0xFF0369A1),
                          fontSize: 11,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (e.overallRating != null) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color:
                            _ratingColor(e.overallRating).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        e.overallRating!,
                        style: TextStyle(
                            color: _ratingColor(e.overallRating),
                            fontSize: 11,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ],
              ),
              if (_expanded) ...[
                const SizedBox(height: 12),
                ...dimensions.entries
                    .where((entry) => entry.value != null)
                    .map((entry) => _ScoreRow(
                          label: entry.key,
                          score: entry.value!,
                        )),
                if (e.observations != null) ...[
                  const SizedBox(height: 8),
                  Text('Observações:',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(e.observations!,
                      style: const TextStyle(
                          color: AppTheme.textSecondary, fontSize: 13)),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ScoreRow extends StatelessWidget {
  final String label;
  final int score;

  const _ScoreRow({required this.label, required this.score});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 130,
            child: Text(label,
                style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
          ),
          Expanded(
            child: LinearProgressIndicator(
              value: score / 5,
              backgroundColor: AppTheme.border,
              color: AppTheme.primary,
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 8),
          Text('$score/5',
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.primary)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Create Evaluation Dialog
// ---------------------------------------------------------------------------
class _CreateEvaluationDialog extends ConsumerStatefulWidget {
  final VoidCallback onCreated;
  const _CreateEvaluationDialog({required this.onCreated});

  @override
  ConsumerState<_CreateEvaluationDialog> createState() =>
      _CreateEvaluationDialogState();
}

class _CreateEvaluationDialogState
    extends ConsumerState<_CreateEvaluationDialog> {
  final _formKey = GlobalKey<FormState>();
  final _obsCtrl = TextEditingController();
  String? _selectedChildId;
  String _period = '1T';
  DateTime _evaluationDate = DateTime.now();
  String? _overallRating;
  int _cognitive = 3;
  int _motor = 3;
  int _language = 3;
  int _socialEmotional = 3;
  int _creativity = 3;
  int _autonomy = 3;
  bool _isLoading = false;
  String? _error;

  static const _periods = {
    '1T': '1º Trimestre',
    '2T': '2º Trimestre',
    '3T': '3º Trimestre',
    'anual': 'Anual',
  };

  static const _ratings = [
    'Excelente',
    'Bom',
    'Satisfatório',
    'Precisa Melhorar',
  ];

  @override
  void dispose() {
    _obsCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _evaluationDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _evaluationDate = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedChildId == null) {
      setState(() => _error = 'Seleccione uma criança');
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      final dateStr =
          '${_evaluationDate.year.toString().padLeft(4, '0')}-${_evaluationDate.month.toString().padLeft(2, '0')}-${_evaluationDate.day.toString().padLeft(2, '0')}';
      await api.post('/evaluations', data: {
        'child_id': _selectedChildId,
        'evaluation_period': _period,
        'evaluation_date': dateStr,
        'cognitive': _cognitive,
        'motor': _motor,
        'language': _language,
        'social_emotional': _socialEmotional,
        'creativity': _creativity,
        'autonomy': _autonomy,
        if (_overallRating != null) 'overall_rating': _overallRating,
        if (_obsCtrl.text.trim().isNotEmpty)
          'observations': _obsCtrl.text.trim(),
      });
      widget.onCreated();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final childrenAsync = ref.watch(childrenForEvaluationProvider);

    return AlertDialog(
      title: const Text('Nova Avaliação'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                childrenAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Text('Erro: $e'),
                  data: (children) => DropdownButtonFormField<String>(
                    value: _selectedChildId,
                    decoration: const InputDecoration(labelText: 'Criança *'),
                    isExpanded: true,
                    items: children
                        .map((c) => DropdownMenuItem(
                            value: c.id, child: Text(c.fullName)))
                        .toList(),
                    onChanged: (v) =>
                        setState(() => _selectedChildId = v),
                    validator: (v) =>
                        v == null ? 'Seleccione uma criança' : null,
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _period,
                  decoration: const InputDecoration(labelText: 'Período'),
                  items: _periods.entries
                      .map((e) => DropdownMenuItem(
                          value: e.key, child: Text(e.value)))
                      .toList(),
                  onChanged: (v) =>
                      setState(() => _period = v ?? '1T'),
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: _pickDate,
                  child: InputDecorator(
                    decoration:
                        const InputDecoration(labelText: 'Data da avaliação'),
                    child: Text(DateFormat('dd/MM/yyyy')
                        .format(_evaluationDate)),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Dimensões (1-5)',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                _DimensionRating(
                  label: 'Cognitivo',
                  value: _cognitive,
                  onChanged: (v) => setState(() => _cognitive = v),
                ),
                _DimensionRating(
                  label: 'Motor',
                  value: _motor,
                  onChanged: (v) => setState(() => _motor = v),
                ),
                _DimensionRating(
                  label: 'Linguagem',
                  value: _language,
                  onChanged: (v) => setState(() => _language = v),
                ),
                _DimensionRating(
                  label: 'Social/Emocional',
                  value: _socialEmotional,
                  onChanged: (v) =>
                      setState(() => _socialEmotional = v),
                ),
                _DimensionRating(
                  label: 'Criatividade',
                  value: _creativity,
                  onChanged: (v) => setState(() => _creativity = v),
                ),
                _DimensionRating(
                  label: 'Autonomia',
                  value: _autonomy,
                  onChanged: (v) => setState(() => _autonomy = v),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _overallRating,
                  decoration:
                      const InputDecoration(labelText: 'Avaliação global'),
                  items: _ratings
                      .map((r) =>
                          DropdownMenuItem(value: r, child: Text(r)))
                      .toList(),
                  onChanged: (v) => setState(() => _overallRating = v),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _obsCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Observações (opcional)'),
                  maxLines: 3,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!,
                      style: const TextStyle(color: AppTheme.danger)),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _isLoading ? null : _submit,
          child: _isLoading
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Text('Guardar'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Dimension rating widget (1-5 dots)
// ---------------------------------------------------------------------------
class _DimensionRating extends StatelessWidget {
  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  const _DimensionRating({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 130,
            child: Text(label,
                style: const TextStyle(fontSize: 13)),
          ),
          ...List.generate(
            5,
            (i) => GestureDetector(
              onTap: () => onChanged(i + 1),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Icon(
                  i < value ? Icons.circle : Icons.circle_outlined,
                  size: 20,
                  color: i < value ? AppTheme.primary : Colors.grey.shade400,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
