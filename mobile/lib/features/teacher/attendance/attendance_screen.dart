import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_client.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/models/attendance.dart';
import '../../../core/models/school_terms.dart';
import '../../../core/providers/currency_provider.dart';

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------
final attendanceTodayProvider =
    FutureProvider.autoDispose<AttendanceSummary>((ref) async {
  final api = ref.read(apiClientProvider);
  final data = await api.get('/attendance/today');
  if (data is Map<String, dynamic>) {
    return AttendanceSummary.fromJson(data);
  }
  // If endpoint returns a list instead of a summary object
  if (data is List) {
    final records = data
        .map((e) => AttendanceRecord.fromJson(e as Map<String, dynamic>))
        .toList();
    final checkedIn =
        records.where((r) => r.status == 'present' || r.status == 'late').length;
    final checkedOut =
        records.where((r) => r.checkOutTime != null && r.checkOutTime!.isNotEmpty).length;
    final absent = records.where((r) => r.status == 'absent').length;
    return AttendanceSummary(
      totalEnrolled: records.length,
      checkedIn: checkedIn,
      checkedOut: checkedOut,
      absent: absent,
      records: records,
    );
  }
  return const AttendanceSummary(
    totalEnrolled: 0,
    checkedIn: 0,
    checkedOut: 0,
    absent: 0,
    records: [],
  );
});

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------
class AttendanceScreen extends ConsumerStatefulWidget {
  const AttendanceScreen({super.key});

  @override
  ConsumerState<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends ConsumerState<AttendanceScreen> {
  String _searchQuery = '';
  bool _isBulkLoading = false;

  @override
  Widget build(BuildContext context) {
    final attendanceAsync = ref.watch(attendanceTodayProvider);
    final auth = ref.watch(authProvider);
    final today = DateFormat('d \'de\' MMMM yyyy', 'pt_PT').format(DateTime.now());
    final terms = SchoolTerms.of(ref.watch(schoolInfoProvider).valueOrNull);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Presenças de Hoje'),
            Text(
              today,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withOpacity(0.6),
                  ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Histórico',
            onPressed: () => context.push('/teacher/attendance/history'),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
            onPressed: () => ref.invalidate(attendanceTodayProvider),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isBulkLoading ? null : _markAllPresent,
        icon: _isBulkLoading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.done_all),
        label: const Text('Marcar todos presentes'),
      ),
      body: attendanceAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorView(
          message: e.toString(),
          onRetry: () => ref.invalidate(attendanceTodayProvider),
        ),
        data: (summary) {
          final filtered = summary.records
              .where((r) =>
                  _searchQuery.isEmpty ||
                  r.childName
                      .toLowerCase()
                      .contains(_searchQuery.toLowerCase()))
              .toList();

          return Column(
            children: [
              // Stats card
              Container(
                margin: const EdgeInsets.all(16),
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
                      value: '${summary.totalEnrolled}',
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    _StatChip(
                      label: 'Presentes',
                      value: '${summary.checkedIn}',
                      color: Colors.green,
                    ),
                    _StatChip(
                      label: 'Saíram',
                      value: '${summary.checkedOut}',
                      color: Colors.blue,
                    ),
                    _StatChip(
                      label: 'Ausentes',
                      value: '${summary.absent}',
                      color: Colors.red,
                    ),
                  ],
                ),
              ),

              // Search bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Pesquisar ${terms.student.toLowerCase()}...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                  ),
                  onChanged: (v) => setState(() => _searchQuery = v),
                ),
              ),
              const SizedBox(height: 8),

              // List
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Text('Nenhum ${terms.student.toLowerCase()} encontrado'),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
                        itemCount: filtered.length,
                        itemBuilder: (context, i) {
                          return _AttendanceCard(
                            record: filtered[i],
                            onCheckIn: () =>
                                _checkIn(filtered[i].childId),
                            onCheckOut: () =>
                                _checkOut(filtered[i].childId),
                            onTap: auth.isAdmin
                                ? () => context.push('/admin/children/${filtered[i].childId}')
                                : null,
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _checkIn(String childId) async {
    try {
      await ref
          .read(apiClientProvider)
          .post('/attendance/checkin', data: {'child_id': childId});
      ref.invalidate(attendanceTodayProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao registar entrada: $e')),
        );
      }
    }
  }

  Future<void> _checkOut(String childId) async {
    try {
      await ref
          .read(apiClientProvider)
          .post('/attendance/checkout', data: {'child_id': childId});
      ref.invalidate(attendanceTodayProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao registar saída: $e')),
        );
      }
    }
  }

  Future<void> _markAllPresent() async {
    setState(() => _isBulkLoading = true);
    final terms = SchoolTerms.of(ref.read(schoolInfoProvider).valueOrNull);
    try {
      final summary = ref.read(attendanceTodayProvider).value;
      final today = DateTime.now();
      final dateStr =
          '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      final records = (summary?.records ?? [])
          .where((r) => r.status != 'present' && r.status != 'late')
          .map((r) => {'child_id': r.childId, 'status': 'present'})
          .toList();
      if (records.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Todos os ${terms.students.toLowerCase()} já marcados')),
          );
        }
        setState(() => _isBulkLoading = false);
        return;
      }
      await ref
          .read(apiClientProvider)
          .post('/attendance/bulk', data: {'date': dateStr, 'records': records});
      ref.invalidate(attendanceTodayProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Todos os ${terms.students.toLowerCase()} marcados como presentes'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isBulkLoading = false);
    }
  }
}

// ---------------------------------------------------------------------------
// Widgets
// ---------------------------------------------------------------------------

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withOpacity(0.4)),
          ),
          child: Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ],
    );
  }
}

class _AttendanceCard extends StatelessWidget {
  final AttendanceRecord record;
  final VoidCallback onCheckIn;
  final VoidCallback onCheckOut;
  final VoidCallback? onTap;

  const _AttendanceCard({
    required this.record,
    required this.onCheckIn,
    required this.onCheckOut,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final initials = record.childName.isNotEmpty
        ? record.childName.trim().split(' ').take(2).map((w) => w[0]).join()
        : '?';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // Avatar
            CircleAvatar(
              radius: 22,
              backgroundColor:
                  Theme.of(context).colorScheme.primaryContainer,
              child: Text(
                initials.toUpperCase(),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
            ),
            const SizedBox(width: 12),

            // Name + status
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    record.childName,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _statusChip(context, record.status),
                      if (record.checkInTime != null &&
                          record.checkInTime!.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Text(
                          'Entrada: ${record.checkInTime}',
                          style:
                              Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),

            // Actions
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (record.status != 'present' && record.status != 'late')
                  IconButton(
                    icon: const Icon(Icons.login, color: Colors.green),
                    tooltip: 'Check-in',
                    onPressed: onCheckIn,
                  ),
                if ((record.status == 'present' || record.status == 'late') &&
                    (record.checkOutTime == null ||
                        record.checkOutTime!.isEmpty))
                  IconButton(
                    icon: const Icon(Icons.logout, color: Colors.blue),
                    tooltip: 'Check-out',
                    onPressed: onCheckOut,
                  ),
              ],
            ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _statusChip(BuildContext context, String status) {
    Color color;
    String label;
    switch (status) {
      case 'present':
        color = Colors.green;
        label = 'Presente';
        break;
      case 'late':
        color = Colors.orange;
        label = 'Tarde';
        break;
      case 'absent':
        color = Colors.red;
        label = 'Ausente';
        break;
      case 'excused':
        color = Colors.purple;
        label = 'Justificado';
        break;
      default:
        color = Colors.grey;
        label = '—';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
            color: color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
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
      child: Padding(
        padding: const EdgeInsets.all(24),
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
      ),
    );
  }
}
