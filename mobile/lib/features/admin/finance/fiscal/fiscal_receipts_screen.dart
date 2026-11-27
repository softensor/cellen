import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/api_client.dart';
import '../../../../core/providers/currency_provider.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_error_widget.dart';
import 'fiscal_common.dart';

/// Official FinReg receipts for every payment the school recorded.
class FiscalReceiptsScreen extends ConsumerStatefulWidget {
  const FiscalReceiptsScreen({super.key});

  @override
  ConsumerState<FiscalReceiptsScreen> createState() => _FiscalReceiptsScreenState();
}

class _FiscalReceiptsScreenState extends ConsumerState<FiscalReceiptsScreen> {
  static const _pageSize = 50;
  final List<Map<String, dynamic>> _items = [];
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  Object? _error;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Map<String, dynamic> _params(int offset) => {
        'limit': _pageSize,
        'offset': offset,
        if (_query.isNotEmpty) 'q': _query,
      };

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ref
          .read(apiClientProvider)
          .get('/finreg/admin/receipts', queryParameters: _params(0)) as Map<String, dynamic>;
      setState(() {
        _items
          ..clear()
          ..addAll((data['items'] as List).cast<Map<String, dynamic>>());
        _total = (data['total'] as num?)?.toInt() ?? _items.length;
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
      final data = await ref.read(apiClientProvider).get('/finreg/admin/receipts',
          queryParameters: _params(_items.length)) as Map<String, dynamic>;
      setState(() {
        _items.addAll((data['items'] as List).cast<Map<String, dynamic>>());
        _loadingMore = false;
      });
    } catch (_) {
      setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = ref.watch(currencyFormatProvider);
    Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      body = AppErrorWidget(error: _error!, onRetry: _load);
    } else if (_items.isEmpty) {
      body = FiscalEmptyState(
        icon: Icons.receipt_outlined,
        message: _query.isEmpty ? 'Ainda não há recibos.' : 'Nenhum recibo corresponde à pesquisa.',
      );
    } else {
      body = RefreshIndicator(
        onRefresh: _load,
        child: NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification.metrics.pixels > notification.metrics.maxScrollExtent - 200) {
              _loadMore();
            }
            return false;
          },
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
            itemCount: _items.length,
            itemBuilder: (_, index) {
              final item = _items[index];
              final reversed = item['status'] != 'normal';
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: const BorderSide(color: AppTheme.border),
                ),
                child: ListTile(
                  title: Text(item['guardian_name'] as String? ?? '—',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text([
                    fiscalDate(item['payment_date'] as String?),
                    paymentMethodLabel(item['payment_method'] as String?),
                    if (item['document_number'] != null) 'ref. ${item['document_number']}',
                    if (reversed) 'Estornado',
                  ].join(' · ')),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(
                      currency.format((item['amount'] as num?)?.toDouble() ?? 0),
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        decoration: reversed ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Recibo oficial (PDF)',
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      onPressed: () => openFiscalPdf(context, ref,
                          path: '/finreg/admin/receipts/${item['id']}/pdf',
                          filename: 'recibo-${item['id']}.pdf'),
                    ),
                  ]),
                ),
              );
            },
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recibos'),
        actions: [IconButton(tooltip: 'Atualizar', icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: FiscalSearchField(
            hint: 'Encarregado ou NIF',
            onSubmitted: (value) {
              _query = value;
              _load();
            },
          ),
        ),
        Expanded(child: body),
      ]),
    );
  }
}
