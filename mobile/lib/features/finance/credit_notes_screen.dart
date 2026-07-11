import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/app_theme.dart';

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------
class CreditNote {
  final String id;
  final String fullDocumentNumber;
  final String? relatedInvoiceNumber;
  final String? reason;
  final double amount;
  final String issuedAt;

  const CreditNote({
    required this.id,
    required this.fullDocumentNumber,
    this.relatedInvoiceNumber,
    this.reason,
    required this.amount,
    required this.issuedAt,
  });

  factory CreditNote.fromJson(Map<String, dynamic> json) {
    return CreditNote(
      id: json['id']?.toString() ?? '',
      fullDocumentNumber: json['full_document_number'] as String? ??
          json['document_number'] as String? ?? '',
      relatedInvoiceNumber: json['related_invoice_number'] as String? ??
          json['invoice_number'] as String?,
      reason: json['reason'] as String? ?? json['void_reason'] as String?,
      amount: (json['amount'] as num?)?.toDouble() ??
          (json['total_amount'] as num?)?.toDouble() ?? 0.0,
      issuedAt: json['issued_at'] as String? ?? json['created_at'] as String? ?? '',
    );
  }
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------
final creditNotesProvider =
    FutureProvider.autoDispose<List<CreditNote>>((ref) async {
  final api = ref.read(apiClientProvider);
  final data = await api.get('/finance/credit-notes') as List;
  return data
      .map((e) => CreditNote.fromJson(e as Map<String, dynamic>))
      .toList();
});

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------
class CreditNotesScreen extends ConsumerWidget {
  const CreditNotesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notesAsync = ref.watch(creditNotesProvider);
    final currency = NumberFormat.currency(locale: 'pt_PT', symbol: 'Kz');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notas de Crédito'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(creditNotesProvider),
          ),
        ],
      ),
      body: notesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: AppTheme.danger),
              const SizedBox(height: 8),
              Text(e.toString(), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => ref.invalidate(creditNotesProvider),
                icon: const Icon(Icons.refresh),
                label: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
        data: (notes) {
          if (notes.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.credit_score_outlined,
                      size: 64, color: Colors.grey.shade400),
                  const SizedBox(height: 16),
                  const Text('Nenhuma nota de crédito encontrada',
                      style: TextStyle(color: AppTheme.textSecondary)),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(creditNotesProvider),
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              itemCount: notes.length,
              itemBuilder: (context, i) {
                final n = notes[i];
                final dateStr = n.issuedAt.isNotEmpty
                    ? (() {
                        try {
                          return DateFormat('dd/MM/yyyy')
                              .format(DateTime.parse(n.issuedAt));
                        } catch (_) {
                          return n.issuedAt;
                        }
                      })()
                    : '';
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFDE8E8),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.credit_score,
                              color: AppTheme.danger, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                n.fullDocumentNumber,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700, fontSize: 14),
                              ),
                              if (n.relatedInvoiceNumber != null)
                                Text(
                                  'Ref. FT: ${n.relatedInvoiceNumber}',
                                  style: const TextStyle(
                                      color: AppTheme.textSecondary,
                                      fontSize: 12),
                                ),
                              if (n.reason != null)
                                Text(
                                  n.reason!,
                                  style: const TextStyle(
                                      color: AppTheme.textSecondary,
                                      fontSize: 12),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              Text(dateStr,
                                  style: const TextStyle(
                                      color: AppTheme.textSecondary,
                                      fontSize: 12)),
                            ],
                          ),
                        ),
                        Text(
                          currency.format(n.amount),
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: AppTheme.danger),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Void invoice dialog (can be called from invoices screen)
// ---------------------------------------------------------------------------
class VoidInvoiceDialog extends ConsumerStatefulWidget {
  final String invoiceId;
  final VoidCallback onVoided;

  const VoidInvoiceDialog({
    super.key,
    required this.invoiceId,
    required this.onVoided,
  });

  @override
  ConsumerState<VoidInvoiceDialog> createState() => _VoidInvoiceDialogState();
}

class _VoidInvoiceDialogState extends ConsumerState<VoidInvoiceDialog> {
  final _reasonCtrl = TextEditingController();
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_reasonCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Por favor, indique um motivo');
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      await api.post('/finance/invoices/${widget.invoiceId}/void',
          data: {'reason': _reasonCtrl.text.trim()});
      widget.onVoided();
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
      title: const Text('Anular Factura'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Esta acção irá anular a factura e gerar uma Nota de Crédito automaticamente.',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _reasonCtrl,
              decoration: const InputDecoration(labelText: 'Motivo *'),
              maxLines: 3,
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!,
                  style: const TextStyle(color: AppTheme.danger)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
          onPressed: _isLoading ? null : _submit,
          child: _isLoading
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Text('Anular Factura'),
        ),
      ],
    );
  }
}
