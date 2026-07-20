import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';

class ParentAuthHubScreen extends StatelessWidget {
  const ParentAuthHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const items = [
      (
        icon: Icons.assignment_outlined,
        color: Colors.blue,
        label: 'Visitas de Estudo',
        description: 'Autorizar ou recusar pedidos de visitas de estudo',
        path: '/trip-authorizations',
      ),
      (
        icon: Icons.transfer_within_a_station_outlined,
        color: Colors.teal,
        label: 'Levantamentos',
        description: 'Gerir pessoas autorizadas a levantar o seu filho',
        path: '/pickup-authorizations',
      ),
      (
        icon: Icons.lunch_dining_outlined,
        color: Colors.orange,
        label: 'Refeições',
        description: 'Pedir e gerir refeições para o seu filho',
        path: '/meal-orders',
      ),
      (
        icon: Icons.event_available_outlined,
        color: Colors.purple,
        label: 'Marcações',
        description: 'Agendar reuniões com educadores e administração',
        path: '/appointments',
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Autorizações')),
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 340,
          mainAxisExtent: 160,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: items.length,
        itemBuilder: (context, i) {
          final item = items[i];
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
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 4),
              Text(description,
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }
}
