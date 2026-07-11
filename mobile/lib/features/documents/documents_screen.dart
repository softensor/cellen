import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_client.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/auth/auth_state.dart';
import '../../core/theme/app_theme.dart';

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------
class LibraryDocument {
  final String id;
  final String title;
  final String? description;
  final String fileUrl;
  final String fileName;
  final String? fileType;
  final String? category;
  final String target;
  final String? childId;
  final String createdAt;

  const LibraryDocument({
    required this.id,
    required this.title,
    this.description,
    required this.fileUrl,
    required this.fileName,
    this.fileType,
    this.category,
    required this.target,
    this.childId,
    required this.createdAt,
  });

  factory LibraryDocument.fromJson(Map<String, dynamic> json) {
    return LibraryDocument(
      id: json['id']?.toString() ?? '',
      title: json['title'] as String? ?? '',
      description: json['description'] as String?,
      fileUrl: json['file_url'] as String? ?? '',
      fileName: json['file_name'] as String? ?? '',
      fileType: json['file_type'] as String?,
      category: json['category'] as String?,
      target: json['target'] as String? ?? 'all',
      childId: json['child_id']?.toString(),
      createdAt: json['created_at'] as String? ?? '',
    );
  }
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------
final documentsProvider =
    FutureProvider.autoDispose<List<LibraryDocument>>((ref) async {
  final api = ref.read(apiClientProvider);
  final data = await api.get('/documents') as List;
  return data
      .map((e) => LibraryDocument.fromJson(e as Map<String, dynamic>))
      .toList();
});

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------
class DocumentsScreen extends ConsumerStatefulWidget {
  const DocumentsScreen({super.key});

  @override
  ConsumerState<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends ConsumerState<DocumentsScreen> {
  String _categoryFilter = 'Todos';
  static const _categories = [
    'Todos',
    'Contrato',
    'Circular',
    'Autorização',
    'Médico',
  ];

  @override
  Widget build(BuildContext context) {
    final documentsAsync = ref.watch(documentsProvider);
    final auth = ref.watch(authProvider);
    final isAdmin = auth.isAdmin;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Documentos'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(documentsProvider),
          ),
        ],
      ),
      floatingActionButton: isAdmin
          ? FloatingActionButton.extended(
              onPressed: () => _showAddDialog(context),
              icon: const Icon(Icons.add),
              label: const Text('Adicionar Documento'),
            )
          : null,
      body: Column(
        children: [
          // Category filter chips
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _categories
                    .map((cat) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            label: Text(cat),
                            selected: _categoryFilter == cat,
                            showCheckmark: false,
                            selectedColor: AppTheme.primaryLight,
                            onSelected: (_) =>
                                setState(() => _categoryFilter = cat),
                          ),
                        ))
                    .toList(),
              ),
            ),
          ),

          Expanded(
            child: documentsAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline,
                        size: 48, color: AppTheme.danger),
                    const SizedBox(height: 8),
                    Text(e.toString(), textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () => ref.invalidate(documentsProvider),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Tentar novamente'),
                    ),
                  ],
                ),
              ),
              data: (docs) {
                final filtered = _categoryFilter == 'Todos'
                    ? docs
                    : docs
                        .where((d) => d.category == _categoryFilter)
                        .toList();

                if (filtered.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.folder_open,
                            size: 64, color: Colors.grey.shade400),
                        const SizedBox(height: 16),
                        const Text('Nenhum documento encontrado',
                            style:
                                TextStyle(color: AppTheme.textSecondary)),
                      ],
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(documentsProvider),
                  child: ListView.builder(
                    padding:
                        const EdgeInsets.fromLTRB(12, 8, 12, 100),
                    itemCount: filtered.length,
                    itemBuilder: (context, i) {
                      final doc = filtered[i];
                      return _DocumentCard(
                        doc: doc,
                        isAdmin: isAdmin,
                        onDelete: () async {
                          try {
                            await ref
                                .read(apiClientProvider)
                                .delete('/documents/${doc.id}');
                            ref.invalidate(documentsProvider);
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text('Erro ao eliminar: $e')),
                              );
                            }
                          }
                        },
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showAddDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => _AddDocumentDialog(
        onAdded: () => ref.invalidate(documentsProvider),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Document card
// ---------------------------------------------------------------------------
class _DocumentCard extends StatelessWidget {
  final LibraryDocument doc;
  final bool isAdmin;
  final VoidCallback onDelete;

  const _DocumentCard({
    required this.doc,
    required this.isAdmin,
    required this.onDelete,
  });

  IconData _fileIcon(String? type) => switch (type) {
        'pdf' => Icons.picture_as_pdf,
        'docx' || 'doc' => Icons.description,
        'xlsx' || 'xls' => Icons.table_chart,
        'image' || 'jpg' || 'jpeg' || 'png' => Icons.image,
        _ => Icons.insert_drive_file,
      };

  Color _fileColor(String? type) => switch (type) {
        'pdf' => Colors.red,
        'docx' || 'doc' => Colors.blue,
        'xlsx' || 'xls' => Colors.green,
        'image' || 'jpg' || 'jpeg' || 'png' => Colors.purple,
        _ => Colors.grey,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _fileColor(doc.fileType);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(_fileIcon(doc.fileType), color: color, size: 26),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(doc.title,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  if (doc.description != null) ...[
                    const SizedBox(height: 2),
                    Text(doc.description!,
                        style: const TextStyle(
                            color: AppTheme.textSecondary, fontSize: 12),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                  ],
                  if (doc.category != null) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        doc.category!,
                        style: const TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Column(
              children: [
                OutlinedButton(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('URL: ${doc.fileUrl}')),
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                  ),
                  child: const Text('Abrir'),
                ),
                if (isAdmin) ...[
                  const SizedBox(height: 4),
                  IconButton(
                    icon: const Icon(Icons.delete_outline,
                        color: AppTheme.danger, size: 20),
                    onPressed: () => _confirmDelete(context),
                    tooltip: 'Eliminar',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar documento'),
        content: Text('Tem a certeza que deseja eliminar "${doc.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () {
              Navigator.of(context).pop();
              onDelete();
            },
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Add Document Dialog
// ---------------------------------------------------------------------------
class _AddDocumentDialog extends ConsumerStatefulWidget {
  final VoidCallback onAdded;
  const _AddDocumentDialog({required this.onAdded});

  @override
  ConsumerState<_AddDocumentDialog> createState() =>
      _AddDocumentDialogState();
}

class _AddDocumentDialogState extends ConsumerState<_AddDocumentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _fileUrlCtrl = TextEditingController();
  String? _category;
  bool _isLoading = false;
  String? _error;

  static const _categories = [
    'Contrato',
    'Circular',
    'Autorização',
    'Médico',
    'Outro',
  ];

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _fileUrlCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      await api.post('/documents', data: {
        'title': _titleCtrl.text.trim(),
        if (_descCtrl.text.trim().isNotEmpty)
          'description': _descCtrl.text.trim(),
        'file_url': _fileUrlCtrl.text.trim(),
        'file_name': _fileUrlCtrl.text.trim().split('/').last,
        if (_category != null) 'category': _category,
        'target': 'all',
      });
      widget.onAdded();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Adicionar Documento'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _titleCtrl,
                  decoration: const InputDecoration(labelText: 'Título *'),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Obrigatório' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Descrição (opcional)'),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _fileUrlCtrl,
                  decoration: const InputDecoration(labelText: 'URL do Ficheiro *'),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Obrigatório' : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _category,
                  decoration: const InputDecoration(labelText: 'Categoria'),
                  items: _categories
                      .map((c) =>
                          DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (v) => setState(() => _category = v),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!,
                      style: const TextStyle(color: AppTheme.danger)),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _isLoading ? null : _submit,
          child: _isLoading
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Text('Adicionar'),
        ),
      ],
    );
  }
}
