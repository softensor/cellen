import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_client.dart';
import '../../../core/models/caderneta.dart';

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------
final cadernetaListProvider =
    FutureProvider.autoDispose<List<Caderneta>>((ref) async {
  final api = ref.read(apiClientProvider);
  final data = await api.get('/cadernetas/my',
      queryParameters: {'ordering': '-report_date'}) as List;
  return data
      .map((e) => Caderneta.fromJson(e as Map<String, dynamic>))
      .toList();
});

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------
class CadernetaListScreen extends ConsumerWidget {
  const CadernetaListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cadernetasAsync = ref.watch(cadernetaListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cadernetas'),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/teacher/caderneta/new'),
        tooltip: 'Nova Caderneta',
        child: const Icon(Icons.add),
      ),
      body: cadernetasAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 8),
              Text(e.toString(), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => ref.invalidate(cadernetaListProvider),
                icon: const Icon(Icons.refresh),
                label: const Text('Tentar novamente'),
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
                    'Nenhuma caderneta preenchida',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () =>
                        context.push('/teacher/caderneta/new'),
                    icon: const Icon(Icons.add),
                    label: const Text('Preencher Caderneta'),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async =>
                ref.invalidate(cadernetaListProvider),
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 88),
              itemCount: cadernetas.length,
              itemBuilder: (context, i) {
                final c = cadernetas[i];
                return _CadernetaTile(caderneta: c);
              },
            ),
          );
        },
      ),
    );
  }
}

class _CadernetaTile extends StatelessWidget {
  final Caderneta caderneta;
  const _CadernetaTile({required this.caderneta});

  @override
  Widget build(BuildContext context) {
    final ratings = [
      if (caderneta.breakfastRating != null)
        ('PA', caderneta.breakfastRating!),
      if (caderneta.lunchRating != null) ('Almoço', caderneta.lunchRating!),
      if (caderneta.snackRating != null) ('Lanche', caderneta.snackRating!),
    ];

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor:
              Theme.of(context).colorScheme.secondaryContainer,
          child: Icon(Icons.book,
              color: Theme.of(context).colorScheme.onSecondaryContainer),
        ),
        title: Text(
          caderneta.childName ??
              'Criança ${caderneta.childId.substring(0, 6)}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(DateFormat('dd/MM/yyyy').format(caderneta.reportDate)),
            if (ratings.isNotEmpty) ...[
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                children: ratings
                    .map((r) => _RatingBadge(meal: r.$1, rating: r.$2))
                    .toList(),
              ),
            ],
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () =>
            context.push('/teacher/caderneta/${caderneta.id}/edit'),
      ),
    );
  }
}

class _RatingBadge extends StatelessWidget {
  final String meal;
  final String rating;
  const _RatingBadge({required this.meal, required this.rating});

  @override
  Widget build(BuildContext context) {
    Color color;
    switch (rating) {
      case 'Muito Bem':
        color = Colors.green;
        break;
      case 'Bem':
        color = Colors.teal;
        break;
      case 'Mal':
        color = Colors.red;
        break;
      case 'Não Comeu':
        color = Colors.orange;
        break;
      default:
        color = Colors.grey;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$meal: $rating',
        style: TextStyle(
            color: color, fontSize: 10, fontWeight: FontWeight.w600),
      ),
    );
  }
}
