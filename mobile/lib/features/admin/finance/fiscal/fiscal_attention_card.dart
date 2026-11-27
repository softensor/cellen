import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/api/api_client.dart';
import '../../../../core/theme/app_theme.dart';

final fiscalAttentionProvider =
    FutureProvider.autoDispose<Map<String, dynamic>?>((ref) async {
  try {
    final data = await ref.read(apiClientProvider).get('/finreg/admin/attention');
    return Map<String, dynamic>.from(data as Map);
  } catch (_) {
    // A school without certified invoicing has nothing to flag here.
    return null;
  }
});

/// What in certified invoicing needs a person: documents the AGT rejected,
/// operations that failed, and documents still being confirmed. Hidden when
/// there is nothing to do.
class FiscalAttentionCard extends ConsumerWidget {
  const FiscalAttentionCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(fiscalAttentionProvider).valueOrNull;
    if (data == null) return const SizedBox.shrink();
    int count(String key) => (data[key] as num?)?.toInt() ?? 0;
    final rejected = count('rejected_documents');
    final failed = count('failed_operations');
    final pending = count('pending_documents');
    if (rejected + failed + pending == 0) return const SizedBox.shrink();

    final urgent = rejected + failed > 0;
    final color = urgent ? AppTheme.danger : AppTheme.secondary;
    final lines = <(String, String)>[
      if (rejected > 0)
        (
          rejected == 1
              ? '1 documento rejeitado pela AGT'
              : '$rejected documentos rejeitados pela AGT',
          '/admin/finance/invoices'
        ),
      if (failed > 0)
        (
          failed == 1 ? '1 operação fiscal com erro' : '$failed operações fiscais com erro',
          '/admin/finance/audit-log'
        ),
      if (pending > 0)
        (
          pending == 1
              ? '1 documento a aguardar confirmação'
              : '$pending documentos a aguardar confirmação',
          '/admin/finance/invoices'
        ),
    ];
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(children: [
        for (final line in lines)
          ListTile(
            dense: true,
            leading: Icon(
              urgent ? Icons.error_outline : Icons.cloud_sync_outlined,
              color: color,
            ),
            title: Text(line.$1, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(line.$2),
          ),
      ]),
    );
  }
}
