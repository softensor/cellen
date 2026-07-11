import 'package:badges/badges.dart' as badges;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_client.dart';
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
      floatingActionButton: FloatingActionButton(
        onPressed: _showNewThreadDialog,
        child: const Icon(Icons.edit),
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

  void _showNewThreadDialog() {
    final subjectCtrl = TextEditingController();
    final messageCtrl = TextEditingController();
    bool isLoading = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Nova Mensagem'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: subjectCtrl,
                decoration: const InputDecoration(
                  labelText: 'Assunto',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: messageCtrl,
                decoration: const InputDecoration(
                  labelText: 'Mensagem',
                  border: OutlineInputBorder(),
                ),
                maxLines: 4,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: isLoading
                  ? null
                  : () async {
                      if (subjectCtrl.text.trim().isEmpty ||
                          messageCtrl.text.trim().isEmpty) {
                        return;
                      }
                      setDialogState(() => isLoading = true);
                      try {
                        await ref.read(apiClientProvider).post(
                          '/messages/threads',
                          data: {
                            'subject': subjectCtrl.text.trim(),
                            'body': messageCtrl.text.trim(),
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
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Enviar'),
            ),
          ],
        ),
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
    final timeStr = DateFormat('dd/MM HH:mm').format(thread.createdAt);

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
          Text(timeStr,
              style: Theme.of(context).textTheme.labelSmall),
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
