import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_client.dart';
import '../../../core/providers/currency_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_error_widget.dart';

final _cashSessionsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final api = ref.read(apiClientProvider);
  final data = await api.get('/finance/cash-sessions') as List;
  return data.cast<Map<String, dynamic>>();
});

class CashSessionsScreen extends ConsumerWidget {
  const CashSessionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionsAsync = ref.watch(_cashSessionsProvider);
    final currency = ref.watch(currencyFormatProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fecho de Caixa'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: () => ref.invalidate(_cashSessionsProvider)),
        ],
      ),
      body: sessionsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AppErrorWidget(error: e, onRetry: () => ref.invalidate(_cashSessionsProvider)),
        data: (sessions) {
          final openSession = sessions.where((s) => s['status'] == 'open').firstOrNull;
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(_cashSessionsProvider),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              children: [
                // Current session banner
                if (openSession != null) ...[
                  _OpenSessionBanner(session: openSession, currency: currency, onChanged: () => ref.invalidate(_cashSessionsProvider)),
                  const SizedBox(height: 20),
                ] else ...[
                  _ClosedSessionBanner(onOpened: () => ref.invalidate(_cashSessionsProvider)),
                  const SizedBox(height: 20),
                ],

                // History
                Text('Histórico', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: AppTheme.textSecondary, letterSpacing: 0.5)),
                const SizedBox(height: 8),
                ...sessions.map((s) => _SessionCard(session: s, currency: currency, onChanged: () => ref.invalidate(_cashSessionsProvider))),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ─── Open session banner ─────────────────────────────────────────────────────

class _OpenSessionBanner extends ConsumerStatefulWidget {
  final Map<String, dynamic> session;
  final NumberFormat currency;
  final VoidCallback onChanged;
  const _OpenSessionBanner({required this.session, required this.currency, required this.onChanged});

  @override
  ConsumerState<_OpenSessionBanner> createState() => _OpenSessionBannerState();
}

class _OpenSessionBannerState extends ConsumerState<_OpenSessionBanner> {
  @override
  Widget build(BuildContext context) {
    final openedAt = widget.session['opened_at'] as String?;
    final float = (widget.session['opening_float'] as num?)?.toDouble() ?? 0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.success.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.success.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: AppTheme.success, borderRadius: BorderRadius.circular(20)),
                child: const Text('CAIXA ABERTA', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
              ),
              const Spacer(),
              if (openedAt != null)
                Text(
                  DateFormat('dd/MM HH:mm').format(DateTime.parse(openedAt)),
                  style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text('Fundo inicial: ${widget.currency.format(float)}', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _showCloseDialog(context),
              icon: const Icon(Icons.lock_outline),
              label: const Text('Fechar Caixa'),
              style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            ),
          ),
        ],
      ),
    );
  }

  void _showCloseDialog(BuildContext context) {
    showDialog(useRootNavigator: false, 
      context: context,
      builder: (_) => _CloseSessionDialog(
        session: widget.session,
        onClosed: widget.onChanged,
      ),
    );
  }
}

// ─── Closed banner ───────────────────────────────────────────────────────────

class _ClosedSessionBanner extends ConsumerStatefulWidget {
  final VoidCallback onOpened;
  const _ClosedSessionBanner({required this.onOpened});

  @override
  ConsumerState<_ClosedSessionBanner> createState() => _ClosedSessionBannerState();
}

class _ClosedSessionBannerState extends ConsumerState<_ClosedSessionBanner> {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        children: [
          const Icon(Icons.lock_outline, size: 36, color: AppTheme.textSecondary),
          const SizedBox(height: 8),
          const Text('Nenhuma sessão de caixa aberta', style: TextStyle(color: AppTheme.textSecondary)),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => _showOpenDialog(context),
            icon: const Icon(Icons.lock_open_outlined),
            label: const Text('Abrir Caixa'),
          ),
        ],
      ),
    );
  }

  void _showOpenDialog(BuildContext context) {
    final ctrl = TextEditingController(text: '0');
    showDialog(useRootNavigator: false, 
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Abrir Sessão de Caixa'),
        content: TextFormField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Fundo Inicial (Kz)', prefixIcon: Icon(Icons.payments_outlined)),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () async {
              try {
                final api = ref.read(apiClientProvider);
                await api.post('/finance/cash-sessions/open', data: {
                  'opening_float': double.tryParse(ctrl.text) ?? 0.0,
                });
                if (context.mounted) Navigator.pop(context);
                widget.onOpened();
              } catch (e) {
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e'), backgroundColor: AppTheme.danger));
              }
            },
            child: const Text('Abrir'),
          ),
        ],
      ),
    );
  }
}

// ─── Close Session Dialog ────────────────────────────────────────────────────

class _CloseSessionDialog extends ConsumerStatefulWidget {
  final Map<String, dynamic> session;
  final VoidCallback onClosed;
  const _CloseSessionDialog({required this.session, required this.onClosed});

  @override
  ConsumerState<_CloseSessionDialog> createState() => _CloseSessionDialogState();
}

class _CloseSessionDialogState extends ConsumerState<_CloseSessionDialog> {
  final _cashCtrl = TextEditingController(text: '0');
  final _transferCtrl = TextEditingController(text: '0');
  final _checkCtrl = TextEditingController(text: '0');
  final _varianceReasonCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _cashCtrl.dispose(); _transferCtrl.dispose(); _checkCtrl.dispose(); _varianceReasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    setState(() { _loading = true; _error = null; });
    try {
      final api = ref.read(apiClientProvider);
      await api.post('/finance/cash-sessions/${widget.session['id']}/close', data: {
        'counted_by_method': {
          'cash': double.tryParse(_cashCtrl.text) ?? 0.0,
          'bank_transfer': double.tryParse(_transferCtrl.text) ?? 0.0,
          'check': double.tryParse(_checkCtrl.text) ?? 0.0,
        },
        if (_varianceReasonCtrl.text.trim().isNotEmpty) 'variance_reason': _varianceReasonCtrl.text.trim(),
      });
      widget.onClosed();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Fechar Sessão de Caixa'),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Insira os valores contados por método:', style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
              const SizedBox(height: 12),
              TextFormField(controller: _cashCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Numerário (Kz)', prefixIcon: Icon(Icons.payments_outlined))),
              const SizedBox(height: 10),
              TextFormField(controller: _transferCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Transferência Bancária (Kz)', prefixIcon: Icon(Icons.account_balance_outlined))),
              const SizedBox(height: 10),
              TextFormField(controller: _checkCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Cheques (Kz)', prefixIcon: Icon(Icons.money_outlined))),
              const SizedBox(height: 12),
              TextFormField(controller: _varianceReasonCtrl, decoration: const InputDecoration(labelText: 'Justificação de Diferença', helperText: 'Obrigatório se houver diferença'), maxLines: 2),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: const TextStyle(color: AppTheme.danger, fontSize: 12)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _loading ? null : () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: _loading ? null : _close,
          style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
          child: _loading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Fechar Caixa'),
        ),
      ],
    );
  }
}

// ─── Session Card ─────────────────────────────────────────────────────────────

class _SessionCard extends ConsumerStatefulWidget {
  final Map<String, dynamic> session;
  final NumberFormat currency;
  final VoidCallback onChanged;
  const _SessionCard({required this.session, required this.currency, required this.onChanged});

  @override
  ConsumerState<_SessionCard> createState() => _SessionCardState();
}

class _SessionCardState extends ConsumerState<_SessionCard> {
  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final isOpen = s['status'] == 'open';
    final openedAt = s['opened_at'] as String?;
    final closedAt = s['closed_at'] as String?;
    final variance = (s['variance'] as num?)?.toDouble();
    final hasVariance = variance != null && variance.abs() > 0.01;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: Colors.grey.shade200)),
      child: ListTile(
        leading: Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: isOpen ? AppTheme.success.withOpacity(0.12) : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(isOpen ? Icons.lock_open : Icons.lock_outline, color: isOpen ? AppTheme.success : Colors.grey, size: 20),
        ),
        title: Text(
          openedAt != null ? DateFormat('dd/MM/yyyy').format(DateTime.parse(openedAt)) : '—',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          isOpen ? 'Aberta' : (closedAt != null ? 'Fechada às ${DateFormat('HH:mm').format(DateTime.parse(closedAt))}' : 'Fechada'),
          style: TextStyle(fontSize: 12, color: isOpen ? AppTheme.success : AppTheme.textSecondary),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasVariance)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: AppTheme.danger.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
                child: Text(
                  'Diff: ${widget.currency.format(variance)}',
                  style: const TextStyle(color: AppTheme.danger, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            if (!isOpen)
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, size: 18),
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'reopen', child: Row(children: [Icon(Icons.lock_open, size: 18), SizedBox(width: 8), Text('Reabrir Sessão')])),
                ],
                onSelected: (action) {
                  if (action == 'reopen') _showReopenDialog(context);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _showReopenDialog(BuildContext context) {
    final reasonCtrl = TextEditingController();
    showDialog(useRootNavigator: false, 
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Reabrir Sessão'),
        content: TextFormField(
          controller: reasonCtrl,
          decoration: const InputDecoration(labelText: 'Motivo *'),
          maxLines: 2,
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () async {
              if (reasonCtrl.text.trim().isEmpty) return;
              try {
                final api = ref.read(apiClientProvider);
                await api.post('/finance/cash-sessions/${widget.session['id']}/reopen', data: {'reason': reasonCtrl.text.trim()});
                if (context.mounted) Navigator.pop(context);
                widget.onChanged();
              } catch (e) {
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e'), backgroundColor: AppTheme.danger));
              }
            },
            child: const Text('Reabrir'),
          ),
        ],
      ),
    );
  }
}
