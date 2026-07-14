import 'package:badges/badges.dart' as badges;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../core/api/api_client.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/auth/auth_state.dart';
import '../../core/models/message.dart';

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------
final messageThreadsProvider =
    FutureProvider.autoDispose<List<MessageThread>>((ref) async {
  final api = ref.read(apiClientProvider);
  final data = await api.get('/messages/threads') as List;
  return data
      .map((e) => MessageThread.fromJson(e as Map<String, dynamic>))
      .toList();
});

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------
class MessagesScreen extends ConsumerStatefulWidget {
  const MessagesScreen({super.key});

  @override
  ConsumerState<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends ConsumerState<MessagesScreen> {
  @override
  Widget build(BuildContext context) {
    final threadsAsync = ref.watch(messageThreadsProvider);
    final authState = ref.watch(authProvider);
    final canBroadcast = authState.isAdmin || authState.isTeacher;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mensagens'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(messageThreadsProvider),
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Broadcast FAB — only for admins/teachers
          if (canBroadcast) ...[
            FloatingActionButton.extended(
              heroTag: 'broadcast_fab',
              onPressed: _showBroadcastDialog,
              icon: const Icon(Icons.campaign_outlined),
              label: const Text('Comunicado'),
              backgroundColor: Theme.of(context).colorScheme.secondary,
              foregroundColor: Theme.of(context).colorScheme.onSecondary,
            ),
            const SizedBox(height: 12),
          ],
          // Standard new thread FAB
          FloatingActionButton(
            heroTag: 'new_thread_fab',
            onPressed: _showNewThreadDialog,
            child: const Icon(Icons.edit),
          ),
        ],
      ),
      body: threadsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorView(
          message: e.toString(),
          onRetry: () => ref.invalidate(messageThreadsProvider),
        ),
        data: (threads) {
          if (threads.isEmpty) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.chat_bubble_outline,
                      size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'Sem mensagens',
                    style: TextStyle(color: Colors.grey, fontSize: 16),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Inicie uma conversa com o botão abaixo',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(messageThreadsProvider),
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: threads.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, indent: 72),
              itemBuilder: (context, i) {
                return _ThreadTile(
                  thread: threads[i],
                  onTap: () =>
                      context.push('/messages/thread/${threads[i].id}'),
                );
              },
            ),
          );
        },
      ),
    );
  }

  void _showBroadcastDialog() {
    final subjectCtrl = TextEditingController();
    final messageCtrl = TextEditingController();
    String selectedTarget = 'all';
    bool isLoading = false;

    const targetOptions = [
      ('all', 'Todos'),
      ('parents', 'Encarregados'),
      ('teachers', 'Professores/Staff'),
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Title
              Row(
                children: [
                  const Icon(Icons.campaign_outlined, size: 22),
                  const SizedBox(width: 8),
                  Text(
                    'Novo Comunicado',
                    style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Subject
              TextField(
                controller: subjectCtrl,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Assunto',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),

              // Message
              TextField(
                controller: messageCtrl,
                decoration: const InputDecoration(
                  labelText: 'Mensagem',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                maxLines: 4,
                textInputAction: TextInputAction.newline,
              ),
              const SizedBox(height: 12),

              // Target dropdown
              DropdownButtonFormField<String>(
                value: selectedTarget,
                decoration: const InputDecoration(
                  labelText: 'Destinatários',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.people_outline),
                ),
                items: targetOptions
                    .map((opt) => DropdownMenuItem(
                          value: opt.$1,
                          child: Text(opt.$2),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setSheetState(() => selectedTarget = v);
                },
              ),
              const SizedBox(height: 20),

              // Send button
              ElevatedButton.icon(
                onPressed: isLoading
                    ? null
                    : () async {
                        if (subjectCtrl.text.trim().isEmpty ||
                            messageCtrl.text.trim().isEmpty) {
                          return;
                        }
                        setSheetState(() => isLoading = true);
                        try {
                          await ref.read(apiClientProvider).post(
                            '/messages/broadcast',
                            data: {
                              'subject': subjectCtrl.text.trim(),
                              'body': messageCtrl.text.trim(),
                              'target': selectedTarget,
                            },
                          );
                          if (ctx.mounted) Navigator.pop(ctx);
                          ref.invalidate(messageThreadsProvider);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Comunicado enviado'),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        } catch (e) {
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              SnackBar(content: Text('Erro: $e')),
                            );
                          }
                        } finally {
                          setSheetState(() => isLoading = false);
                        }
                      },
                icon: isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_outlined),
                label: Text(isLoading ? 'A enviar...' : 'Enviar Comunicado'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Shows a loading indicator, fetches users, then shows the real dialog or an error.
  Future<void> _showNewThreadDialog() async {
    // 1. Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('A carregar utilizadores...'),
          ],
        ),
      ),
    );

    // 2. Fetch data asynchronously
    final (:users, :error) = await _fetchUsersForNewThread();

    // 3. Handle result. If screen is gone, do nothing.
    if (!mounted) return;

    // Dismiss loading dialog
    Navigator.pop(context);

    // Show error or the actual dialog
    if (error != null) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Erro'),
          content: Text(error),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            )
          ],
        ),
      );
    } else {
      _showUserSelectionDialog(users);
    }
  }

  /// Fetches the list of users a person can send a message to.
  Future<({List<Map<String, dynamic>> users, String? error})>
      _fetchUsersForNewThread() async {
    try {
      final api = ref.read(apiClientProvider);
      // Prefer the more comprehensive endpoint that lists all users (for admins)
      final data = await api.get('/schools/users') as List;
      return (users: data.cast<Map<String, dynamic>>(), error: null);
    } catch (e) {
      // If the primary endpoint fails (e.g., for non-admins), try falling back
      // to fetching just employees.
      try {
        final api = ref.read(apiClientProvider);
        final empData = await api.get('/employees') as List;
        final users = empData.map((item) {
          final m = item as Map<String, dynamic>;
          return {
            'id': m['id'],
            'username': '${m['first_name'] ?? ''} ${m['last_name'] ?? ''}'.trim(),
            'role': m['employee_type'] ?? 'staff',
          };
        }).toList();
        return (users: users, error: null);
      } catch (e2) {
        return (
          users: [],
          error: 'Falha ao carregar a lista de destinatários.\n'
              'Por favor, tente novamente mais tarde.'
        );
      }
    }
  }

  /// The actual UI for selecting users and composing a new message.
  void _showUserSelectionDialog(List<Map<String, dynamic>> users) {
    final subjectCtrl = TextEditingController();
    final messageCtrl = TextEditingController();
    final searchCtrl = TextEditingController();
    final selectedParticipants = <String>{};
    bool isLoading = false;
    String searchQuery = '';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final filtered = searchQuery.isEmpty
              ? users
              : users.where((u) {
                  final name = (u['username'] ?? '').toString().toLowerCase();
                  return name.contains(searchQuery.toLowerCase());
                }).toList();

          return AlertDialog(
            title: const Text('Nova Mensagem'),
            content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: subjectCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Assunto *',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Participant search
                    TextField(
                      controller: searchCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Pesquisar destinatário *',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Nome do utilizador...', 
                      ),
                      onChanged: (v) =>
                          setDialogState(() => searchQuery = v),
                    ),
                    if (selectedParticipants.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: selectedParticipants.map((pid) {
                          final user = users.firstWhere(
                            (u) => u['id']?.toString() == pid,
                            orElse: () => {'username': pid},
                          );
                          return Chip(
                            label: Text(
                              user['username']?.toString() ?? pid,
                              style: const TextStyle(fontSize: 12),
                            ),
                            deleteIcon: const Icon(Icons.close, size: 16),
                            onDeleted: () => setDialogState(
                                () => selectedParticipants.remove(pid)),
                            visualDensity: VisualDensity.compact,
                          );
                        }).toList(),
                      ),
                    ],
                    if (filtered.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 150),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: filtered.length,
                          itemBuilder: (_, i) {
                            final u = filtered[i];
                            final uid = u['id']?.toString() ?? '';
                            final selected =
                                selectedParticipants.contains(uid);
                            return ListTile(
                              dense: true,
                              visualDensity: VisualDensity.compact,
                              leading: Icon(
                                selected
                                    ? Icons.check_circle
                                    : Icons.person_outline,
                                color: selected
                                    ? Theme.of(ctx).colorScheme.primary
                                    : null,
                                size: 20,
                              ),
                              title: Text(
                                u['username']?.toString() ?? '',
                                style: const TextStyle(fontSize: 13),
                              ),
                              subtitle: Text(
                                u['role']?.toString() ?? '',
                                style: const TextStyle(fontSize: 11),
                              ),
                              onTap: () {
                                setDialogState(() {
                                  if (selected) {
                                    selectedParticipants.remove(uid);
                                  } else {
                                    selectedParticipants.add(uid);
                                  }
                                });
                              },
                            );
                          },
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: messageCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Mensagem',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 3,
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: isLoading
                    ? null
                    : () async {
                        if (subjectCtrl.text.trim().isEmpty) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(
                                content: Text('Preencha o assunto')),
                          );
                          return;
                        }
                        if (selectedParticipants.isEmpty) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(
                                content: Text(
                                    'Seleccione pelo menos um destinatário')),
                          );
                          return;
                        }
                        setDialogState(() => isLoading = true);
                        try {
                          await ref.read(apiClientProvider).post(
                            '/messages/threads',
                            data: {
                              'subject': subjectCtrl.text.trim(),
                              'participant_ids':
                                  selectedParticipants.toList(),
                              if (messageCtrl.text.trim().isNotEmpty)
                                'message': messageCtrl.text.trim(),
                            },
                          );
                          if (ctx.mounted) Navigator.pop(ctx);
                          ref.invalidate(messageThreadsProvider);
                        } catch (e) {
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              SnackBar(content: Text('Erro: $e')),
                            );
                          }
                        } finally {
                          setDialogState(() => isLoading = false);
                        }
                      },
                child: isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Enviar'),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Widgets
// ---------------------------------------------------------------------------

class _ThreadTile extends StatelessWidget {
  final MessageThread thread;
  final VoidCallback onTap;

  const _ThreadTile({required this.thread, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final displayAt = thread.lastMessageAt ?? thread.createdAt;
    final timeStr = timeago.format(displayAt, locale: 'pt_BR', allowFromNow: true);

    return ListTile(
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          CircleAvatar(
            backgroundColor: _typeColor(thread.threadType).withOpacity(0.15),
            child: Icon(
              _typeIcon(thread.threadType),
              color: _typeColor(thread.threadType),
            ),
          ),
        ],
      ),
      title: Text(
        thread.subject,
        style: TextStyle(
          fontWeight:
              thread.unreadCount > 0 ? FontWeight.bold : FontWeight.normal,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: thread.lastMessage != null
          ? Text(
              thread.lastMessage!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: thread.unreadCount > 0
                    ? FontWeight.w600
                    : FontWeight.normal,
                color: thread.unreadCount > 0
                    ? Theme.of(context).colorScheme.onSurface
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            )
          : null,
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            timeStr,
            style: Theme.of(context).textTheme.labelSmall,
          ),
          const SizedBox(height: 4),
          if (thread.unreadCount > 0)
            badges.Badge(
              badgeContent: Text(
                '${thread.unreadCount}',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold),
              ),
              badgeStyle: badges.BadgeStyle(
                badgeColor: Theme.of(context).colorScheme.primary,
              ),
            ),
        ],
      ),
      onTap: onTap,
    );
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'broadcast':
        return Icons.campaign;
      case 'announcement':
        return Icons.campaign;
      case 'invoice':
        return Icons.receipt;
      case 'incident':
        return Icons.warning_amber;
      default:
        return Icons.chat_bubble_outline;
    }
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'broadcast':
        return Colors.purple;
      case 'announcement':
        return Colors.blue;
      case 'invoice':
        return Colors.orange;
      case 'incident':
        return Colors.red;
      default:
        return Colors.teal;
    }
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline,
              size: 48, color: Theme.of(context).colorScheme.error),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Tentar novamente'),
          ),
        ],
      ),
    );
  }
}
