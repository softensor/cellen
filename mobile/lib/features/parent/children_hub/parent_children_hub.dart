import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/school_terms.dart';
import '../../../core/providers/currency_provider.dart';
import '../../../core/theme/app_theme.dart';

/// Hub for parents to access all child-specific information in one place.
/// Cards are filtered by school segment features.
class ParentChildrenHubScreen extends ConsumerWidget {
  const ParentChildrenHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final school = ref.watch(schoolInfoProvider).valueOrNull;
    final terms = SchoolTerms.of(school);
    final k12 = terms.isK12;

    final allCards = [
      // Preschool-only cards
      if (!k12 && (school?.hasFeature('caderneta') ?? true))
        (
          icon: Icons.menu_book_outlined,
          color: Colors.blue,
          label: 'Caderneta',
          description: 'Relatórios diários dos educadores — humor, sono, alimentação',
          path: '/parent/caderneta',
        ),
      if (!k12 && (school?.hasFeature('evaluations') ?? true))
        (
          icon: Icons.school_outlined,
          color: Colors.purple,
          label: 'Avaliações',
          description: 'Avaliações pedagógicas e boletim de desenvolvimento',
          path: '/evaluations',
        ),

      // K-12-only cards
      if (k12 && (school?.hasFeature('grades') ?? true))
        (
          icon: Icons.grade_outlined,
          color: Colors.green,
          label: 'Notas & Boletim',
          description: 'Notas por disciplina e trimestre — boletim escolar',
          path: '/parent/grades',
        ),

      // Shared cards (all segments)
      (
        icon: Icons.fact_check_outlined,
        color: Colors.indigo,
        label: 'Presenças',
        description: 'Histórico de presenças e faltas',
        path: '/parent/attendance',
      ),
      if (school?.hasFeature('health') ?? true)
        (
          icon: Icons.health_and_safety_outlined,
          color: Colors.red,
          label: 'Saúde',
          description: 'Registos de saúde e bem-estar',
          path: '/health',
        ),
      if (school?.hasFeature('immunizations') ?? true)
        (
          icon: Icons.vaccines_outlined,
          color: Colors.teal,
          label: 'Vacinas',
          description: 'Calendário vacinal e registos de imunização',
          path: '/health/immunizations',
        ),
      (
        icon: Icons.warning_amber_outlined,
        color: Colors.orange,
        label: 'Ocorrências',
        description: 'Incidentes e ocorrências registadas',
        path: '/incidents',
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(k12 ? 'O Meu Educando' : 'Os Meus Filhos'),
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 340,
          mainAxisExtent: 160,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: allCards.length,
        itemBuilder: (context, i) {
          final item = allCards[i];
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
