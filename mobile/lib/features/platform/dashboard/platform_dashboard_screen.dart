import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';

class PlatformDashboardScreen extends ConsumerStatefulWidget {
  const PlatformDashboardScreen({super.key});

  @override
  ConsumerState<PlatformDashboardScreen> createState() =>
      _PlatformDashboardScreenState();
}

class _PlatformDashboardScreenState
    extends ConsumerState<PlatformDashboardScreen> {
  Map<String, dynamic>? _stats;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      final data = await api.get('/platform/stats');
      setState(() {
        _stats = Map<String, dynamic>.from(data as Map);
        _loading = false;
      });
    } on ApiException catch (e) {
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Plataforma Cellen')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.error_outline,
                            color: theme.colorScheme.error, size: 48),
                        const SizedBox(height: 8),
                        Text(_error!),
                        TextButton(
                          onPressed: _load,
                          child: const Text('Tentar novamente'),
                        ),
                      ],
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text('Resumo da Plataforma',
                          style: theme.textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text('Visão geral de todas as escolas na plataforma',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: Colors.grey)),
                      const SizedBox(height: 16),
                      _StatsGrid(stats: _stats!, onSchoolsTap: () => context.go('/platform/schools')),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: () => context.go('/platform/schools'),
                        icon: const Icon(Icons.school_outlined),
                        label: const Text('Gerir Escolas'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                        ),
                      ),
                      const SizedBox(height: 10),
                      FilledButton.tonalIcon(
                        onPressed: () => context.go('/platform/payments'),
                        icon: const Icon(Icons.payments_outlined),
                        label: const Text('Pagamentos e referências'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  final Map<String, dynamic> stats;
  final VoidCallback onSchoolsTap;
  const _StatsGrid({required this.stats, required this.onSchoolsTap});

  @override
  Widget build(BuildContext context) {
    final items = [
      (label: 'Total de Escolas',    value: '${stats['total_schools'] ?? 0}',        icon: Icons.school,      color: Colors.blue,   onTap: onSchoolsTap),
      (label: 'Escolas Activas',     value: '${stats['active_schools'] ?? 0}',        icon: Icons.check_circle, color: Colors.green,  onTap: onSchoolsTap),
      (label: 'Total de Crianças',   value: '${stats['total_children'] ?? 0}',        icon: Icons.child_care,  color: Colors.orange, onTap: null),
      (label: 'Utilizadores Activos',value: '${stats['total_active_users'] ?? 0}',    icon: Icons.people,      color: Colors.purple, onTap: null),
    ];

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.4,
      children: items.map((item) {
        return Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: item.onTap,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(item.icon, color: item.color, size: 32),
                  const SizedBox(height: 8),
                  Text(
                    item.value,
                    style: Theme.of(context)
                        .textTheme
                        .headlineMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    item.label,
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                  if (item.onTap != null) ...[
                    const SizedBox(height: 4),
                    Text('Ver detalhes →',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: item.color, fontWeight: FontWeight.w600),
                        textAlign: TextAlign.center),
                  ],
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
