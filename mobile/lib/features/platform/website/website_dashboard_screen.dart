import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/models/website.dart';

class WebsiteDashboardScreen extends ConsumerStatefulWidget {
  const WebsiteDashboardScreen({super.key});

  @override
  ConsumerState<WebsiteDashboardScreen> createState() =>
      _WebsiteDashboardScreenState();
}

class _WebsiteDashboardScreenState
    extends ConsumerState<WebsiteDashboardScreen> {
  List<WebsitePage> _pages = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  bool _seeded = false;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      final data = await api.get('/website/admin/pages');
      final pages = (data as List)
          .map((e) => WebsitePage.fromJson(e as Map<String, dynamic>))
          .toList();

      // Auto-seed from static website content on first empty load
      if (pages.isEmpty && !_seeded) {
        _seeded = true;
        await api.post('/website/admin/seed');
        // Reload after seeding
        final newData = await api.get('/website/admin/pages');
        setState(() {
          _pages = (newData as List)
              .map((e) => WebsitePage.fromJson(e as Map<String, dynamic>))
              .toList();
          _loading = false;
        });
        return;
      }

      setState(() {
        _pages = pages;
        _loading = false;
      });
    } on ApiException catch (e) {
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  Future<void> _togglePublished(WebsitePage page) async {
    try {
      final api = ref.read(apiClientProvider);
      await api.patch('/website/admin/pages/${page.id}', data: {
        'is_published': !page.isPublished,
      });
      await _load();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _deletePage(WebsitePage page) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar página'),
        content: Text('Eliminar "${page.title}" e todas as suas secções?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final api = ref.read(apiClientProvider);
      await api.delete('/website/admin/pages/${page.id}');
      await _load();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _createPage() async {
    final slugCtrl = TextEditingController();
    final titleCtrl = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nova página'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              decoration: const InputDecoration(labelText: 'Título'),
              onChanged: (v) {
                slugCtrl.text = v
                    .toLowerCase()
                    .replaceAll(RegExp(r'[^a-z0-9\s-]'), '')
                    .trim()
                    .replaceAll(RegExp(r'\s+'), '-');
              },
            ),
            const SizedBox(height: 8),
            TextField(
              controller: slugCtrl,
              decoration: const InputDecoration(labelText: 'Slug'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Criar'),
          ),
        ],
      ),
    );

    if (result != true) return;

    try {
      final api = ref.read(apiClientProvider);
      await api.post('/website/admin/pages', data: {
        'slug': slugCtrl.text,
        'title': titleCtrl.text,
      });
      await _load();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _seed() async {
    try {
      final api = ref.read(apiClientProvider);
      await api.post('/website/admin/seed');
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Website populado com conteúdo padrão.')),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Website CMS'),
        actions: [
          IconButton(
            icon: const Icon(Icons.image_outlined),
            tooltip: 'Media',
            onPressed: () => context.push('/platform/website/media'),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Configurações',
            onPressed: () => context.push('/platform/website/settings'),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.small(
            heroTag: 'seed',
            tooltip: 'Popular com demo',
            onPressed: _seed,
            child: const Icon(Icons.auto_fix_high),
          ),
          const SizedBox(height: 8),
          FloatingActionButton.extended(
            heroTag: 'add',
            onPressed: _createPage,
            icon: const Icon(Icons.add),
            label: const Text('Nova página'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline,
                          color: Theme.of(context).colorScheme.error, size: 48),
                      const SizedBox(height: 8),
                      Text(_error!),
                      TextButton(
                        onPressed: _load,
                        child: const Text('Tentar novamente'),
                      ),
                    ],
                  ),
                )
              : _pages.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.language_outlined,
                              size: 64, color: Colors.grey),
                          const SizedBox(height: 16),
                          const Text('Nenhuma página criada'),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              OutlinedButton.icon(
                                onPressed: _seed,
                                icon: const Icon(Icons.auto_fix_high),
                                label: const Text('Criar demo'),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton.icon(
                                onPressed: _createPage,
                                icon: const Icon(Icons.add),
                                label: const Text('Criar página'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                        itemCount: _pages.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final page = _pages[i];
                          return Card(
                            child: ListTile(
                              leading: Icon(
                                page.isPublished
                                    ? Icons.public
                                    : Icons.public_off,
                                color: page.isPublished
                                    ? Colors.green
                                    : Colors.grey,
                              ),
                              title: Text(page.title,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600)),
                              subtitle: Text(
                                '/${page.slug}  ·  ${page.sections.length} secções',
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit_outlined),
                                    tooltip: 'Editar',
                                    onPressed: () => context.push(
                                      '/platform/website/pages/${page.id}',
                                    ),
                                  ),
                                  IconButton(
                                    icon: Icon(
                                      page.isPublished
                                          ? Icons.visibility_off_outlined
                                          : Icons.visibility_outlined,
                                    ),
                                    tooltip: page.isPublished
                                        ? 'Despublicar'
                                        : 'Publicar',
                                    onPressed: () => _togglePublished(page),
                                  ),
                                  IconButton(
                                    icon: Icon(Icons.delete_outline,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .error),
                                    tooltip: 'Eliminar',
                                    onPressed: () => _deletePage(page),
                                  ),
                                ],
                              ),
                              onTap: () => context.push(
                                '/platform/website/pages/${page.id}',
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
