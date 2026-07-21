import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_client.dart';

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------
class Enrollment {
  final String id;
  final String childId;
  final String childName;
  final String turmaId;
  final String turmaName;
  final String schoolYear;
  final String status; // active, withdrawn, graduated, pending

  const Enrollment({
    required this.id,
    required this.childId,
    required this.childName,
    required this.turmaId,
    required this.turmaName,
    required this.schoolYear,
    required this.status,
  });

  String get statusLabel {
    switch (status) {
      case 'active':
        return 'Activo';
      case 'withdrawn':
        return 'Desistência';
      case 'graduated':
        return 'Concluído';
      case 'pending':
        return 'Pendente';
      default:
        return status;
    }
  }

  factory Enrollment.fromJson(Map<String, dynamic> json) {
    return Enrollment(
      id: json['id']?.toString() ?? '',
      childId: json['child_id']?.toString() ?? '',
      childName: json['child_name'] as String? ?? '',
      turmaId: json['turma_id']?.toString() ?? '',
      turmaName: json['turma_name'] as String? ?? '',
      schoolYear: json['school_year'] as String? ?? '',
      status: json['status'] as String? ?? 'active',
    );
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------
final enrollmentsProvider =
    FutureProvider.autoDispose<List<Enrollment>>((ref) async {
  final api = ref.read(apiClientProvider);
  final data = await api.get('/academic/enrollments') as List;
  return data
      .map((e) => Enrollment.fromJson(e as Map<String, dynamic>))
      .toList();
});

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------
class EnrollmentsScreen extends ConsumerStatefulWidget {
  const EnrollmentsScreen({super.key});

  @override
  ConsumerState<EnrollmentsScreen> createState() =>
      _EnrollmentsScreenState();
}

class _EnrollmentsScreenState
    extends ConsumerState<EnrollmentsScreen> {
  String? _schoolYearFilter;

  @override
  Widget build(BuildContext context) {
    final enrollmentsAsync = ref.watch(enrollmentsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Matrículas'),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCreateEnrollmentSheet(context),
        tooltip: 'Nova Matrícula',
        child: const Icon(Icons.add),
      ),
      body: enrollmentsAsync.when(
        loading: () =>
            const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline,
                  size: 48, color: Colors.red),
              const SizedBox(height: 8),
              Text(e.toString()),
              TextButton(
                onPressed: () =>
                    ref.invalidate(enrollmentsProvider),
                child: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
        data: (enrollments) {
          // Build list of unique school years for filter
          final schoolYears =
              enrollments.map((e) => e.schoolYear).toSet().toList()
                ..sort((a, b) => b.compareTo(a));

          final filtered = _schoolYearFilter == null
              ? enrollments
              : enrollments
                  .where(
                      (e) => e.schoolYear == _schoolYearFilter)
                  .toList();

          if (enrollments.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.how_to_reg,
                      size: 64,
                      color: Theme.of(context)
                          .colorScheme
                          .outlineVariant),
                  const SizedBox(height: 16),
                  Text('Nenhuma matrícula encontrada',
                      style: Theme.of(context).textTheme.bodyLarge),
                ],
              ),
            );
          }

          return Column(
            children: [
              // School year filter
              if (schoolYears.isNotEmpty)
                Padding(
                  padding:
                      const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        FilterChip(
                          label: const Text('Todos'),
                          selected: _schoolYearFilter == null,
                          onSelected: (_) => setState(
                              () => _schoolYearFilter = null),
                          showCheckmark: false,
                        ),
                        const SizedBox(width: 8),
                        ...schoolYears.map(
                          (year) => Padding(
                            padding:
                                const EdgeInsets.only(right: 8),
                            child: FilterChip(
                              label: Text(year),
                              selected:
                                  _schoolYearFilter == year,
                              onSelected: (_) => setState(
                                  () =>
                                      _schoolYearFilter = year),
                              showCheckmark: false,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // Table
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async =>
                      ref.invalidate(enrollmentsProvider),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columnSpacing: 24,
                      columns: const [
                        DataColumn(label: Text('Criança')),
                        DataColumn(label: Text('Turma')),
                        DataColumn(
                            label: Text('Ano Lectivo')),
                        DataColumn(label: Text('Estado')),
                      ],
                      rows: filtered.map((e) {
                        return DataRow(cells: [
                          DataCell(Text(e.childName)),
                          DataCell(Text(e.turmaName)),
                          DataCell(Text(e.schoolYear)),
                          DataCell(_StatusChip(
                              status: e.status,
                              label: e.statusLabel)),
                        ]);
                      }).toList(),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showCreateEnrollmentSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CreateEnrollmentSheet(
        onCreated: () {
          ref.invalidate(enrollmentsProvider);
          Navigator.pop(context);
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Create enrollment bottom sheet
// ---------------------------------------------------------------------------
class _CreateEnrollmentSheet extends ConsumerStatefulWidget {
  final VoidCallback onCreated;

  const _CreateEnrollmentSheet({required this.onCreated});

  @override
  ConsumerState<_CreateEnrollmentSheet> createState() =>
      _CreateEnrollmentSheetState();
}

class _CreateEnrollmentSheetState
    extends ConsumerState<_CreateEnrollmentSheet> {
  final _formKey = GlobalKey<FormState>();

  // selections
  String? _selectedChildId;
  String? _selectedScheduleId;
  String? _selectedSchoolYearId;
  String _status = 'active';
  DateTime _enrollmentDate = DateTime.now();

  // loaded data
  bool _loadingChildren = true;
  bool _loadingSchedules = true;
  bool _loadingYears = true;
  List<Map<String, dynamic>> _children = [];
  List<Map<String, dynamic>> _schedules = [];
  List<Map<String, dynamic>> _schoolYears = [];

  bool _isLoading = false;
  String? _error;

  static const _statusOptions = {
    'active': 'Activo',
    'pending': 'Pendente',
    'withdrawn': 'Desistência',
    'graduated': 'Concluído',
  };

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final api = ref.read(apiClientProvider);
    await Future.wait([
      _loadChildren(api),
      _loadSchedules(api),
      _loadSchoolYears(api),
    ]);
  }

  Future<void> _loadChildren(dynamic api) async {
    try {
      final data = await api.get('/children') as List;
      if (mounted) {
        setState(() {
          _children = data
              .map((e) => e as Map<String, dynamic>)
              .toList();
          _loadingChildren = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingChildren = false);
    }
  }

  Future<void> _loadSchedules(dynamic api) async {
    try {
      final data =
          await api.get('/academic/schedules') as List;
      if (mounted) {
        setState(() {
          _schedules = data
              .map((e) => e as Map<String, dynamic>)
              .toList();
          _loadingSchedules = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingSchedules = false);
    }
  }

  Future<void> _loadSchoolYears(dynamic api) async {
    try {
      final data =
          await api.get('/schools/school-years') as List;
      if (mounted) {
        setState(() {
          _schoolYears = data
              .map((e) => e as Map<String, dynamic>)
              .toList();
          _loadingYears = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingYears = false);
    }
  }

  String _scheduleLabel(Map<String, dynamic> s) {
    final turmaName = s['turma_name'] as String?;
    final yearLabel = s['school_year_label'] as String?;
    final id = s['id']?.toString() ?? '';
    final shortId = id.length >= 8 ? id.substring(0, 8) : id;
    if (turmaName != null && yearLabel != null) {
      return '$turmaName – $yearLabel';
    } else if (turmaName != null) {
      return turmaName;
    }
    return 'Horário: $shortId';
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _enrollmentDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2050),
    );
    if (picked != null) {
      setState(() => _enrollmentDate = picked);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedChildId == null) {
      setState(() => _error = 'Seleccione uma criança');
      return;
    }
    if (_selectedScheduleId == null) {
      setState(() => _error = 'Seleccione um horário');
      return;
    }
    if (_selectedSchoolYearId == null) {
      setState(() => _error = 'Seleccione um ano lectivo');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final api = ref.read(apiClientProvider);
      final dateStr =
          '${_enrollmentDate.year.toString().padLeft(4, '0')}-${_enrollmentDate.month.toString().padLeft(2, '0')}-${_enrollmentDate.day.toString().padLeft(2, '0')}';

      await api.post('/academic/enrollments', data: {
        'child_id': _selectedChildId,
        'schedule_id': _selectedScheduleId,
        'school_year_id': _selectedSchoolYearId,
        'enrollment_date': dateStr,
        'status': _status,
      });

      widget.onCreated();
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoadingData =
        _loadingChildren || _loadingSchedules || _loadingYears;
    final displayFmt = DateFormat('dd/MM/yyyy');

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: isLoadingData
          ? const SizedBox(
              height: 120,
              child: Center(child: CircularProgressIndicator()))
          : Form(
              key: _formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Nova Matrícula',
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(
                              fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),

                    // Child dropdown
                    DropdownButtonFormField<String>(
                      value: _selectedChildId,
                      decoration: const InputDecoration(
                        labelText: 'Criança *',
                        prefixIcon: Icon(Icons.child_care),
                      ),
                      items: _children
                          .map((c) {
                                final fullName = (c['full_name'] as String?) ??
                                    (c['name'] as String?);
                                final composed = fullName ??
                                    [c['first_name']?.toString(), c['last_name']?.toString()]
                                        .where((s) => s != null && s.isNotEmpty)
                                        .join(' ');
                                return DropdownMenuItem(
                                  value: c['id']?.toString() ?? '',
                                  child: Text(composed.isNotEmpty ? composed : c['id']?.toString() ?? ''),
                                );
                              })
                          .toList(),
                      onChanged: (v) =>
                          setState(() => _selectedChildId = v),
                      validator: (v) => v == null
                          ? 'Seleccione uma criança'
                          : null,
                    ),
                    const SizedBox(height: 12),

                    // Schedule dropdown
                    DropdownButtonFormField<String>(
                      value: _selectedScheduleId,
                      decoration: const InputDecoration(
                        labelText: 'Horário / Turma *',
                        prefixIcon: Icon(Icons.schedule),
                      ),
                      items: _schedules
                          .map((s) => DropdownMenuItem(
                                value:
                                    s['id']?.toString() ?? '',
                                child: Text(
                                    _scheduleLabel(s)),
                              ))
                          .toList(),
                      onChanged: (v) {
                        setState(() {
                          _selectedScheduleId = v;
                          // Auto-populate school year if
                          // schedule carries school_year_id
                          if (v != null) {
                            final sch = _schedules
                                .firstWhere(
                                    (s) =>
                                        s['id']?.toString() ==
                                        v,
                                    orElse: () => {});
                            final syId = sch[
                                    'school_year_id']
                                ?.toString();
                            if (syId != null &&
                                syId.isNotEmpty) {
                              _selectedSchoolYearId = syId;
                            }
                          }
                        });
                      },
                      validator: (v) => v == null
                          ? 'Seleccione um horário'
                          : null,
                    ),
                    const SizedBox(height: 12),

                    // School year dropdown
                    DropdownButtonFormField<String>(
                      value: _selectedSchoolYearId,
                      decoration: const InputDecoration(
                        labelText: 'Ano Lectivo *',
                        prefixIcon: Icon(Icons.school),
                      ),
                      items: _schoolYears
                          .map((y) => DropdownMenuItem(
                                value:
                                    y['id']?.toString() ?? '',
                                child: Text(
                                    y['year_label']
                                            as String? ??
                                        ''),
                              ))
                          .toList(),
                      onChanged: (v) => setState(
                          () => _selectedSchoolYearId = v),
                      validator: (v) => v == null
                          ? 'Seleccione um ano lectivo'
                          : null,
                    ),
                    const SizedBox(height: 12),

                    // Status dropdown
                    DropdownButtonFormField<String>(
                      value: _status,
                      decoration: const InputDecoration(
                        labelText: 'Estado *',
                        prefixIcon:
                            Icon(Icons.flag_outlined),
                      ),
                      items: _statusOptions.entries
                          .map((e) => DropdownMenuItem(
                                value: e.key,
                                child: Text(e.value),
                              ))
                          .toList(),
                      onChanged: (v) =>
                          setState(() => _status = v!),
                    ),
                    const SizedBox(height: 12),

                    // Enrollment date
                    InkWell(
                      onTap: _pickDate,
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Data de Matrícula',
                          prefixIcon:
                              Icon(Icons.calendar_today),
                        ),
                        child: Text(
                            displayFmt.format(_enrollmentDate)),
                      ),
                    ),

                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .error),
                      ),
                    ],

                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _isLoading ? null : _submit,
                      child: _isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white))
                          : const Text('Criar Matrícula'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  final String label;
  const _StatusChip({required this.status, required this.label});

  @override
  Widget build(BuildContext context) {
    Color color;
    switch (status) {
      case 'active':
        color = Colors.green;
        break;
      case 'withdrawn':
        color = Colors.red;
        break;
      case 'graduated':
        color = Colors.blue;
        break;
      default:
        color = Colors.orange;
    }
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w600),
      ),
    );
  }
}
