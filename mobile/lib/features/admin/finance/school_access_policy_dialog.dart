import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/models/custom_role.dart';
import '../../../core/models/role_definitions.dart';
import '../../../core/providers/currency_provider.dart';

/// Which Cellen areas each school role may navigate.
///
/// Saving keeps the role capability grants exactly as loaded: they are
/// enforced by the backend, and this dialog only edits Cellen navigation.
Future<void> showSchoolAccessPolicyDialog(
  BuildContext context,
  ApiClient api,
) =>
    showDialog<void>(
      context: context,
      useRootNavigator: false,
      builder: (_) => _SchoolAccessPolicyDialog(api: api),
    );

class _SchoolAccessPolicyDialog extends StatefulWidget {
  const _SchoolAccessPolicyDialog({required this.api});

  final ApiClient api;

  @override
  State<_SchoolAccessPolicyDialog> createState() =>
      _SchoolAccessPolicyDialogState();
}

class _SchoolAccessPolicyDialogState extends State<_SchoolAccessPolicyDialog> {
  late final Future<void> _load = _loadPolicy();
  final Map<String, Set<String>> _roleCapabilities = {};
  final Map<String, Map<String, bool>> _roleFeatures = {};
  final Map<String, bool> _schoolFeatures = {};
  final Map<String, bool> _roleAvailable = {};
  List<RoleDef> _roles = kConfigRoles;
  List<String> _featureKeys = const [];
  bool _saving = false;

  Future<void> _loadPolicy() async {
    final payload = Map<String, dynamic>.from(
        await widget.api.get('/finreg/local-access-policy') as Map);
    final customRoles = (payload['custom_roles'] as List? ?? const [])
        .map((entry) =>
            CustomRole.fromJson(Map<String, dynamic>.from(entry as Map)))
        .map((role) => role.definition)
        .toList();
    _roles = [...kConfigRoles, ...customRoles];
    final roles =
        Map<String, dynamic>.from(payload['role_capabilities'] as Map);
    for (final entry in roles.entries) {
      _roleCapabilities[entry.key] = Set<String>.from(entry.value as List);
    }
    _featureKeys =
        List<String>.from(payload['feature_keys'] as List? ?? const []);
    _schoolFeatures.addAll(
        Map<String, bool>.from(payload['school_features'] as Map? ?? const {}));
    _roleAvailable.addAll(
        Map<String, bool>.from(payload['role_available'] as Map? ?? const {}));
    final features =
        Map<String, dynamic>.from(payload['role_features'] as Map? ?? const {});
    for (final entry in features.entries) {
      _roleFeatures[entry.key] = Map<String, bool>.from(entry.value as Map);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.api.put('/finreg/local-access-policy', data: {
        'role_capabilities': _roleCapabilities.map(
          (role, capabilities) => MapEntry(role, capabilities.toList()..sort()),
        ),
        'role_features': _roleFeatures,
      });
      // Refresh navigation immediately after policy changes.
      if (mounted) {
        // The dialog is hosted by a Consumer screen, so its nearest container
        // can invalidate the shared school policy provider.
        ProviderScope.containerOf(context).invalidate(schoolInfoProvider);
      }
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final portuguese = Localizations.localeOf(context).languageCode == 'pt';
    return AlertDialog(
      title: Text(portuguese ? 'Acessos e funções' : 'Access and roles'),
      content: SizedBox(
        width: 720,
        height: 520,
        child: FutureBuilder<void>(
          future: _load,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(child: Text(snapshot.error.toString()));
            }
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            return ListView(
              children: [
                Text(portuguese
                    ? 'Estas permissões apenas restringem o acesso dentro da escola. Administradores da escola mantêm acesso completo.'
                    : 'These permissions only restrict access inside the school. School administrators retain full access.'),
                const SizedBox(height: 16),
                for (final definition in _roles)
                  ExpansionTile(
                    enabled: _roleAvailable[definition.key] ?? true,
                    leading: Icon(definition.icon, color: definition.color),
                    title: Text(definition.label),
                    subtitle: Text((_roleAvailable[definition.key] ?? true)
                        ? definition.description
                        : (portuguese
                            ? 'Função desativada para esta escola'
                            : 'Role disabled for this school')),
                    children: [
                      ListTile(
                        dense: true,
                        title: Text(
                            portuguese ? 'Áreas do Cellen' : 'Cellen areas'),
                        subtitle: Text(portuguese
                            ? 'Controla a navegação. As ações continuam protegidas pelo tipo de função.'
                            : 'Controls navigation. Actions remain protected by the role type.'),
                      ),
                      for (final feature in _featureKeys)
                        CheckboxListTile(
                          dense: true,
                          value: _roleFeatures[definition.key]?[feature] ??
                              definition.defaultFeatures.contains(feature),
                          title: Text(_humanize(feature)),
                          onChanged: _schoolFeatures[feature] == false
                              ? null
                              : (selected) => setState(() {
                                    _roleFeatures.putIfAbsent(
                                            definition.key, () => {})[feature] =
                                        selected == true;
                                  }),
                        ),
                    ],
                  ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: Text(portuguese ? 'Cancelar' : 'Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(portuguese ? 'Guardar' : 'Save'),
        ),
      ],
    );
  }

  String _humanize(String value) => value
      .split('_')
      .map((part) =>
          part.isEmpty ? part : '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}

