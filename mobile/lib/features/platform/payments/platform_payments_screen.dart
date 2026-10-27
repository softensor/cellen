import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';

final _statusProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final data =
      await ref.read(apiClientProvider).get('/platform/payments/status') as Map;
  return Map<String, dynamic>.from(data);
});

final _schoolsProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final data = await ref
      .read(apiClientProvider)
      .get('/platform/payments/schools') as Map;
  return Map<String, dynamic>.from(data);
});

const _railStateLabels = <String, String>{
  'platform_off': 'Pagamentos desactivados',
  'unreachable': 'principia-pay indisponível',
  'unregistered': 'Não registada',
  'missing_on_rail': 'Registo em falta no rail',
  'unlinked': 'Rail sem chave local',
  'needs_credentials': 'Faltam credenciais do fornecedor',
  'needs_verification': 'Credenciais por verificar',
  'needs_activation': 'Fornecedor por activar',
  'active': 'Pronta a receber',
};

const _providerStateLabels = <String, String>{
  'unverified': 'por verificar',
  'verified': 'verificado',
  'active': 'activo',
};

/// The platform owner's principia-pay switch.
///
/// One product token, minted in the rail's Products dashboard, is the only
/// value copied by hand. Each school is its own rail client and registers
/// from this screen; provider credentials stay on the rail, per client.
class PlatformPaymentsScreen extends ConsumerStatefulWidget {
  const PlatformPaymentsScreen({super.key});

  @override
  ConsumerState<PlatformPaymentsScreen> createState() =>
      _PlatformPaymentsScreenState();
}

class _PlatformPaymentsScreenState
    extends ConsumerState<PlatformPaymentsScreen> {
  final _tokenController = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _activate() async {
    final token = _tokenController.text.trim();
    if (token.isEmpty) return;
    setState(() => _busy = true);
    try {
      final data = await ref.read(apiClientProvider).post(
        '/platform/payments/activate',
        data: {'product_token': token},
      ) as Map;
      final status = Map<String, dynamic>.from(data);
      if (status['status'] == 'connected') {
        _tokenController.clear();
      }
      ref.invalidate(_statusProvider);
      ref.invalidate(_schoolsProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            status['status'] == 'connected'
                ? 'principia-pay activo.'
                : 'Token guardado, mas a verificação falhou: '
                    '${status['last_error'] ?? status['status']}',
          ),
        ),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Activação falhou: ${error.message}')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deactivate() async {
    setState(() => _busy = true);
    try {
      await ref.read(apiClientProvider).post('/platform/payments/deactivate');
      ref.invalidate(_statusProvider);
      ref.invalidate(_schoolsProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('principia-pay desactivado.')),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Não foi possível desactivar: ${error.message}')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _registerSchool(Map<String, dynamic> school) async {
    setState(() => _busy = true);
    try {
      await ref.read(apiClientProvider).post(
            '/platform/payments/schools/${school['id']}/register',
          );
      ref.invalidate(_schoolsProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${school['name']} registada no principia-pay.'),
        ),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Registo falhou: ${error.message}')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reload() async {
    ref.invalidate(_statusProvider);
    ref.invalidate(_schoolsProvider);
    await Future.wait([
      ref.read(_statusProvider.future),
      ref.read(_schoolsProvider.future),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(_statusProvider);
    final schools = ref.watch(_schoolsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pagamentos'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _reload,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            status.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => _ErrorCard(
                message: '$error',
                onRetry: () => ref.invalidate(_statusProvider),
              ),
              data: (data) => _StatusCard(
                status: data,
                busy: _busy,
                onDeactivate: _deactivate,
              ),
            ),
            const SizedBox(height: 12),
            _ActivationCard(
              controller: _tokenController,
              busy: _busy,
              onActivate: _activate,
            ),
            const SizedBox(height: 12),
            schools.when(
              loading: () => const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
              error: (error, _) => _ErrorCard(
                message: '$error',
                onRetry: () => ref.invalidate(_schoolsProvider),
              ),
              data: (data) => _SchoolsCard(
                data: data,
                busy: _busy,
                onRegister: _registerSchool,
              ),
            ),
            const SizedBox(height: 12),
            const _HowItWorksCard(),
          ],
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.status,
    required this.busy,
    required this.onDeactivate,
  });

  final Map<String, dynamic> status;
  final bool busy;
  final VoidCallback onDeactivate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final configured = status['configured'] == true;
    final state = status['status']?.toString() ?? 'not_configured';
    final attention = state == 'attention';
    final color = configured
        ? Colors.green
        : attention
            ? Colors.orange
            : theme.colorScheme.onSurfaceVariant;
    final icon = configured
        ? Icons.check_circle
        : attention
            ? Icons.error_outline
            : Icons.link_off;
    final title = configured
        ? 'principia-pay activo'
        : attention
            ? 'Configuração precisa de atenção'
            : 'principia-pay não configurado';
    final prefix = status['token_prefix']?.toString() ?? '';
    final source = status['token_source']?.toString();
    final lastError = status['last_error']?.toString();
    final lastChecked = status['last_checked_at']?.toString();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Fornecedor: ${status['provider'] ?? '—'} · '
              'Produto: ${status['source_system'] ?? '—'}',
              style: theme.textTheme.bodySmall,
            ),
            if (prefix.isNotEmpty)
              Text(
                'Token: $prefix…  '
                '(${source == 'admin' ? 'guardado neste ecrã' : 'vindo do servidor'})',
                style: theme.textTheme.bodySmall,
              ),
            if (lastError != null && lastError.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Último erro: $lastError',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error),
              ),
            ],
            if (lastChecked != null) ...[
              const SizedBox(height: 4),
              Text(
                'Última verificação: ${_formatDate(lastChecked)}',
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
              ),
            ],
            if (configured) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  onPressed: busy ? null : onDeactivate,
                  icon: const Icon(Icons.power_settings_new, size: 18),
                  label: const Text('Desactivar'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ActivationCard extends StatelessWidget {
  const _ActivationCard({
    required this.controller,
    required this.busy,
    required this.onActivate,
  });

  final TextEditingController controller;
  final bool busy;
  final VoidCallback onActivate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Activar com o token do produto',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              'No dashboard do principia-pay, abra Produtos → cellen (o '
              'identificador do produto, em minúsculas) e gere (ou copie) o '
              'token. Cole-o aqui: é o único código que se copia à mão.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                labelText: 'Token do produto (ppt_…)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: busy ? null : onActivate,
                icon: const Icon(Icons.verified_user_outlined, size: 18),
                label: Text(busy ? 'A verificar…' : 'Activar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SchoolsCard extends StatelessWidget {
  const _SchoolsCard({
    required this.data,
    required this.busy,
    required this.onRegister,
  });

  final Map<String, dynamic> data;
  final bool busy;
  final Future<void> Function(Map<String, dynamic> school) onRegister;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = (data['schools'] as List? ?? [])
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
    final railError = data['rail_error']?.toString();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Escolas nesta plataforma',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              'Cada escola é um cliente próprio no principia-pay. Registe-a '
              'aqui; as credenciais do fornecedor configuram-se depois, no '
              'rail, por cliente.',
              style: theme.textTheme.bodySmall,
            ),
            if (railError != null && railError.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Não foi possível consultar o principia-pay: $railError',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error),
              ),
            ],
            const SizedBox(height: 8),
            if (rows.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Ainda não há escolas.'),
              )
            else
              for (final school in rows)
                _SchoolRow(
                  school: school,
                  busy: busy,
                  canRegister: data['configured'] == true,
                  onRegister: () => onRegister(school),
                ),
          ],
        ),
      ),
    );
  }
}

class _SchoolRow extends StatelessWidget {
  const _SchoolRow({
    required this.school,
    required this.busy,
    required this.canRegister,
    required this.onRegister,
  });

  final Map<String, dynamic> school;
  final bool busy;
  final bool canRegister;
  final VoidCallback onRegister;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = school['rail_state']?.toString() ?? 'unknown';
    final active = state == 'active';
    final repairable = state == 'unregistered' || state == 'missing_on_rail';
    final providers = Map<String, dynamic>.from(
      (school['providers'] as Map?) ?? const {},
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                active ? Icons.check_circle : Icons.circle_outlined,
                size: 18,
                color:
                    active ? Colors.green : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  school['name']?.toString() ?? '—',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Chip(
                label: Text(_railStateLabels[state] ?? state),
                visualDensity: VisualDensity.compact,
                backgroundColor:
                    active ? Colors.green.withValues(alpha: 0.12) : null,
              ),
            ],
          ),
          if (providers.isNotEmpty) ...[
            const SizedBox(height: 2),
            Padding(
              padding: const EdgeInsets.only(left: 26),
              child: Text(
                providers.entries
                    .map((entry) =>
                        '${entry.key}: ${_providerStateLabels[entry.value] ?? entry.value}')
                    .join(' · '),
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
          if (repairable) ...[
            const SizedBox(height: 2),
            Padding(
              padding: const EdgeInsets.only(left: 26),
              child: TextButton.icon(
                onPressed: busy || !canRegister ? null : onRegister,
                icon: const Icon(Icons.add_link, size: 18),
                label: Text(busy ? 'A registar…' : 'Registar escola'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HowItWorksCard extends StatelessWidget {
  const _HowItWorksCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Como funciona',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              '1. O token do produto é o único código copiado à mão; ele '
              'identifica a Cellen no principia-pay.\n'
              '2. Cada escola regista-se no rail com a sua própria chave — '
              'o dinheiro de uma nunca se mistura com o de outra.\n'
              '3. As credenciais do fornecedor (AppyPay) configuram-se no '
              'rail, por cliente; esta lista mostra o que falta.\n'
              '4. Uma referência só é emitida contra uma dívida em aberto, '
              'e a liquidação fecha no FinReg quando a escola lá está.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message),
            TextButton(
              onPressed: onRetry,
              child: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatDate(String value) {
  final parsed = DateTime.tryParse(value);
  if (parsed == null) return value;
  return DateFormat('dd/MM/yyyy HH:mm').format(parsed.toLocal());
}
