import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/models/website.dart';

class WebsitePageEditorScreen extends ConsumerStatefulWidget {
  final String pageId;

  const WebsitePageEditorScreen({super.key, required this.pageId});

  @override
  ConsumerState<WebsitePageEditorScreen> createState() =>
      _WebsitePageEditorScreenState();
}

class _WebsitePageEditorScreenState
    extends ConsumerState<WebsitePageEditorScreen> {
  WebsitePage? _page;
  List<WebsiteSection> _sections = [];
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
      final data = await api.get('/website/admin/pages/${widget.pageId}');
      final page = WebsitePage.fromJson(data as Map<String, dynamic>);
      setState(() {
        _page = page;
        _sections = page.sections;
        _loading = false;
      });
    } on ApiException catch (e) {
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  Future<void> _updatePageField(String field, dynamic value) async {
    try {
      final api = ref.read(apiClientProvider);
      await api.patch('/website/admin/pages/${widget.pageId}', data: {field: value});
      await _load();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _deleteSection(WebsiteSection section) async {
    final confirmed = await showDialog<bool>(useRootNavigator: false, 
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar secção'),
        content: Text('Eliminar "${section.name}"?'),
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
      await api.delete('/website/admin/sections/${section.id}');
      await _load();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _addSection() async {
    final type = await showDialog<String>(useRootNavigator: false, 
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Tipo de secção'),
        children: [
          for (final t in [
            ('hero', 'Hero (cabeçalho)'),
            ('features', 'Funcionalidades'),
            ('steps', 'Passos / Como funciona'),
            ('benefits', 'Benefícios'),
            ('pricing', 'Preços'),
            ('contact', 'Contacto'),
            ('custom', 'Personalizada'),
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, t.$1),
              child: ListTile(
                leading: Icon(_sectionIcon(t.$1)),
                title: Text(t.$2),
              ),
            ),
        ],
      ),
    );

    if (type == null) return;

    try {
      final api = ref.read(apiClientProvider);
      await api.post('/website/admin/sections', data: {
        'page_id': widget.pageId,
        'section_type': type,
        'name': 'Nova secção $type',
        'sort_order': _sections.length,
        'content': <String, dynamic>{},
        'settings': <String, dynamic>{},
      });
      await _load();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _reorder() async {
    final api = ref.read(apiClientProvider);
    final orders = <Map<String, dynamic>>[];
    for (var i = 0; i < _sections.length; i++) {
      orders.add({'id': _sections[i].id, 'sort_order': i});
    }
    try {
      await api.put('/website/admin/sections/reorder', data: orders);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  IconData _sectionIcon(String type) => switch (type) {
        'hero' => Icons.web,
        'features' => Icons.grid_view,
        'steps' => Icons.format_list_numbered,
        'benefits' => Icons.auto_awesome,
        'pricing' => Icons.attach_money,
        'contact' => Icons.email_outlined,
        _ => Icons.code,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_page?.title ?? 'Editar página'),
        actions: [
          if (_page != null)
            IconButton(
              icon: Icon(_page!.isPublished ? Icons.public : Icons.public_off),
              tooltip:
                  _page!.isPublished ? 'Despublicar' : 'Publicar',
              onPressed: () =>
                  _updatePageField('is_published', !_page!.isPublished),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addSection,
        icon: const Icon(Icons.add),
        label: const Text('Nova secção'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline,
                          color: Theme.of(context).colorScheme.error,
                          size: 48),
                      const SizedBox(height: 8),
                      Text(_error!),
                      TextButton(
                        onPressed: _load,
                        child: const Text('Tentar novamente'),
                      ),
                    ],
                  ),
                )
              : _page == null
                  ? const Center(child: Text('Página não encontrada'))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding:
                            const EdgeInsets.fromLTRB(16, 16, 16, 120),
                        children: [
                          // Page info card
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(_page!.title,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge),
                                  const SizedBox(height: 4),
                                  Text('/${_page!.slug}',
                                      style: const TextStyle(
                                          color: Colors.grey)),
                                  if (_page!.metaDescription != null) ...[
                                    const SizedBox(height: 8),
                                    Text(_page!.metaDescription!,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall),
                                  ],
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      OutlinedButton(
                                        onPressed: () => _editPageInfo(),
                                        child: const Text('Editar info'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          // Sections header
                          Row(
                            children: [
                              Text(
                                'Secções (${_sections.length})',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium,
                              ),
                              const Spacer(),
                              Text(
                                'Arraste para reordenar',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: Colors.grey),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          // Section list
                          ReorderableListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _sections.length,
                            onReorder: (oldIndex, newIndex) {
                              setState(() {
                                if (newIndex > oldIndex) newIndex--;
                                final item = _sections.removeAt(oldIndex);
                                _sections.insert(newIndex, item);
                              });
                              _reorder();
                            },
                            itemBuilder: (_, i) {
                              final section = _sections[i];
                              return Card(
                                key: ValueKey(section.id),
                                child: ListTile(
                                  leading: Icon(
                                    _sectionIcon(section.sectionType),
                                    color: Colors.blue,
                                  ),
                                  title: Text(section.name,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w500)),
                                  subtitle: Text(
                                    section.sectionType,
                                    style:
                                        const TextStyle(fontSize: 12),
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(
                                            Icons.edit_outlined),
                                        tooltip: 'Editar',
                                        onPressed: () => context.push(
                                          '/platform/website/pages/${widget.pageId}/sections/${section.id}',
                                        ),
                                      ),
                                      Icon(
                                        section.isVisible
                                            ? Icons.visibility
                                            : Icons.visibility_off,
                                        size: 16,
                                        color: section.isVisible
                                            ? Colors.green
                                            : Colors.grey,
                                      ),
                                      IconButton(
                                        icon: Icon(
                                          Icons.delete_outline,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .error,
                                        ),
                                        tooltip: 'Eliminar',
                                        onPressed: () =>
                                            _deleteSection(section),
                                      ),
                                      const Icon(Icons.drag_handle,
                                          color: Colors.grey),
                                    ],
                                  ),
                                  onTap: () => context.push(
                                    '/platform/website/pages/${widget.pageId}/sections/${section.id}',
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
    );
  }

  Future<void> _editPageInfo() async {
    final titleCtrl = TextEditingController(text: _page!.title);
    final slugCtrl = TextEditingController(text: _page!.slug);
    final metaCtrl =
        TextEditingController(text: _page!.metaDescription ?? '');

    final result = await showDialog<bool>(useRootNavigator: false, 
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Editar página'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(labelText: 'Título'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: slugCtrl,
                decoration: const InputDecoration(labelText: 'Slug'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: metaCtrl,
                decoration: const InputDecoration(
                    labelText: 'Meta Description'),
                maxLines: 3,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (result != true) return;

    try {
      final api = ref.read(apiClientProvider);
      await api.patch('/website/admin/pages/${widget.pageId}', data: {
        'title': titleCtrl.text,
        'slug': slugCtrl.text,
        'meta_description':
            metaCtrl.text.isEmpty ? null : metaCtrl.text,
      });
      await _load();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }
}
