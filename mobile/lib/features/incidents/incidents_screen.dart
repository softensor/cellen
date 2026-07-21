import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_client.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/auth/auth_state.dart';
import '../../core/models/incident.dart';

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------
final incidentsProvider =
    FutureProvider.autoDispose<List<Incident>>((ref) async {
  final api = ref.read(apiClientProvider);
  final auth = ref.read(authProvider);
  final path = auth.role == UserRole.parent ? '/incidents/mine' : '/incidents';
  final data = await api.get(path) as List;
  return data
      .map((e) => Incident.fromJson(e as Map<String, dynamic>))
      .toList();
});

// Simple children list for the dropdown (id + name)
final childrenForIncidentProvider =
    FutureProvider.autoDispose<List<Map<String, String>>>((ref) async {
  final api = ref.read(apiClientProvider);
  final data = await api.get('/children') as List;
  return data.map((e) {
    final m = e as Map<String, dynamic>;
    final id = m['id']?.toString() ?? '';
    final firstName = m['first_name']?.toString() ?? '';
    final lastName = m['last_name']?.toString() ?? '';
    return {'id': id, 'name': '$firstName $lastName'.trim()};
  }).toList();
});

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------
class IncidentsScreen extends ConsumerStatefulWidget {
  const IncidentsScreen({super.key});

  @override
  ConsumerState<IncidentsScreen> createState() => _IncidentsScreenState();
}

class _IncidentsScreenState extends ConsumerState<IncidentsScreen> {
  final Set<String> _expanded = {};

  @override
  Widget build(BuildContext context) {
    final incidentsAsync = ref.watch(incidentsProvider);
    final auth = ref.watch(authProvider);
    final canCreate = auth.role != UserRole.parent;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ocorrências'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(incidentsProvider),
          ),
        ],
      ),
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              onPressed: _showCreateDialog,
              icon: const Icon(Icons.add),
              label: const Text('Nova Ocorrência'),
            )
          : null,
      body: incidentsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorView(
          message: e.toString(),
          onRetry: () => ref.invalidate(incidentsProvider),
        ),
        data: (incidents) {
          if (incidents.isEmpty) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.shield_outlined, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'Sem ocorrências registadas',
                    style: TextStyle(color: Colors.grey, fontSize: 16),
                  ),
                ],
              ),
            );
          }

          // Sort newest first
          final sorted = List<Incident>.from(incidents)
            ..sort((a, b) => b.incidentDate.compareTo(a.incidentDate));

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(incidentsProvider),
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
              itemCount: sorted.length,
              itemBuilder: (context, i) {
                final incident = sorted[i];
                final isExpanded = _expanded.contains(incident.id);
                return _IncidentCard(
                  incident: incident,
                  isExpanded: isExpanded,
                  onToggle: () {
                    setState(() {
                      if (isExpanded) {
                        _expanded.remove(incident.id);
                      } else {
                        _expanded.add(incident.id);
                      }
                    });
                  },
                );
              },
            ),
          );
        },
      ),
    );
  }

  void _showCreateDialog() {
    showDialog(useRootNavigator: false,
      context: context,
      builder: (ctx) => _CreateIncidentDialog(
        onCreated: () => ref.invalidate(incidentsProvider),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Widgets
// ---------------------------------------------------------------------------

class _IncidentCard extends StatelessWidget {
  final Incident incident;
  final bool isExpanded;
  final VoidCallback onToggle;

  const _IncidentCard({
    required this.incident,
    required this.isExpanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final severityColor = _severityColor(incident.severity);
    final severityLabel = _severityLabel(incident.severity);

    // Format date
    String dateLabel = incident.incidentDate;
    final parsed = DateTime.tryParse(incident.incidentDate);
    if (parsed != null) {
      dateLabel = DateFormat('dd/MM/yyyy').format(parsed);
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onToggle,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: severityColor, width: 4),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: severityColor.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                      color: severityColor.withOpacity(0.4)),
                                ),
                                child: Text(
                                  severityLabel,
                                  style: TextStyle(
                                    color: severityColor,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (incident.parentNotified)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.green.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Text(
                                    'Enc. Notificado',
                                    style: TextStyle(
                                      color: Colors.green,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            incident.childName,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '$dateLabel${incident.incidentTime != null ? ' às ${incident.incidentTime}' : ''}',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                          if (!isExpanded) ...[
                            const SizedBox(height: 4),
                            Text(
                              incident.description,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Icon(
                      isExpanded
                          ? Icons.expand_less
                          : Icons.expand_more,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),

            // Expanded content
            if (isExpanded)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Divider(),
                    Text(
                      'Descrição',
                      style: Theme.of(context)
                          .textTheme
                          .labelMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(incident.description),
                    if (incident.actionTaken != null &&
                        incident.actionTaken!.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Medidas Tomadas',
                        style: Theme.of(context)
                            .textTheme
                            .labelMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(incident.actionTaken!),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Color _severityColor(String severity) {
    switch (severity) {
      case 'moderate':
        return Colors.deepOrange;
      case 'serious':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  String _severityLabel(String severity) {
    switch (severity) {
      case 'moderate':
        return 'Moderada';
      case 'serious':
        return 'Grave';
      default:
        return 'Ligeira';
    }
  }
}

// ---------------------------------------------------------------------------
// Create incident dialog (ConsumerStatefulWidget so it can watch providers)
// ---------------------------------------------------------------------------
class _CreateIncidentDialog extends ConsumerStatefulWidget {
  final VoidCallback onCreated;
  const _CreateIncidentDialog({required this.onCreated});

  @override
  ConsumerState<_CreateIncidentDialog> createState() =>
      _CreateIncidentDialogState();
}

class _CreateIncidentDialogState extends ConsumerState<_CreateIncidentDialog> {
  final _descCtrl = TextEditingController();
  final _actionCtrl = TextEditingController();
  String? _selectedChildId;
  String _severity = 'minor';
  TimeOfDay? _time;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _descCtrl.dispose();
    _actionCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_selectedChildId == null || _descCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Seleccione a criança e preencha a descrição');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final timeStr = _time != null
          ? '${_time!.hour.toString().padLeft(2, '0')}:${_time!.minute.toString().padLeft(2, '0')}'
          : null;
      await ref.read(apiClientProvider).post('/incidents', data: {
        'child_id': _selectedChildId,
        'severity': _severity,
        'description': _descCtrl.text.trim(),
        if (_actionCtrl.text.trim().isNotEmpty)
          'action_taken': _actionCtrl.text.trim(),
        'incident_date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
        if (timeStr != null) 'incident_time': timeStr,
      });
      widget.onCreated();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final childrenAsync = ref.watch(childrenForIncidentProvider);

    return AlertDialog(
      title: const Text('Nova Ocorrência'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            childrenAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (_, __) => const Text('Erro ao carregar crianças'),
              data: (children) => DropdownButtonFormField<String>(
                value: _selectedChildId,
                decoration: const InputDecoration(
                  labelText: 'Criança *',
                  border: OutlineInputBorder(),
                ),
                items: children
                    .map((c) => DropdownMenuItem(
                          value: c['id'],
                          child: Text(c['name'] ?? ''),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _selectedChildId = v),
                validator: (v) => v == null ? 'Obrigatório' : null,
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _severity,
              decoration: const InputDecoration(
                labelText: 'Gravidade',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'minor', child: Text('Ligeira')),
                DropdownMenuItem(value: 'moderate', child: Text('Moderada')),
                DropdownMenuItem(value: 'serious', child: Text('Grave')),
              ],
              onChanged: (v) => setState(() => _severity = v ?? 'minor'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descCtrl,
              decoration: const InputDecoration(
                labelText: 'Descrição *',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _actionCtrl,
              decoration: const InputDecoration(
                labelText: 'Medidas tomadas',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.access_time),
              label: Text(_time != null
                  ? '${_time!.hour.toString().padLeft(2, '0')}:${_time!.minute.toString().padLeft(2, '0')}'
                  : 'Hora da ocorrência'),
              onPressed: () async {
                final t = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay.now(),
                );
                if (t != null) setState(() => _time = t);
              },
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
        FilledButton(
          onPressed: _loading ? null : _submit,
          child: _loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Registar'),
        ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline,
              size: 48, color: Theme.of(context).colorScheme.error),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Tentar novamente'),
          ),
        ],
      ),
    );
  }
}
