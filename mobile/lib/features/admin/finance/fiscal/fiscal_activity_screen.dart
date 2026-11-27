import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/api_client.dart';
import '../../../../core/api/api_exception.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_error_widget.dart';
import 'fiscal_common.dart';

/// Every fiscal instruction Cellen sent: who, when, what, and the outcome.
class FiscalActivityScreen extends ConsumerStatefulWidget {
  const FiscalActivityScreen({super.key});

  @override
  ConsumerState<FiscalActivityScreen> createState() => _FiscalActivityScreenState();
}

class _FiscalActivityScreenState extends ConsumerState<FiscalActivityScreen> {
  static const _pageSize = 50;
  final List<Map<String, dynamic>> _items = [];
  int _total = 0;
  bool _loading = true;
  Object? _error;
  String? _status;
  final Set<String> _retrying = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool more = false}) async {
    if (!more) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final data = await ref.read(apiClientProvider).get('/finreg/admin/activity', queryParameters: {
        'limit': _pageSize,
        'offset': more ? _items.length : 0,
        if (_status != null) 'status': _status,
      }) as Map<String, dynamic>;
      setState(() {
        if (!more) _items.clear();
        _items.addAll((data['items'] as List).cast<Map<String, dynamic>>());
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

  Future<void> _retry(Map<String, dynamic> item) async {
    final id = item['id'] as String;
    setState(() => _retrying.add(id));
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(apiClientProvider).post('/finreg/instructions/$id/retry');
      messenger.showSnackBar(const SnackBar(content: Text('Operação reenviada.')));
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(apiErrorMessage(error))));
    } finally {
      if (mounted) setState(() => _retrying.remove(id));
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      body = AppErrorWidget(error: _error!, onRetry: _load);
    } else if (_items.isEmpty) {
      body = const FiscalEmptyState(
          icon: Icons.history, message: 'Sem operações fiscais registadas.');
    } else {
      body = RefreshIndicator(
        onRefresh: _load,
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
          itemCount: _items.length + (_items.length < _total ? 1 : 0),
          itemBuilder: (_, index) {
            if (index >= _items.length) {
              return TextButton(
                  onPressed: () => _load(more: true), child: const Text('Mostrar mais'));
            }
            final item = _items[index];
            final status = item['status'] as String?;
            final id = item['id'] as String;
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: const BorderSide(color: AppTheme.border),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                      child: Text(item['label'] as String? ?? '—',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    FiscalStateChip(
                      state: status == 'processing' ? 'processing' : (status == 'rejected' ? 'rejected' : 'confirmed'),
                      dense: true,
                    ),
                  ]),
                  const SizedBox(height: 4),
                  Text(
                    [
                      fiscalDate(item['created_at'] as String?),
                      item['actor'] as String? ?? 'Sistema',
                      if (item['document_number'] != null) item['document_number'],
                      if ((item['attempts'] as num? ?? 0) > 1) '${item['attempts']} tentativas',
                    ].join(' · '),
                    style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                  ),
                  if (status != 'confirmed' && item['error_detail'] != null) ...[
                    const SizedBox(height: 6),
                    Text(item['error_detail'] as String,
                        style: TextStyle(
                            color: status == 'rejected' ? AppTheme.danger : AppTheme.warning)),
                  ],
                  if (item['can_retry'] == true)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: _retrying.contains(id) ? null : () => _retry(item),
                        icon: const Icon(Icons.replay),
                        label: const Text('Tentar novamente'),
                      ),
                    ),
                ]),
              ),
            );
          },
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Registo fiscal'),
        actions: [IconButton(tooltip: 'Atualizar', icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      body: Column(children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Row(children: [
            for (final option in const [
              (null, 'Todas'),
              ('processing', 'Em curso'),
              ('rejected', 'Com erro'),
              ('confirmed', 'Concluídas'),
            ])
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(option.$2),
                  selected: _status == option.$1,
                  onSelected: (_) {
                    _status = option.$1;
                    _load();
                  },
                ),
              ),
          ]),
        ),
        Expanded(child: body),
      ]),
    );
  }
}
