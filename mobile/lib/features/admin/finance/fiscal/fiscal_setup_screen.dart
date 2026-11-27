import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/api/api_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_error_widget.dart';

final _setupProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final data = await ref.read(apiClientProvider).get('/finreg/admin/setup');
  return Map<String, dynamic>.from(data as Map);
});

/// "Dados fiscais": the school's certified-invoicing setup as a checklist.
///
/// Read-only: the fiscal identity, AGT channel and series are configured by
/// the platform owner. What the school can fix itself links to its screen.
class FiscalSetupScreen extends ConsumerWidget {
  const FiscalSetupScreen({super.key});

  static const _fixRoutes = <String, String>{
    'billing_items': '/admin/finance/billing-items',
    'guardian_nif': '/admin/guardians',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final setup = ref.watch(_setupProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dados fiscais'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(_setupProvider),
          ),
        ],
      ),
      body: setup.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) =>
            AppErrorWidget(error: error, onRetry: () => ref.invalidate(_setupProvider)),
        data: (data) {
          final profile = data['profile'] as Map?;
          final checks = (data['checks'] as List? ?? const []).cast<Map>();
          return ListView(padding: const EdgeInsets.all(16), children: [
            if (profile != null)
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: AppTheme.border),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(profile['name'] as String? ?? '—',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text('NIF ${profile['tax_id'] ?? '—'}'),
                    if (profile['address'] != null)
                      Text([profile['address'], profile['city']].whereType<String>().join(', '),
                          style: const TextStyle(color: AppTheme.textSecondary)),
                    if (profile['software_cert_number'] != null) ...[
                      const SizedBox(height: 8),
                      Text('Software certificado: ${profile['software_cert_number']}',
                          style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                    ],
                  ]),
                ),
              ),
            const SizedBox(height: 8),
            for (final check in checks) _CheckTile(
              check: check,
              onFix: _fixRoutes[check['key']] == null || check['level'] == 'ok'
                  ? null
                  : () => context.push(_fixRoutes[check['key']]!),
            ),
            const SizedBox(height: 16),
            const Text(
              'A identidade fiscal, a ligação à AGT e as séries são configuradas pela equipa Cellen. Para alterar estes dados, contacte o suporte.',
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
          ]);
        },
      ),
    );
  }
}

class _CheckTile extends StatelessWidget {
  final Map check;
  final VoidCallback? onFix;
  const _CheckTile({required this.check, this.onFix});

  @override
  Widget build(BuildContext context) {
    final level = check['level'] as String?;
    final (icon, color) = switch (level) {
      'ok' => (Icons.check_circle, AppTheme.success),
      'warning' => (Icons.warning_amber_rounded, AppTheme.warning),
      _ => (Icons.error, AppTheme.danger),
    };
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: color),
      title: Text(check['label'] as String? ?? ''),
      subtitle: check['detail'] == null ? null : Text(check['detail'] as String),
      trailing: onFix == null ? null : TextButton(onPressed: onFix, child: const Text('Corrigir')),
    );
  }
}
