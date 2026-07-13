import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_client.dart';
import '../../../core/models/caderneta.dart';

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------
final parentCadernetasProvider =
    FutureProvider.autoDispose<List<Caderneta>>((ref) async {
  final api = ref.read(apiClientProvider);
  final data = await api.get('/cadernetas/parent',
      queryParameters: {'ordering': '-report_date'}) as List;
  return data
      .map((e) => Caderneta.fromJson(e as Map<String, dynamic>))
      .toList();
});

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------
class ChildCadernetaScreen extends ConsumerWidget {
  const ChildCadernetaScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cadernetasAsync = ref.watch(parentCadernetasProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Caderneta'),
      ),
      body: cadernetasAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 8),
              Text(e.toString()),
              TextButton(
                onPressed: () => ref.invalidate(parentCadernetasProvider),
                child: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
        data: (cadernetas) {
          if (cadernetas.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.book,
                      size: 64,
                      color:
                          Theme.of(context).colorScheme.outlineVariant),
                  const SizedBox(height: 16),
                  Text(
                    'Nenhum relatório disponível',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async =>
                ref.invalidate(parentCadernetasProvider),
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: cadernetas.length,
              itemBuilder: (context, i) {
                final c = cadernetas[i];
                final isLatest = i == 0;
                return _CadernetaCard(
                    caderneta: c, isLatest: isLatest);
              },
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Caderneta Detail Card
// ---------------------------------------------------------------------------
class _CadernetaCard extends StatelessWidget {
  final Caderneta caderneta;
  final bool isLatest;

  const _CadernetaCard(
      {required this.caderneta, required this.isLatest});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: isLatest ? 4 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isLatest
            ? BorderSide(
                color: Theme.of(context).colorScheme.primary, width: 1.5)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(Icons.calendar_today,
                    size: 16,
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  DateFormat('EEEE, d \'de\' MMMM yyyy', 'pt_PT')
                      .format(caderneta.reportDate),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
                if (isLatest) ...[
                  const Spacer(),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Hoje',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.onPrimary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ],
            ),
            const Divider(height: 20),

            // Food section
            _SectionLabel('Alimentação'),
            const SizedBox(height: 8),
            Row(
              children: [
                _FoodIndicator(
                    meal: 'Pequeno-almoço',
                    rating: caderneta.breakfastRating),
                const SizedBox(width: 8),
                _FoodIndicator(
                    meal: 'Almoço', rating: caderneta.lunchRating),
                const SizedBox(width: 8),
                _FoodIndicator(
                    meal: 'Lanche', rating: caderneta.snackRating),
              ],
            ),
            const SizedBox(height: 16),

            // Physio + Nap
            Row(
              children: [
                if (caderneta.physiologicalNeeds != null) ...[
                  Expanded(
                    child: _InfoChip(
                      icon: Icons.wc,
                      label: 'Fezes',
                      value: caderneta.physiologicalNeeds!,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                if (caderneta.hadNap != null)
                  Expanded(
                    child: _InfoChip(
                      icon: Icons.bedtime,
                      label: 'Sesta',
                      value: caderneta.hadNap! ? 'Dormiu' : 'Não dormiu',
                      valueColor: caderneta.hadNap!
                          ? Colors.green
                          : Colors.grey,
                    ),
                  ),
              ],
            ),

            // Development sections
            if (_hasDevelopment(caderneta)) ...[
              const SizedBox(height: 16),
              _SectionLabel('Desenvolvimento'),
              const SizedBox(height: 8),
              if (caderneta.sensorialMotorDevelopment != null &&
                  caderneta.sensorialMotorDevelopment!.isNotEmpty)
                _DevRow(
                    label: 'Sensorial/Motor',
                    text: caderneta.sensorialMotorDevelopment!),
              if (caderneta.intellectualDevelopment != null &&
                  caderneta.intellectualDevelopment!.isNotEmpty)
                _DevRow(
                    label: 'Intelectual',
                    text: caderneta.intellectualDevelopment!),
              if (caderneta.socialDevelopment != null &&
                  caderneta.socialDevelopment!.isNotEmpty)
                _DevRow(
                    label: 'Social',
                    text: caderneta.socialDevelopment!),
              if (caderneta.affectiveDevelopment != null &&
                  caderneta.affectiveDevelopment!.isNotEmpty)
                _DevRow(
                    label: 'Afectivo',
                    text: caderneta.affectiveDevelopment!),
            ],

            if (caderneta.generalObservations != null &&
                caderneta.generalObservations!.isNotEmpty) ...[
              const SizedBox(height: 16),
              _SectionLabel('Observações'),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(caderneta.generalObservations!),
              ),
            ],
          ],
        ),
      ),
    );
  }

  bool _hasDevelopment(Caderneta c) {
    return (c.sensorialMotorDevelopment?.isNotEmpty ?? false) ||
        (c.intellectualDevelopment?.isNotEmpty ?? false) ||
        (c.socialDevelopment?.isNotEmpty ?? false) ||
        (c.affectiveDevelopment?.isNotEmpty ?? false);
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
    );
  }
}

class _FoodIndicator extends StatelessWidget {
  final String meal;
  final String? rating;

  const _FoodIndicator({required this.meal, this.rating});

  @override
  Widget build(BuildContext context) {
    Color color;
    IconData icon;
    if (rating == null) {
      color = Colors.grey.shade300;
      icon = Icons.remove;
    } else {
      switch (rating) {
        case 'Muito Bem':
          color = Colors.green;
          icon = Icons.sentiment_very_satisfied;
          break;
        case 'Bem':
          color = Colors.teal;
          icon = Icons.sentiment_satisfied;
          break;
        case 'Mal':
          color = Colors.red;
          icon = Icons.sentiment_dissatisfied;
          break;
        case 'Não Comeu':
          color = Colors.orange;
          icon = Icons.no_food;
          break;
        default:
          color = Colors.grey;
          icon = Icons.remove;
      }
    }

    return Expanded(
      child: Column(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: color.withOpacity(0.15),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 4),
          Text(
            meal,
            style: const TextStyle(fontSize: 10),
            textAlign: TextAlign.center,
          ),
          if (rating != null)
            Text(
              rating!,
              style: TextStyle(
                  fontSize: 10,
                  color: color,
                  fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const _InfoChip({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon,
              size: 16,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(fontSize: 10, color: Colors.grey)),
              Text(
                value,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: valueColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DevRow extends StatelessWidget {
  final String label;
  final String text;

  const _DevRow({required this.label, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color:
                    Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
