import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/models/website.dart';

class WebsiteSettingsScreen extends ConsumerStatefulWidget {
  const WebsiteSettingsScreen({super.key});

  @override
  ConsumerState<WebsiteSettingsScreen> createState() =>
      _WebsiteSettingsScreenState();
}

class _WebsiteSettingsScreenState
    extends ConsumerState<WebsiteSettingsScreen> {
  List<WebsiteSetting> _settings = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      final data = await api.get('/website/admin/settings');
      setState(() {
        _settings = (data as List)
            .map((e) => WebsiteSetting.fromJson(e as Map<String, dynamic>))
            .toList();
        _loading = false;
      });
    } on ApiException catch (e) {
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  Future<void> _editSetting(WebsiteSetting setting) async {
    final valueCtrl = TextEditingController(
      text: _prettyJson(setting.value),
    );

    final result = await showDialog<bool>(useRootNavigator: false, 
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Editar: ${setting.key}'),
        content: TextField(
          controller: valueCtrl,
          decoration: const InputDecoration(labelText: 'Valor (JSON)'),
          maxLines: 8,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (result != true) return;

    try {
      final parsed = const JsonDecoder().convert(valueCtrl.text);
      final api = ref.read(apiClientProvider);
      await api.put('/website/admin/settings', data: {
        'key': setting.key,
        'value': parsed,
      });
      await _load();
    } on FormatException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('JSON inválido')),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _addSetting() async {
    final keyCtrl = TextEditingController();

    final result = await showDialog<bool>(useRootNavigator: false, 
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nova configuração'),
        content: TextField(
          controller: keyCtrl,
          decoration: const InputDecoration(labelText: 'Chave'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Criar'),
          ),
        ],
      ),
    );

    if (result != true) return;

    try {
      final api = ref.read(apiClientProvider);
      await api.put('/website/admin/settings', data: {
        'key': keyCtrl.text.trim(),
        'value': <String, dynamic>{},
      });
      await _load();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _deleteSetting(WebsiteSetting setting) async {
    final confirmed = await showDialog<bool>(useRootNavigator: false, 
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar configuração'),
        content: Text('Eliminar "${setting.key}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final api = ref.read(apiClientProvider);
      await api.delete('/website/admin/settings/${setting.key}');
      await _load();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  String _prettyJson(dynamic obj) {
    return const JsonEncoder.withIndent('  ').convert(obj);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configurações do Website'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addSetting,
        icon: const Icon(Icons.add),
        label: const Text('Nova'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline,
                          color: Theme.of(context).colorScheme.error,
                          size: 48),
                      const SizedBox(height: 8),
                      Text(_error!),
                      TextButton(
                        onPressed: _load,
                        child: const Text('Tentar novamente'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                    itemCount: _settings.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final s = _settings[i];
                      return Card(
                        child: ListTile(
                          title: Text(s.key,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600)),
                          subtitle: Text(
                            _prettyJson(s.value),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontFamily: 'monospace', fontSize: 11),
                          ),
                          isThreeLine: true,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit_outlined),
                                tooltip: 'Editar',
                                onPressed: () => _editSetting(s),
                              ),
                              IconButton(
                                icon: Icon(Icons.delete_outline,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .error),
                                tooltip: 'Eliminar',
                                onPressed: () => _deleteSetting(s),
                              ),
                            ],
                          ),
                          onTap: () => _editSetting(s),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
