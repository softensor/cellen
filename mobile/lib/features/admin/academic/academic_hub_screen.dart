import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/school_terms.dart';
import '../../../core/providers/currency_provider.dart';
import '../../../core/theme/app_theme.dart';

class AcademicHubScreen extends ConsumerWidget {
  const AcademicHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final school = ref.watch(schoolInfoProvider).valueOrNull;
    final terms = SchoolTerms.of(school);
    final k12 = terms.isK12;

    // ── Shared items (all segments) ──────────────────────────────────────────
    final shared = [
      (
        icon: Icons.fact_check_outlined,
        color: Colors.blue,
        label: 'Presenças',
        description: 'Registo diário de ${terms.students.toLowerCase()}',
        path: '/teacher/attendance',
        feature: null,
      ),
      (
        icon: Icons.event_busy_outlined,
        color: Colors.red,
        label: 'Faltas',
        description: 'Faltas e ausências de funcionários',
        path: '/admin/absences',
        feature: null,
      ),
      (
        icon: terms.classroomIcon,
        color: Colors.teal,
        label: 'Turmas',
        description: 'Gestão das turmas e ${terms.students.toLowerCase()}',
        path: '/admin/academic/turmas',
        feature: null,
      ),
      (
        icon: Icons.how_to_reg_outlined,
        color: Colors.orange,
        label: 'Matrículas',
        description: 'Matrículas e transferências de turma',
        path: '/admin/academic/enrollments',
        feature: null,
      ),
    ];

    // ── K-12 specific ────────────────────────────────────────────────────────
    final k12Items = [
      (
        icon: Icons.table_chart_outlined,
        color: Colors.indigo,
        label: 'Horário Lectivo',
        description: 'Grade de horário: períodos × dias × disciplinas',
        path: '/admin/academic/timetable',
        feature: 'timetable_k12',
      ),
      (
        icon: Icons.how_to_reg_outlined,
        color: Colors.deepOrange,
        label: 'Livro de Ponto',
        description: 'Presenças por aula — registo de faltas por disciplina',
        path: '/lesson-attendance',
        feature: 'timetable_k12',
      ),
      (
        icon: Icons.book_outlined,
        color: Colors.purple,
        label: 'Disciplinas',
        description: 'Disciplinas lectivas e currículos',
        path: '/admin/academic/subjects',
        feature: 'subjects',
      ),
      (
        icon: Icons.assignment_outlined,
        color: Colors.teal,
        label: 'Pautas & Notas',
        description: 'Disciplinas por turma e lançamento de notas',
        path: '/admin/academic/turma-subjects',
        feature: 'grades',
      ),
      (
        icon: Icons.grade_outlined,
        color: Colors.green,
        label: 'Boletins',
        description: 'Boletins e médias por turma e aluno',
        path: '/admin/academic/report-cards',
        feature: 'grades',
      ),
    ];

    // ── Preschool specific ───────────────────────────────────────────────────
    final preschoolItems = [
      (
        icon: Icons.schedule_outlined,
        color: Colors.orange,
        label: 'Horários',
        description: 'Horários semanais por grupo e actividade',
        path: '/admin/academic/schedules',
        feature: null,
      ),
      (
        icon: Icons.menu_book_outlined,
        color: Colors.purple,
        label: 'Caderneta',
        description: 'Relatórios diários pelos educadores',
        path: '/teacher/caderneta',
        feature: 'caderneta',
      ),
      (
        icon: Icons.school_outlined,
        color: Colors.purple,
        label: 'Avaliações',
        description: 'Avaliações pedagógicas de desenvolvimento',
        path: '/evaluations',
        feature: 'evaluations',
      ),
    ];

    final allItems = [
      ...shared,
      if (k12) ...k12Items else ...preschoolItems,
    ].where((item) => item.feature == null || (school?.hasFeature(item.feature!) ?? true)).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Académico')),
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 340,
          mainAxisExtent: 160,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: allItems.length,
        itemBuilder: (context, i) {
          final item = allItems[i];
          return _HubCard(
            icon: item.icon,
            color: item.color,
            label: item.label,
            description: item.description,
            onTap: () => context.push(item.path),
          );
        },
      ),
    );
  }
}

class _HubCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String description;
  final VoidCallback onTap;

  const _HubCard({
    required this.icon,
    required this.color,
    required this.label,
    required this.description,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: color.withAlpha(60), width: 1.5),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withAlpha(25),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 26),
              ),
              const SizedBox(height: 12),
              Text(label,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 4),
              Text(description,
                  style: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 12),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }
}
