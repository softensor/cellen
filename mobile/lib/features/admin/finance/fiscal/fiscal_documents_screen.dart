import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/api/api_client.dart';
import '../../../../core/api/api_exception.dart';
import '../../../../core/providers/currency_provider.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_error_widget.dart';
import 'fiscal_common.dart';
import 'fiscal_issue_invoice_screen.dart';

/// Fiscal documents (invoices, credit notes, debit notes) issued by FinReg
/// for this school, listed natively from Cellen's ledger.
class FiscalDocumentsScreen extends ConsumerStatefulWidget {
  /// Comma-separated FinReg kinds this screen lists.
  final String kinds;
  final String title;
  final bool allowIssue;

  const FiscalDocumentsScreen({
    super.key,
    this.kinds = 'invoice,invoice_receipt,debit_note',
    this.title = 'Faturas',
    this.allowIssue = true,
  });

  const FiscalDocumentsScreen.creditNotes({super.key})
      : kinds = 'credit_note',
        title = 'Notas de crédito',
        allowIssue = false;

  @override
  ConsumerState<FiscalDocumentsScreen> createState() =>
      _FiscalDocumentsScreenState();
}

class _FiscalDocumentsScreenState extends ConsumerState<FiscalDocumentsScreen> {
  static const _pageSize = 50;
  final List<Map<String, dynamic>> _items = [];
  Map<String, dynamic> _summary = const {};
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  Object? _error;
  String _query = '';
  String? _state;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Map<String, dynamic> _params(int offset) => {
        'kind': widget.kinds,
        'limit': _pageSize,
        'offset': offset,
        if (_query.isNotEmpty) 'q': _query,
        if (_state != null) 'state': _state,
      };

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ref
          .read(apiClientProvider)
          .get('/finreg/admin/documents', queryParameters: _params(0))
          as Map<String, dynamic>;
      setState(() {
        _items
          ..clear()
          ..addAll((data['items'] as List).cast<Map<String, dynamic>>());
        _total = (data['total'] as num?)?.toInt() ?? _items.length;
        _summary = Map<String, dynamic>.from(data['summary'] as Map? ?? {});
        _loading = false;
      });
    } catch (error) {
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _items.length >= _total) return;
    setState(() => _loadingMore = true);
    try {
      final data = await ref.read(apiClientProvider).get(
          '/finreg/admin/documents',
          queryParameters: _params(_items.length)) as Map<String, dynamic>;
      setState(() {
        _items.addAll((data['items'] as List).cast<Map<String, dynamic>>());
        _loadingMore = false;
      });
    } catch (_) {
      setState(() => _loadingMore = false);
    }
  }

  Future<void> _openDetail(Map<String, dynamic> item) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => FiscalDocumentDetailSheet(documentId: item['id'] as String),
    );
    if (changed == true) _load();
  }

  Future<void> _issue() async {
    final issued = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const FiscalIssueInvoiceScreen()),
    );
    if (issued == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final currency = ref.watch(currencyFormatProvider);
    final rejected = (_summary['rejected'] as num?)?.toInt() ?? 0;
    final pending = ((_summary['processing'] as num?)?.toInt() ?? 0) +
        ((_summary['submitted'] as num?)?.toInt() ?? 0);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
              tooltip: 'Atualizar',
              icon: const Icon(Icons.refresh),
              onPressed: _load),
        ],
      ),
      floatingActionButton: widget.allowIssue
          ? FloatingActionButton.extended(
              onPressed: _issue,
              icon: const Icon(Icons.add),
              label: const Text('Emitir fatura'),
            )
          : null,
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: FiscalSearchField(
            hint: 'Número, encarregado, aluno ou NIF',
            onSubmitted: (value) {
              _query = value;
              _load();
            },
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(children: [
            for (final option in const [
              (null, 'Todos'),
              ('issued', 'Emitidas'),
              ('submitted', 'Enviadas à AGT'),
              ('processing', 'Em processamento'),
              ('rejected', 'Rejeitadas'),
              ('cancelled', 'Anuladas'),
            ])
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(option.$2),
                  selected: _state == option.$1,
                  onSelected: (_) {
                    _state = option.$1;
                    _load();
                  },
                ),
              ),
          ]),
        ),
        if (rejected > 0 && _state != 'rejected')
          _AttentionBanner(
            color: AppTheme.danger,
            icon: Icons.error_outline,
            text: rejected == 1
                ? '1 documento foi rejeitado pela AGT.'
                : '$rejected documentos foram rejeitados pela AGT.',
            action: 'Ver',
            onTap: () {
              _state = 'rejected';
              _load();
            },
          )
        else if (pending > 0 && _state == null)
          _AttentionBanner(
            color: AppTheme.secondary,
            icon: Icons.cloud_sync_outlined,
            text: pending == 1
                ? '1 documento aguarda confirmação fiscal.'
                : '$pending documentos aguardam confirmação fiscal.',
          ),
        Expanded(child: _body(currency)),
      ]),
    );
  }

  Widget _body(NumberFormat currency) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return AppErrorWidget(error: _error!, onRetry: _load);
    if (_items.isEmpty) {
      return FiscalEmptyState(
        icon: Icons.receipt_long_outlined,
        message: _query.isEmpty && _state == null
            ? 'Ainda não há ${widget.title.toLowerCase()}.'
            : 'Nenhum documento corresponde à pesquisa.',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification.metrics.pixels >
              notification.metrics.maxScrollExtent - 200) {
            _loadMore();
          }
          return false;
        },
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
          itemCount: _items.length + (_items.length < _total ? 1 : 0),
          itemBuilder: (_, index) {
            if (index >= _items.length) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final item = _items[index];
            return _DocumentTile(
              item: item,
              currency: currency,
              onTap: () => _openDetail(item),
            );
          },
        ),
      ),
    );
  }
}

class _AttentionBanner extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String text;
  final String? action;
  final VoidCallback? onTap;
  const _AttentionBanner({
    required this.color,
    required this.icon,
    required this.text,
    this.action,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: TextStyle(color: color))),
        if (action != null)
          TextButton(onPressed: onTap, child: Text(action!)),
      ]),
    );
  }
}

class _DocumentTile extends StatelessWidget {
  final Map<String, dynamic> item;
  final NumberFormat currency;
  final VoidCallback onTap;
  const _DocumentTile(
      {required this.item, required this.currency, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final number = item['full_document_number'] as String?;
    final gross = (item['gross_total'] as num?)?.toDouble();
    final who = [item['pupil_name'], item['customer_name'] ?? item['guardian_name']]
        .whereType<String>()
        .where((value) => value.isNotEmpty)
        .join(' · ');
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: AppTheme.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    number ?? '${fiscalKindLabel(item['kind'] as String?)} em emissão',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  if (who.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(who,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppTheme.textSecondary)),
                  ],
                  const SizedBox(height: 6),
                  Row(children: [
                    FiscalStateChip(state: item['state'] as String?, dense: true),
                    const SizedBox(width: 8),
                    Text(fiscalDate(item['document_date'] as String?),
                        style: const TextStyle(
                            fontSize: 12, color: AppTheme.textSecondary)),
                  ]),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              gross == null ? '—' : currency.format(gross),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ]),
        ),
      ),
    );
  }
}

/// One document: FinReg's lines and totals, its official PDF, a refresh,
/// and the correction (credit note) flow.
class FiscalDocumentDetailSheet extends ConsumerStatefulWidget {
  final String documentId;
  const FiscalDocumentDetailSheet({super.key, required this.documentId});

  @override
  ConsumerState<FiscalDocumentDetailSheet> createState() =>
      _FiscalDocumentDetailSheetState();
}

class _FiscalDocumentDetailSheetState
    extends ConsumerState<FiscalDocumentDetailSheet> {
  Map<String, dynamic>? _document;
  Object? _error;
  bool _refreshing = false;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _load(refresh: true);
  }

  Future<void> _load({bool refresh = false}) async {
    setState(() => _refreshing = true);
    try {
      final data = await ref.read(apiClientProvider).get(
            '/finreg/admin/documents/${widget.documentId}',
            queryParameters: {'refresh': refresh},
          ) as Map<String, dynamic>;
      setState(() {
        _document = data;
        _error = null;
        _refreshing = false;
      });
    } catch (error) {
      setState(() {
        _error = error;
        _refreshing = false;
      });
    }
  }

  Future<void> _correct() async {
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => FiscalCorrectionDialog(document: _document!),
    );
    if (done == true) {
      _changed = true;
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = ref.watch(currencyFormatProvider);
    final document = _document;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.9,
        maxChildSize: 0.95,
        builder: (_, controller) {
          if (document == null) {
            if (_error != null) {
              return AppErrorWidget(error: _error!, onRetry: () => _load(refresh: true));
            }
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: _content(document, currency),
          );
        },
      ),
    );
  }

  List<Widget> _content(Map<String, dynamic> document, NumberFormat currency) {
    final state = document['state'] as String?;
    final kind = document['kind'] as String?;
    final number = document['full_document_number'] as String?;
    final lines = (document['lines'] as List? ?? const []).cast<Map>();
    final related = (document['related'] as List? ?? const []).cast<Map>();
    final canCorrect = const {'invoice', 'invoice_receipt', 'debit_note'}.contains(kind) &&
        document['document_status'] == 'finalized';
    final canPdf = document['document_status'] != 'draft';
    double? money(String key) => (document[key] as num?)?.toDouble();

    return [
      Center(
        child: Container(
          width: 40,
          height: 4,
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
              color: AppTheme.border, borderRadius: BorderRadius.circular(2)),
        ),
      ),
      Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(fiscalKindLabel(kind),
                style: const TextStyle(color: AppTheme.textSecondary)),
            Text(number ?? 'Em emissão',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          ]),
        ),
        FiscalStateChip(state: state),
      ]),
      if (document['stale'] == true)
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text(
            'Não foi possível confirmar o estado agora; a mostrar a última informação recebida.',
            style: TextStyle(fontSize: 12, color: AppTheme.warning),
          ),
        ),
      if (state == 'rejected' && document['agt_message'] != null)
        Container(
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.danger.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text('Motivo da AGT: ${document['agt_message']}',
              style: const TextStyle(color: AppTheme.danger)),
        ),
      const SizedBox(height: 16),
      _Field('Encarregado', document['customer_name'] ?? document['guardian_name']),
      _Field('NIF', document['customer_tax_id']),
      _Field('Aluno', document['pupil_name']),
      _Field('Período', document['billing_period']),
      _Field('Data', fiscalDate(document['document_date'] as String?)),
      _Field('Vencimento', fiscalDate(document['due_date'] as String?)),
      const Divider(height: 32),
      if (lines.isEmpty)
        const Text('As linhas aparecem quando o documento for confirmado.',
            style: TextStyle(color: AppTheme.textSecondary))
      else
        for (final line in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              Expanded(
                child: Text(
                    '${line['description'] ?? '—'}  ×${line['quantity'] ?? 1}'),
              ),
              Text(line['line_total'] == null
                  ? '—'
                  : currency.format((line['line_total'] as num).toDouble())),
            ]),
          ),
      const Divider(height: 24),
      _Total('Sem imposto', money('net_total'), currency),
      _Total('Imposto', money('tax_total'), currency),
      _Total('Total', money('gross_total'), currency, bold: true),
      if (document['software_cert_number'] != null) ...[
        const SizedBox(height: 12),
        Text('Software certificado: ${document['software_cert_number']}',
            style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
      ],
      if (related.isNotEmpty) ...[
        const SizedBox(height: 20),
        const Text('Documentos relacionados',
            style: TextStyle(fontWeight: FontWeight.w700)),
        for (final item in related)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(item['full_document_number'] as String? ??
                fiscalKindLabel(item['kind'] as String?)),
            subtitle: Text(fiscalKindLabel(item['kind'] as String?)),
            trailing: FiscalStateChip(state: item['state'] as String?, dense: true),
          ),
      ],
      const SizedBox(height: 24),
      Wrap(spacing: 8, runSpacing: 8, children: [
        FilledButton.icon(
          onPressed: canPdf
              ? () => openFiscalPdf(context, ref,
                  path: '/finreg/admin/documents/${widget.documentId}/pdf',
                  filename: '${(number ?? widget.documentId).replaceAll('/', '-')}.pdf')
              : null,
          icon: const Icon(Icons.picture_as_pdf_outlined),
          label: const Text('PDF oficial'),
        ),
        OutlinedButton.icon(
          onPressed: _refreshing ? null : () => _load(refresh: true),
          icon: _refreshing
              ? const SizedBox(
                  width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.sync),
          label: const Text('Confirmar estado'),
        ),
        if (canCorrect)
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: AppTheme.danger),
            onPressed: _correct,
            icon: const Icon(Icons.undo),
            label: const Text('Anular (nota de crédito)'),
          ),
      ]),
    ];
  }
}

class _Field extends StatelessWidget {
  final String label;
  final Object? value;
  const _Field(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final text = value?.toString();
    if (text == null || text.isEmpty || text == '—') return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 110,
          child: Text(label, style: const TextStyle(color: AppTheme.textSecondary)),
        ),
        Expanded(child: Text(text)),
      ]),
    );
  }
}

class _Total extends StatelessWidget {
  final String label;
  final double? value;
  final NumberFormat currency;
  final bool bold;
  const _Total(this.label, this.value, this.currency, {this.bold = false});

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
        fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
        fontSize: bold ? 16 : 14);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(children: [
        Expanded(child: Text(label, style: style)),
        Text(value == null ? '—' : currency.format(value), style: style),
      ]),
    );
  }
}

/// Cancels a fiscal document. FinReg issues the credit note; Cellen only
/// sends the reason, under one request id per dialog.
class FiscalCorrectionDialog extends ConsumerStatefulWidget {
  final Map<String, dynamic> document;
  const FiscalCorrectionDialog({super.key, required this.document});

  @override
  ConsumerState<FiscalCorrectionDialog> createState() =>
      _FiscalCorrectionDialogState();
}

class _FiscalCorrectionDialogState extends ConsumerState<FiscalCorrectionDialog> {
  final _reason = TextEditingController();
  final String _requestId = newRequestId();
  bool _sending = false;
  String? _error;
  String? _notice;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final reason = _reason.text.trim();
    if (reason.length < 3) {
      setState(() => _error = 'Indique o motivo da anulação.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final result = await ref.read(apiClientProvider).post(
        '/finreg/admin/documents/${widget.document['id']}/corrections',
        data: {'request_id': _requestId, 'reason': reason},
      ) as Map<String, dynamic>;
      if (!mounted) return;
      if (result['status'] == 'confirmed') {
        final credit = result['credit_note'] as Map?;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(credit?['full_document_number'] != null
              ? 'Documento anulado. Nota de crédito ${credit!['full_document_number']}.'
              : 'Documento anulado.'),
        ));
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _sending = false;
          _notice =
              'A anulação foi enviada e está a ser confirmada. Pode fechar esta janela; o estado atualiza sozinho.';
        });
      }
    } catch (error) {
      setState(() {
        _sending = false;
        _error = apiErrorMessage(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final number = widget.document['full_document_number'] ?? 'este documento';
    return AlertDialog(
      title: const Text('Anular documento'),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
              'Será emitida uma nota de crédito que anula $number. Esta operação é fiscal e não pode ser desfeita.'),
          const SizedBox(height: 12),
          TextField(
            controller: _reason,
            maxLength: 250,
            maxLines: 2,
            enabled: !_sending && _notice == null,
            decoration: const InputDecoration(
              labelText: 'Motivo',
              border: OutlineInputBorder(),
            ),
          ),
          if (_error != null)
            Text(_error!, style: const TextStyle(color: AppTheme.danger)),
          if (_notice != null)
            Text(_notice!, style: const TextStyle(color: AppTheme.secondary)),
        ]),
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.of(context).pop(_notice != null),
          child: Text(_notice != null ? 'Fechar' : 'Cancelar'),
        ),
        if (_notice == null)
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: _sending ? null : _submit,
            child: _sending
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Anular'),
          ),
      ],
    );
  }
}
