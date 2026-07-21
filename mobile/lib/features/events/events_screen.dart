import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../core/api/api_client.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/auth/auth_state.dart';
import '../../core/models/event.dart';

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------
final eventsProvider =
    FutureProvider.autoDispose<List<SchoolEvent>>((ref) async {
  final api = ref.read(apiClientProvider);
  final now = DateTime.now();
  final from = DateTime(now.year, now.month - 1, 1);
  final to = DateTime(now.year, now.month + 2, 0);
  final data = await api.get(
    '/events',
    queryParameters: {
      'from_date': DateFormat('yyyy-MM-dd').format(from),
      'to_date': DateFormat('yyyy-MM-dd').format(to),
    },
  ) as List;
  return data
      .map((e) => SchoolEvent.fromJson(e as Map<String, dynamic>))
      .toList();
});

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------
class EventsScreen extends ConsumerStatefulWidget {
  const EventsScreen({super.key});

  @override
  ConsumerState<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends ConsumerState<EventsScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  @override
  void initState() {
    super.initState();
    _selectedDay = DateTime.now();
  }

  @override
  Widget build(BuildContext context) {
    final eventsAsync = ref.watch(eventsProvider);
    final auth = ref.read(authProvider);
    final isAdmin = auth.role == UserRole.schoolAdmin ||
        auth.role == UserRole.platformAdmin;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Calendário & Eventos'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(eventsProvider),
          ),
        ],
      ),
      floatingActionButton: isAdmin
          ? FloatingActionButton.extended(
              onPressed: _showCreateEventDialog,
              icon: const Icon(Icons.add),
              label: const Text('Novo Evento'),
            )
          : null,
      body: eventsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorView(
          message: e.toString(),
          onRetry: () => ref.invalidate(eventsProvider),
        ),
        data: (events) {
          // Build event map by day
          final eventsByDay = <DateTime, List<SchoolEvent>>{};
          for (final event in events) {
            final day = DateTime(event.startDate.year, event.startDate.month,
                event.startDate.day);
            eventsByDay.putIfAbsent(day, () => []).add(event);
          }

          // Events for selected day
          final selectedDayNorm = _selectedDay != null
              ? DateTime(
                  _selectedDay!.year,
                  _selectedDay!.month,
                  _selectedDay!.day,
                )
              : null;
          final selectedEvents =
              selectedDayNorm != null ? (eventsByDay[selectedDayNorm] ?? []) : [];

          return Column(
            children: [
              // Calendar
              Card(
                margin: const EdgeInsets.all(12),
                child: TableCalendar<SchoolEvent>(
                  firstDay: DateTime.utc(2020, 1, 1),
                  lastDay: DateTime.utc(2030, 12, 31),
                  focusedDay: _focusedDay,
                  selectedDayPredicate: (day) =>
                      isSameDay(_selectedDay, day),
                  eventLoader: (day) {
                    final key = DateTime(day.year, day.month, day.day);
                    return eventsByDay[key] ?? [];
                  },
                  onDaySelected: (selected, focused) {
                    setState(() {
                      _selectedDay = selected;
                      _focusedDay = focused;
                    });
                  },
                  onPageChanged: (focused) {
                    setState(() => _focusedDay = focused);
                  },
                  calendarStyle: CalendarStyle(
                    markerDecoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                    todayDecoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .primary
                          .withOpacity(0.3),
                      shape: BoxShape.circle,
                    ),
                    selectedDecoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  headerStyle: const HeaderStyle(
                    formatButtonVisible: false,
                    titleCentered: true,
                  ),
                  locale: 'pt_PT',
                ),
              ),

              // Events list for selected day
              if (_selectedDay != null)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Row(
                    children: [
                      Text(
                        DateFormat('d \'de\' MMMM', 'pt_PT')
                            .format(_selectedDay!),
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .primaryContainer,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${selectedEvents.length}',
                          style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onPrimaryContainer,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: selectedEvents.isEmpty
                    ? Center(
                        child: Text(
                          'Sem eventos neste dia',
                          style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 88),
                        itemCount: selectedEvents.length,
                        itemBuilder: (context, i) {
                          return _EventCard(event: selectedEvents[i]);
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showCreateEventDialog() {
    final titleCtrl = TextEditingController();
    final locationCtrl = TextEditingController();
    String selectedType = 'general';
    DateTime? selectedDate;
    bool allDay = true;
    TimeOfDay? startTime;
    TimeOfDay? endTime;
    bool isLoading = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Novo Evento'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Título *',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: selectedType,
                  decoration: const InputDecoration(
                    labelText: 'Tipo',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                        value: 'general', child: Text('Geral')),
                    DropdownMenuItem(
                        value: 'holiday', child: Text('Feriado')),
                    DropdownMenuItem(
                        value: 'meeting', child: Text('Reunião')),
                    DropdownMenuItem(
                        value: 'activity', child: Text('Actividade')),
                    DropdownMenuItem(
                        value: 'closure', child: Text('Encerramento')),
                  ],
                  onChanged: (v) =>
                      setDialogState(() => selectedType = v ?? 'general'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_today),
                  label: Text(
                    selectedDate != null
                        ? DateFormat('dd/MM/yyyy').format(selectedDate!)
                        : 'Seleccionar data *',
                  ),
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2030),
                    );
                    if (picked != null) {
                      setDialogState(() => selectedDate = picked);
                    }
                  },
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  title: const Text('Dia inteiro'),
                  value: allDay,
                  onChanged: (v) => setDialogState(() => allDay = v),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
                if (!allDay) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.access_time),
                          label: Text(
                            startTime != null
                                ? '${startTime!.hour.toString().padLeft(2, '0')}:${startTime!.minute.toString().padLeft(2, '0')}'
                                : 'Início',
                          ),
                          onPressed: () async {
                            final t = await showTimePicker(
                              context: ctx,
                              initialTime: TimeOfDay.now(),
                            );
                            if (t != null) {
                              setDialogState(() => startTime = t);
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.access_time),
                          label: Text(
                            endTime != null
                                ? '${endTime!.hour.toString().padLeft(2, '0')}:${endTime!.minute.toString().padLeft(2, '0')}'
                                : 'Fim',
                          ),
                          onPressed: () async {
                            final t = await showTimePicker(
                              context: ctx,
                              initialTime: TimeOfDay.now(),
                            );
                            if (t != null) {
                              setDialogState(() => endTime = t);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: locationCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Localização',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.location_on),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: isLoading
                  ? null
                  : () async {
                      if (titleCtrl.text.trim().isEmpty ||
                          selectedDate == null) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(
                              content: Text(
                                  'Preencha o título e seleccione a data')),
                        );
                        return;
                      }
                      setDialogState(() => isLoading = true);
                      try {
                        String startDateStr =
                            DateFormat('yyyy-MM-dd').format(selectedDate!);
                        if (!allDay && startTime != null) {
                          startDateStr =
                              '${startDateStr}T${startTime!.hour.toString().padLeft(2, '0')}:${startTime!.minute.toString().padLeft(2, '0')}:00';
                        }
                        await ref.read(apiClientProvider).post(
                          '/events/',
                          data: {
                            'title': titleCtrl.text.trim(),
                            'event_type': selectedType,
                            'start_date': startDateStr,
                            'all_day': allDay,
                            'location': locationCtrl.text.trim().isNotEmpty
                                ? locationCtrl.text.trim()
                                : null,
                          },
                        );
                        if (ctx.mounted) Navigator.pop(ctx);
                        ref.invalidate(eventsProvider);
                      } catch (e) {
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(content: Text('Erro: $e')),
                          );
                        }
                      } finally {
                        setDialogState(() => isLoading = false);
                      }
                    },
              child: isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Criar'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Widgets
// ---------------------------------------------------------------------------

class _EventCard extends StatelessWidget {
  final SchoolEvent event;

  const _EventCard({required this.event});

  @override
  Widget build(BuildContext context) {
    final typeColor = _typeColor(event.eventType);
    final typeIcon = _typeIcon(event.eventType);
    final typeLabel = _typeLabel(event.eventType);

    String timeLabel = event.allDay
        ? 'Dia inteiro'
        : DateFormat('HH:mm').format(event.startDate);
    if (!event.allDay && event.endDate != null) {
      timeLabel += ' – ${DateFormat('HH:mm').format(event.endDate!)}';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: typeColor.withOpacity(0.15),
          child: Icon(typeIcon, color: typeColor, size: 20),
        ),
        title: Text(
          event.title,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: typeColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    typeLabel,
                    style: TextStyle(
                      color: typeColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(timeLabel,
                    style: Theme.of(context).textTheme.labelSmall),
              ],
            ),
            if (event.location != null && event.location!.isNotEmpty) ...[
              const SizedBox(height: 2),
              Row(
                children: [
                  Icon(Icons.location_on,
                      size: 12,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant),
                  const SizedBox(width: 2),
                  Text(
                    event.location!,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ],
          ],
        ),
        isThreeLine: event.location != null,
      ),
    );
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'holiday':
        return Colors.orange;
      case 'meeting':
        return Colors.blue;
      case 'activity':
        return Colors.green;
      case 'closure':
        return Colors.red;
      default:
        return Colors.purple;
    }
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'holiday':
        return Icons.celebration;
      case 'meeting':
        return Icons.groups;
      case 'activity':
        return Icons.sports_gymnastics;
      case 'closure':
        return Icons.lock;
      default:
        return Icons.event;
    }
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'holiday':
        return 'Feriado';
      case 'meeting':
        return 'Reunião';
      case 'activity':
        return 'Actividade';
      case 'closure':
        return 'Encerramento';
      default:
        return 'Geral';
    }
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
