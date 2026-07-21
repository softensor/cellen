import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_client.dart';
import '../../../core/providers/currency_provider.dart';
import '../../../core/theme/app_theme.dart';

final _delinquentProvider2 = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final api = ref.read(apiClientProvider);
  final data = await api.get('/finance/reports/delinquent') as List;
  return data.cast<Map<String, dynamic>>();
});

final _remindersProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final api = ref.read(apiClientProvider);
  final data = await api.get('/finance/reminders') as List;
  return data.cast<Map<String, dynamic>>();
});

class RemindersScreen extends ConsumerWidget {
  const RemindersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final delinquentAsync = ref.watch(_delinquentProvider2);
    final currency = ref.watch(currencyFormatProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Lembretes de Pagamento'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: () {
            ref.invalidate(_delinquentProvider2);
            ref.invalidate(_remindersProvider);
          }),
        ],
      ),
      body: delinquentAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(e.toString(), style: const TextStyle(color: AppTheme.danger))),
        data: (delinquents) {
          if (delinquents.isEmpty) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle_outline, size: 64, color: AppTheme.success),
                  SizedBox(height: 12),
                  Text('Nenhum devedor activo', style: TextStyle(color: AppTheme.textSecondary)),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(_delinquentProvider2);
              ref.invalidate(_remindersProvider);
            },
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
              itemCount: delinquents.length,
              itemBuilder: (_, i) => _DelinquentReminderCard(
                guardian: delinquents[i],
                currency: currency,
                onSent: () => ref.invalidate(_remindersProvider),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DelinquentReminderCard extends ConsumerStatefulWidget {
  final Map<String, dynamic> guardian;
  final NumberFormat currency;
  final VoidCallback onSent;
  const _DelinquentReminderCard({required this.guardian, required this.currency, required this.onSent});

  @override
  ConsumerState<_DelinquentReminderCard> createState() => _DelinquentReminderCardState();
}

class _DelinquentReminderCardState extends ConsumerState<_DelinquentReminderCard> {
  bool _showHistory = false;

  @override
  Widget build(BuildContext context) {
    final g = widget.guardian;
    final total = (g['total_overdue'] as num?)?.toDouble() ?? 0;
    final count = (g['invoice_count'] as num?)?.toInt() ?? 0;
    final name = g['guardian_name'] as String? ?? '—';
    final guardianId = g['billing_guardian_id']?.toString() ?? g['guardian_id']?.toString() ?? '';

    // Filter reminders for this guardian from the shared provider
    final remindersAsync = ref.watch(_remindersProvider);
    final guardianReminders = remindersAsync.when(
      data: (all) => all.where((r) {
        final rid = r['billing_guardian_id']?.toString() ?? r['guardian_id']?.toString() ?? '';
        return rid == guardianId;
      }).toList(),
      loading: () => <Map<String, dynamic>>[],
      error: (_, __) => <Map<String, dynamic>>[],
    );

    // Determine the last sent level for escalation enforcement
    final lastLevel = guardianReminders.isNotEmpty
        ? guardianReminders.map((r) => (r['level'] as num?)?.toInt() ?? 1).reduce((a, b) => a > b ? a : b)
        : 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: AppTheme.danger.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          ListTile(
            leading: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(color: AppTheme.danger.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.warning_amber_outlined, color: AppTheme.danger, size: 20),
            ),
            title: Row(children: [
              Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w700))),
              if (guardianReminders.isNotEmpty)
                GestureDetector(
                  onTap: () => setState(() => _showHistory = !_showHistory),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: Colors.blue.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                    child: Text('${guardianReminders.length} lembrete(s)', style: const TextStyle(fontSize: 10, color: Colors.blue, fontWeight: FontWeight.w600)),
                  ),
                ),
            ]),
            subtitle: Text('$count factura(s) · ${widget.currency.format(total)}', style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
            trailing: FilledButton.tonal(
              onPressed: () => _showSendReminder(context, g, lastLevel),
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), visualDensity: VisualDensity.compact),
              child: const Text('Enviar Lembrete', style: TextStyle(fontSize: 12)),
            ),
          ),
          // Reminder history (UC-DN3)
          if (_showHistory && guardianReminders.isNotEmpty)
            Container(
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Histórico de Lembretes', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11, color: AppTheme.textSecondary)),
                  const SizedBox(height: 6),
                  ...guardianReminders.reversed.take(5).map((r) {
                    final level = (r['level'] as num?)?.toInt() ?? 1;
                    final channel = r['channel'] as String? ?? '—';
                    final sentAt = r['sent_at'] as String? ?? r['created_at'] as String? ?? '—';
                    String formattedDate = sentAt;
                    try { formattedDate = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.parse(sentAt)); } catch (_) {}
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          Container(
                            width: 22, height: 22,
                            decoration: BoxDecoration(
                              color: [Colors.blue, Colors.orange, AppTheme.danger][level.clamp(1,3)-1].withOpacity(0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Center(child: Text('N$level', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: [Colors.blue, Colors.orange, AppTheme.danger][level.clamp(1,3)-1]))),
                          ),
                          const SizedBox(width: 8),
                          Expanded(child: Text(channel, style: const TextStyle(fontSize: 12))),
                          Text(formattedDate, style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _showSendReminder(BuildContext context, Map<String, dynamic> guardian, int lastLevel) {
    showDialog(useRootNavigator: false, 
      context: context,
      builder: (_) => _SendReminderDialog(
        guardian: guardian,
        currency: widget.currency,
        onSent: widget.onSent,
        minLevel: lastLevel + 1 <= 3 ? lastLevel + 1 : 3,
      ),
    );
  }
}

class _SendReminderDialog extends ConsumerStatefulWidget {
  final Map<String, dynamic> guardian;
  final NumberFormat currency;
  final VoidCallback onSent;
  final int minLevel;
  const _SendReminderDialog({required this.guardian, required this.currency, required this.onSent, this.minLevel = 1});

  @override
  ConsumerState<_SendReminderDialog> createState() => _SendReminderDialogState();
}

class _SendReminderDialogState extends ConsumerState<_SendReminderDialog> {
  late int _level;
  String _channel = 'whatsapp';
  late TextEditingController _messageCtrl;
  bool _loading = false;
  String? _error;
  List<String> _invoiceIds = [];

  static const _channels = {
    'whatsapp': 'WhatsApp',
    'email': 'Email',
    'sms': 'SMS',
    'letter': 'Carta',
    'verbal': 'Verbal',
  };

  @override
  void initState() {
    super.initState();
    _level = widget.minLevel.clamp(1, 3);
    _loadInvoices();
    _messageCtrl = TextEditingController(text: _buildTemplate());
  }

  String _buildTemplate() {
    final name = widget.guardian['guardian_name'] as String? ?? '';
    final total = (widget.guardian['total_overdue'] as num?)?.toDouble() ?? 0;
    final count = (widget.guardian['invoice_count'] as num?)?.toInt() ?? 0;
    return 'Caro/a $name,\n\nInformamos que tem $count factura(s) em atraso no valor total de ${widget.currency.format(total)}.\n\nAgradecemos que proceda à regularização o mais brevemente possível.\n\nCom os melhores cumprimentos,\nSecretaria';
  }

  Future<void> _loadInvoices() async {
    try {
      final api = ref.read(apiClientProvider);
      final guardianId = widget.guardian['billing_guardian_id']?.toString() ?? widget.guardian['guardian_id']?.toString() ?? '';
      if (guardianId.isEmpty) return;
      final data = await api.get('/finance/invoices', queryParameters: {
        'billing_guardian_id': guardianId,
        'status': 'overdue',
      }) as List;
      setState(() => _invoiceIds = data.cast<Map<String, dynamic>>().map((i) => i['id']?.toString() ?? '').where((id) => id.isNotEmpty).toList());
    } catch (_) {}
  }

  @override
  void dispose() {
    _messageCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_messageCtrl.text.trim().isEmpty) return;
    setState(() { _loading = true; _error = null; });
    try {
      final api = ref.read(apiClientProvider);
      final guardianId = widget.guardian['billing_guardian_id']?.toString() ?? widget.guardian['guardian_id']?.toString() ?? '';
      await api.post('/finance/reminders', data: {
        'billing_guardian_id': guardianId,
        'invoice_ids': _invoiceIds,
        'level': _level,
        'channel': _channel,
        'message_snapshot': _messageCtrl.text.trim(),
      });
      widget.onSent();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lembrete registado com sucesso'), backgroundColor: AppTheme.success));
      }
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Lembrete — ${widget.guardian['guardian_name'] ?? ''}'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Text('Nível: ', style: TextStyle(fontWeight: FontWeight.w600)),
                ...[1, 2, 3].map((l) => Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: ChoiceChip(
                    label: Text('N$l'),
                    selected: _level == l,
                    // Enforce escalation: cannot select level below minLevel (spec 20.16.3)
                    onSelected: l >= widget.minLevel ? (_) => setState(() { _level = l; _messageCtrl.text = _buildTemplate(); }) : null,
                  ),
                )),
              ]),
              if (widget.minLevel > 1)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('Escalada obrigatória: já foram enviados lembretes até N${widget.minLevel - 1}', style: const TextStyle(fontSize: 11, color: Colors.orange)),
                ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _channel,
                decoration: const InputDecoration(labelText: 'Canal'),
                items: _channels.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                onChanged: (v) => setState(() => _channel = v ?? 'whatsapp'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _messageCtrl,
                decoration: const InputDecoration(labelText: 'Mensagem', border: OutlineInputBorder()),
                maxLines: 6,
              ),
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
        FilledButton.icon(
          onPressed: _loading ? null : _send,
          icon: _loading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.send, size: 16),
          label: const Text('Registar Envio'),
        ),
      ],
    );
  }
}
