import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_client.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/models/child.dart';
import '../../../core/models/caderneta.dart';
import 'caderneta_list_screen.dart' show cadernetaListProvider;
import '../../teacher/dashboard/teacher_dashboard_screen.dart'
    show teacherRecentCadernetsProvider;

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------
final childrenForCadernetaProvider =
    FutureProvider.autoDispose<List<Child>>((ref) async {
  final api = ref.read(apiClientProvider);
  final data = await api.get('/children/my') as List;
  return data
      .map((e) => Child.fromJson(e as Map<String, dynamic>))
      .toList();
});

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------
const _foodRatings = ['Bem', 'Muito Bem', 'Mal', 'Não Comeu'];
const _physioOptions = ['Normal', 'Mole', 'Duro'];

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------
class CadernetaFormScreen extends ConsumerStatefulWidget {
  final String? cadernetaId;
  const CadernetaFormScreen({super.key, this.cadernetaId});

  @override
  ConsumerState<CadernetaFormScreen> createState() =>
      _CadernetaFormScreenState();
}

class _CadernetaFormScreenState
    extends ConsumerState<CadernetaFormScreen> {
  final _formKey = GlobalKey<FormState>();

  String? _selectedChildId;
  DateTime _reportDate = DateTime.now();

  String? _breakfastRating;
  String? _lunchRating;
  String? _snackRating;
  String? _physioNeeds;
  bool _hadNap = false;

  final _sensorialCtrl = TextEditingController();
  final _intellectualCtrl = TextEditingController();
  final _socialCtrl = TextEditingController();
  final _affectiveCtrl = TextEditingController();
  final _observationsCtrl = TextEditingController();

  bool _isLoading = false;
  bool _isLoadingExisting = false;
  String? _error;

  bool get isEditing => widget.cadernetaId != null;

  @override
  void initState() {
    super.initState();
    if (isEditing) _loadExisting();
  }

  Future<void> _loadExisting() async {
    setState(() => _isLoadingExisting = true);
    try {
      final api = ref.read(apiClientProvider);
      final data = await api.get('/cadernetas/${widget.cadernetaId}');
      final c = Caderneta.fromJson(data as Map<String, dynamic>);
      _sensorialCtrl.text = c.sensorialMotorDevelopment ?? '';
      _intellectualCtrl.text = c.intellectualDevelopment ?? '';
      _socialCtrl.text = c.socialDevelopment ?? '';
      _affectiveCtrl.text = c.affectiveDevelopment ?? '';
      _observationsCtrl.text = c.generalObservations ?? '';
      setState(() {
        _selectedChildId = c.childId;
        _reportDate = c.reportDate;
        _breakfastRating = c.breakfastRating;
        _lunchRating = c.lunchRating;
        _snackRating = c.snackRating;
        _physioNeeds = c.physiologicalNeeds;
        _hadNap = c.hadNap ?? false;
        _isLoadingExisting = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoadingExisting = false;
      });
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _reportDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _reportDate = picked);
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

    final auth = ref.read(authProvider);
    final body = <String, dynamic>{
      'child_id': _selectedChildId,
      'teacher_id': auth.userId,
      'report_date':
          '${_reportDate.year.toString().padLeft(4, '0')}-${_reportDate.month.toString().padLeft(2, '0')}-${_reportDate.day.toString().padLeft(2, '0')}',
      'had_nap': _hadNap,
      if (_breakfastRating != null) 'breakfast_rating': _breakfastRating,
      if (_lunchRating != null) 'lunch_rating': _lunchRating,
      if (_snackRating != null) 'snack_rating': _snackRating,
      if (_physioNeeds != null) 'physiological_needs': _physioNeeds,
      if (_sensorialCtrl.text.trim().isNotEmpty)
        'sensorial_motor_development': _sensorialCtrl.text.trim(),
      if (_intellectualCtrl.text.trim().isNotEmpty)
        'intellectual_development': _intellectualCtrl.text.trim(),
      if (_socialCtrl.text.trim().isNotEmpty)
        'social_development': _socialCtrl.text.trim(),
      if (_affectiveCtrl.text.trim().isNotEmpty)
        'affective_development': _affectiveCtrl.text.trim(),
      if (_observationsCtrl.text.trim().isNotEmpty)
        'general_observations': _observationsCtrl.text.trim(),
    };

    try {
      final api = ref.read(apiClientProvider);
      if (isEditing) {
        await api.patch('/cadernetas/${widget.cadernetaId}', data: body);
      } else {
        await api.post('/cadernetas', data: body);
      }
      ref.invalidate(cadernetaListProvider);
      ref.invalidate(teacherRecentCadernetsProvider);
      if (mounted) context.pop();
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _sensorialCtrl.dispose();
    _intellectualCtrl.dispose();
    _socialCtrl.dispose();
    _affectiveCtrl.dispose();
    _observationsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingExisting) {
      return Scaffold(
        appBar: AppBar(
            title:
                Text(isEditing ? 'Editar Caderneta' : 'Nova Caderneta')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final childrenAsync = ref.watch(childrenForCadernetaProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Editar Caderneta' : 'Nova Caderneta'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ---- Child selector ----
              _SectionHeader('Criança e Data'),
              const SizedBox(height: 12),

              childrenAsync.when(
                loading: () => const Center(
                    child: CircularProgressIndicator()),
                error: (e, _) => Text('Erro ao carregar crianças: $e'),
                data: (children) => DropdownButtonFormField<String>(
                  value: _selectedChildId,
                  decoration: const InputDecoration(
                    labelText: 'Criança *',
                    prefixIcon: Icon(Icons.child_care),
                  ),
                  isExpanded: true,
                  items: children
                      .map(
                        (c) => DropdownMenuItem(
                          value: c.id,
                          child: Text(c.fullName),
                        ),
                      )
                      .toList(),
                  onChanged: (v) =>
                      setState(() => _selectedChildId = v),
                  validator: (v) =>
                      v == null ? 'Seleccione uma criança' : null,
                ),
              ),
              const SizedBox(height: 12),

              InkWell(
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(8),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Data do Relatório',
                    prefixIcon: Icon(Icons.calendar_today),
                  ),
                  child: Text(
                      DateFormat('dd/MM/yyyy').format(_reportDate)),
                ),
              ),
              const SizedBox(height: 24),

              // ---- Food ratings ----
              _SectionHeader('Alimentação'),
              const SizedBox(height: 12),

              _FoodRatingRow(
                label: 'Pequeno-almoço',
                value: _breakfastRating,
                onChanged: (v) =>
                    setState(() => _breakfastRating = v),
              ),
              const SizedBox(height: 12),

              _FoodRatingRow(
                label: 'Almoço',
                value: _lunchRating,
                onChanged: (v) =>
                    setState(() => _lunchRating = v),
              ),
              const SizedBox(height: 12),

              _FoodRatingRow(
                label: 'Lanche',
                value: _snackRating,
                onChanged: (v) => setState(() => _snackRating = v),
              ),
              const SizedBox(height: 24),

              // ---- Physiological ----
              _SectionHeader('Necessidades Fisiológicas'),
              const SizedBox(height: 12),

              Wrap(
                spacing: 8,
                children: _physioOptions
                    .map(
                      (option) => ChoiceChip(
                        label: Text(option),
                        selected: _physioNeeds == option,
                        onSelected: (_) => setState(
                            () => _physioNeeds = _physioNeeds == option
                                ? null
                                : option),
                        selectedColor: Theme.of(context)
                            .colorScheme
                            .primaryContainer,
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 24),

              // ---- Nap ----
              _SectionHeader('Sesta'),
              const SizedBox(height: 8),

              Card(
                child: SwitchListTile(
                  title: const Text('Fez sesta?'),
                  value: _hadNap,
                  onChanged: (v) => setState(() => _hadNap = v),
                  secondary: Icon(
                    _hadNap ? Icons.bedtime : Icons.bedtime_off,
                    color: _hadNap
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // ---- Development ----
              _SectionHeader('Desenvolvimento'),
              const SizedBox(height: 12),

              TextFormField(
                controller: _sensorialCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Desenvolvimento Sensorial/Motor',
                  prefixIcon: Icon(Icons.directions_run),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _intellectualCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Desenvolvimento Intelectual',
                  prefixIcon: Icon(Icons.psychology),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _socialCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Desenvolvimento Social',
                  prefixIcon: Icon(Icons.group),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _affectiveCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Desenvolvimento Afectivo',
                  prefixIcon: Icon(Icons.favorite),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 24),

              // ---- General observations ----
              _SectionHeader('Observações Gerais'),
              const SizedBox(height: 12),

              TextFormField(
                controller: _observationsCtrl,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Observações',
                  prefixIcon: Icon(Icons.notes),
                  alignLabelWithHint: true,
                ),
              ),

              if (_error != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color:
                        Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _error!,
                    style: TextStyle(
                        color: Theme.of(context)
                            .colorScheme
                            .onErrorContainer),
                  ),
                ),
              ],

              const SizedBox(height: 32),

              FilledButton(
                onPressed: _isLoading ? null : _submit,
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : Text(isEditing
                        ? 'Guardar Alterações'
                        : 'Registar Caderneta'),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helper widgets
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.bold,
          ),
    );
  }
}

class _FoodRatingRow extends StatelessWidget {
  final String label;
  final String? value;
  final ValueChanged<String?> onChanged;

  const _FoodRatingRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: _foodRatings
              .map(
                (rating) => ChoiceChip(
                  label: Text(rating),
                  selected: value == rating,
                  onSelected: (_) =>
                      onChanged(value == rating ? null : rating),
                  selectedColor: _ratingColor(rating).withOpacity(0.3),
                  labelStyle: value == rating
                      ? TextStyle(
                          color: _ratingColor(rating),
                          fontWeight: FontWeight.w600)
                      : null,
                ),
              )
              .toList(),
        ),
      ],
    );
  }

  Color _ratingColor(String rating) {
    switch (rating) {
      case 'Muito Bem':
        return Colors.green;
      case 'Bem':
        return Colors.teal;
      case 'Mal':
        return Colors.red;
      case 'Não Comeu':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }
}
