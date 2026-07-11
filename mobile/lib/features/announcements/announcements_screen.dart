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
class Announcement {
  final String id;
  final String title;
  final String body;
  final String? attachmentUrl;
  final String? attachmentName;
  final String target;
  final bool pinned;
  final String createdAt;
  final String createdByName;

  const Announcement({
    required this.id,
    required this.title,
    required this.body,
    this.attachmentUrl,
    this.attachmentName,
    required this.target,
    required this.pinned,
    required this.createdAt,
    required this.createdByName,
  });

  factory Announcement.fromJson(Map<String, dynamic> json) {
    return Announcement(
      id: json['id']?.toString() ?? '',
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      attachmentUrl: json['attachment_url'] as String?,
      attachmentName: json['attachment_name'] as String?,
      target: json['target'] as String? ?? 'all',
      pinned: json['pinned'] as bool? ?? false,
      createdAt: json['created_at'] as String? ?? '',
      createdByName: json['created_by_name'] as String? ?? '',
    );
  }
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------
final announcementsProvider =
    FutureProvider.autoDispose<List<Announcement>>((ref) async {
  final api = ref.read(apiClientProvider);
  final data = await api.get('/announcements') as List;
  return data
      .map((e) => Announcement.fromJson(e as Map<String, dynamic>))
      .toList();
});

final pinnedAnnouncementsProvider =
    FutureProvider.autoDispose<List<Announcement>>((ref) async {
  final api = ref.read(apiClientProvider);
  final data = await api.get('/announcements/pinned') as List;
  return data
      .map((e) => Announcement.fromJson(e as Map<String, dynamic>))
      .toList();
});

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------
class AnnouncementsScreen extends ConsumerWidget {
  const AnnouncementsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final announcementsAsync = ref.watch(announcementsProvider);
    final pinnedAsync = ref.watch(pinnedAnnouncementsProvider);
    final auth = ref.watch(authProvider);
    final canPost = auth.isAdmin || auth.isTeacher;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Comunicados'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(announcementsProvider);
              ref.invalidate(pinnedAnnouncementsProvider);
            },
          ),
        ],
      ),
      floatingActionButton: canPost
          ? FloatingActionButton.extended(
              onPressed: () => _showCreateDialog(context, ref),
              icon: const Icon(Icons.add),
              label: const Text('Novo Comunicado'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(announcementsProvider);
          ref.invalidate(pinnedAnnouncementsProvider);
        },
        child: CustomScrollView(
          slivers: [
            // Pinned section
            SliverToBoxAdapter(
              child: pinnedAsync.when(
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
                data: (pinned) {
                  if (pinned.isEmpty) return const SizedBox.shrink();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: Row(
                          children: [
                            const Icon(Icons.push_pin,
                                size: 16, color: AppTheme.primary),
                            const SizedBox(width: 6),
                            Text(
                              'Fixados',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: AppTheme.primary,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        height: 140,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding:
                              const EdgeInsets.symmetric(horizontal: 12),
                          itemCount: pinned.length,
                          itemBuilder: (context, i) =>
                              _PinnedCard(announcement: pinned[i]),
                        ),
                      ),
                      const Divider(height: 24),
                    ],
                  );
                },
              ),
            ),

            // All announcements
            SliverToBoxAdapter(
              child: announcementsAsync.when(
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
                        onPressed: () =>
                            ref.invalidate(announcementsProvider),
                        icon: const Icon(Icons.refresh),
                        label: const Text('Tentar novamente'),
                      ),
                    ],
                  ),
                ),
                data: (announcements) {
                  if (announcements.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(48),
                        child: Column(
                          children: [
                            Icon(Icons.campaign_outlined,
                                size: 64, color: Colors.grey.shade400),
                            const SizedBox(height: 16),
                            const Text('Nenhum comunicado',
                                style: TextStyle(
                                    color: AppTheme.textSecondary)),
                          ],
                        ),
                      ),
                    );
                  }
                  return ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 100),
                    itemCount: announcements.length,
                    itemBuilder: (context, i) =>
                        _AnnouncementCard(announcement: announcements[i]),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCreateDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (_) => _CreateAnnouncementDialog(
        onCreated: () {
          ref.invalidate(announcementsProvider);
          ref.invalidate(pinnedAnnouncementsProvider);
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pinned card (horizontal scroll)
// ---------------------------------------------------------------------------
class _PinnedCard extends StatelessWidget {
  final Announcement announcement;
  const _PinnedCard({required this.announcement});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF3730A3), Color(0xFF4F46E5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.push_pin, color: Colors.white70, size: 16),
          const SizedBox(height: 6),
          Text(
            announcement.title,
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 14),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const Spacer(),
          Text(
            announcement.body,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Announcement card
// ---------------------------------------------------------------------------
class _AnnouncementCard extends StatefulWidget {
  final Announcement announcement;
  const _AnnouncementCard({required this.announcement});

  @override
  State<_AnnouncementCard> createState() => _AnnouncementCardState();
}

class _AnnouncementCardState extends State<_AnnouncementCard> {
  bool _expanded = false;

  String _targetLabel(String t) => switch (t) {
        'all' => 'Todos',
        'parents' => 'Pais',
        'teachers' => 'Professores',
        _ => t,
      };

  @override
  Widget build(BuildContext context) {
    final a = widget.announcement;
    final theme = Theme.of(context);
    final dateStr = a.createdAt.isNotEmpty
        ? (() {
            try {
              return DateFormat('dd/MM/yyyy').format(DateTime.parse(a.createdAt));
            } catch (_) {
              return a.createdAt;
            }
          })()
        : '';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      a.title,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (a.pinned)
                    const Icon(Icons.push_pin,
                        size: 16, color: AppTheme.primary),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                _expanded ? a.body : a.body,
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 13),
                maxLines: _expanded ? null : 2,
                overflow:
                    _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE0F2FE),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _targetLabel(a.target),
                      style: const TextStyle(
                          color: Color(0xFF0369A1),
                          fontSize: 11,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '$dateStr · ${a.createdByName}',
                    style: const TextStyle(
                        color: AppTheme.textSecondary, fontSize: 11),
                  ),
                ],
              ),
              if (a.attachmentUrl != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.attach_file,
                        size: 16, color: AppTheme.primary),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                                'Abrir: ${a.attachmentName ?? a.attachmentUrl}'),
                          ),
                        );
                      },
                      child: Text(
                        a.attachmentName ?? 'Anexo',
                        style: const TextStyle(
                            color: AppTheme.primary,
                            fontSize: 13,
                            decoration: TextDecoration.underline),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Create Announcement Dialog
// ---------------------------------------------------------------------------
class _CreateAnnouncementDialog extends ConsumerStatefulWidget {
  final VoidCallback onCreated;
  const _CreateAnnouncementDialog({required this.onCreated});

  @override
  ConsumerState<_CreateAnnouncementDialog> createState() =>
      _CreateAnnouncementDialogState();
}

class _CreateAnnouncementDialogState
    extends ConsumerState<_CreateAnnouncementDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  final _attachmentUrlCtrl = TextEditingController();
  String _target = 'all';
  bool _pinned = false;
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    _attachmentUrlCtrl.dispose();
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
      await api.post('/announcements', data: {
        'title': _titleCtrl.text.trim(),
        'body': _bodyCtrl.text.trim(),
        'target': _target,
        'pinned': _pinned,
        if (_attachmentUrlCtrl.text.trim().isNotEmpty)
          'attachment_url': _attachmentUrlCtrl.text.trim(),
      });
      widget.onCreated();
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
      title: const Text('Novo Comunicado'),
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
                  controller: _bodyCtrl,
                  decoration: const InputDecoration(labelText: 'Mensagem *'),
                  maxLines: 4,
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Obrigatório' : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _target,
                  decoration: const InputDecoration(labelText: 'Destinatários'),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('Todos')),
                    DropdownMenuItem(
                        value: 'parents', child: Text('Pais')),
                    DropdownMenuItem(
                        value: 'teachers', child: Text('Professores')),
                  ],
                  onChanged: (v) => setState(() => _target = v ?? 'all'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _attachmentUrlCtrl,
                  decoration: const InputDecoration(
                      labelText: 'URL do Anexo (opcional)'),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  title: const Text('Fixar comunicado'),
                  value: _pinned,
                  onChanged: (v) => setState(() => _pinned = v),
                  contentPadding: EdgeInsets.zero,
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
              : const Text('Publicar'),
        ),
      ],
    );
  }
}
