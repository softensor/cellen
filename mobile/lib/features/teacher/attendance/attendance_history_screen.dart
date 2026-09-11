import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_client.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/auth/auth_state.dart';
import '../../../core/models/school_terms.dart';
import '../../../core/providers/currency_provider.dart';

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

final _attendanceHistoryProvider = FutureProvider.autoDispose
    .family<List<_HistoryRecord>, _HistoryQuery>((ref, query) async {
  final api = ref.read(apiClientProvider);
  final params = <String, String>{};
  if (query.childId != null) params['child_id'] = query.childId!;
  if (query.from != null) {
    params['start_date'] = DateFormat('yyyy-MM-dd').format(query.from!);
  }
  if (query.to != null) {
    params['end_date'] = DateFormat('yyyy-MM-dd').format(query.to!);
  }
  final qs = params.entries.map((e) => '${e.key}=${e.value}').join('&');
  final path = '/attendance/history${qs.isNotEmpty ? '?$qs' : ''}';

  final data = await api.get(path);
  if (data is List) {
    return data
        .map((e) => _HistoryRecord.fromJson(e as Map<String, dynamic>))
        .toList();
  }
  if (data is Map<String, dynamic> && data.containsKey('records')) {
    return (data['records'] as List)
        .map((e) => _HistoryRecord.fromJson(e as Map<String, dynamic>))
        .toList();
  }
  return [];
});

final _childrenPickerProvider = FutureProvider.autoDispose((ref) async {
  final api = ref.read(apiClientProvider);
  final auth = ref.read(authProvider);
  final path =
      auth.role == UserRole.parent ? '/parent/children' : '/children?limit=200';
  final data = await api.get(path) as List;
  return data.map((e) {
    final m = e as Map<String, dynamic>;
    return _ChildOption(
      id: m['id']?.toString() ?? '',
      name: '${m['first_name'] ?? ''} ${m['last_name'] ?? ''}'.trim(),
    );
  }).toList();
});

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

class _HistoryQuery {
  final String? childId;
  final DateTime? from;
  final DateTime? to;

  const _HistoryQuery({this.childId, this.from, this.to});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _HistoryQuery &&
          childId == other.childId &&
          from == other.from &&
          to == other.to;

  @override
  int get hashCode => Object.hash(childId, from, to);
}

class _ChildOption {
  final String id;
  final String name;
  const _ChildOption({required this.id, required this.name});
}

class _HistoryRecord {
  final String id;
  final String childId;
  final String childName;
  final String date;
  final String status;
  final String? checkInTime;
  final String? checkOutTime;
  final String? notes;

  const _HistoryRecord({
    required this.id,
    required this.childId,
    required this.childName,
    required this.date,
    required this.status,
    this.checkInTime,
    this.checkOutTime,
    this.notes,
  });

  factory _HistoryRecord.fromJson(Map<String, dynamic> json) {
    return _HistoryRecord(
      id: json['id']?.toString() ?? '',
      childId: json['child_id']?.toString() ?? '',
      childName: json['child_name']?.toString() ??
          json['child_full_name']?.toString() ??
          '',
      date: json['attendance_date']?.toString() ??
          json['status_date']?.toString() ??
          json['log_date']?.toString() ??
          '',
      status: json['status']?.toString() ?? 'absent',
      checkInTime:
          json['check_in_time']?.toString() ?? json['checkin_time']?.toString(),
      checkOutTime: json['check_out_time']?.toString() ??
          json['checkout_time']?.toString(),
      notes: json['notes']?.toString(),
    );
  }
}

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class AttendanceHistoryScreen extends ConsumerStatefulWidget {
  const AttendanceHistoryScreen({super.key});

  @override
  ConsumerState<AttendanceHistoryScreen> createState() =>
      _AttendanceHistoryScreenState();
}

class _AttendanceHistoryScreenState
    extends ConsumerState<AttendanceHistoryScreen> {
  String? _selectedChildId;
  bool _childInitialized = false;
  DateTime _from = DateTime.now().subtract(const Duration(days: 30));
  DateTime _to = DateTime.now();

  _HistoryQuery get _query =>
      _HistoryQuery(childId: _selectedChildId, from: _from, to: _to);

  @override
  Widget build(BuildContext context) {
    final auth = ref.read(authProvider);
    final isParent = auth.role == UserRole.parent;
    final historyAsync = ref.watch(_attendanceHistoryProvider(_query));
    final childrenAsync = ref.watch(_childrenPickerProvider);
    final dateFmt = DateFormat('dd/MM/yyyy');
    final terms = SchoolTerms.of(ref.watch(schoolInfoProvider).valueOrNull);

    // Auto-select first child for parents (they can't use "all children" endpoint)
    childrenAsync.whenData((children) {
      if (isParent && !_childInitialized && children.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _selectedChildId == null) {
            setState(() {
              _selectedChildId = children.first.id;
              _childInitialized = true;
            });
          }
        });
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Histórico de Presenças'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(_attendanceHistoryProvider(_query)),
          ),
        ],
      ),
      body: Column(
        children: [
          // Filters
          Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Child picker
                childrenAsync.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (_, __) => const SizedBox.shrink(),
                  data: (children) {
                    return DropdownButtonFormField<String?>(
                      initialValue: _selectedChildId,
                      decoration: InputDecoration(
                        labelText: terms.student,
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                      ),
                      items: [
                        if (!isParent)
                          DropdownMenuItem<String?>(
                            value: null,
                            child: Text(
                                'Todos os ${terms.students.toLowerCase()}'),
                          ),
                        ...children.map((c) => DropdownMenuItem<String?>(
                              value: c.id,
                              child: Text(c.name),
                            )),
                      ],
                      onChanged: (v) => setState(() => _selectedChildId = v),
                    );
                  },
                ),
                const SizedBox(height: 12),
                // Date range
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _from,
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now(),
                          );
                          if (picked != null) setState(() => _from = picked);
                        },
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'De',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                          ),
                          child: Text(dateFmt.format(_from)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _to,
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now(),
                          );
                          if (picked != null) setState(() => _to = picked);
                        },
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Até',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                          ),
                          child: Text(dateFmt.format(_to)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Summary stats
          historyAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: LinearProgressIndicator(),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Erro: $e',
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
            data: (records) {
              final present =
                  records.where((r) => r.status == 'present').length;
              final absent = records.where((r) => r.status == 'absent').length;
              final late = records.where((r) => r.status == 'late').length;
              final excused =
                  records.where((r) => r.status == 'excused').length;

              return Column(
                children: [
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Theme.of(context).colorScheme.primaryContainer,
                          Theme.of(context).colorScheme.secondaryContainer,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _StatChip(
                            label: 'Total',
                            value: '${records.length}',
                            color: Theme.of(context).colorScheme.primary),
                        _StatChip(
                            label: 'Presente',
                            value: '$present',
                            color: Colors.green),
                        _StatChip(
                            label: 'Ausente',
                            value: '$absent',
                            color: Colors.red),
                        _StatChip(
                            label: 'Atraso',
                            value: '$late',
                            color: Colors.orange),
                        _StatChip(
                            label: 'Justif.',
                            value: '$excused',
                            color: Colors.blue),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              );
            },
          ),

          // Records list
          Expanded(
            child: historyAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline,
                        size: 48, color: Colors.grey),
                    const SizedBox(height: 12),
                    Text('Erro ao carregar: $e'),
                    TextButton(
                      onPressed: () =>
                          ref.invalidate(_attendanceHistoryProvider(_query)),
                      child: const Text('Tentar novamente'),
                    ),
                  ],
                ),
              ),
              data: (records) {
                if (records.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.event_busy, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text('Nenhum registo encontrado',
                            style: TextStyle(color: Colors.grey, fontSize: 16)),
                      ],
                    ),
                  );
                }

                // Group by date
                final grouped = <String, List<_HistoryRecord>>{};
                for (final r in records) {
                  grouped.putIfAbsent(r.date, () => []).add(r);
                }
                final dates = grouped.keys.toList()
                  ..sort((a, b) => b.compareTo(a));

                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  itemCount: dates.length,
                  itemBuilder: (context, i) {
                    final date = dates[i];
                    final dayRecords = grouped[date]!;
                    final formattedDate = _formatDate(date);

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            formattedDate,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                        ...dayRecords.map((r) => Card(
                              child: ListTile(
                                leading: _statusIcon(r.status),
                                title: Text(r.childName.isNotEmpty
                                    ? r.childName
                                    : terms.student),
                                subtitle: Text(
                                  [
                                    _statusLabel(r.status),
                                    if (r.checkInTime != null &&
                                        r.checkInTime!.isNotEmpty)
                                      'Entrada: ${r.checkInTime}',
                                    if (r.checkOutTime != null &&
                                        r.checkOutTime!.isNotEmpty)
                                      'Saída: ${r.checkOutTime}',
                                  ].join(' · '),
                                ),
                                trailing: _statusBadge(r.status),
                              ),
                            )),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      return DateFormat('EEEE, d \'de\' MMMM', 'pt_PT').format(date);
    } catch (_) {
      return dateStr;
    }
  }

  Widget _statusIcon(String status) {
    return switch (status) {
      'present' => const Icon(Icons.check_circle, color: Colors.green),
      'absent' => const Icon(Icons.cancel, color: Colors.red),
      'late' => const Icon(Icons.schedule, color: Colors.orange),
      'excused' => const Icon(Icons.info, color: Colors.blue),
      _ => const Icon(Icons.help_outline, color: Colors.grey),
    };
  }

  String _statusLabel(String status) {
    return switch (status) {
      'present' => 'Presente',
      'absent' => 'Ausente',
      'late' => 'Atraso',
      'excused' => 'Justificado',
      _ => status,
    };
  }

  Widget _statusBadge(String status) {
    final (color, label) = switch (status) {
      'present' => (Colors.green, 'P'),
      'absent' => (Colors.red, 'F'),
      'late' => (Colors.orange, 'A'),
      'excused' => (Colors.blue, 'J'),
      _ => (Colors.grey, '?'),
    };
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(label,
          style: TextStyle(
              color: color, fontWeight: FontWeight.bold, fontSize: 12)),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatChip(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value,
            style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.bold, color: color)),
        const SizedBox(height: 4),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}
