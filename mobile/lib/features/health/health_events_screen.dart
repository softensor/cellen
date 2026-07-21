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
class HealthEvent {
  final String id;
  final String childId;
  final String? childName;
  final String eventDate;
  final String? eventTime;
  final String eventType;
  final String description;
  final double? temperature;
  final String? medicationGiven;
  final bool parentNotified;
  final String? actionTaken;

  const HealthEvent({
    required this.id,
    required this.childId,
    this.childName,
    required this.eventDate,
    this.eventTime,
    required this.eventType,
    required this.description,
    this.temperature,
    this.medicationGiven,
    this.parentNotified = false,
    this.actionTaken,
  });

  factory HealthEvent.fromJson(Map<String, dynamic> json) {
    return HealthEvent(
      id: json['id']?.toString() ?? '',
      childId: json['child_id']?.toString() ?? '',
      childName: json['child_name'] as String?,
      eventDate: json['event_date'] as String? ?? '',
      eventTime: json['event_time'] as String?,
      eventType: json['event_type'] as String? ?? '',
      description: json['description'] as String? ?? '',
      temperature: json['temperature'] != null
          ? double.tryParse(json['temperature'].toString())
          : null,
      medicationGiven: json['medication_given'] as String?,
      parentNotified: json['parent_notified'] as bool? ?? false,
      actionTaken: json['action_taken'] as String?,
    );
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------
final healthEventsProvider =
    FutureProvider.autoDispose.family<List<HealthEvent>, String?>(
  (ref, childId) async {
    final client = ref.read(apiClientProvider);
    final path = childId != null
        ? '/health-events?child_id=$childId'
        : '/health-events';
    final res = await client.get(path) as List;
    return res
        .map((e) => HealthEvent.fromJson(e as Map<String, dynamic>))
        .toList();
  },
);

final childrenForHealthProvider = FutureProvider.autoDispose((ref) async {
  final client = ref.read(apiClientProvider);
  final res = await client.get('/children?limit=200') as List;
  return res
      .map((e) => Child.fromJson(e as Map<String, dynamic>))
      .toList();
});

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------
class HealthEventsScreen extends ConsumerStatefulWidget {
  const HealthEventsScreen({super.key});

  @override
  ConsumerState<HealthEventsScreen> createState() => _HealthEventsScreenState();
}

class _HealthEventsScreenState extends ConsumerState<HealthEventsScreen> {
  String? _selectedChildId;

  @override
  Widget build(BuildContext context) {
    final eventsAsync = ref.watch(healthEventsProvider(_selectedChildId));
    final childrenAsync = ref.watch(childrenForHealthProvider);

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text('Saúde'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(healthEventsProvider(_selectedChildId));
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Child filter
          childrenAsync.when(
            data: (children) => Padding(
              padding: const EdgeInsets.all(16),
              child: DropdownButtonFormField<String?>(
                value: _selectedChildId,
                decoration: const InputDecoration(
                  labelText: 'Filtrar por criança',
                  prefixIcon: Icon(Icons.child_care),
                  border: OutlineInputBorder(),
                  filled: true,
                  fillColor: Colors.white,
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Todas as crianças'),
                  ),
                  ...children.map((c) => DropdownMenuItem<String?>(
                        value: c.id,
                        child: Text('${c.firstName} ${c.lastName}'),
                      )),
                ],
                onChanged: (v) => setState(() => _selectedChildId = v),
              ),
            ),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
          // List
          Expanded(
            child: eventsAsync.when(
              data: (events) => events.isEmpty
                  ? const Center(child: Text('Nenhum evento de saúde registado'))
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: events.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => _HealthEventCard(event: events[i]),
                    ),
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Erro: $e')),
            ),
          ),
        ],
      ),
      floatingActionButton: ref.watch(authProvider).role != UserRole.parent
          ? FloatingActionButton.extended(
              onPressed: () async {
                if (!mounted) return;
                final created = await showDialog<bool>(useRootNavigator: false,
                  context: context,
                  builder: (ctx) => _CreateHealthEventDialog(
                    preselectedChildId: _selectedChildId,
                  ),
                );
                if (created == true) {
                  ref.invalidate(healthEventsProvider(_selectedChildId));
                }
              },
              icon: const Icon(Icons.add),
              label: const Text('Registar'),
            )
          : null,
    );
  }
}

// ---------------------------------------------------------------------------
// Health Event Card
// ---------------------------------------------------------------------------
class _HealthEventCard extends StatelessWidget {
  final HealthEvent event;
  const _HealthEventCard({required this.event});

  Color _typeColor(String type) {
    return switch (type) {
      'fever' || 'febre' => AppTheme.danger,
      'injury' || 'lesão' => AppTheme.warning,
      'medication' || 'medicação' => AppTheme.primary,
      'allergy' || 'alergia' => Colors.purple,
      _ => AppTheme.textSecondary,
    };
  }

  String _typeLabel(String type) {
    return switch (type) {
      'fever' => 'Febre',
      'injury' => 'Lesão',
      'medication' => 'Medicação',
      'allergy' => 'Alergia',
      'vomiting' => 'Vómito',
      'diarrhea' => 'Diarreia',
      'other' => 'Outro',
      _ => type,
    };
  }

  @override
  Widget build(BuildContext context) {
    final color = _typeColor(event.eventType);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppTheme.border),
      ),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _typeLabel(event.eventType),
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  event.eventDate,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            if (event.childName != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.child_care,
                      size: 14, color: AppTheme.textSecondary),
                  const SizedBox(width: 4),
                  Text(
                    event.childName!,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Text(
              event.description,
              style: const TextStyle(color: AppTheme.textPrimary),
            ),
            if (event.temperature != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.thermostat,
                      size: 14, color: AppTheme.textSecondary),
                  const SizedBox(width: 4),
                  Text(
                    'Temperatura: ${event.temperature!.toStringAsFixed(1)}°C',
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ],
            if (event.medicationGiven != null &&
                event.medicationGiven!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.medication,
                      size: 14, color: AppTheme.textSecondary),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Medicação: ${event.medicationGiven}',
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (event.actionTaken != null && event.actionTaken!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Ação: ${event.actionTaken}',
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 13,
                ),
              ),
            ],
            if (event.parentNotified) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.check_circle,
                      size: 14, color: AppTheme.success),
                  const SizedBox(width: 4),
                  const Text(
                    'Encarregado notificado',
                    style: TextStyle(
                      color: AppTheme.success,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Create Health Event Dialog
// ---------------------------------------------------------------------------
class _CreateHealthEventDialog extends ConsumerStatefulWidget {
  final String? preselectedChildId;
  const _CreateHealthEventDialog({
    this.preselectedChildId,
  });

  @override
  ConsumerState<_CreateHealthEventDialog> createState() =>
      _CreateHealthEventDialogState();
}

class _CreateHealthEventDialogState
    extends ConsumerState<_CreateHealthEventDialog> {
  final _formKey = GlobalKey<FormState>();
  String? _childId;
  String _eventType = 'fever';
  final _descCtrl = TextEditingController();
  final _tempCtrl = TextEditingController();
  final _medCtrl = TextEditingController();
  final _actionCtrl = TextEditingController();
  bool _parentNotified = false;
  bool _loading = false;

  final _types = [
    ('fever', 'Febre'),
    ('injury', 'Lesão'),
    ('medication', 'Medicação'),
    ('allergy', 'Alergia'),
    ('vomiting', 'Vómito'),
    ('diarrhea', 'Diarreia'),
    ('other', 'Outro'),
  ];

  @override
  void initState() {
    super.initState();
    _childId = widget.preselectedChildId;
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    _tempCtrl.dispose();
    _medCtrl.dispose();
    _actionCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_childId == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Selecione uma criança')));
      return;
    }
    setState(() => _loading = true);
    try {
      final client = ref.read(apiClientProvider);
      final body = {
        'child_id': _childId,
        'event_type': _eventType,
        'description': _descCtrl.text.trim(),
        'parent_notified': _parentNotified,
        'event_date': DateTime.now().toIso8601String().substring(0, 10),
      };
      if (_tempCtrl.text.trim().isNotEmpty) {
        body['temperature'] = _tempCtrl.text.trim() as dynamic;
      }
      if (_medCtrl.text.trim().isNotEmpty) {
        body['medication_given'] = _medCtrl.text.trim() as dynamic;
      }
      if (_actionCtrl.text.trim().isNotEmpty) {
        body['action_taken'] = _actionCtrl.text.trim() as dynamic;
      }
      await client.post('/health-events', data: body);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final childrenAsync = ref.watch(childrenForHealthProvider);
    return AlertDialog(
      title: const Text('Registar Evento de Saúde'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                childrenAsync.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (_, __) => const Text('Erro ao carregar crianças'),
                  data: (children) => DropdownButtonFormField<String?>(
                    value: _childId,
                    decoration: const InputDecoration(
                      labelText: 'Criança *',
                      border: OutlineInputBorder(),
                    ),
                    items: children
                        .map((c) => DropdownMenuItem<String?>(
                              value: c.id,
                              child: Text('${c.firstName} ${c.lastName}'),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => _childId = v),
                    validator: (v) => v == null ? 'Obrigatório' : null,
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _eventType,
                  decoration: const InputDecoration(
                    labelText: 'Tipo de Evento *',
                    border: OutlineInputBorder(),
                  ),
                  items: _types
                      .map((t) => DropdownMenuItem(
                            value: t.$1,
                            child: Text(t.$2),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _eventType = v!),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Descrição *',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Obrigatório' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _tempCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Temperatura (°C)',
                    border: OutlineInputBorder(),
                    hintText: 'Ex: 38.5',
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _medCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Medicação Administrada',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _actionCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Ação Tomada',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  value: _parentNotified,
                  onChanged: (v) => setState(() => _parentNotified = v),
                  title: const Text('Encarregado Notificado'),
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _loading ? null : _submit,
          child: _loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Text('Registar'),
        ),
      ],
    );
  }
}
