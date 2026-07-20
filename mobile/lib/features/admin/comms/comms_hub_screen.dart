import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';

class CommsHubScreen extends StatelessWidget {
  const CommsHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const items = [
      (
        icon: Icons.campaign_outlined,
        color: Colors.blue,
        label: 'Comunicados',
        description: 'Avisos, circulares e comunicações para encarregados e staff',
        path: '/announcements',
      ),
      (
        icon: Icons.chat_bubble_outline,
        color: Colors.green,
        label: 'Mensagens',
        description: 'Mensagens directas com encarregados e funcionários',
        path: '/messages',
      ),
      (
        icon: Icons.photo_library_outlined,
        color: Colors.pink,
        label: 'Galeria',
        description: 'Fotos e momentos da vida escolar',
        path: '/photos',
      ),
      (
        icon: Icons.calendar_month_outlined,
        color: Colors.orange,
        label: 'Calendário',
        description: 'Eventos, feriados e actividades escolares',
        path: '/events',
      ),
      (
        icon: Icons.folder_outlined,
        color: Colors.purple,
        label: 'Documentos',
        description: 'Biblioteca de documentos partilhados com encarregados',
        path: '/documents',
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Comunicação')),
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
