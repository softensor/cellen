import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

class _EnrollmentsScreenState extends ConsumerState<EnrollmentsScreen> {
  String? _schoolYearFilter;

  @override
  Widget build(BuildContext context) {
    final enrollmentsAsync = ref.watch(enrollmentsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Matrículas'),
      ),
      body: enrollmentsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 8),
              Text(e.toString()),
              TextButton(
                onPressed: () => ref.invalidate(enrollmentsProvider),
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
                  .where((e) => e.schoolYear == _schoolYearFilter)
                  .toList();

          if (enrollments.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.how_to_reg,
                      size: 64,
                      color: Theme.of(context).colorScheme.outlineVariant),
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
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        FilterChip(
                          label: const Text('Todos'),
                          selected: _schoolYearFilter == null,
                          onSelected: (_) =>
                              setState(() => _schoolYearFilter = null),
                          showCheckmark: false,
                        ),
                        const SizedBox(width: 8),
                        ...schoolYears.map(
                          (year) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: FilterChip(
                              label: Text(year),
                              selected: _schoolYearFilter == year,
                              onSelected: (_) =>
                                  setState(() => _schoolYearFilter = year),
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
                        DataColumn(label: Text('Ano Lectivo')),
                        DataColumn(label: Text('Estado')),
                      ],
                      rows: filtered.map((e) {
                        return DataRow(cells: [
                          DataCell(Text(e.childName)),
                          DataCell(Text(e.turmaName)),
                          DataCell(Text(e.schoolYear)),
                          DataCell(_StatusChip(
                              status: e.status, label: e.statusLabel)),
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
            color: color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}
