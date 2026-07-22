import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_client.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/auth/auth_state.dart';
import '../../core/models/child.dart';
import '../../core/models/employee.dart';
import '../../core/models/school_terms.dart';
import '../../core/providers/currency_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_error_widget.dart';

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------
class Appointment {
  final String id;
  final String title;
  final String? notes;
  final String proposedDate;
  final String? proposedTime;
  final String? confirmedDate;
  final String? confirmedTime;
  final String status;
  final String? responseNotes;
  final String? employeeName;
  final String? childName;
  final String createdAt;

  const Appointment({
    required this.id,
    required this.title,
    this.notes,
    required this.proposedDate,
    this.proposedTime,
    this.confirmedDate,
    this.confirmedTime,
    required this.status,
    this.responseNotes,
    this.employeeName,
    this.childName,
    required this.createdAt,
  });

  factory Appointment.fromJson(Map<String, dynamic> json) {
    return Appointment(
      id: json['id']?.toString() ?? '',
      title: json['title'] as String? ?? '',
      notes: json['notes'] as String?,
      proposedDate: json['proposed_date'] as String? ?? '',
      proposedTime: json['proposed_time'] as String?,
      confirmedDate: json['confirmed_date'] as String?,
      confirmedTime: json['confirmed_time'] as String?,
      status: json['status'] as String? ?? 'pending',
      responseNotes: json['response_notes'] as String?,
      employeeName: json['employee_name'] as String?,
      childName: json['child_name'] as String?,
      createdAt: json['created_at'] as String? ?? '',
    );
  }
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------
final appointmentsProvider =
    FutureProvider.autoDispose<List<Appointment>>((ref) async {
  final api = ref.read(apiClientProvider);
  final data = await api.get('/appointments') as List;
  return data
      .map((e) => Appointment.fromJson(e as Map<String, dynamic>))
      .toList();
});

final employeesForAppointmentProvider =
    FutureProvider.autoDispose<List<Employee>>((ref) async {
  final api = ref.read(apiClientProvider);
  final data = await api.get('/employees') as List;
  return data
      .map((e) => Employee.fromJson(e as Map<String, dynamic>))
      .toList();
});

final childrenForAppointmentProvider =
    FutureProvider.autoDispose<List<Child>>((ref) async {
  final api = ref.read(apiClientProvider);
  final data = await api.get('/children/my') as List;
  return data.map((e) => Child.fromJson(e as Map<String, dynamic>)).toList();
});

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------
class AppointmentsScreen extends ConsumerStatefulWidget {
  const AppointmentsScreen({super.key});

  @override
  ConsumerState<AppointmentsScreen> createState() =>
      _AppointmentsScreenState();
}

class _AppointmentsScreenState extends ConsumerState<AppointmentsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appointmentsAsync = ref.watch(appointmentsProvider);
    final auth = ref.watch(authProvider);
    final isParent = auth.isParent;
    final isStaffOrAdmin = auth.isAdmin || auth.isTeacher || auth.isStaff;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Marcações'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(appointmentsProvider),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Pendentes'),
            Tab(text: 'Confirmadas'),
            Tab(text: 'Histórico'),
          ],
        ),
      ),
      floatingActionButton: isParent
          ? FloatingActionButton.extended(
              onPressed: () => _showCreateDialog(context),
              icon: const Icon(Icons.add),
              label: const Text('Nova Marcação'),
            )
          : null,
      body: appointmentsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AppErrorWidget(error: e, onRetry: () => ref.invalidate(appointmentsProvider)),
        data: (appointments) {
          final pending =
              appointments.where((a) => a.status == 'pending').toList();
          final confirmed =
              appointments.where((a) => a.status == 'confirmed').toList();
          final history = appointments
              .where((a) => ['declined', 'cancelled', 'completed']
                  .contains(a.status))
              .toList();

          return TabBarView(
            controller: _tabController,
            children: [
              _AppointmentsList(
                appointments: pending,
                isStaffOrAdmin: isStaffOrAdmin,
                isParent: isParent,
                onRefresh: () => ref.invalidate(appointmentsProvider),
              ),
              _AppointmentsList(
                appointments: confirmed,
                isStaffOrAdmin: isStaffOrAdmin,
                isParent: isParent,
                onRefresh: () => ref.invalidate(appointmentsProvider),
              ),
              _AppointmentsList(
                appointments: history,
                isStaffOrAdmin: false,
                isParent: false,
                onRefresh: () => ref.invalidate(appointmentsProvider),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showCreateDialog(BuildContext context) {
    showDialog(useRootNavigator: false, 
      context: context,
      builder: (_) => _CreateAppointmentDialog(
        onCreated: () => ref.invalidate(appointmentsProvider),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Appointments list
// ---------------------------------------------------------------------------
class _AppointmentsList extends ConsumerWidget {
  final List<Appointment> appointments;
  final bool isStaffOrAdmin;
  final bool isParent;
  final VoidCallback onRefresh;

  const _AppointmentsList({
    required this.appointments,
    required this.isStaffOrAdmin,
    required this.isParent,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (appointments.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.calendar_today_outlined,
                size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            const Text('Nenhuma marcação',
                style: TextStyle(color: AppTheme.textSecondary)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
        itemCount: appointments.length,
        itemBuilder: (context, i) {
          final a = appointments[i];
          return _AppointmentCard(
            appointment: a,
            showAdminActions: isStaffOrAdmin && a.status == 'pending',
            showParentCancel: isParent && a.status == 'pending',
            onRespond: (confirm) async {
              try {
                await ref.read(apiClientProvider).patch(
                  '/appointments/${a.id}/respond',
                  data: {'status': confirm ? 'confirmed' : 'declined'},
                );
                onRefresh();
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Erro: $e')),
                  );
                }
              }
            },
            onCancel: () async {
              try {
                await ref.read(apiClientProvider).patch(
                  '/appointments/${a.id}/cancel',
                );
                onRefresh();
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Erro: $e')),
                  );
                }
              }
            },
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Appointment card
// ---------------------------------------------------------------------------
class _AppointmentCard extends StatelessWidget {
  final Appointment appointment;
  final bool showAdminActions;
  final bool showParentCancel;
  final void Function(bool confirm) onRespond;
  final VoidCallback onCancel;

  const _AppointmentCard({
    required this.appointment,
    required this.showAdminActions,
    required this.showParentCancel,
    required this.onRespond,
    required this.onCancel,
  });

  Color _statusColor(String status) => switch (status) {
        'pending' => Colors.amber,
        'confirmed' => AppTheme.success,
        'declined' => AppTheme.danger,
        'cancelled' => Colors.grey,
        'completed' => AppTheme.primary,
        _ => Colors.grey,
      };

  String _statusLabel(String status) => switch (status) {
        'pending' => 'Pendente',
        'confirmed' => 'Confirmada',
        'declined' => 'Recusada',
        'cancelled' => 'Cancelada',
        'completed' => 'Concluída',
        _ => status,
      };

  @override
  Widget build(BuildContext context) {
    final a = appointment;
    final theme = Theme.of(context);
    final color = _statusColor(a.status);
    final dateStr = a.proposedDate.isNotEmpty
        ? (() {
            try {
              return DateFormat('dd/MM/yyyy')
                  .format(DateTime.parse(a.proposedDate));
            } catch (_) {
              return a.proposedDate;
            }
          })()
        : '';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(a.title,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _statusLabel(a.status),
                    style: TextStyle(
                        color: color,
                        fontSize: 11,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (a.employeeName != null)
              Row(
                children: [
                  const Icon(Icons.person_outline,
                      size: 14, color: AppTheme.textSecondary),
                  const SizedBox(width: 4),
                  Text(a.employeeName!,
                      style: const TextStyle(
                          color: AppTheme.textSecondary, fontSize: 12)),
                ],
              ),
            if (a.childName != null) ...[
              const SizedBox(height: 2),
              Row(
                children: [
                  const Icon(Icons.person_outlined,
                      size: 14, color: AppTheme.textSecondary),
                  const SizedBox(width: 4),
                  Text(a.childName!,
                      style: const TextStyle(
                          color: AppTheme.textSecondary, fontSize: 12)),
                ],
              ),
            ],
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.calendar_today,
                    size: 14, color: AppTheme.textSecondary),
                const SizedBox(width: 4),
                Text(
                  '$dateStr${a.proposedTime != null ? ' às ${a.proposedTime}' : ''}',
                  style: const TextStyle(fontSize: 13),
                ),
              ],
            ),
            if (a.notes != null) ...[
              const SizedBox(height: 4),
              Text(a.notes!,
                  style: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 12),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
            ],
            if (showAdminActions) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => onRespond(false),
                      icon: const Icon(Icons.close, size: 16),
                      label: const Text('Recusar'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.danger,
                        side: const BorderSide(color: AppTheme.danger),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => onRespond(true),
                      icon: const Icon(Icons.check, size: 16),
                      label: const Text('Confirmar'),
                    ),
                  ),
                ],
              ),
            ],
            if (showParentCancel) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: onCancel,
                icon: const Icon(Icons.cancel_outlined, size: 16),
                label: const Text('Cancelar'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.grey,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Create Appointment Dialog
// ---------------------------------------------------------------------------
class _CreateAppointmentDialog extends ConsumerStatefulWidget {
  final VoidCallback onCreated;
  const _CreateAppointmentDialog({required this.onCreated});

  @override
  ConsumerState<_CreateAppointmentDialog> createState() =>
      _CreateAppointmentDialogState();
}

class _CreateAppointmentDialogState
    extends ConsumerState<_CreateAppointmentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _timeCtrl = TextEditingController();
  String? _selectedEmployeeId;
  String? _selectedChildId;
  DateTime _proposedDate = DateTime.now().add(const Duration(days: 1));
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _notesCtrl.dispose();
    _timeCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _proposedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _proposedDate = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      final dateStr =
          '${_proposedDate.year.toString().padLeft(4, '0')}-${_proposedDate.month.toString().padLeft(2, '0')}-${_proposedDate.day.toString().padLeft(2, '0')}';
      await api.post('/appointments', data: {
        'title': _titleCtrl.text.trim(),
        if (_notesCtrl.text.trim().isNotEmpty)
          'notes': _notesCtrl.text.trim(),
        'proposed_date': dateStr,
        if (_timeCtrl.text.trim().isNotEmpty)
          'proposed_time': _timeCtrl.text.trim(),
        if (_selectedEmployeeId != null) 'employee_id': _selectedEmployeeId,
        if (_selectedChildId != null) 'child_id': _selectedChildId,
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
    final employeesAsync = ref.watch(employeesForAppointmentProvider);
    final childrenAsync = ref.watch(childrenForAppointmentProvider);
    final terms = SchoolTerms.of(ref.watch(schoolInfoProvider).valueOrNull);

    return AlertDialog(
      title: const Text('Nova Marcação'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _titleCtrl,
                  decoration: const InputDecoration(labelText: 'Assunto *'),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Obrigatório' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _notesCtrl,
                  decoration: const InputDecoration(labelText: 'Notas'),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                employeesAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Text('Erro: $e'),
                  data: (employees) => DropdownButtonFormField<String>(
                    value: _selectedEmployeeId,
                    decoration: const InputDecoration(
                        labelText: 'Funcionário *'),
                    isExpanded: true,
                    items: employees
                        .map((e) => DropdownMenuItem(
                            value: e.id,
                            child: Text(e.fullName)))
                        .toList(),
                    onChanged: (v) =>
                        setState(() => _selectedEmployeeId = v),
                    validator: (v) =>
                        v == null ? 'Seleccione um funcionário' : null,
                  ),
                ),
                const SizedBox(height: 12),
                childrenAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Text('Erro: $e'),
                  data: (children) => DropdownButtonFormField<String>(
                    value: _selectedChildId,
                    decoration: InputDecoration(labelText: terms.student),
                    isExpanded: true,
                    items: children
                        .map((c) => DropdownMenuItem(
                            value: c.id,
                            child: Text(c.fullName)))
                        .toList(),
                    onChanged: (v) =>
                        setState(() => _selectedChildId = v),
                  ),
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: _pickDate,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                        labelText: 'Data proposta'),
                    child: Text(DateFormat('dd/MM/yyyy')
                        .format(_proposedDate)),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _timeCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Hora (opcional, ex: 10:00)',
                    prefixIcon: Icon(Icons.access_time),
                  ),
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
              : const Text('Agendar'),
        ),
      ],
    );
  }
}
